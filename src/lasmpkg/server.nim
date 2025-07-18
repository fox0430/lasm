import std/[strutils, strformat, json]

import pkg/chronos

import scenario, logger, lsp_handler, transport
import protocol/types

export tables, scenario

type LSPServer* = ref object
  transport*: Transport
  lspHandler*: LSPHandler

proc newLSPServer*(configPath: string = "", transport: Transport = nil): LSPServer =
  ## LSP Server Implementation
  logInfo("Creating new LSP server with config: " & configPath)

  result = LSPServer()

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

proc handleHover(server: LSPServer, id: JsonNode, params: JsonNode) {.async.} =
  try:
    let response = await server.lspHandler.handleHover(id, params)
    await server.sendResponse(id, response)
  except LSPError as e:
    await server.sendError(-32603, e.msg, id)

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
  of "workspace/executeCommand":
    await server.handleExecuteCommand(id, params)
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
