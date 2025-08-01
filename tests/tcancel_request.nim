import std/[unittest, json, tables]
import pkg/chronos
import ../src/lasmpkg/[server, transport, logger, scenario]

suite "$/cancelRequest functionality tests":
  setup:
    setGlobalLogger(newFileLogger(enabled = false))

  test "PendingRequest creation and management":
    let server = newLSPServer("", newMockTransport())
    let requestId = %42
    let requestFuture = newFuture[void]("test")

    # Add pending request
    server.addPendingRequest(requestId, requestFuture)

    # Check if request exists
    check server.pendingRequests.len == 1
    check "42" in server.pendingRequests
    check server.pendingRequests["42"].id == requestId
    check server.pendingRequests["42"].cancelled == false

    # Remove pending request
    server.removePendingRequest(requestId)
    check server.pendingRequests.len == 0

  test "Request cancellation basic functionality":
    let server = newLSPServer("", newMockTransport())
    let requestId = %99
    let requestFuture = newFuture[void]("test")

    # Add request
    server.addPendingRequest(requestId, requestFuture)
    check not server.isRequestCancelled(requestId)

    # Cancel request
    let cancelled = server.cancelRequest(requestId)
    check cancelled == true

    # Verify request no longer exists
    check server.pendingRequests.len == 0
    check not server.isRequestCancelled(requestId)

  test "Cancel non-existent request":
    let server = newLSPServer("", newMockTransport())
    let requestId = %123

    # Try to cancel non-existent request
    let cancelled = server.cancelRequest(requestId)
    check cancelled == false

  test "isRequestCancelled with non-existent request":
    let server = newLSPServer("", newMockTransport())
    let requestId = %456

    check not server.isRequestCancelled(requestId)

  test "Multiple pending requests management":
    let server = newLSPServer("", newMockTransport())
    let id1 = %1
    let id2 = %2
    let id3 = %3
    let future1 = newFuture[void]("test1")
    let future2 = newFuture[void]("test2")
    let future3 = newFuture[void]("test3")

    # Add multiple requests
    server.addPendingRequest(id1, future1)
    server.addPendingRequest(id2, future2)
    server.addPendingRequest(id3, future3)

    check server.pendingRequests.len == 3

    # Cancel middle request
    let cancelled = server.cancelRequest(id2)
    check cancelled == true
    check server.pendingRequests.len == 2
    check "1" in server.pendingRequests
    check "3" in server.pendingRequests
    check "2" notin server.pendingRequests

    # Clean up remaining
    server.removePendingRequest(id1)
    server.removePendingRequest(id3)
    check server.pendingRequests.len == 0

  test "handleCancelRequest with valid ID":
    let mockTransport = newMockTransport()
    let server = newLSPServer("", mockTransport)
    let requestId = %789
    let requestFuture = newFuture[void]("test")

    # Add a pending request
    server.addPendingRequest(requestId, requestFuture)

    # Create cancel request params
    let cancelParams = %*{"id": 789}

    # Handle cancel request
    waitFor server.handleCancelRequest(cancelParams)

    # Request should be cancelled and removed
    check server.pendingRequests.len == 0

  test "handleCancelRequest without ID parameter":
    let mockTransport = newMockTransport()
    let server = newLSPServer("", mockTransport)

    # Create cancel request params without ID
    let cancelParams = %*{}

    # Should not crash
    waitFor server.handleCancelRequest(cancelParams)

  test "handleCancelRequest with non-existent ID":
    let mockTransport = newMockTransport()
    let server = newLSPServer("", mockTransport)

    # Create cancel request params with non-existent ID
    let cancelParams = %*{"id": 999}

    # Should not crash
    waitFor server.handleCancelRequest(cancelParams)

  test "Request ID string conversion consistency":
    let server = newLSPServer("", newMockTransport())
    let numericId = %42
    let stringId = %"test-id"
    let nullId = newJNull()

    let future1 = newFuture[void]("test1")
    let future2 = newFuture[void]("test2")
    let future3 = newFuture[void]("test3")

    # Add requests with different ID types
    server.addPendingRequest(numericId, future1)
    server.addPendingRequest(stringId, future2)
    server.addPendingRequest(nullId, future3)

    check server.pendingRequests.len == 3
    check "42" in server.pendingRequests
    check "\"test-id\"" in server.pendingRequests
    check "null" in server.pendingRequests

    # Cancel by ID
    check server.cancelRequest(numericId) == true
    check server.cancelRequest(stringId) == true
    check server.cancelRequest(nullId) == true

    check server.pendingRequests.len == 0

  test "Cancellation with finished future":
    let server = newLSPServer("", newMockTransport())
    let requestId = %100
    let requestFuture = newFuture[void]("test")

    # Complete the future first
    requestFuture.complete()

    # Add request with finished future
    server.addPendingRequest(requestId, requestFuture)

    # Cancel should still work (future is already finished)
    let cancelled = server.cancelRequest(requestId)
    check cancelled == true
    check server.pendingRequests.len == 0

  test "LSP message handling integration":
    let mockTransport = newMockTransport()
    let server = newLSPServer("", mockTransport)

    # Create a proper LSP cancel request message
    let cancelMessage =
      %*{"jsonrpc": "2.0", "method": "$/cancelRequest", "params": {"id": 42}}

    # Handle the message
    waitFor server.handleMessage(cancelMessage)

    # Should not crash and should handle gracefully

  test "Multiple cancel requests for same ID":
    let server = newLSPServer("", newMockTransport())
    let requestId = %555
    let requestFuture = newFuture[void]("test")

    # Add request
    server.addPendingRequest(requestId, requestFuture)

    # First cancel should succeed
    let cancelled1 = server.cancelRequest(requestId)
    check cancelled1 == true

    # Second cancel should fail (already cancelled)
    let cancelled2 = server.cancelRequest(requestId)
    check cancelled2 == false

  test "Request management cleanup":
    let server = newLSPServer("", newMockTransport())

    # Add many requests
    for i in 1 .. 10:
      let id = %i
      let future = newFuture[void]("test")
      server.addPendingRequest(id, future)

    check server.pendingRequests.len == 10

    # Cancel every other request
    for i in countup(2, 10, 2):
      let id = %i
      check server.cancelRequest(id) == true

    check server.pendingRequests.len == 5

    # Clean up remaining
    for i in countup(1, 9, 2):
      let id = %i
      server.removePendingRequest(id)

    check server.pendingRequests.len == 0
