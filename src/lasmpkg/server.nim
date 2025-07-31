import std/[strutils, strformat, json, tables]

import pkg/chronos

import scenario, logger, lsp_handler, transport
import protocol/types

export tables, scenario

type
  PendingRequest* = ref object
    id*: JsonNode
    future*: Future[void]
    cancelled*: bool

  LSPServer* = ref object
    transport*: Transport
    lspHandler*: LSPHandler
    pendingRequests*: Table[string, PendingRequest]

proc newLSPServer*(configPath: string = "", transport: Transport = nil): LSPServer =
  ## LSP Server Implementation
  logInfo("Creating new LSP server with config: " & configPath)

  result = LSPServer()
  result.pendingRequests = initTable[string, PendingRequest]()

  # Use provided transport or create default stdio transport
  if transport == nil:
    result.transport = newLSPTransport()
    logInfo("Created default stdio transport")
  else:
    result.transport = transport
    logInfo("Using provided transport")

  logInfo("Initializing scenario manager")
  let scenarioManager = newScenarioManager(configPath)
  result.lspHandler = newLSPHandler(scenarioManager)

  logInfo("LSP server created successfully")

proc readTransportChar*(server: LSPServer): Future[char] {.async.} =
  return await server.transport.read()

proc writeTransportData*(server: LSPServer, buf: string) {.async.} =
  await server.transport.write(buf)

proc sendMessage*(server: LSPServer, message: JsonNode) {.async.} =
  let
    content = $message
    header = "Content-Length: " & $content.len & "\r\n\r\n"
    buf = header & content

  logDebug(fmt"Send message: {buf}")

  try:
    await server.writeTransportData(buf)
  except IOError as e:
    logError(fmt"sendMessage: {e.msg}")

proc sendResponse*(server: LSPServer, id: JsonNode, r: JsonNode) {.async.} =
  let response = %*{"jsonrpc": "2.0", "id": id, "result": r}
  await server.sendMessage(response)

