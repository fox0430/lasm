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
    completion: CompletionConfig(enabled: true, isIncomplete: false, items: @[]),
    delays: DelayConfig(hover: 0, completion: 0),
    errors: initTable[string, ErrorConfig](),
  )

  # Add test scenario with hover content
  result.scenarios["test"] = Scenario(
    name: "Test Scenario",
    hover: HoverConfig(enabled: true, content: none(HoverContent), contents: @[]),
    completion: CompletionConfig(
      enabled: true,
      isIncomplete: false,
      items:
        @[
          CompletionContent(
            label: "testFunc",
            kind: 3, # Function
            detail: some("func testFunc(x: int): string"),
            documentation: some("Test function for completion"),
            insertText: some("testFunc(${1:x})"),
            sortText: some("1"),
          ),
          CompletionContent(
            label: "testVar",
            kind: 6, # Variable
            detail: some("var testVar: bool"),
            documentation: some("Test variable"),
          ),
        ],
    ),
    delays: DelayConfig(hover: 50, completion: 30),
    errors: initTable[string, ErrorConfig](),
  )

  # Add error scenario
  result.scenarios["error"] = Scenario(
    name: "Error Test",
    hover: HoverConfig(enabled: true),
    completion: CompletionConfig(enabled: true, isIncomplete: false, items: @[]),
    delays: DelayConfig(hover: 0, completion: 0),
    errors: {
      "hover": ErrorConfig(code: -32603, message: "Test error"),
      "completion": ErrorConfig(code: -32602, message: "Completion error"),
    }.toTable,
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
    check commands.len == 5
    var foundCommands = 0
    for cmd in commands:
      if cmd.getStr() in [
        "lsptest.switchScenario", "lsptest.listScenarios", "lsptest.reloadConfig",
        "lsptest.createSampleConfig", "lsptest.listOpenFiles",
      ]:
        foundCommands += 1
    check foundCommands == 5

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

  test "handleCompletion with enabled completion":
    let sm = createTestScenarioManager()
    sm.currentScenario = "test" # Has completion items
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 5, "character": 10},
      }

    let response = waitFor handler.handleCompletion(%1, params)

    check response.hasKey("isIncomplete")
    check response["isIncomplete"].getBool() == false
    check response.hasKey("items")

    let items = response["items"]
    check items.kind == JArray
    check items.len == 2

    # Check first item (testFunc)
    let item1 = items[0]
    check item1["label"].getStr() == "testFunc"
    check item1["kind"].getInt() == 3
    check item1["detail"].getStr() == "func testFunc(x: int): string"
    check item1["documentation"].getStr() == "Test function for completion"
    check item1["insertText"].getStr() == "testFunc(${1:x})"
    check item1["sortText"].getStr() == "1"

    # Check second item (testVar)
    let item2 = items[1]
    check item2["label"].getStr() == "testVar"
    check item2["kind"].getInt() == 6
    check item2["detail"].getStr() == "var testVar: bool"
    check item2["documentation"].getStr() == "Test variable"
    check item2["insertText"].getStr() == "testVar" # Defaults to label

  test "handleCompletion with disabled completion":
    let sm = createTestScenarioManager()
    # Set scenario with disabled completion
    sm.scenarios["disabled"] = Scenario(
      name: "Disabled Completion",
      hover: HoverConfig(enabled: true),
      completion: CompletionConfig(enabled: false),
      delays: DelayConfig(hover: 0, completion: 0),
      errors: initTable[string, ErrorConfig](),
    )
    sm.currentScenario = "disabled"

    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 0},
      }

    let response = waitFor handler.handleCompletion(%1, params)

    check response.kind == JNull

  test "handleCompletion with error scenario":
    let sm = createTestScenarioManager()
    sm.currentScenario = "error"
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 0},
      }

    expect LSPError:
      discard waitFor handler.handleCompletion(%1, params)

  test "handleCompletion with delay":
    let sm = createTestScenarioManager()
    sm.currentScenario = "test" # This scenario has 30ms delay for completion
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 0},
      }

    let startTime = getTime()
    let response = waitFor handler.handleCompletion(%1, params)
    let endTime = getTime()

    # Check that some delay occurred (should be at least 20ms due to 30ms delay)
    let duration = (endTime - startTime).inMilliseconds
    check duration >= 20

    check response.hasKey("items")

  test "handleCompletion with incomplete list":
    let sm = createTestScenarioManager()
    # Set scenario with incomplete completion list
    sm.scenarios["incomplete"] = Scenario(
      name: "Incomplete Completion",
      hover: HoverConfig(enabled: true),
      completion: CompletionConfig(
        enabled: true,
        isIncomplete: true,
        items:
          @[
            CompletionContent(
              label: "partialItem", kind: 1 # Text
            )
          ],
      ),
      delays: DelayConfig(hover: 0, completion: 0),
      errors: initTable[string, ErrorConfig](),
    )
    sm.currentScenario = "incomplete"

    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 0},
      }

    let response = waitFor handler.handleCompletion(%1, params)

    check response["isIncomplete"].getBool() == true
    check response["items"].len == 1
    check response["items"][0]["label"].getStr() == "partialItem"

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

  test "handleExecuteCommand - listOpenFiles with no files":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    let params = %*{"command": "lsptest.listOpenFiles"}

    let (response, notifications) = waitFor handler.handleExecuteCommand(%1, params)

    check response.kind == JArray
    check response.len == 0
    check notifications.len == 1
    check notifications[0]["method"].getStr() == "window/showMessage"
    check notifications[0]["params"]["message"].getStr() == "No files currently open"

  test "handleExecuteCommand - listOpenFiles with multiple files":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    # Add some test documents
    handler.documents["file:///test1.nim"] = Document(content: "content1", version: 1)
    handler.documents["file:///test2.py"] =
      Document(content: "longer content", version: 2)

    let params = %*{"command": "lsptest.listOpenFiles"}

    let (response, notifications) = waitFor handler.handleExecuteCommand(%1, params)

    check response.kind == JArray
    check response.len == 2
    check notifications.len == 1
    check notifications[0]["method"].getStr() == "window/showMessage"
    check notifications[0]["params"]["message"].getStr().contains("Open files (2):")
    check notifications[0]["params"]["message"].getStr().contains("test1.nim")
    check notifications[0]["params"]["message"].getStr().contains("test2.py")

    # Check response structure
    var foundTest1 = false
    var foundTest2 = false
    for item in response:
      if item["fileName"].getStr() == "test1.nim":
        foundTest1 = true
        check item["version"].getInt() == 1
        check item["contentLength"].getInt() == 8
      elif item["fileName"].getStr() == "test2.py":
        foundTest2 = true
        check item["version"].getInt() == 2
        check item["contentLength"].getInt() == 14
    check foundTest1 and foundTest2

  test "improved multi-file logging messages":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    # Test didOpen with count
    let openParams =
      %*{
        "textDocument": {
          "uri": "file:///test.nim",
          "languageId": "nim",
          "version": 1,
          "text": "echo \"hello\"",
        }
      }
    let openNotifications = waitFor handler.handleDidOpen(openParams)
    check openNotifications[0]["params"]["message"].getStr().contains(
      "(total: 1 files)"
    )

    # Test didChange with content length
    let changeParams =
      %*{
        "textDocument": {"uri": "file:///test.nim", "version": 2},
        "contentChanges": [{"text": "new content"}],
      }
    let changeNotifications = waitFor handler.handleDidChange(changeParams)
    check changeNotifications[0]["params"]["message"].getStr().contains(
      "(v2, 11 chars)"
    )

    # Test didClose with remaining count
    let closeParams = %*{"textDocument": {"uri": "file:///test.nim"}}
    let closeNotifications = waitFor handler.handleDidClose(closeParams)
    check closeNotifications[0]["params"]["message"].getStr().contains(
      "(remaining: 0 files)"
    )

  test "didChange and didClose with non-existent files":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    # Test didChange on non-existent file
    let changeParams =
      %*{
        "textDocument": {"uri": "file:///nonexistent.nim", "version": 1},
        "contentChanges": [{"text": "content"}],
      }
    let changeNotifications = waitFor handler.handleDidChange(changeParams)
    check changeNotifications[0]["params"]["type"].getInt() == 2 # Warning
    check changeNotifications[0]["params"]["message"].getStr().contains(
      "Warning: Attempted to update unopened document"
    )

    # Test didClose on non-existent file
    let closeParams = %*{"textDocument": {"uri": "file:///nonexistent.nim"}}
    let closeNotifications = waitFor handler.handleDidClose(closeParams)
    check closeNotifications[0]["params"]["type"].getInt() == 2 # Warning
    check closeNotifications[0]["params"]["message"].getStr().contains(
      "Warning: Attempted to close unopened document"
    )

  test "handleDidChangeConfiguration with no settings":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    # Test with empty params
    let params = %*{}

    let notifications = waitFor handler.handleDidChangeConfiguration(params)

    check notifications.len == 1
    check notifications[0]["params"]["message"].getStr() ==
      "Received workspace/didChangeConfiguration notification"
    check sm.currentScenario == "default" # Should remain unchanged

  test "handleDidChangeConfiguration with non-lsptest settings":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    # Test with settings that don't include lsptest
    let params = %*{"settings": {"other": {"config": "value"}}}

    let notifications = waitFor handler.handleDidChangeConfiguration(params)

    check notifications.len == 1
    check notifications[0]["params"]["message"].getStr() ==
      "Received workspace/didChangeConfiguration notification"
    check sm.currentScenario == "default" # Should remain unchanged
