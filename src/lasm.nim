import std/[json, tables, strutils, sequtils, os, options]

import pkg/chronos

type
  HoverConfig = object
    enabled: bool
    message: string

  DelayConfig = object
    hover: int

  ErrorConfig = object
    code: int
    message: string

  Scenario = object
    name: string
    hover: HoverConfig
    delays: DelayConfig
    errors: Table[string, ErrorConfig]

  Document = object
    content: string
    version: int

  ScenarioManager = ref object
    scenarios: Table[string, Scenario]
    currentScenario: string
    configPath: string

  LSPServer = ref object
    documents: Table[string, Document]
    scenarioManager: ScenarioManager

proc loadConfigFile(sm: ScenarioManager, configPath: string = ""): bool =
  let actualPath = if configPath == "":
    getCurrentDir() / "lsp-test-config.json"
  else:
    configPath

  if not fileExists(actualPath):
    stderr.writeLine("Error: Configuration file not found: " & actualPath)
    if configPath == "":
      stderr.writeLine(
        "Please create a configuration file or use --create-sample-config to generate one."
      )
    return false

  try:
    let configContent = readFile(actualPath)
    let config = parseJson(configContent)

    if config.hasKey("currentScenario"):
      sm.currentScenario = config["currentScenario"].getStr()

    if config.hasKey("scenarios"):
      let scenariosNode = config["scenarios"]
      for scenarioName, scenarioData in scenariosNode.pairs():
        var scenario = Scenario()
        scenario.name = scenarioData{"name"}.getStr(scenarioName)

        # Load hover configuration
        if scenarioData.hasKey("hover"):
          let hoverNode = scenarioData["hover"]
          scenario.hover = HoverConfig(
            enabled: hoverNode{"enabled"}.getBool(true),
            message: hoverNode{"message"}.getStr("Default hover message"),
          )

        # Load delay configuration
        if scenarioData.hasKey("delays"):
          let delaysNode = scenarioData["delays"]
          scenario.delays = DelayConfig(hover: delaysNode{"hover"}.getInt(0))

        # Load error configuration
        if scenarioData.hasKey("errors"):
          let errorsNode = scenarioData["errors"]
          for errorType, errorData in errorsNode.pairs():
            scenario.errors[errorType] = ErrorConfig(
              code: errorData["code"].getInt(-32603),
              message: errorData["message"].getStr("Unknown error"),
            )

        sm.scenarios[scenarioName] = scenario

    stderr.writeLine("Loaded config from " & actualPath)
    return true
  except:
    stderr.writeLine("Error loading config: " & getCurrentExceptionMsg())
    return false

proc newScenarioManager(configPath: string = ""): ScenarioManager =
  result = ScenarioManager()
  result.currentScenario = "default"
  result.configPath = if configPath == "":
    getCurrentDir() / "lsp-test-config.json"
  else:
    configPath
  if not result.loadConfigFile(result.configPath):
    quit(1)

proc getCurrentScenario(sm: ScenarioManager): Scenario =
  if sm.currentScenario in sm.scenarios:
    return sm.scenarios[sm.currentScenario]
  else:
    return sm.scenarios["default"]

proc setScenario(sm: ScenarioManager, scenarioName: string): bool =
  if scenarioName in sm.scenarios:
    sm.currentScenario = scenarioName
    stderr.writeLine("Switched to scenario: " & scenarioName)
    return true
  return false

proc listScenarios(sm: ScenarioManager): seq[tuple[name: string, description: string]] =
  for name, scenario in sm.scenarios.pairs():
    result.add((name: name, description: scenario.name))

proc createSampleConfig(sm: ScenarioManager) =
  let sampleConfig =
    %*{
      "currentScenario": "default",
      "scenarios": {
        "txt": {
          "name": "Nim Language Testing",
          "hover": {
            "enabled": true,
            "message": "**Nim Symbol**\n\nThis is a Nim language symbol.",
          },
          "delays": {"completion": 100, "diagnostics": 200, "hover": 50},
        }
      },
    }

  let configPath = getCurrentDir() / "lsp-test-config-sample.json"
  writeFile(configPath, pretty(sampleConfig, 2))
  stderr.writeLine("Sample config created at " & configPath)

# LSP Server Implementation
proc newLSPServer(configPath: string = ""): LSPServer =
  result = LSPServer()
  result.documents = initTable[string, Document]()
  result.scenarioManager = newScenarioManager(configPath)

proc sendMessage(server: LSPServer, message: JsonNode) =
  let content = $message
  let header = "Content-Length: " & $content.len & "\r\n\r\n"
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

  case methodName
  of "initialize":
    server.handleInitialize(id, params)
  of "initialized":
    server.sendNotification(
      "window/showMessage",
      %*{
        "type": 3,
        "message":
          "LSP Server ready! Current scenario: " &
          server.scenarioManager.currentScenario,
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
    server.sendResponse(id, newJNull())
  of "exit":
    quit(0)
  else:
    stderr.writeLine("Unknown method: " & methodName)
    server.sendError(-32601, "Method not found: " & methodName, id)

proc processInput(server: LSPServer) {.async.} =
  var buffer = ""

  while true:
    # Read input character by character to handle LSP protocol properly
    try:
      let ch = stdin.readChar()
      buffer.add(ch)
    except EOFError:
      break
    except IOError:
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
        stderr.writeLine("Error: No valid Content-Length found")
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
      except JsonParsingError:
        server.sendError(-32700, "Parse error", newJNull())
      except Exception as e:
        stderr.writeLine("Error processing message: " & e.msg)

proc main() {.async.} =
  # Handle command line arguments
  if paramCount() == 0:
    # Default: start with lsp-test-config.json
    let server = newLSPServer()
    stderr.writeLine(
      "Starting LSP Server with scenario: " &
        server.scenarioManager.currentScenario
    )
    await server.processInput()
    return

  if paramStr(1) == "--create-sample-config":
    let sm = ScenarioManager()
    sm.createSampleConfig()
    stderr.writeLine("Sample configuration created. Exiting.")
    return

  if paramStr(1) == "--config":
    if paramCount() < 2:
      stderr.writeLine("Error: --config requires a file path")
      stderr.writeLine("Usage:")
      stderr.writeLine("  lasm                                 # Start LSP server (requires lsp-test-config.json)")
      stderr.writeLine("  lasm --config <path>                 # Start LSP server with custom config file")
      stderr.writeLine("  lasm --create-sample-config          # Create sample configuration")
      return

    let configPath = paramStr(2)
    let server = newLSPServer(configPath)
    stderr.writeLine(
      "Starting LSP Server with scenario: " &
        server.scenarioManager.currentScenario
    )
    await server.processInput()
  else:
    stderr.writeLine("Error: Unknown option '" & paramStr(1) & "'")
    stderr.writeLine("Usage:")
    stderr.writeLine("  lasm                                 # Start LSP server (requires lsp-test-config.json)")
    stderr.writeLine("  lasm --config <path>                 # Start LSP server with custom config file")
    stderr.writeLine("  lasm --create-sample-config          # Create sample configuration")
    return

when isMainModule:
  waitFor main()
