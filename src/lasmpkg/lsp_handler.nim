import std/[sequtils, strutils, strformat, json, options]

import pkg/chronos

import scenario, logger
import protocol/types

type LSPHandler* = ref object
  documents*: Table[string, Document]
  scenarioManager*: ScenarioManager

proc newLSPHandler*(scenarioManager: ScenarioManager): LSPHandler =
  result = LSPHandler()
  result.documents = initTable[string, Document]()
  result.scenarioManager = scenarioManager

proc handleInitialize*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
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

  return
    %*{
      "capabilities": capabilities,
      "serverInfo": {"name": "LSP Test Server", "version": "0.1.0"},
    }

proc handleExecuteCommand*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[tuple[response: JsonNode, notifications: seq[JsonNode]]] {.async.} =
  let command = params["command"].getStr()
  let args =
    if params.hasKey("arguments"):
      params["arguments"]
    else:
      newJArray()

  var notifications: seq[JsonNode] = @[]

  case command
  of "lsptest.switchScenario":
    if args.len > 0:
      let scenarioName = args[0].getStr()
      if handler.scenarioManager.setScenario(scenarioName):
        let response = %*{"success": true}
        notifications.add(
          %*{
            "method": "window/showMessage",
            "params": {"type": 3, "message": "Switched to scenario: " & scenarioName},
          }
        )
        return (response, notifications)
      else:
        raise newException(LSPError, "Unknown scenario: " & scenarioName)
    else:
      raise newException(LSPError, "Missing scenario name argument")
  of "lsptest.listScenarios":
    let scenarios = handler.scenarioManager.listScenarios()
    let scenarioList = scenarios.map(
      proc(s: auto): JsonNode =
        %*{"name": s.name, "description": s.description}
    )
    let response = %scenarioList
    let names = scenarios
      .map(
        proc(s: auto): string =
          s.name
      )
      .join(", ")
    notifications.add(
      %*{
        "method": "window/showMessage",
        "params": {"type": 3, "message": "Available scenarios: " & names},
      }
    )
    return (response, notifications)
  of "lsptest.reloadConfig":
    if handler.scenarioManager.loadConfigFile(handler.scenarioManager.configPath):
      let response = %*{"success": true}
      notifications.add(
        %*{
          "method": "window/showMessage",
          "params": {"type": 3, "message": "Configuration reloaded"},
        }
      )
      return (response, notifications)
    else:
      raise newException(LSPError, "Failed to reload configuration")
  of "lsptest.createSampleConfig":
    handler.scenarioManager.createSampleConfig()
    let response = %*{"success": true}
    notifications.add(
      %*{
        "method": "window/showMessage",
        "params": {"type": 3, "message": "Sample configuration file created"},
      }
    )
    return (response, notifications)
  else:
    raise newException(LSPError, "Unknown command: " & command)

proc handleDidOpen*(
    handler: LSPHandler, params: JsonNode
): Future[seq[JsonNode]] {.async.} =
  let
    textDocument = params["textDocument"]
    uri = textDocument["uri"].getStr
    content = textDocument["text"].getStr
    version = textDocument["version"].getInt

  handler.documents[uri] = Document(content: content, version: version)

  return
    @[
      %*{
        "method": "window/logMessage",
        "params":
          {"type": 5, "message": fmt"Received textDocument/didOpen notify: {params}"},
      }
    ]

proc handleDidChange*(
    handler: LSPHandler, params: JsonNode
): Future[seq[JsonNode]] {.async.} =
  let
    textDocument = params["textDocument"]
    uri = textDocument["uri"].getStr()
    version = textDocument["version"].getInt()
    contentChanges = params["contentChanges"]

  if uri in handler.documents:
    for change in contentChanges.items():
      if change.hasKey("range"):
        handler.documents[uri].content = change["text"].getStr()
      else:
        handler.documents[uri].content = change["text"].getStr()

    handler.documents[uri].version = version

  return
    @[
      %*{
        "method": "window/logMessage",
        "params":
          {"type": 5, "message": fmt"Received textDocument/didChange notify: {params}"},
      }
    ]

proc handleDidClose*(
    handler: LSPHandler, params: JsonNode
): Future[seq[JsonNode]] {.async.} =
  let
    textDocument = params["textDocument"]
    uri = textDocument["uri"].getStr()
  handler.documents.del(uri)

  return
    @[
      %*{
        "method": "window/logMessage",
        "params":
          {"type": 5, "message": fmt"Received textDocument/didClose notify: {params}"},
      }
    ]

proc handleHover*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  if scenario.delays.hover > 0:
    await sleepAsync(scenario.delays.hover.milliseconds)

  if not scenario.hover.enabled:
    return newJNull()

  if "hover" in scenario.errors:
    let error = scenario.errors["hover"]
    raise newException(LSPError, error.message)

  let position = params["position"]

  let hover = Hover()
  if scenario.hover.content.isSome:
    hover.contents = some(
      %*{
        "kind": scenario.hover.content.get.kind,
        "value": scenario.hover.content.get.message,
      }
    )
  elif scenario.hover.contents.len > 0:
    var contentsArray = newJArray()
    for hoverContent in scenario.hover.contents:
      contentsArray.add(%*{"kind": hoverContent.kind, "value": hoverContent.message})
    hover.contents = some(%contentsArray)
  else:
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

  return %hover

proc handleInitialized*(handler: LSPHandler): seq[JsonNode] =
  return
    @[
      %*{
        "method": "window/showMessage",
        "params": {
          "type": 3,
          "message":
            "LSP Server ready! Current scenario: " &
            handler.scenarioManager.currentScenario,
        },
      }
    ]
