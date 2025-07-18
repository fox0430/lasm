import std/[unittest, json, os, strutils]

import pkg/chronos

import ../src/lasmpkg/[transport, logger]

# Test server.nim functionality via transport abstraction
# This tests the refactored server architecture without creating actual servers

suite "server.nim functionality tests":
  setup:
    setGlobalLogger(newFileLogger(enabled = false))

  test "Transport abstraction read functionality":
    # Tests the base functionality that server.readTransportChar() uses
    let mockTransport = newMockTransport("Hello World")

    let ch1 = waitFor mockTransport.read()
    let ch2 = waitFor mockTransport.read()
    let ch3 = waitFor mockTransport.read()

    check ch1 == 'H'
    check ch2 == 'e'
    check ch3 == 'l'

  test "Transport abstraction write functionality":
    # Tests the base functionality that server.writeTransportData() uses
    let mockTransport = newMockTransport()

    waitFor mockTransport.write("LSP Message Content")

    check mockTransport.getOutputData() == "LSP Message Content"

  test "Transport error handling - read failure":
    # Tests error handling that server.readTransportChar() would encounter
    let mockTransport = newMockTransport()
    mockTransport.setFailureMode(failRead = true)

    expect IOError:
      discard waitFor mockTransport.read()

  test "Transport error handling - write failure":
    # Tests error handling that server.writeTransportData() would encounter
    let mockTransport = newMockTransport()
    mockTransport.setFailureMode(failWrite = true)

    expect IOError:
      waitFor mockTransport.write("test")

  test "Transport EOF handling":
    # Tests EOF handling that server.readTransportChar() would encounter
    let mockTransport = newMockTransport("") # Empty buffer

    expect EOFError:
      discard waitFor mockTransport.read()

  test "LSP message format simulation":
    # Simulates how server.sendMessage() would format messages
    let mockTransport = newMockTransport()

    let message =
      %*{"jsonrpc": "2.0", "method": "textDocument/hover", "params": {"key": "value"}}

    let content = $message
    let header = "Content-Length: " & $content.len & "\r\n\r\n"
    let fullMessage = header & content

    waitFor mockTransport.write(fullMessage)

    let output = mockTransport.getOutputData()
    check output == fullMessage
    check output.startsWith("Content-Length:")
    check output.contains("\r\n\r\n")
    check output.contains("\"jsonrpc\":\"2.0\"")

  test "LSP response format simulation":
    # Simulates how server.sendResponse() would format responses
    let mockTransport = newMockTransport()

    let response =
      %*{"jsonrpc": "2.0", "id": 1, "result": {"capabilities": {"hoverProvider": true}}}

    let content = $response
    let header = "Content-Length: " & $content.len & "\r\n\r\n"
    let fullMessage = header & content

    waitFor mockTransport.write(fullMessage)

    let output = mockTransport.getOutputData()
    check output.contains("\"jsonrpc\":\"2.0\"")
    check output.contains("\"id\":1")
    check output.contains("\"result\":")
    check output.contains("\"hoverProvider\":true")

  test "LSP error format simulation":
    # Simulates how server.sendError() would format errors
    let mockTransport = newMockTransport()

    let errorResponse =
      %*{
        "jsonrpc": "2.0",
        "id": 1,
        "error": {"code": -32601, "message": "Method not found"},
      }

    let content = $errorResponse
    let header = "Content-Length: " & $content.len & "\r\n\r\n"
    let fullMessage = header & content

    waitFor mockTransport.write(fullMessage)

    let output = mockTransport.getOutputData()
    check output.contains("\"jsonrpc\":\"2.0\"")
    check output.contains("\"id\":1")
    check output.contains("\"error\":")
    check output.contains("\"code\":-32601")
    check output.contains("\"message\":\"Method not found\"")

  test "LSP notification format simulation":
    # Simulates how server.sendNotification() would format notifications
    let mockTransport = newMockTransport()

    let notification =
      %*{
        "jsonrpc": "2.0",
        "method": "window/showMessage",
        "params": {"type": 1, "message": "Test notification"},
      }

    let content = $notification
    let header = "Content-Length: " & $content.len & "\r\n\r\n"
    let fullMessage = header & content

    waitFor mockTransport.write(fullMessage)

    let output = mockTransport.getOutputData()
    check output.contains("\"jsonrpc\":\"2.0\"")
    check output.contains("\"method\":\"window/showMessage\"")
    check output.contains("\"params\":")
    check not output.contains("\"id\":") # Notifications don't have IDs

  test "Transport polymorphism validation":
    # Tests that the Transport interface works correctly (used by server.nim)
    let mockTransport1 = newMockTransport("A")
    let mockTransport2 = newMockTransport("B")

    # Both should work as Transport
    let transport1: Transport = mockTransport1
    let transport2: Transport = mockTransport2

    let ch1 = waitFor transport1.read()
    let ch2 = waitFor transport2.read()

    check ch1 == 'A'
    check ch2 == 'B'

  test "Multiple transport operations":
    # Tests multiple operations that server methods would perform
    let mockTransport = newMockTransport("ABC")

    # Test multiple reads (like server.readTransportChar() calls)
    let ch1 = waitFor mockTransport.read()
    let ch2 = waitFor mockTransport.read()
    let ch3 = waitFor mockTransport.read()

    check ch1 == 'A'
    check ch2 == 'B'
    check ch3 == 'C'

    # Test multiple writes (like server.writeTransportData() calls)
    waitFor mockTransport.write("Response1")
    waitFor mockTransport.write("Response2")

    check mockTransport.getOutputData() == "Response1Response2"

  test "LSP message parsing simulation":
    # Simulates how server.startServer() would parse incoming messages
    let testMessage =
      %*{
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {"capabilities": {}},
      }
    let content = $testMessage
    let header = "Content-Length: " & $content.len & "\r\n\r\n"
    let fullMessage = header & content

    let mockTransport = newMockTransport(fullMessage)

    # Read the message character by character (like server.readTransportChar())
    var buffer = ""
    for i in 0 ..< fullMessage.len:
      let ch = waitFor mockTransport.read()
      buffer.add(ch)

    # Verify we read the complete message
    check buffer == fullMessage

    # Parse like the real server would
    let headerEnd = buffer.find("\r\n\r\n")
    check headerEnd != -1

    let headerPart = buffer[0 ..< headerEnd]
    var contentLength = 0

    for line in headerPart.split("\r\n"):
      if line.startsWith("Content-Length:"):
        let parts = line.split(':')
        if parts.len >= 2:
          contentLength = parseInt(parts[1].strip())
          break

    check contentLength == content.len

    let messageStart = headerEnd + 4
    let messageContent = buffer[messageStart ..< messageStart + contentLength]

    let parsed = parseJson(messageContent)
    check parsed["method"].getStr() == "initialize"
    check parsed["jsonrpc"].getStr() == "2.0"
    check parsed["id"].getInt() == 1

  test "Transport failure recovery simulation":
    # Tests how server would handle transport failures
    let mockTransport = newMockTransport("data")

    # First, normal operation
    let ch = waitFor mockTransport.read()
    check ch == 'd'

    # Then simulate failure
    mockTransport.setFailureMode(failRead = true)

    expect IOError:
      discard waitFor mockTransport.read()

    # Recovery
    mockTransport.setFailureMode(failRead = false)
    mockTransport.setInputData("recovered")

    let recoveredCh = waitFor mockTransport.read()
    check recoveredCh == 'r'