proc sendError*(
    server: LSPServer, code: int, message: string, id: JsonNode = newJNull()
) {.async.} =
  let response =
    %*{"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}
  await server.sendMessage(response)

proc sendNotification*(
    server: LSPServer, methodName: string, params: JsonNode
) {.async.} =
  let notification = %*{"jsonrpc": "2.0", "method": methodName, "params": params}
  await server.sendMessage(notification)

proc addPendingRequest*(server: LSPServer, id: JsonNode, future: Future[void]) =
  let requestId = $id
  let pendingRequest = PendingRequest(id: id, future: future, cancelled: false)
  server.pendingRequests[requestId] = pendingRequest

proc removePendingRequest*(server: LSPServer, id: JsonNode) =
  let requestId = $id
  server.pendingRequests.del(requestId)

proc cancelRequest*(server: LSPServer, id: JsonNode): bool =
  let requestId = $id
  if requestId in server.pendingRequests:
    let pendingRequest = server.pendingRequests[requestId]
    pendingRequest.cancelled = true
    if not pendingRequest.future.finished():
      pendingRequest.future.cancelSoon()
    server.pendingRequests.del(requestId)
    return true
  return false

proc isRequestCancelled*(server: LSPServer, id: JsonNode): bool =
  let requestId = $id
  if requestId in server.pendingRequests:
    return server.pendingRequests[requestId].cancelled
  return false

template withCancellationSupport*(
    server: LSPServer, id: JsonNode, methodName: string, body: untyped
): untyped =
  # Add to pending requests immediately when the template is expanded
  let requestFuture = newFuture[void](methodName)
  server.addPendingRequest(id, requestFuture)

  # Create an async closure that handles the actual work and cleanup  
  proc doWork() {.async.} =
    try:
      if server.isRequestCancelled(id):
        await server.sendError(-32800, "Request was cancelled", id)
        requestFuture.complete()
        return

      body

      if server.isRequestCancelled(id):
        await server.sendError(-32800, "Request was cancelled", id)
        requestFuture.complete()
        return

      requestFuture.complete()
    except LSPError as e:
      await server.sendError(-32603, e.msg, id)
      requestFuture.fail(e)
    except CancelledError:
      await server.sendError(-32800, "Request was cancelled", id)
      requestFuture.fail(newException(CancelledError, "Request cancelled"))
    except Exception as e:
      await server.sendError(-32603, "Internal error: " & e.msg, id)
      requestFuture.fail(newException(CatchableError, e.msg))
    finally:
      server.removePendingRequest(id)

  # Start the work asynchronously
  await doWork()

proc handleInitialize*(server: LSPServer, id: JsonNode, params: JsonNode) {.async.} =
  let response = await server.lspHandler.handleInitialize(id, params)
  await server.sendResponse(id, response)

proc handleExecuteCommand(server: LSPServer, id: JsonNode, params: JsonNode) {.async.} =
  try:
    let (response, notifications) =
      await server.lspHandler.handleExecuteCommand(id, params)
    await server.sendResponse(id, response)
    for notification in notifications:
      await server.sendNotification(
        notification["method"].getStr(), notification["params"]
      )
  except LSPError as e:
    await server.sendError(-32602, e.msg, id)

proc handleDidOpen(server: LSPServer, params: JsonNode) {.async.} =
  let notifications = await server.lspHandler.handleDidOpen(params)
  for notification in notifications:
    await server.sendNotification(
      notification["method"].getStr(), notification["params"]
    )

proc handleDidChange(server: LSPServer, params: JsonNode) {.async.} =
  let notifications = await server.lspHandler.handleDidChange(params)
  for notification in notifications:
    await server.sendNotification(
      notification["method"].getStr(), notification["params"]
    )

proc handleDidClose(server: LSPServer, params: JsonNode) {.async.} =
  let notifications = await server.lspHandler.handleDidClose(params)
  for notification in notifications:
    await server.sendNotification(
      notification["method"].getStr(), notification["params"]
    )

proc handleDidChangeConfiguration(server: LSPServer, params: JsonNode) {.async.} =
  let notifications = await server.lspHandler.handleDidChangeConfiguration(params)
  for notification in notifications:
    await server.sendNotification(
      notification["method"].getStr(), notification["params"]
    )

proc handleHoverImpl(server: LSPServer, id: JsonNode, params: JsonNode) {.async.} =
  try:
    if server.isRequestCancelled(id):
      await server.sendError(-32800, "Request was cancelled", id)
      return

    let response = await server.lspHandler.handleHover(id, params)

    if server.isRequestCancelled(id):
      await server.sendError(-32800, "Request was cancelled", id)
      return

    await server.sendResponse(id, response)
  except LSPError as e:
    await server.sendError(-32603, e.msg, id)
  except CancelledError:
    await server.sendError(-32800, "Request was cancelled", id)
  except Exception as e:
    await server.sendError(-32603, "Internal error: " & e.msg, id)

proc handleHover*(server: LSPServer, id: JsonNode, params: JsonNode): Future[void] =
  # Add to pending requests immediately (synchronously) when called
  let requestFuture = newFuture[void]("handleHover")
  server.addPendingRequest(id, requestFuture)

  # Start the async implementation and handle cleanup asynchronously
  proc asyncWrapper() {.async.} =
    try:
      await server.handleHoverImpl(id, params)
      requestFuture.complete()
    except Exception as e:
      requestFuture.fail(newException(CatchableError, e.msg))
    finally:
      server.removePendingRequest(id)

  # Start the wrapper
  asyncSpawn asyncWrapper()

  return requestFuture

proc handleCompletionImpl(server: LSPServer, id: JsonNode, params: JsonNode) {.async.} =
  try:
    if server.isRequestCancelled(id):
      await server.sendError(-32800, "Request was cancelled", id)
      return

    let response = await server.lspHandler.handleCompletion(id, params)

    if server.isRequestCancelled(id):
      await server.sendError(-32800, "Request was cancelled", id)
      return

    await server.sendResponse(id, response)
  except LSPError as e:
    await server.sendError(-32603, e.msg, id)
  except CancelledError:
    await server.sendError(-32800, "Request was cancelled", id)
  except Exception as e:
    await server.sendError(-32603, "Internal error: " & e.msg, id)

proc handleCompletion*(
    server: LSPServer, id: JsonNode, params: JsonNode
): Future[void] =
  let requestFuture = newFuture[void]("handleCompletion")
  server.addPendingRequest(id, requestFuture)

  proc asyncWrapper() {.async.} =
    try:
      await server.handleCompletionImpl(id, params)
      requestFuture.complete()
    except Exception as e:
      requestFuture.fail(newException(CatchableError, e.msg))
    finally:
      server.removePendingRequest(id)

  asyncSpawn asyncWrapper()
  return requestFuture

proc handleSemanticTokensFullImpl(
    server: LSPServer, id: JsonNode, params: JsonNode
) {.async.} =
  try:
    if server.isRequestCancelled(id):
      await server.sendError(-32800, "Request was cancelled", id)
      return

    let response = await server.lspHandler.handleSemanticTokensFull(id, params)

    if server.isRequestCancelled(id):
      await server.sendError(-32800, "Request was cancelled", id)
      return

    await server.sendResponse(id, response)
  except LSPError as e:
    await server.sendError(-32603, e.msg, id)
  except CancelledError:
    await server.sendError(-32800, "Request was cancelled", id)
  except Exception as e:
    await server.sendError(-32603, "Internal error: " & e.msg, id)

proc handleSemanticTokensFull*(
    server: LSPServer, id: JsonNode, params: JsonNode
): Future[void] =
  let requestFuture = newFuture[void]("handleSemanticTokensFull")
  server.addPendingRequest(id, requestFuture)

  proc asyncWrapper() {.async.} =
    try:
      await server.handleSemanticTokensFullImpl(id, params)
      requestFuture.complete()
    except Exception as e:
      requestFuture.fail(newException(CatchableError, e.msg))
    finally:
      server.removePendingRequest(id)

  asyncSpawn asyncWrapper()
  return requestFuture

proc handleSemanticTokensRange(
    server: LSPServer, id: JsonNode, params: JsonNode
) {.async.} =
  server.withCancellationSupport(id, "handleSemanticTokensRange"):
    let response = await server.lspHandler.handleSemanticTokensRange(id, params)
    await server.sendResponse(id, response)

proc handleInlayHint(server: LSPServer, id: JsonNode, params: JsonNode) {.async.} =
  try:
    let response = await server.lspHandler.handleInlayHint(id, params)
    await server.sendResponse(id, response)
  except LSPError as e:
    await server.sendError(-32603, e.msg, id)

proc handleDeclaration(server: LSPServer, id: JsonNode, params: JsonNode) {.async.} =
  try:
    let response = await server.lspHandler.handleDeclaration(id, params)
    await server.sendResponse(id, response)
  except LSPError as e:
    await server.sendError(-32603, e.msg, id)

proc handleDefinitionImpl(server: LSPServer, id: JsonNode, params: JsonNode) {.async.} =
  try:
    if server.isRequestCancelled(id):
      await server.sendError(-32800, "Request was cancelled", id)
      return

    let response = await server.lspHandler.handleDefinition(id, params)

    if server.isRequestCancelled(id):
      await server.sendError(-32800, "Request was cancelled", id)
      return

    await server.sendResponse(id, response)
  except LSPError as e:
    await server.sendError(-32603, e.msg, id)
  except CancelledError:
    await server.sendError(-32800, "Request was cancelled", id)
  except Exception as e:
    await server.sendError(-32603, "Internal error: " & e.msg, id)

proc handleDefinition*(
    server: LSPServer, id: JsonNode, params: JsonNode
): Future[void] =
  let requestFuture = newFuture[void]("handleDefinition")
  server.addPendingRequest(id, requestFuture)

  proc asyncWrapper() {.async.} =
    try:
      await server.handleDefinitionImpl(id, params)
      requestFuture.complete()
    except Exception as e:
      requestFuture.fail(newException(CatchableError, e.msg))
    finally:
      server.removePendingRequest(id)

  asyncSpawn asyncWrapper()
  return requestFuture

proc handleTypeDefinition(server: LSPServer, id: JsonNode, params: JsonNode) {.async.} =
  try:
    let response = await server.lspHandler.handleTypeDefinition(id, params)
    await server.sendResponse(id, response)
  except LSPError as e:
    await server.sendError(-32603, e.msg, id)

proc handleImplementation(server: LSPServer, id: JsonNode, params: JsonNode) {.async.} =
  try:
    let response = await server.lspHandler.handleImplementation(id, params)
    await server.sendResponse(id, response)
  except LSPError as e:
    await server.sendError(-32603, e.msg, id)

proc handleReferences(server: LSPServer, id: JsonNode, params: JsonNode) {.async.} =
  try:
    let response = await server.lspHandler.handleReferences(id, params)
    await server.sendResponse(id, response)
  except LSPError as e:
    await server.sendError(-32603, e.msg, id)

proc handleDocumentHighlight(
    server: LSPServer, id: JsonNode, params: JsonNode
) {.async.} =
  try:
    let response = await server.lspHandler.handleDocumentHighlight(id, params)
    await server.sendResponse(id, response)
  except LSPError as e:
    await server.sendError(-32603, e.msg, id)

proc handleTextDocumentRename(
    server: LSPServer, id: JsonNode, params: JsonNode
) {.async.} =
  try:
    let response = await server.lspHandler.handleTextDocumentRename(id, params)
    await server.sendResponse(id, response)
  except LSPError as e:
    await server.sendError(-32603, e.msg, id)

proc handleDocumentFormatting(
    server: LSPServer, id: JsonNode, params: JsonNode
) {.async.} =
  try:
    let response = await server.lspHandler.handleDocumentFormatting(id, params)
    await server.sendResponse(id, response)
  except LSPError as e:
    await server.sendError(-32603, e.msg, id)

proc handleCancelRequest*(server: LSPServer, params: JsonNode) {.async.} =
  if params.hasKey("id"):
    let requestId = params["id"]
    let cancelled = server.cancelRequest(requestId)
    if cancelled:
      logInfo("Successfully cancelled request: " & $requestId)
    else:
      logInfo("Request not found or already completed: " & $requestId)
  else:
    logWarn("Cancel request missing id parameter")

proc handleMessage*(server: LSPServer, message: JsonNode) {.async.} =
  let methodName = message["method"].getStr()
  let params =
    if message.hasKey("params"):
      message["params"]
    else:
      newJObject()
  let id =
    if message.hasKey("id"):
      message["id"]
    else:
      newJNull()

  logDebug("Handling LSP message: " & methodName)

  case methodName
  of "initialize":
    await server.handleInitialize(id, params)
  of "initialized":
    let notifications = server.lspHandler.handleInitialized()
    for notification in notifications:
      await server.sendNotification(
        notification["method"].getStr(), notification["params"]
      )
  of "textDocument/didOpen":
    await server.handleDidOpen(params)
  of "textDocument/didChange":
    await server.handleDidChange(params)
  of "textDocument/didClose":
    await server.handleDidClose(params)
  of "textDocument/hover":
    await server.handleHover(id, params)
  of "textDocument/completion":
    await server.handleCompletion(id, params)
  of "textDocument/semanticTokens/full":
    await server.handleSemanticTokensFull(id, params)
  of "textDocument/semanticTokens/range":
    await server.handleSemanticTokensRange(id, params)
  of "textDocument/inlayHint":
    await server.handleInlayHint(id, params)
  of "textDocument/declaration":
    await server.handleDeclaration(id, params)
  of "textDocument/definition":
    await server.handleDefinition(id, params)
  of "textDocument/typeDefinition":
    await server.handleTypeDefinition(id, params)
  of "textDocument/implementation":
    await server.handleImplementation(id, params)
  of "textDocument/references":
    await server.handleReferences(id, params)
  of "textDocument/documentHighlight":
    await server.handleDocumentHighlight(id, params)
  of "textDocument/rename":
    await server.handleTextDocumentRename(id, params)
  of "textDocument/formatting":
    await server.handleDocumentFormatting(id, params)
  of "workspace/executeCommand":
    await server.handleExecuteCommand(id, params)
  of "workspace/didChangeConfiguration":
    await server.handleDidChangeConfiguration(params)
  of "$/cancelRequest":
    await server.handleCancelRequest(params)
  of "shutdown":
    logInfo("Received shutdown request")
    await server.sendResponse(id, newJNull())
  of "exit":
    logInfo("Received exit request, shutting down server")
    quit(0)
  else:
    logWarn("Unknown LSP method: " & methodName)
    await server.sendError(-32601, "Method not found: " & methodName, id)

proc startServer*(server: LSPServer) {.async.} =
  logInfo("Starting LSP server main loop")
  var buffer = ""

  while true:
    # Read input character by character to handle LSP protocol properly
    try:
      let ch = await server.readTransportChar()
      buffer.add(ch)
    except EOFError:
      logInfo("EOF received, stopping server")
      break
    except IOError as e:
      logError("IO error reading from stdin: " & e.msg)
      break

    # Process complete messages
    while true:
      let headerEnd = buffer.find("\r\n\r\n")
      if headerEnd == -1:
        break

      let header = buffer[0 ..< headerEnd]
      var contentLength = 0

      # Parse Content-Length header
      for line in header.split("\r\n"):
        if line.startsWith("Content-Length:"):
          let parts = line.split(':')
          if parts.len >= 2:
            try:
              contentLength = parseInt(parts[1].strip())
            except ValueError:
              continue
            break

      if contentLength == 0:
        logError("No valid Content-Length found in LSP message header")
        break

      let messageStart = headerEnd + 4

      # Check if we have the complete message
      if buffer.len < messageStart + contentLength:
        break

      let messageContent = buffer[messageStart ..< messageStart + contentLength]
      buffer = buffer[messageStart + contentLength ..^ 1]

      logDebug(fmt"Received message: {messageContent}")

      try:
        let message = parseJson(messageContent)
        await server.handleMessage(message)
      except JsonParsingError as e:
        logError("JSON parsing error: " & e.msg)
        await server.sendError(-32700, "Parse error", newJNull())
      except Exception as e:
        logError("Internal server error: " & e.msg)
        await server.sendError(-32603, "Internal error", newJNull())
