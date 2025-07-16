import std/[sequtils, strutils, strformat, json, options]

import pkg/chronos
import pkg/chronos/transports/stream

import scenario, logger
import protocol/types

export tables, scenario

type
  Transports = ref object
    input: StreamTransport
    output: StreamTransport

  LSPServer = ref object
    transports: Transports
    documents*: Table[string, Document]
    scenarioManager*: ScenarioManager

# LSP Server Implementation
proc newLSPServer*(configPath: string = ""): LSPServer =
  logInfo("Creating new LSP server with config: " & configPath)

  result = LSPServer()

  result.documents = initTable[string, Document]()

  const
    STDIN_FD = 0
    STDOUT_FD = 1
  result.transports = Transports()
  result.transports.input = fromPipe(AsyncFD(STDIN_FD))
  result.transports.output = fromPipe(AsyncFD(STDOUT_FD))

  logInfo("Initializing scenario manager")
  result.scenarioManager = newScenarioManager(configPath)

  logInfo("LSP server created successfully")

proc read(server: LSPServer): Future[char] {.async.} =
  let r = await server.transports.input.read(1)
  return char(r[0])

proc write(server: LSPServer, buf: string) {.async.} =
  let r = await server.transports.output.write(buf)
  if r == -1:
    raise newException(IOError, "Failed to write messages")

proc sendMessage(server: LSPServer, message: JsonNode) {.async.} =
  let
    content = $message
    header = "Content-Length: " & $content.len & "\r\n\r\n"
    buf = header & content

  logDebug(fmt"Send message: {buf}")

  try:
    await server.write(buf)
  except IOError as e:
    logError(fmt"sendMessage: {e.msg}")

proc sendResponse(server: LSPServer, id: JsonNode, r: JsonNode) {.async.} =
  let response = %*{"jsonrpc": "2.0", "id": id, "result": r}
  await server.sendMessage(response)

