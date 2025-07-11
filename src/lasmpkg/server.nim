import std/[sequtils, strutils]

import pkg/chronos

import scenario, logger

export tables, scenario

type LSPServer = ref object
  documents*: Table[string, Document]
  scenarioManager*: ScenarioManager

# LSP Server Implementation
proc newLSPServer*(configPath: string = ""): LSPServer =
  logInfo("Creating new LSP server with config: " & configPath)
  result = LSPServer()
  result.documents = initTable[string, Document]()
  logInfo("Initializing scenario manager")
  result.scenarioManager = newScenarioManager(configPath)
  logInfo("LSP server created successfully")

proc sendMessage(server: LSPServer, message: JsonNode) =
  let content = $message
  let header = "Content-Length: " & $content.len & "\r\n\r\n"
  let messageMethod = message.getOrDefault("method").getStr("response")
  logDebug(
    "Sending LSP message: " & messageMethod & " (size: " & $content.len & " bytes)"
  )
  stdout.write(header & content)
  stdout.flushFile()

proc sendResponse(server: LSPServer, id: JsonNode, result: JsonNode) =
  let response = %*{"jsonrpc": "2.0", "id": id, "result": result}
  server.sendMessage(response)

proc sendError(
    server: LSPServer, code: int, message: string, id: JsonNode = newJNull()
) =
  let response =
    %*{"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}
  server.sendMessage(response)

proc sendNotification(server: LSPServer, methodName: string, params: JsonNode) =
  let notification = %*{"jsonrpc": "2.0", "method": methodName, "params": params}
  server.sendMessage(notification)

proc handleInitialize(server: LSPServer, id: JsonNode, params: JsonNode) =
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

  server.sendResponse(id, r)

proc handleExecuteCommand(server: LSPServer, id: JsonNode, params: JsonNode) =
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
        server.sendResponse(id, %*{"success": true})
        server.sendNotification(
          "window/showMessage",
          %*{"type": 3, "message": "Switched to scenario: " & scenarioName},
        )
      else:
        server.sendError(-32602, "Unknown scenario: " & scenarioName, id)
    else:
      server.sendError(-32602, "Missing scenario name argument", id)
  of "lsptest.listScenarios":
    let scenarios = server.scenarioManager.listScenarios()
    let scenarioList = scenarios.map(
      proc(s: auto): JsonNode =
        %*{"name": s.name, "description": s.description}
    )
    server.sendResponse(id, %scenarioList)
    let names = scenarios
      .map(
        proc(s: auto): string =
          s.name
      )
      .join(", ")
    server.sendNotification(
      "window/showMessage", %*{"type": 3, "message": "Available scenarios: " & names}
    )
  of "lsptest.reloadConfig":
    if server.scenarioManager.loadConfigFile(server.scenarioManager.configPath):
      server.sendResponse(id, %*{"success": true})
      server.sendNotification(
        "window/showMessage", %*{"type": 3, "message": "Configuration reloaded"}
      )
    else:
      server.sendError(-32603, "Failed to reload configuration", id)
  of "lsptest.createSampleConfig":
    server.scenarioManager.createSampleConfig()
    server.sendResponse(id, %*{"success": true})
    server.sendNotification(
      "window/showMessage",
      %*{"type": 3, "message": "Sample configuration file created"},
    )
  else:
    server.sendError(-32601, "Unknown command: " & command, id)

proc handleDidOpen(server: LSPServer, params: JsonNode) {.async.} =
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()
  let content = textDocument["text"].getStr()
  let version = textDocument["version"].getInt()

  server.documents[uri] = Document(content: content, version: version)

proc handleDidChange(server: LSPServer, params: JsonNode) {.async.} =
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()
  let version = textDocument["version"].getInt()
  let contentChanges = params["contentChanges"]

  if uri in server.documents:
    for change in contentChanges.items():
      if change.hasKey("range"):
        # Range-based change (simple implementation)
        server.documents[uri].content = change["text"].getStr()
      else:
        # Full content change
        server.documents[uri].content = change["text"].getStr()

    server.documents[uri].version = version

proc handleDidClose(server: LSPServer, params: JsonNode) {.async.} =
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()
  server.documents.del(uri)

proc handleHover(server: LSPServer, id: JsonNode, params: JsonNode) {.async.} =
  let scenario = server.scenarioManager.getCurrentScenario()

  # Delay processing
  if scenario.delays.hover > 0:
    await sleepAsync(scenario.delays.hover.milliseconds)

  if not scenario.hover.enabled:
    server.sendResponse(id, newJNull())
    return

  # Handle error scenarios
  if "hover" in scenario.errors:
    let error = scenario.errors["hover"]
    server.sendError(error.code, error.message, id)
    return

  let position = params["position"]
  let r =
    %*{
      "contents": {"kind": "markdown", "value": scenario.hover.message},
      "range": {
        "start": position,
        "end": {
          "line": position["line"].getInt(),
          "character": position["character"].getInt() + 5,
        },
      },
    }
  server.sendResponse(id, r)

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
    server.handleInitialize(id, params)
  of "initialized":
    server.sendNotification(
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
    server.handleExecuteCommand(id, params)
  of "shutdown":
    logInfo("Received shutdown request")
    server.sendResponse(id, newJNull())
  of "exit":
    logInfo("Received exit request, shutting down server")
    quit(0)
  else:
    logWarn("Unknown LSP method: " & methodName)
    server.sendError(-32601, "Method not found: " & methodName, id)

proc startServer*(server: LSPServer) {.async.} =
  logInfo("Starting LSP server main loop")
  var buffer = ""

  while true:
    # Read input character by character to handle LSP protocol properly
    try:
      let ch = stdin.readChar()
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

      try:
        let message = parseJson(messageContent)
        await server.handleMessage(message)
      except JsonParsingError as e:
        logError("JSON parsing error: " & e.msg)
        server.sendError(-32700, "Parse error", newJNull())
      except Exception as e:
        logError("Internal server error: " & e.msg)
        server.sendError(-32603, "Internal error", newJNull())
