import std/[unittest, json, tables, options, times, strutils]

import pkg/chronos

import ../src/lasmpkg/[lsp_handler, scenario, logger]
import ../src/lasmpkg/protocol/types

proc createTestScenarioManager(): ScenarioManager =
  result = ScenarioManager()
  result.currentScenario = "default"
  result.scenarios = initTable[string, Scenario]()
  result.configPath = "test_config.json"

  # Add default scenario
  result.scenarios["default"] = Scenario(
    name: "Default Test",
    hover: HoverConfig(enabled: true, content: none(HoverContent), contents: @[]),
    delays: DelayConfig(hover: 0),
    errors: initTable[string, ErrorConfig](),
  )

  # Add test scenario with hover content
  result.scenarios["test"] = Scenario(
    name: "Test Scenario",
    hover: HoverConfig(enabled: true, content: none(HoverContent), contents: @[]),
    delays: DelayConfig(hover: 50),
    errors: initTable[string, ErrorConfig](),
  )

  # Add error scenario
  result.scenarios["error"] = Scenario(
    name: "Error Test",
    hover: HoverConfig(enabled: true),
    delays: DelayConfig(hover: 0),
    errors: {"hover": ErrorConfig(code: -32603, message: "Test error")}.toTable,
  )

suite "lsp_handler module tests":
  setup:
    # Initialize logger for tests - disable logging
    setGlobalLogger(newFileLogger(enabled = false))

  test "LSPHandler initialization":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    check handler.documents.len == 0
    check handler.scenarioManager == sm

  test "handleInitialize returns proper capabilities":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    let params =
      %*{"processId": 1234, "clientInfo": {"name": "test-client"}, "capabilities": {}}

    let response = waitFor handler.handleInitialize(%1, params)

    check response.hasKey("capabilities")
    check response.hasKey("serverInfo")

    let capabilities = response["capabilities"]
    check capabilities.hasKey("textDocumentSync")
    check capabilities.hasKey("completionProvider")
    check capabilities.hasKey("hoverProvider")
    check capabilities.hasKey("executeCommandProvider")
    check capabilities.hasKey("diagnosticProvider")

    check capabilities["hoverProvider"].getBool() == true

    let serverInfo = response["serverInfo"]
    check serverInfo["name"].getStr() == "LSP Test Server"
    check serverInfo["version"].getStr() == "0.1.0"

    let executeCommandProvider = capabilities["executeCommandProvider"]
    check executeCommandProvider.hasKey("commands")
    let commands = executeCommandProvider["commands"]
    check commands.len == 4
    var foundCommands = 0
    for cmd in commands:
      if cmd.getStr() in [
        "lsptest.switchScenario", "lsptest.listScenarios", "lsptest.reloadConfig",
        "lsptest.createSampleConfig",
      ]:
        foundCommands += 1
    check foundCommands == 4

  test "handleExecuteCommand - switchScenario success":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    let params = %*{"command": "lsptest.switchScenario", "arguments": ["test"]}

    let (response, notifications) = waitFor handler.handleExecuteCommand(%1, params)

    check response["success"].getBool() == true
    check notifications.len == 1
    check notifications[0]["method"].getStr() == "window/showMessage"
    check notifications[0]["params"]["message"].getStr().contains(
      "Switched to scenario: test"
    )
    check sm.currentScenario == "test"

  test "handleExecuteCommand - switchScenario with invalid scenario":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    let params = %*{"command": "lsptest.switchScenario", "arguments": ["nonexistent"]}

    expect LSPError:
      discard waitFor handler.handleExecuteCommand(%1, params)

  test "handleExecuteCommand - switchScenario missing arguments":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    let params = %*{"command": "lsptest.switchScenario", "arguments": []}

    expect LSPError:
      discard waitFor handler.handleExecuteCommand(%1, params)

  test "handleExecuteCommand - listScenarios":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    let params = %*{"command": "lsptest.listScenarios"}

    let (response, notifications) = waitFor handler.handleExecuteCommand(%1, params)

    check response.kind == JArray
    check response.len >= 2 # At least default and test scenarios
    check notifications.len == 1
    check notifications[0]["method"].getStr() == "window/showMessage"
    check notifications[0]["params"]["message"].getStr().contains(
      "Available scenarios:"
    )

  test "handleExecuteCommand - createSampleConfig":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    let params = %*{"command": "lsptest.createSampleConfig"}

    let (response, notifications) = waitFor handler.handleExecuteCommand(%1, params)

    check response["success"].getBool() == true
    check notifications.len == 1
    check notifications[0]["method"].getStr() == "window/showMessage"
    check notifications[0]["params"]["message"].getStr().contains(
      "Sample configuration file created"
    )

  test "handleExecuteCommand - unknown command":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    let params = %*{"command": "unknown.command"}

    expect LSPError:
      discard waitFor handler.handleExecuteCommand(%1, params)

  test "handleDidOpen adds document":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {
          "uri": "file:///test.nim",
          "languageId": "nim",
          "version": 1,
          "text": "echo \"hello\"",
        }
      }

    let notifications = waitFor handler.handleDidOpen(params)

    check handler.documents.len == 1
    check "file:///test.nim" in handler.documents
    let doc = handler.documents["file:///test.nim"]
    check doc.content == "echo \"hello\""
    check doc.version == 1

    check notifications.len == 1
    check notifications[0]["method"].getStr() == "window/logMessage"

  test "handleDidChange updates document":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    # First add a document
    handler.documents["file:///test.nim"] = Document(content: "old content", version: 1)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim", "version": 2},
        "contentChanges": [{"text": "new content"}],
      }

    let notifications = waitFor handler.handleDidChange(params)

    check handler.documents.len == 1
    let doc = handler.documents["file:///test.nim"]
    check doc.content == "new content"
    check doc.version == 2

    check notifications.len == 1
    check notifications[0]["method"].getStr() == "window/logMessage"

  test "handleDidChange with range-based change":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    # First add a document
    handler.documents["file:///test.nim"] = Document(content: "old content", version: 1)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim", "version": 2},
        "contentChanges": [
          {
            "range":
              {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 3}},
            "text": "updated content",
          }
        ],
      }

    discard waitFor handler.handleDidChange(params)

    check handler.documents.len == 1
    let doc = handler.documents["file:///test.nim"]
    check doc.content == "updated content"
    check doc.version == 2

  test "handleDidChange for non-existent document":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///nonexistent.nim", "version": 1},
        "contentChanges": [{"text": "new content"}],
      }

    let notifications = waitFor handler.handleDidChange(params)

    check handler.documents.len == 0
    check notifications.len == 1

  test "handleDidClose removes document":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    # First add a document
    handler.documents["file:///test.nim"] =
      Document(content: "test content", version: 1)

    let params = %*{"textDocument": {"uri": "file:///test.nim"}}

    let notifications = waitFor handler.handleDidClose(params)

    check handler.documents.len == 0
    check "file:///test.nim" notin handler.documents

    check notifications.len == 1
    check notifications[0]["method"].getStr() == "window/logMessage"

  test "handleHover with enabled hover":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 5, "character": 10},
      }

    let response = waitFor handler.handleHover(%1, params)

    check response.hasKey("contents")
    check response.hasKey("range")

    let range = response["range"]
    check range["start"]["line"].getInt() == 5
    check range["start"]["character"].getInt() == 10
    check range["end"]["line"].getInt() == 5
    check range["end"]["character"].getInt() == 10

  test "handleHover with disabled hover":
    let sm = createTestScenarioManager()
    # Set scenario with disabled hover
    sm.scenarios["disabled"] = Scenario(
      name: "Disabled Hover",
      hover: HoverConfig(enabled: false),
      delays: DelayConfig(hover: 0),
      errors: initTable[string, ErrorConfig](),
    )
    sm.currentScenario = "disabled"

    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 0},
      }

    let response = waitFor handler.handleHover(%1, params)

    check response.kind == JNull

  test "handleHover with error scenario":
    let sm = createTestScenarioManager()
    sm.currentScenario = "error"
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 0},
      }

    expect LSPError:
      discard waitFor handler.handleHover(%1, params)

  test "handleHover with delay":
    let sm = createTestScenarioManager()
    sm.currentScenario = "test" # This scenario has 50ms delay
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 0},
      }

    let startTime = getTime()
    let response = waitFor handler.handleHover(%1, params)
    let endTime = getTime()

    # Check that some delay occurred (should be at least 40ms due to 50ms delay)
    let duration = (endTime - startTime).inMilliseconds
    check duration >= 40

    check response.hasKey("contents")

  test "handleInitialized returns notification":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    let notifications = handler.handleInitialized()

    check notifications.len == 1
    check notifications[0]["method"].getStr() == "window/showMessage"
    check notifications[0]["params"]["type"].getInt() == 3
    check notifications[0]["params"]["message"].getStr().contains(
      "LSP Server ready! Current scenario: default"
    )

  test "multiple document operations":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    # Open multiple documents
    var params1 =
      %*{
        "textDocument": {
          "uri": "file:///test1.nim",
          "languageId": "nim",
          "version": 1,
          "text": "content1",
        }
      }
    discard waitFor handler.handleDidOpen(params1)

    var params2 =
      %*{
        "textDocument": {
          "uri": "file:///test2.nim",
          "languageId": "nim",
          "version": 1,
          "text": "content2",
        }
      }
    discard waitFor handler.handleDidOpen(params2)

    check handler.documents.len == 2
    check "file:///test1.nim" in handler.documents
    check "file:///test2.nim" in handler.documents

    # Close one document
    let closeParams = %*{"textDocument": {"uri": "file:///test1.nim"}}
    discard waitFor handler.handleDidClose(closeParams)

    check handler.documents.len == 1
    check "file:///test1.nim" notin handler.documents
    check "file:///test2.nim" in handler.documents
