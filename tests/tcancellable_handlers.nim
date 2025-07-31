import std/[unittest, json, strutils]
import pkg/chronos
import ../src/lasmpkg/[server, transport, logger, scenario, lsp_handler]
import ../src/lasmpkg/protocol/types

proc createTestServer(): LSPServer =
  let mockTransport = newMockTransport()
  return newLSPServer("", mockTransport)

proc waitForResponse(transport: MockTransport): JsonNode =
  let output = transport.getOutputData()
  if output.len == 0:
    return newJNull()

  # Parse LSP message format
  let headerEnd = output.find("\r\n\r\n")
  if headerEnd == -1:
    return newJNull()

  let header = output[0 ..< headerEnd]
  var contentLength = 0

  for line in header.split("\r\n"):
    if line.startsWith("Content-Length:"):
      let parts = line.split(':')
      if parts.len >= 2:
        contentLength = parseInt(parts[1].strip())
        break

  if contentLength == 0:
    return newJNull()

  let messageStart = headerEnd + 4
  if output.len < messageStart + contentLength:
    return newJNull()

  let messageContent = output[messageStart ..< messageStart + contentLength]
  return parseJson(messageContent)

suite "Cancellable request handlers tests":
  setup:
    setGlobalLogger(newFileLogger(enabled = false))

  test "handleHover with cancellation support":
    let server = createTestServer()
    let requestId = %42
    let params =
      %*{
        "textDocument": {"uri": "file:///test.txt"},
        "position": {"line": 0, "character": 0},
      }

    # Start hover request (should add to pending requests)
    let hoverFuture = server.handleHover(requestId, params)

    # Check that request was added to pending requests
    check server.pendingRequests.len == 1
    check "42" in server.pendingRequests

    # Wait for completion
    waitFor hoverFuture

    # Request should be removed after completion
    check server.pendingRequests.len == 0

    # Check response was sent
    let transport = cast[MockTransport](server.transport)
    let response = waitForResponse(transport)
    check response != newJNull()
    check response.hasKey("result") or response.hasKey("error")

  test "handleHover cancellation during processing":
    let server = createTestServer()
    let requestId = %100
    let params =
      %*{
        "textDocument": {"uri": "file:///test.txt"},
        "position": {"line": 0, "character": 0},
      }

    # Start hover request
    let hoverFuture = server.handleHover(requestId, params)

    # Immediately cancel the request
    let cancelled = server.cancelRequest(requestId)
    check cancelled == true

    # Wait for hover to complete (should handle cancellation)
    waitFor hoverFuture

    # Check error response was sent
    let transport = cast[MockTransport](server.transport)
    let response = waitForResponse(transport)
    check response != newJNull()

    if response.hasKey("error"):
      check response["error"]["code"].getInt() == -32800
      check "cancelled" in response["error"]["message"].getStr().toLower()

  test "handleCompletion with cancellation support":
    let server = createTestServer()
    let requestId = %200
    let params =
      %*{
        "textDocument": {"uri": "file:///test.txt"},
        "position": {"line": 0, "character": 5},
      }

    # Start completion request
    let completionFuture = server.handleCompletion(requestId, params)

    # Check pending request
    check server.pendingRequests.len == 1

    # Wait for completion
    waitFor completionFuture

    # Should be cleaned up
    check server.pendingRequests.len == 0

  test "handleCompletion cancellation":
    let server = createTestServer()
    let requestId = %201
    let params =
      %*{
        "textDocument": {"uri": "file:///test.txt"},
        "position": {"line": 0, "character": 5},
      }

    # Start and immediately cancel
    let completionFuture = server.handleCompletion(requestId, params)
    discard server.cancelRequest(requestId)

    waitFor completionFuture

    # Check for cancellation error response
    let transport = cast[MockTransport](server.transport)
    let response = waitForResponse(transport)

    if response.hasKey("error"):
      check response["error"]["code"].getInt() == -32800

  test "handleDefinition with cancellation support":
    let server = createTestServer()
    let requestId = %300
    let params =
      %*{
        "textDocument": {"uri": "file:///test.txt"},
        "position": {"line": 2, "character": 10},
      }

    let definitionFuture = server.handleDefinition(requestId, params)

    check server.pendingRequests.len == 1

    waitFor definitionFuture
    check server.pendingRequests.len == 0

  test "handleSemanticTokensFull with cancellation":
    let server = createTestServer()
    let requestId = %400
    let params = %*{"textDocument": {"uri": "file:///test.txt"}}

    let semanticFuture = server.handleSemanticTokensFull(requestId, params)
    discard server.cancelRequest(requestId)

    # Cancel might succeed or fail depending on timing
    waitFor semanticFuture

    # Should be cleaned up regardless
    check server.pendingRequests.len == 0

  test "Multiple handlers with same ID (should not happen but test robustness)":
    let server = createTestServer()
    let requestId = %500
    let hoverParams =
      %*{
        "textDocument": {"uri": "file:///test.txt"},
        "position": {"line": 0, "character": 0},
      }
    let completionParams =
      %*{
        "textDocument": {"uri": "file:///test.txt"},
        "position": {"line": 0, "character": 5},
      }

    # Start two requests with same ID (unusual but should handle gracefully)
    let hoverFuture = server.handleHover(requestId, hoverParams)

    # Second request should replace the first
    let completionFuture = server.handleCompletion(requestId, completionParams)

    waitFor hoverFuture
    waitFor completionFuture

    # Should not crash and should clean up properly
    check server.pendingRequests.len == 0

  test "Cancellation after natural completion":
    let server = createTestServer()
    let requestId = %600
    let params =
      %*{
        "textDocument": {"uri": "file:///test.txt"},
        "position": {"line": 0, "character": 0},
      }

    # Complete request naturally
    let hoverFuture = server.handleHover(requestId, params)
    waitFor hoverFuture

    # Try to cancel after completion
    let cancelled = server.cancelRequest(requestId)
    check cancelled == false # Should fail because request already completed

  test "withCancellationSupport template behavior":
    # This tests the template indirectly through handler usage
    let server = createTestServer()
    let requestId = %700
    let params =
      %*{
        "textDocument": {"uri": "file:///test.txt"},
        "position": {"line": 0, "character": 0},
      }

    # The template should:
    # 1. Add request to pending
    # 2. Check cancellation before processing  
    # 3. Check cancellation after processing
    # 4. Clean up in finally block

    let hoverFuture = server.handleHover(requestId, params)

    # During processing, request should be tracked
    check server.pendingRequests.len == 1

    waitFor hoverFuture

    # After processing, should be cleaned up
    check server.pendingRequests.len == 0

  test "Exception handling in cancellable handlers":
    let server = createTestServer()
    let requestId = %800
    let invalidParams = %*{} # Invalid params to trigger error

    # Handler should handle errors gracefully even with cancellation support
    let hoverFuture = server.handleHover(requestId, invalidParams)

    # Should not crash
    waitFor hoverFuture

    # Should clean up even on error
    check server.pendingRequests.len == 0

    # Should send error response
    let transport = cast[MockTransport](server.transport)
    let response = waitForResponse(transport)
    check response.hasKey("error") or response.hasKey("result")

  test "Rapid cancel requests":
    let server = createTestServer()

    # Start multiple requests rapidly
    var futures: seq[Future[void]] = @[]
    for i in 1 .. 5:
      let requestId = %i
      let params =
        %*{
          "textDocument": {"uri": "file:///test.txt"},
          "position": {"line": i, "character": 0},
        }
      futures.add(server.handleHover(requestId, params))

    # Cancel them all rapidly
    for i in 1 .. 5:
      let requestId = %i
      discard server.cancelRequest(requestId)

    # Wait for all to complete
    for future in futures:
      waitFor future

    # All should be cleaned up
    check server.pendingRequests.len == 0

  test "Request ID type consistency in cancellable handlers":
    let server = createTestServer()

    # Test with different ID types
    let numericId = %42
    let stringId = %"test-request"
    let floatId = %3.14

    let params =
      %*{
        "textDocument": {"uri": "file:///test.txt"},
        "position": {"line": 0, "character": 0},
      }

    # Start requests with different ID types
    let future1 = server.handleHover(numericId, params)
    let future2 = server.handleHover(stringId, params)
    let future3 = server.handleHover(floatId, params)

    check server.pendingRequests.len == 3

    # Cancel by different ID types
    check server.cancelRequest(numericId) == true
    check server.cancelRequest(stringId) == true
    check server.cancelRequest(floatId) == true

    # Wait for completion
    waitFor future1
    waitFor future2
    waitFor future3

    check server.pendingRequests.len == 0
