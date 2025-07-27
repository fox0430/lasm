import std/[unittest, json, tables, options, times, strutils, sequtils]

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
    diagnostics: DiagnosticConfig(enabled: false, diagnostics: @[]),
    semanticTokens: SemanticTokensConfig(enabled: false, tokens: @[]),
    inlayHint: InlayHintConfig(enabled: false, hints: @[]),
    declaration: DeclarationConfig(
      enabled: false,
      location: DeclarationContent(
        uri: "",
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 0)
        ),
      ),
      locations: @[],
    ),
    definition: DefinitionConfig(
      enabled: false,
      location: DefinitionContent(
        uri: "",
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 0)
        ),
      ),
      locations: @[],
    ),
    typeDefinition: TypeDefinitionConfig(
      enabled: false,
      location: TypeDefinitionContent(
        uri: "",
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 0)
        ),
      ),
      locations: @[],
    ),
    delays: DelayConfig(
      hover: 0,
      completion: 0,
      diagnostics: 0,
      semanticTokens: 0,
      inlayHint: 0,
      declaration: 0,
      definition: 0,
      typeDefinition: 0,
      implementation: 0,
    ),
    implementation: ImplementationConfig(
      enabled: false,
      location: ImplementationContent(
        uri: "",
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 0)
        ),
      ),
      locations: @[],
    ),
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
    diagnostics: DiagnosticConfig(enabled: false, diagnostics: @[]),
    semanticTokens: SemanticTokensConfig(
      enabled: true,
      tokens:
        @[
          uinteger(0),
          uinteger(0),
          uinteger(8),
          uinteger(14),
          uinteger(0), # function keyword  
          uinteger(0),
          uinteger(9),
          uinteger(4),
          uinteger(12),
          uinteger(1), # function name
          uinteger(1),
          uinteger(2),
          uinteger(3),
          uinteger(6),
          uinteger(0), # variable
        ],
    ),
    inlayHint: InlayHintConfig(
      enabled: true,
      hints:
        @[
          InlayHintContent(
            position: Position(line: 1, character: 15),
            label: ": string",
            kind: some(1),
            tooltip: some("Parameter type hint"),
            paddingLeft: some(false),
            paddingRight: some(false),
            textEdits: @[],
          ),
          InlayHintContent(
            position: Position(line: 5, character: 20),
            label: " -> bool",
            kind: some(1),
            tooltip: some("Return type hint"),
            paddingLeft: some(true),
            paddingRight: some(false),
            textEdits: @[],
          ),
        ],
    ),
    declaration: DeclarationConfig(
      enabled: true,
      location: DeclarationContent(
        uri: "file:///test_declaration.nim",
        range: Range(
          start: Position(line: 5, character: 10),
          `end`: Position(line: 5, character: 20),
        ),
      ),
      locations:
        @[
          DeclarationContent(
            uri: "file:///multiple1.nim",
            range: Range(
              start: Position(line: 3, character: 5),
              `end`: Position(line: 3, character: 15),
            ),
          ),
          DeclarationContent(
            uri: "file:///multiple2.nim",
            range: Range(
              start: Position(line: 7, character: 0),
              `end`: Position(line: 7, character: 10),
            ),
          ),
        ],
    ),
    definition: DefinitionConfig(
      enabled: true,
      location: DefinitionContent(
        uri: "file:///test_definition.nim",
        range: Range(
          start: Position(line: 15, character: 2),
          `end`: Position(line: 15, character: 12),
        ),
      ),
      locations:
        @[
          DefinitionContent(
            uri: "file:///implementation1.nim",
            range: Range(
              start: Position(line: 10, character: 4),
              `end`: Position(line: 10, character: 14),
            ),
          ),
          DefinitionContent(
            uri: "file:///implementation2.nim",
            range: Range(
              start: Position(line: 20, character: 8),
              `end`: Position(line: 20, character: 18),
            ),
          ),
        ],
    ),
    typeDefinition: TypeDefinitionConfig(
      enabled: true,
      location: TypeDefinitionContent(
        uri: "file:///test_type_definition.nim",
        range: Range(
          start: Position(line: 8, character: 0),
          `end`: Position(line: 8, character: 10),
        ),
      ),
      locations:
        @[
          TypeDefinitionContent(
            uri: "file:///type_definition1.nim",
            range: Range(
              start: Position(line: 5, character: 0),
              `end`: Position(line: 5, character: 15),
            ),
          ),
          TypeDefinitionContent(
            uri: "file:///type_definition2.nim",
            range: Range(
              start: Position(line: 12, character: 5),
              `end`: Position(line: 12, character: 20),
            ),
          ),
        ],
    ),
    delays: DelayConfig(
      hover: 50,
      completion: 30,
      diagnostics: 0,
      semanticTokens: 25,
      inlayHint: 40,
      declaration: 60,
      definition: 55,
      typeDefinition: 45,
      implementation: 50,
    ),
    implementation: ImplementationConfig(
      enabled: true,
      location: ImplementationContent(
        uri: "file:///test_implementation.nim",
        range: Range(
          start: Position(line: 30, character: 0),
          `end`: Position(line: 30, character: 20),
        ),
      ),
      locations:
        @[
          ImplementationContent(
            uri: "file:///implementation1.nim",
            range: Range(
              start: Position(line: 25, character: 0),
              `end`: Position(line: 25, character: 15),
            ),
          ),
          ImplementationContent(
            uri: "file:///implementation2.nim",
            range: Range(
              start: Position(line: 35, character: 2),
              `end`: Position(line: 35, character: 17),
            ),
          ),
        ],
    ),
    errors: initTable[string, ErrorConfig](),
  )

  # Add error scenario
  result.scenarios["error"] = Scenario(
    name: "Error Test",
    hover: HoverConfig(enabled: true),
    completion: CompletionConfig(enabled: true, isIncomplete: false, items: @[]),
    diagnostics: DiagnosticConfig(enabled: true, diagnostics: @[]),
    semanticTokens: SemanticTokensConfig(enabled: true, tokens: @[]),
    inlayHint: InlayHintConfig(enabled: true, hints: @[]),
    declaration: DeclarationConfig(
      enabled: true,
      location: DeclarationContent(
        uri: "",
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 0)
        ),
      ),
      locations: @[],
    ),
    definition: DefinitionConfig(
      enabled: true,
      location: DefinitionContent(
        uri: "",
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 0)
        ),
      ),
      locations: @[],
    ),
    typeDefinition: TypeDefinitionConfig(
      enabled: false,
      location: TypeDefinitionContent(
        uri: "",
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 0)
        ),
      ),
      locations: @[],
    ),
    delays: DelayConfig(
      hover: 0,
      completion: 0,
      diagnostics: 0,
      semanticTokens: 0,
      inlayHint: 0,
      declaration: 0,
      definition: 0,
      typeDefinition: 0,
      implementation: 0,
    ),
    implementation: ImplementationConfig(
      enabled: true,
      location: ImplementationContent(
        uri: "",
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 0)
        ),
      ),
      locations: @[],
    ),
    errors: {
      "hover": ErrorConfig(code: -32603, message: "Test error"),
      "completion": ErrorConfig(code: -32602, message: "Completion error"),
      "diagnostics": ErrorConfig(code: -32603, message: "Diagnostic error"),
      "semanticTokens": ErrorConfig(code: -32603, message: "Semantic tokens error"),
      "inlayHint": ErrorConfig(code: -32603, message: "Inlay hint error"),
      "declaration": ErrorConfig(code: -32603, message: "Declaration error"),
      "definition": ErrorConfig(code: -32603, message: "Definition error"),
      "typeDefinition": ErrorConfig(code: -32603, message: "Type definition error"),
      "implementation": ErrorConfig(code: -32603, message: "Implementation error"),
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
    check capabilities.hasKey("semanticTokensProvider")
    check capabilities.hasKey("inlayHintProvider")
    check capabilities.hasKey("declarationProvider")
    check capabilities.hasKey("definitionProvider")
    check capabilities.hasKey("typeDefinitionProvider")
    check capabilities.hasKey("implementationProvider")

    check capabilities["hoverProvider"].getBool() == true
    check capabilities["declarationProvider"].getBool() == true
    check capabilities["definitionProvider"].getBool() == true
    check capabilities["typeDefinitionProvider"].getBool() == true
    check capabilities["implementationProvider"].getBool() == true

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

    # Should have: log message + publishDiagnostics (if enabled) + diagnostic log (if enabled)
    check notifications.len >= 1
    # First notification should be the log message
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

    # Should have: log message + publishDiagnostics (if enabled) + diagnostic log (if enabled)
    check notifications.len >= 1
    # First notification should be the log message
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

    # Should have: log message + clear diagnostics notification
    check notifications.len >= 1
    # Should contain at least a log message
    var hasLogMessage = false
    for notif in notifications:
      if notif["method"].getStr() == "window/logMessage":
        hasLogMessage = true
        break
    check hasLogMessage

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
      completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
      diagnostics: DiagnosticConfig(enabled: false, diagnostics: @[]),
      semanticTokens: SemanticTokensConfig(enabled: false, tokens: @[]),
      inlayHint: InlayHintConfig(enabled: false, hints: @[]),
      delays: DelayConfig(
        hover: 0,
        completion: 0,
        diagnostics: 0,
        semanticTokens: 0,
        inlayHint: 0,
        declaration: 0,
        definition: 0,
        typeDefinition: 0,
      ),
      typeDefinition: TypeDefinitionConfig(
        enabled: false,
        location: TypeDefinitionContent(
          uri: "",
          range: Range(
            start: Position(line: 0, character: 0),
            `end`: Position(line: 0, character: 0),
          ),
        ),
        locations: @[],
      ),
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
      completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
      diagnostics: DiagnosticConfig(enabled: false, diagnostics: @[]),
      semanticTokens: SemanticTokensConfig(enabled: false, tokens: @[]),
      inlayHint: InlayHintConfig(enabled: false, hints: @[]),
      delays: DelayConfig(
        hover: 0,
        completion: 0,
        diagnostics: 0,
        semanticTokens: 0,
        inlayHint: 0,
        declaration: 0,
        definition: 0,
        typeDefinition: 0,
      ),
      typeDefinition: TypeDefinitionConfig(
        enabled: false,
        location: TypeDefinitionContent(
          uri: "",
          range: Range(
            start: Position(line: 0, character: 0),
            `end`: Position(line: 0, character: 0),
          ),
        ),
        locations: @[],
      ),
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
      diagnostics: DiagnosticConfig(enabled: false, diagnostics: @[]),
      semanticTokens: SemanticTokensConfig(enabled: false, tokens: @[]),
      inlayHint: InlayHintConfig(enabled: false, hints: @[]),
      delays: DelayConfig(
        hover: 0,
        completion: 0,
        diagnostics: 0,
        semanticTokens: 0,
        inlayHint: 0,
        declaration: 0,
        definition: 0,
        typeDefinition: 0,
      ),
      typeDefinition: TypeDefinitionConfig(
        enabled: false,
        location: TypeDefinitionContent(
          uri: "",
          range: Range(
            start: Position(line: 0, character: 0),
            `end`: Position(line: 0, character: 0),
          ),
        ),
        locations: @[],
      ),
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

  test "handleSemanticTokensFull with enabled semantic tokens":
    let sm = createTestScenarioManager()
    sm.currentScenario = "test" # Has semantic tokens configured
    let handler = newLSPHandler(sm)

    # Add a document first
    handler.documents["file:///test.nim"] =
      Document(content: "function test() {}", version: 1)

    let params = %*{"textDocument": {"uri": "file:///test.nim"}}

    let response = waitFor handler.handleSemanticTokensFull(%1, params)

    check response.hasKey("resultId")
    check response.hasKey("data")
    check response["resultId"].getStr().startsWith("result-")

    let data = response["data"]
    check data.kind == JArray
    check data.len == 15 # 3 tokens * 5 values each

    # Check first token (function keyword)
    check data[0].getInt() == 0 # deltaLine
    check data[1].getInt() == 0 # deltaStart
    check data[2].getInt() == 8 # length
    check data[3].getInt() == 14 # tokenType (keyword)
    check data[4].getInt() == 0 # tokenModifiers

  test "handleSemanticTokensFull with disabled semantic tokens":
    let sm = createTestScenarioManager()
    # Use default scenario which has semantic tokens disabled
    let handler = newLSPHandler(sm)

    let params = %*{"textDocument": {"uri": "file:///test.nim"}}

    let response = waitFor handler.handleSemanticTokensFull(%1, params)

    check response.kind == JNull

  test "handleSemanticTokensFull with error scenario":
    let sm = createTestScenarioManager()
    sm.currentScenario = "error"
    let handler = newLSPHandler(sm)

    let params = %*{"textDocument": {"uri": "file:///test.nim"}}

    expect LSPError:
      discard waitFor handler.handleSemanticTokensFull(%1, params)

  test "handleSemanticTokensFull with delay":
    let sm = createTestScenarioManager()
    sm.currentScenario = "test" # This scenario has 25ms delay for semantic tokens
    let handler = newLSPHandler(sm)

    # Add a document first
    handler.documents["file:///test.nim"] =
      Document(content: "function test() {}", version: 1)

    let params = %*{"textDocument": {"uri": "file:///test.nim"}}

    let startTime = getTime()
    let response = waitFor handler.handleSemanticTokensFull(%1, params)
    let endTime = getTime()

    # Check that some delay occurred (should be at least 20ms due to 25ms delay)
    let duration = (endTime - startTime).inMilliseconds
    check duration >= 20

    check response.hasKey("data")

  test "handleSemanticTokensFull with non-existent document":
    let sm = createTestScenarioManager()
    sm.currentScenario = "test"
    let handler = newLSPHandler(sm)

    let params = %*{"textDocument": {"uri": "file:///nonexistent.nim"}}

    let response = waitFor handler.handleSemanticTokensFull(%1, params)

    check response.hasKey("resultId")
    check response.hasKey("data")
    check response["resultId"].getStr() == "empty"
    check response["data"].len == 0

  test "handleSemanticTokensFull with default token generation":
    let sm = createTestScenarioManager()
    # Create scenario with semantic tokens enabled but no custom tokens
    sm.scenarios["no_tokens"] = Scenario(
      name: "No Custom Tokens",
      hover: HoverConfig(enabled: true),
      completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
      diagnostics: DiagnosticConfig(enabled: false, diagnostics: @[]),
      semanticTokens: SemanticTokensConfig(enabled: true, tokens: @[]),
      delays: DelayConfig(
        hover: 0,
        completion: 0,
        diagnostics: 0,
        semanticTokens: 0,
        inlayHint: 0,
        declaration: 0,
        definition: 0,
        typeDefinition: 0,
      ),
      typeDefinition: TypeDefinitionConfig(
        enabled: false,
        location: TypeDefinitionContent(
          uri: "",
          range: Range(
            start: Position(line: 0, character: 0),
            `end`: Position(line: 0, character: 0),
          ),
        ),
        locations: @[],
      ),
      errors: initTable[string, ErrorConfig](),
    )
    sm.currentScenario = "no_tokens"
    let handler = newLSPHandler(sm)

    # Add a document first
    handler.documents["file:///test.nim"] =
      Document(content: "function test() {}", version: 1)

    let params = %*{"textDocument": {"uri": "file:///test.nim"}}

    let response = waitFor handler.handleSemanticTokensFull(%1, params)

    check response.hasKey("data")
    let data = response["data"]
    check data.len == 20 # Default sample has 4 tokens * 5 values each

  test "handleSemanticTokensRange with enabled semantic tokens":
    let sm = createTestScenarioManager()
    sm.currentScenario = "test"
    let handler = newLSPHandler(sm)

    # Add a document first
    handler.documents["file:///test.nim"] =
      Document(content: "function test() {}", version: 1)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "range":
          {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 18}},
      }

    let response = waitFor handler.handleSemanticTokensRange(%1, params)

    check response.hasKey("resultId")
    check response.hasKey("data")

    let data = response["data"]
    check data.kind == JArray
    check data.len == 15 # Same as full for this simple implementation

  test "handleSemanticTokensRange with disabled semantic tokens":
    let sm = createTestScenarioManager()
    # Use default scenario which has semantic tokens disabled
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "range":
          {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 10}},
      }

    let response = waitFor handler.handleSemanticTokensRange(%1, params)

    check response.kind == JNull

  test "handleSemanticTokensRange with delay":
    let sm = createTestScenarioManager()
    sm.currentScenario = "test" # This scenario has 25ms delay for semantic tokens
    let handler = newLSPHandler(sm)

    # Add a document first
    handler.documents["file:///test.nim"] =
      Document(content: "function test() {}", version: 1)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "range":
          {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 18}},
      }

    let startTime = getTime()
    let response = waitFor handler.handleSemanticTokensRange(%1, params)
    let endTime = getTime()

    # Check that some delay occurred (should be at least 20ms due to 25ms delay)
    let duration = (endTime - startTime).inMilliseconds
    check duration >= 20

    check response.hasKey("data")

  test "semantic tokens capability in initialization":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    let params = %*{"processId": 1234, "capabilities": {}}
    let response = waitFor handler.handleInitialize(%1, params)

    let capabilities = response["capabilities"]
    check capabilities.hasKey("semanticTokensProvider")

    let semanticTokensProvider = capabilities["semanticTokensProvider"]
    check semanticTokensProvider.hasKey("legend")
    check semanticTokensProvider.hasKey("range")
    check semanticTokensProvider.hasKey("full")

    let legend = semanticTokensProvider["legend"]
    check legend.hasKey("tokenTypes")
    check legend.hasKey("tokenModifiers")

    let tokenTypes = legend["tokenTypes"]
    check tokenTypes.kind == JArray
    check tokenTypes.len == 23 # All standard token types
    check "namespace" in tokenTypes.mapIt(it.getStr())
    check "function" in tokenTypes.mapIt(it.getStr())
    check "keyword" in tokenTypes.mapIt(it.getStr())

    let tokenModifiers = legend["tokenModifiers"]
    check tokenModifiers.kind == JArray
    check tokenModifiers.len == 10 # All standard token modifiers
    check "declaration" in tokenModifiers.mapIt(it.getStr())
    check "definition" in tokenModifiers.mapIt(it.getStr())
    check "readonly" in tokenModifiers.mapIt(it.getStr())

    check semanticTokensProvider["range"].getBool() == true
    check semanticTokensProvider["full"].hasKey("delta")
    check semanticTokensProvider["full"]["delta"].getBool() == false

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

  test "handleInlayHint with enabled inlay hints":
    let sm = createTestScenarioManager()
    sm.currentScenario = "test" # Has inlay hints configured
    let handler = newLSPHandler(sm)

    # Add a document first
    handler.documents["file:///test.nim"] =
      Document(content: "func test(param) -> bool", version: 1)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "range":
          {"start": {"line": 0, "character": 0}, "end": {"line": 10, "character": 0}},
      }

    let response = waitFor handler.handleInlayHint(%1, params)

    check response.kind == JArray
    check response.len == 2

    # Check first hint (parameter type)
    let hint1 = response[0]
    check hint1["position"]["line"].getInt() == 1
    check hint1["position"]["character"].getInt() == 15
    check hint1["label"].getStr() == ": string"
    check hint1["kind"].getInt() == 1
    check hint1["tooltip"].getStr() == "Parameter type hint"
    check hint1["paddingLeft"].getBool() == false
    check hint1["paddingRight"].getBool() == false

    # Check second hint (return type)
    let hint2 = response[1]
    check hint2["position"]["line"].getInt() == 5
    check hint2["position"]["character"].getInt() == 20
    check hint2["label"].getStr() == " -> bool"
    check hint2["kind"].getInt() == 1
    check hint2["tooltip"].getStr() == "Return type hint"
    check hint2["paddingLeft"].getBool() == true
    check hint2["paddingRight"].getBool() == false

  test "handleInlayHint with disabled inlay hints":
    let sm = createTestScenarioManager()
    # Use default scenario which has inlay hints disabled
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "range":
          {"start": {"line": 0, "character": 0}, "end": {"line": 10, "character": 0}},
      }

    let response = waitFor handler.handleInlayHint(%1, params)

    check response.kind == JArray
    check response.len == 0

  test "handleInlayHint with error scenario":
    let sm = createTestScenarioManager()
    sm.currentScenario = "error"
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "range":
          {"start": {"line": 0, "character": 0}, "end": {"line": 10, "character": 0}},
      }

    expect LSPError:
      discard waitFor handler.handleInlayHint(%1, params)

  test "handleInlayHint with delay":
    let sm = createTestScenarioManager()
    sm.currentScenario = "test" # This scenario has 40ms delay for inlay hints
    let handler = newLSPHandler(sm)

    # Add a document first
    handler.documents["file:///test.nim"] =
      Document(content: "func test(param) -> bool", version: 1)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "range":
          {"start": {"line": 0, "character": 0}, "end": {"line": 10, "character": 0}},
      }

    let startTime = getTime()
    let response = waitFor handler.handleInlayHint(%1, params)
    let endTime = getTime()

    # Check that some delay occurred (should be at least 30ms due to 40ms delay)
    let duration = (endTime - startTime).inMilliseconds
    check duration >= 30

    check response.kind == JArray
    check response.len == 2

  test "handleInlayHint with non-existent document":
    let sm = createTestScenarioManager()
    sm.currentScenario = "test"
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///nonexistent.nim"},
        "range":
          {"start": {"line": 0, "character": 0}, "end": {"line": 10, "character": 0}},
      }

    let response = waitFor handler.handleInlayHint(%1, params)

    check response.kind == JArray
    check response.len == 0

  test "inlay hint capability in initialization":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    let params = %*{"processId": 1234, "capabilities": {}}
    let response = waitFor handler.handleInitialize(%1, params)

    let capabilities = response["capabilities"]
    check capabilities.hasKey("inlayHintProvider")

    let inlayHintProvider = capabilities["inlayHintProvider"]
    check inlayHintProvider.hasKey("resolveProvider")
    check inlayHintProvider["resolveProvider"].getBool() == false

  test "handleDeclaration with enabled declaration":
    let sm = createTestScenarioManager()
    sm.currentScenario = "test" # Has declaration configured
    let handler = newLSPHandler(sm)

    # Add a document first
    handler.documents["file:///test.nim"] =
      Document(content: "func test() {}", version: 1)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 5},
      }

    let response = waitFor handler.handleDeclaration(%1, params)

    # Should return single location since scenario has both location and locations
    # When both exist, locations takes precedence and returns array
    check response.kind == JArray
    check response.len == 2

    # Check first location
    let loc1 = response[0]
    check loc1["uri"].getStr() == "file:///multiple1.nim"
    check loc1["range"]["start"]["line"].getInt() == 3
    check loc1["range"]["start"]["character"].getInt() == 5
    check loc1["range"]["end"]["line"].getInt() == 3
    check loc1["range"]["end"]["character"].getInt() == 15

    # Check second location
    let loc2 = response[1]
    check loc2["uri"].getStr() == "file:///multiple2.nim"
    check loc2["range"]["start"]["line"].getInt() == 7
    check loc2["range"]["start"]["character"].getInt() == 0
    check loc2["range"]["end"]["line"].getInt() == 7
    check loc2["range"]["end"]["character"].getInt() == 10

  test "handleDeclaration with single location only":
    let sm = createTestScenarioManager()
    # Create scenario with only single location
    sm.scenarios["single_declaration"] = Scenario(
      name: "Single Declaration",
      hover: HoverConfig(enabled: false),
      completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
      diagnostics: DiagnosticConfig(enabled: false, diagnostics: @[]),
      semanticTokens: SemanticTokensConfig(enabled: false, tokens: @[]),
      inlayHint: InlayHintConfig(enabled: false, hints: @[]),
      declaration: DeclarationConfig(
        enabled: true,
        location: DeclarationContent(
          uri: "file:///single_declaration.nim",
          range: Range(
            start: Position(line: 10, character: 0),
            `end`: Position(line: 10, character: 10),
          ),
        ),
        locations: @[] # Empty locations array
        ,
      ),
      delays: DelayConfig(
        hover: 0,
        completion: 0,
        diagnostics: 0,
        semanticTokens: 0,
        inlayHint: 0,
        declaration: 0,
        definition: 0,
        typeDefinition: 0,
      ),
      typeDefinition: TypeDefinitionConfig(
        enabled: false,
        location: TypeDefinitionContent(
          uri: "",
          range: Range(
            start: Position(line: 0, character: 0),
            `end`: Position(line: 0, character: 0),
          ),
        ),
        locations: @[],
      ),
      errors: initTable[string, ErrorConfig](),
    )
    sm.currentScenario = "single_declaration"
    let handler = newLSPHandler(sm)

    # Add a document first
    handler.documents["file:///test.nim"] =
      Document(content: "func test() {}", version: 1)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 5},
      }

    let response = waitFor handler.handleDeclaration(%1, params)

    # Should return single location object
    check response.kind == JObject
    check response["uri"].getStr() == "file:///single_declaration.nim"
    check response["range"]["start"]["line"].getInt() == 10
    check response["range"]["start"]["character"].getInt() == 0
    check response["range"]["end"]["line"].getInt() == 10
    check response["range"]["end"]["character"].getInt() == 10

  test "handleDeclaration with disabled declaration":
    let sm = createTestScenarioManager()
    # Use default scenario which has declaration disabled
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 0},
      }

    let response = waitFor handler.handleDeclaration(%1, params)

    check response.kind == JNull

  test "handleDeclaration with error scenario":
    let sm = createTestScenarioManager()
    sm.currentScenario = "error"
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 0},
      }

    expect LSPError:
      discard waitFor handler.handleDeclaration(%1, params)

  test "handleDeclaration with delay":
    let sm = createTestScenarioManager()
    sm.currentScenario = "test" # This scenario has 60ms delay for declaration
    let handler = newLSPHandler(sm)

    # Add a document first
    handler.documents["file:///test.nim"] =
      Document(content: "func test() {}", version: 1)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 5},
      }

    let startTime = getTime()
    let response = waitFor handler.handleDeclaration(%1, params)
    let endTime = getTime()

    # Check that some delay occurred (should be at least 50ms due to 60ms delay)
    let duration = (endTime - startTime).inMilliseconds
    check duration >= 50

    check response.kind == JArray
    check response.len == 2

  test "handleDeclaration with non-existent document":
    let sm = createTestScenarioManager()
    sm.currentScenario = "test"
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///nonexistent.nim"},
        "position": {"line": 0, "character": 0},
      }

    let response = waitFor handler.handleDeclaration(%1, params)

    check response.kind == JNull

  test "handleDeclaration with no declaration configured":
    let sm = createTestScenarioManager()
    # Create scenario with declaration enabled but no location/locations configured
    sm.scenarios["no_declarations"] = Scenario(
      name: "No Declarations",
      hover: HoverConfig(enabled: false),
      completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
      diagnostics: DiagnosticConfig(enabled: false, diagnostics: @[]),
      semanticTokens: SemanticTokensConfig(enabled: false, tokens: @[]),
      inlayHint: InlayHintConfig(enabled: false, hints: @[]),
      declaration: DeclarationConfig(
        enabled: true,
        location: DeclarationContent(
          uri: "",
          range: Range(
            start: Position(line: 0, character: 0),
            `end`: Position(line: 0, character: 0),
          ),
        ),
        locations: @[],
      ),
      delays: DelayConfig(
        hover: 0,
        completion: 0,
        diagnostics: 0,
        semanticTokens: 0,
        inlayHint: 0,
        declaration: 0,
        definition: 0,
        typeDefinition: 0,
      ),
      typeDefinition: TypeDefinitionConfig(
        enabled: false,
        location: TypeDefinitionContent(
          uri: "",
          range: Range(
            start: Position(line: 0, character: 0),
            `end`: Position(line: 0, character: 0),
          ),
        ),
        locations: @[],
      ),
      errors: initTable[string, ErrorConfig](),
    )
    sm.currentScenario = "no_declarations"
    let handler = newLSPHandler(sm)

    # Add a document first
    handler.documents["file:///test.nim"] =
      Document(content: "func test() {}", version: 1)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 5},
      }

    let response = waitFor handler.handleDeclaration(%1, params)

    check response.kind == JNull

  test "handleDefinition with enabled definition":
    let sm = createTestScenarioManager()
    sm.currentScenario = "test" # Has definition configured
    let handler = newLSPHandler(sm)

    # Add a document first
    handler.documents["file:///test.nim"] =
      Document(content: "func test() {}", version: 1)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 5},
      }

    let response = waitFor handler.handleDefinition(%1, params)

    # Should return array of locations since scenario has both location and locations
    # When both exist, locations takes precedence and returns array
    check response.kind == JArray
    check response.len == 2

    # Check first location
    let loc1 = response[0]
    check loc1["uri"].getStr() == "file:///implementation1.nim"
    check loc1["range"]["start"]["line"].getInt() == 10
    check loc1["range"]["start"]["character"].getInt() == 4
    check loc1["range"]["end"]["line"].getInt() == 10
    check loc1["range"]["end"]["character"].getInt() == 14

    # Check second location
    let loc2 = response[1]
    check loc2["uri"].getStr() == "file:///implementation2.nim"
    check loc2["range"]["start"]["line"].getInt() == 20
    check loc2["range"]["start"]["character"].getInt() == 8
    check loc2["range"]["end"]["line"].getInt() == 20
    check loc2["range"]["end"]["character"].getInt() == 18

  test "handleDefinition with single location only":
    let sm = createTestScenarioManager()
    # Create scenario with only single location
    sm.scenarios["single_definition"] = Scenario(
      name: "Single Definition",
      hover: HoverConfig(enabled: false),
      completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
      diagnostics: DiagnosticConfig(enabled: false, diagnostics: @[]),
      semanticTokens: SemanticTokensConfig(enabled: false, tokens: @[]),
      inlayHint: InlayHintConfig(enabled: false, hints: @[]),
      declaration: DeclarationConfig(
        enabled: false,
        location: DeclarationContent(
          uri: "",
          range: Range(
            start: Position(line: 0, character: 0),
            `end`: Position(line: 0, character: 0),
          ),
        ),
        locations: @[],
      ),
      definition: DefinitionConfig(
        enabled: true,
        location: DefinitionContent(
          uri: "file:///single_definition.nim",
          range: Range(
            start: Position(line: 25, character: 2),
            `end`: Position(line: 25, character: 12),
          ),
        ),
        locations: @[], # Empty locations array
      ),
      delays: DelayConfig(
        hover: 0,
        completion: 0,
        diagnostics: 0,
        semanticTokens: 0,
        inlayHint: 0,
        declaration: 0,
        definition: 0,
        typeDefinition: 0,
      ),
      typeDefinition: TypeDefinitionConfig(
        enabled: false,
        location: TypeDefinitionContent(
          uri: "",
          range: Range(
            start: Position(line: 0, character: 0),
            `end`: Position(line: 0, character: 0),
          ),
        ),
        locations: @[],
      ),
      errors: initTable[string, ErrorConfig](),
    )
    sm.currentScenario = "single_definition"
    let handler = newLSPHandler(sm)

    # Add a document first
    handler.documents["file:///test.nim"] =
      Document(content: "func test() {}", version: 1)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 5},
      }

    let response = waitFor handler.handleDefinition(%1, params)

    # Should return single location object
    check response.kind == JObject
    check response["uri"].getStr() == "file:///single_definition.nim"
    check response["range"]["start"]["line"].getInt() == 25
    check response["range"]["start"]["character"].getInt() == 2
    check response["range"]["end"]["line"].getInt() == 25
    check response["range"]["end"]["character"].getInt() == 12

  test "handleDefinition with disabled definition":
    let sm = createTestScenarioManager()
    # Use default scenario which has definition disabled
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 0},
      }

    let response = waitFor handler.handleDefinition(%1, params)

    check response.kind == JNull

  test "handleImplementation with enabled implementation":
    let sm = createTestScenarioManager()
    sm.currentScenario = "test" # Has implementation configured
    let handler = newLSPHandler(sm)

    # Add a document first
    handler.documents["file:///test.nim"] =
      Document(content: "func test() {}", version: 1)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 5},
      }

    let response = waitFor handler.handleImplementation(%1, params)

    # Should return array of locations since scenario has both location and locations
    # When both exist, locations takes precedence and returns array
    check response.kind == JArray
    check response.len == 2

    # Check first location
    let loc1 = response[0]
    check loc1["uri"].getStr() == "file:///implementation1.nim"
    check loc1["range"]["start"]["line"].getInt() == 25
    check loc1["range"]["start"]["character"].getInt() == 0
    check loc1["range"]["end"]["line"].getInt() == 25
    check loc1["range"]["end"]["character"].getInt() == 15

    # Check second location
    let loc2 = response[1]
    check loc2["uri"].getStr() == "file:///implementation2.nim"
    check loc2["range"]["start"]["line"].getInt() == 35
    check loc2["range"]["start"]["character"].getInt() == 2
    check loc2["range"]["end"]["line"].getInt() == 35
    check loc2["range"]["end"]["character"].getInt() == 17

  test "handleImplementation with disabled implementation":
    let sm = createTestScenarioManager()
    # Use default scenario which has implementation disabled
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 0},
      }

    let response = waitFor handler.handleImplementation(%1, params)

    check response.kind == JNull

  test "handleImplementation with error scenario":
    let sm = createTestScenarioManager()
    sm.currentScenario = "error"
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 0},
      }

    expect LSPError:
      discard waitFor handler.handleImplementation(%1, params)

  test "handleImplementation with delay":
    let sm = createTestScenarioManager()
    sm.currentScenario = "test" # This scenario has 50ms delay for implementation
    let handler = newLSPHandler(sm)

    # Add a document first
    handler.documents["file:///test.nim"] =
      Document(content: "func test() {}", version: 1)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 5},
      }

    let startTime = getTime()
    let response = waitFor handler.handleImplementation(%1, params)
    let endTime = getTime()

    # Check that some delay occurred (should be at least 40ms due to 50ms delay)
    let duration = (endTime - startTime).inMilliseconds
    check duration >= 40

    check response.kind == JArray
    check response.len == 2

  test "handleImplementation with non-existent document":
    let sm = createTestScenarioManager()
    sm.currentScenario = "test"
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///nonexistent.nim"},
        "position": {"line": 0, "character": 0},
      }

    let response = waitFor handler.handleImplementation(%1, params)

    check response.kind == JNull

  test "handleDefinition with error scenario":
    let sm = createTestScenarioManager()
    sm.currentScenario = "error"
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 0},
      }

    expect LSPError:
      discard waitFor handler.handleDefinition(%1, params)

  test "handleDefinition with delay":
    let sm = createTestScenarioManager()
    sm.currentScenario = "test" # This scenario has 55ms delay for definition
    let handler = newLSPHandler(sm)

    # Add a document first
    handler.documents["file:///test.nim"] =
      Document(content: "func test() {}", version: 1)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 5},
      }

    let startTime = getTime()
    let response = waitFor handler.handleDefinition(%1, params)
    let endTime = getTime()

    # Check that some delay occurred (should be at least 45ms due to 55ms delay)
    let duration = (endTime - startTime).inMilliseconds
    check duration >= 45

    check response.kind == JArray
    check response.len == 2

  test "handleDefinition with non-existent document":
    let sm = createTestScenarioManager()
    sm.currentScenario = "test"
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {"uri": "file:///nonexistent.nim"},
        "position": {"line": 0, "character": 0},
      }

    let response = waitFor handler.handleDefinition(%1, params)

    check response.kind == JNull

  test "handleDefinition with no definition configured":
    let sm = createTestScenarioManager()
    # Create scenario with definition enabled but no location/locations configured
    sm.scenarios["no_definitions"] = Scenario(
      name: "No Definitions",
      hover: HoverConfig(enabled: false),
      completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
      diagnostics: DiagnosticConfig(enabled: false, diagnostics: @[]),
      semanticTokens: SemanticTokensConfig(enabled: false, tokens: @[]),
      inlayHint: InlayHintConfig(enabled: false, hints: @[]),
      declaration: DeclarationConfig(
        enabled: false,
        location: DeclarationContent(
          uri: "",
          range: Range(
            start: Position(line: 0, character: 0),
            `end`: Position(line: 0, character: 0),
          ),
        ),
        locations: @[],
      ),
      definition: DefinitionConfig(
        enabled: true,
        location: DefinitionContent(
          uri: "",
          range: Range(
            start: Position(line: 0, character: 0),
            `end`: Position(line: 0, character: 0),
          ),
        ),
        locations: @[],
      ),
      delays: DelayConfig(
        hover: 0,
        completion: 0,
        diagnostics: 0,
        semanticTokens: 0,
        inlayHint: 0,
        declaration: 0,
        definition: 0,
        typeDefinition: 0,
      ),
      typeDefinition: TypeDefinitionConfig(
        enabled: false,
        location: TypeDefinitionContent(
          uri: "",
          range: Range(
            start: Position(line: 0, character: 0),
            `end`: Position(line: 0, character: 0),
          ),
        ),
        locations: @[],
      ),
      errors: initTable[string, ErrorConfig](),
    )
    sm.currentScenario = "no_definitions"
    let handler = newLSPHandler(sm)

    # Add a document first
    handler.documents["file:///test.nim"] =
      Document(content: "func test() {}", version: 1)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim"},
        "position": {"line": 0, "character": 5},
      }

    let response = waitFor handler.handleDefinition(%1, params)

    check response.kind == JNull