proc sendError(
    server: LSPServer, code: int, message: string, id: JsonNode = newJNull()
) {.async.} =
  let response =
    %*{"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}
  await server.sendMessage(response)

proc sendNotification(
    server: LSPServer, methodName: string, params: JsonNode
) {.async.} =
  let notification = %*{"jsonrpc": "2.0", "method": methodName, "params": params}
  await server.sendMessage(notification)

proc handleInitialize(server: LSPServer, id: JsonNode, params: JsonNode) {.async.} =
  let clientPid = params.getOrDefault("processId")
  logInfo("Handling initialize request from client PID: " & $clientPid)
  let capabilities =
    %*{
      "textDocumentSync":
        {"openClose": true, "change": 2, "save": {"includeText": true}},
      "completionProvider": {"triggerCharacters": [".", ":", "(", " "]},
      "hoverProvider": true,
      "executeCommandProvider": {
        "commands": [
          "lsptest.switchScenario", "lsptest.listScenarios", "lsptest.reloadConfig",
          "lsptest.createSampleConfig",
        ]
      },
      "diagnosticProvider":
        {"interFileDependencies": false, "workspaceDiagnostics": false},
    }

  let r =
    %*{
      "capabilities": capabilities,
      "serverInfo": {"name": "LSP Test Server", "version": "0.1.0"},
    }

  await server.sendResponse(id, r)

proc handleExecuteCommand(server: LSPServer, id: JsonNode, params: JsonNode) {.async.} =
  let command = params["command"].getStr()
  let args =
    if params.hasKey("arguments"):
      params["arguments"]
    else:
      newJArray()

  case command
  of "lsptest.switchScenario":
    if args.len > 0:
      let scenarioName = args[0].getStr()
      if server.scenarioManager.setScenario(scenarioName):
        await server.sendResponse(id, %*{"success": true})
        await server.sendNotification(
          "window/showMessage",
          %*{"type": 3, "message": "Switched to scenario: " & scenarioName},
        )
      else:
        await server.sendError(-32602, "Unknown scenario: " & scenarioName, id)
    else:
      await server.sendError(-32602, "Missing scenario name argument", id)
  of "lsptest.listScenarios":
    let scenarios = server.scenarioManager.listScenarios()
    let scenarioList = scenarios.map(
      proc(s: auto): JsonNode =
        %*{"name": s.name, "description": s.description}
    )
    await server.sendResponse(id, %scenarioList)
    let names = scenarios
      .map(
        proc(s: auto): string =
          s.name
      )
      .join(", ")
    await server.sendNotification(
      "window/showMessage", %*{"type": 3, "message": "Available scenarios: " & names}
    )
  of "lsptest.reloadConfig":
    if server.scenarioManager.loadConfigFile(server.scenarioManager.configPath):
      await server.sendResponse(id, %*{"success": true})
      await server.sendNotification(
        "window/showMessage", %*{"type": 3, "message": "Configuration reloaded"}
      )
    else:
      await server.sendError(-32603, "Failed to reload configuration", id)
  of "lsptest.createSampleConfig":
    server.scenarioManager.createSampleConfig()
    await server.sendResponse(id, %*{"success": true})
    await server.sendNotification(
      "window/showMessage",
      %*{"type": 3, "message": "Sample configuration file created"},
    )
  else:
    await server.sendError(-32601, "Unknown command: " & command, id)

proc handleDidOpen(server: LSPServer, params: JsonNode) {.async.} =
  let
    textDocument = params["textDocument"]
    uri = textDocument["uri"].getStr
    content = textDocument["text"].getStr
    version = textDocument["version"].getInt

  server.documents[uri] = Document(content: content, version: version)

  # Return notify for debug.
  await server.sendNotification(
    "window/logMessage",
    %*{"type": 5, "message": fmt"Received textDocument/didOpen notify: {params}"},
  )

proc handleDidChange(server: LSPServer, params: JsonNode) {.async.} =
  let
    textDocument = params["textDocument"]
    uri = textDocument["uri"].getStr()
    version = textDocument["version"].getInt()
    contentChanges = params["contentChanges"]

  if uri in server.documents:
    for change in contentChanges.items():
      if change.hasKey("range"):
        # Range-based change (simple implementation)
        server.documents[uri].content = change["text"].getStr()
      else:
        # Full content change
        server.documents[uri].content = change["text"].getStr()

    server.documents[uri].version = version

  # Return notify for debug.
  await server.sendNotification(
    "window/logMessage",
    %*{"type": 5, "message": fmt"Received textDocument/didChange notify: {params}"},
  )

proc handleDidClose(server: LSPServer, params: JsonNode) {.async.} =
  let
    textDocument = params["textDocument"]
    uri = textDocument["uri"].getStr()
  server.documents.del(uri)

  # Return notify for debug.
  await server.sendNotification(
    "window/logMessage",
    %*{"type": 5, "message": fmt"Received textDocument/didClose notify: {params}"},
  )

proc handleHover(server: LSPServer, id: JsonNode, params: JsonNode) {.async.} =
  let scenario = server.scenarioManager.getCurrentScenario()

  # Delay processing
  if scenario.delays.hover > 0:
    await sleepAsync(scenario.delays.hover.milliseconds)

  if not scenario.hover.enabled:
    await server.sendResponse(id, newJNull())
    return

  # Handle error scenarios
  if "hover" in scenario.errors:
    let error = scenario.errors["hover"]
    await server.sendError(error.code, error.message, id)
    return

  let position = params["position"]

  # Create a proper Hover object
  let hover = Hover()
  if scenario.hover.content.isSome:
    # Use single content field
    hover.contents = some(
      %*{
        "kind": scenario.hover.content.get.kind,
        "value": scenario.hover.content.get.message,
      }
    )
  elif scenario.hover.contents.len > 0:
    # Use contents array - support multiple contents for rich hover info
    var contentsArray = newJArray()
    for hoverContent in scenario.hover.contents:
      contentsArray.add(%*{"kind": hoverContent.kind, "value": hoverContent.message})
    hover.contents = some(%contentsArray)
  else:
    # Default fallback
    hover.contents =
      some(%*{"kind": "plaintext", "value": "No hover information available"})
  hover.range = some(
    Range(
      start: Position(
        line: uinteger(position["line"].getInt),
        character: uinteger(position["character"].getInt),
      ),
      `end`: Position(
        line: uinteger(position["line"].getInt),
        character: uinteger(position["character"].getInt),
      ),
    )
  )

  await server.sendResponse(id, %hover)

proc handleMessage(server: LSPServer, message: JsonNode) {.async.} =
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
    await server.sendNotification(
      "window/showMessage",
      %*{
        "type": 3,
        "message":
          "LSP Server ready! Current scenario: " & server.scenarioManager.currentScenario,
      },
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
      let ch = await server.read()
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
