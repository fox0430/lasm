import std/[unittest, json, os, tables, options]

import ../src/lasmpkg/[scenario, logger]
import ../src/lasmpkg/protocol/types

suite "scenario module tests":
  setup:
    # Initialize logger for tests - disable logging for tests
    setGlobalLogger(newFileLogger(enabled = false))

    var configPath = ""

  teardown:
    if fileExists(configPath):
      removeFile(configPath)

  test "ScenarioManager creation with default values":
    let sm = ScenarioManager()
    sm.currentScenario = "default"
    sm.scenarios = initTable[string, Scenario]()

    check sm.currentScenario == "default"
    check sm.scenarios.len == 0

  test "HoverConfig initialization":
    let hoverConfig = HoverConfig(enabled: true, contents: @[])

    check hoverConfig.enabled == true
    check hoverConfig.contents.len == 0

  test "Scenario initialization":
    let scenario = Scenario(
      name: "test_scenario",
      hover: HoverConfig(enabled: true),
      completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
      diagnostics: DiagnosticConfig(enabled: false, diagnostics: @[]),
      semanticTokens: SemanticTokensConfig(enabled: false, tokens: @[]),
      inlayHint: InlayHintConfig(enabled: false, hints: @[]),
      delays: DelayConfig(
        hover: 100,
        completion: 0,
        diagnostics: 0,
        semanticTokens: 0,
        inlayHint: 0,
        declaration: 0,
        definition: 0,
        typeDefinition: 0,
      ),
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
        enabled: false,
        location: DefinitionContent(
          uri: "",
          range: Range(
            start: Position(line: 0, character: 0),
            `end`: Position(line: 0, character: 0),
          ),
        ),
        locations: @[],
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

    check scenario.name == "test_scenario"
    check scenario.hover.enabled == true
    check scenario.delays.hover == 100
    check scenario.errors.len == 0

  test "loadConfigFile with non-existent file":
    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile("non_existent_file.json")
    check result == false

  test "loadConfigFile with valid JSON config":
    let tempDir = getTempDir()
    configPath = tempDir / "test_config.json"

    let testConfig =
      %*{
        "currentScenario": "test",
        "scenarios": {
          "test": {
            "name": "Test Scenario",
            "hover": {
              "enabled": true,
              "content": {"kind": "markdown", "message": "Test hover message"},
            },
            "completion": {"enabled": false, "items": []},
            "delays":
              {"hover": 50, "completion": 0, "diagnostics": 0, "semanticTokens": 0},
            "errors": {"hover": {"code": -32603, "message": "Test error"}},
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true
    check sm.currentScenario == "test"
    check sm.scenarios.len == 1
    check "test" in sm.scenarios

    let scenario = sm.scenarios["test"]
    check scenario.name == "Test Scenario"
    check scenario.hover.enabled == true
    check scenario.hover.content.isSome
    check scenario.delays.hover == 50
    check "hover" in scenario.errors
    check scenario.errors["hover"].code == -32603
    check scenario.errors["hover"].message == "Test error"

  test "loadConfigFile with contents array":
    let tempDir = getTempDir()
    configPath = tempDir / "test_config_contents.json"

    let testConfig =
      %*{
        "currentScenario": "multiContent",
        "scenarios": {
          "multiContent": {
            "name": "Multi Content Scenario",
            "hover": {
              "enabled": true,
              "contents": [
                {
                  "kind": "markdown",
                  "message": "First content",
                  "position": {"line": 0, "character": 0},
                },
                {"kind": "plaintext", "message": "Second content"},
              ],
            },
            "completion": {"enabled": false, "items": []},
            "delays":
              {"hover": 25, "completion": 0, "diagnostics": 0, "semanticTokens": 0},
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true
    check sm.currentScenario == "multiContent"

    let scenario = sm.scenarios["multiContent"]
    check scenario.hover.enabled == true
    check scenario.hover.contents.len == 2

  test "loadConfigFile with malformed JSON":
    let tempDir = getTempDir()
    configPath = tempDir / "malformed_config.json"

    writeFile(configPath, "{ invalid json }")

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == false

  test "getCurrentScenario returns default when current scenario not found":
    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()
    sm.currentScenario = "non_existent"

    # Add a default scenario
    sm.scenarios["default"] = Scenario(
      name: "Default Scenario",
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
      ),
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
        enabled: false,
        location: DefinitionContent(
          uri: "",
          range: Range(
            start: Position(line: 0, character: 0),
            `end`: Position(line: 0, character: 0),
          ),
        ),
        locations: @[],
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

    let scenario = sm.getCurrentScenario()
    check scenario.name == "Default Scenario"

  test "getCurrentScenario returns current scenario when it exists":
    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()
    sm.currentScenario = "test"

    sm.scenarios["test"] = Scenario(
      name: "Test Scenario",
      hover: HoverConfig(enabled: true),
      completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
      diagnostics: DiagnosticConfig(enabled: false, diagnostics: @[]),
      semanticTokens: SemanticTokensConfig(enabled: false, tokens: @[]),
      inlayHint: InlayHintConfig(enabled: false, hints: @[]),
      delays: DelayConfig(
        hover: 100,
        completion: 0,
        diagnostics: 0,
        semanticTokens: 0,
        inlayHint: 0,
        declaration: 0,
        definition: 0,
        typeDefinition: 0,
      ),
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
        enabled: false,
        location: DefinitionContent(
          uri: "",
          range: Range(
            start: Position(line: 0, character: 0),
            `end`: Position(line: 0, character: 0),
          ),
        ),
        locations: @[],
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

    let scenario = sm.getCurrentScenario()
    check scenario.name == "Test Scenario"

  test "setScenario with valid scenario name":
    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()
    sm.currentScenario = "default"

    sm.scenarios["test"] = Scenario(
      name: "Test Scenario",
      hover: HoverConfig(enabled: true),
      completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
      diagnostics: DiagnosticConfig(enabled: false, diagnostics: @[]),
      semanticTokens: SemanticTokensConfig(enabled: false, tokens: @[]),
      inlayHint: InlayHintConfig(enabled: false, hints: @[]),
      delays: DelayConfig(
        hover: 100,
        completion: 0,
        diagnostics: 0,
        semanticTokens: 0,
        inlayHint: 0,
        declaration: 0,
        definition: 0,
        typeDefinition: 0,
      ),
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
        enabled: false,
        location: DefinitionContent(
          uri: "",
          range: Range(
            start: Position(line: 0, character: 0),
            `end`: Position(line: 0, character: 0),
          ),
        ),
        locations: @[],
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

    let result = sm.setScenario("test")
    check result == true
    check sm.currentScenario == "test"

  test "setScenario with invalid scenario name":
    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()
    sm.currentScenario = "default"

    let result = sm.setScenario("non_existent")
    check result == false
    check sm.currentScenario == "default"

  test "listScenarios returns all scenarios":
    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    sm.scenarios["scenario1"] = Scenario(
      name: "First Scenario",
      hover: HoverConfig(enabled: true),
      completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
      diagnostics: DiagnosticConfig(enabled: false, diagnostics: @[]),
      semanticTokens: SemanticTokensConfig(enabled: false, tokens: @[]),
      inlayHint: InlayHintConfig(enabled: false, hints: @[]),
      delays: DelayConfig(
        hover: 50,
        completion: 0,
        diagnostics: 0,
        semanticTokens: 0,
        inlayHint: 0,
        declaration: 0,
      ),
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
        enabled: false,
        location: DefinitionContent(
          uri: "",
          range: Range(
            start: Position(line: 0, character: 0),
            `end`: Position(line: 0, character: 0),
          ),
        ),
        locations: @[],
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

    sm.scenarios["scenario2"] = Scenario(
      name: "Second Scenario",
      hover: HoverConfig(enabled: false),
      completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
      diagnostics: DiagnosticConfig(enabled: false, diagnostics: @[]),
      semanticTokens: SemanticTokensConfig(enabled: false, tokens: @[]),
      inlayHint: InlayHintConfig(enabled: false, hints: @[]),
      delays: DelayConfig(
        hover: 100,
        completion: 0,
        diagnostics: 0,
        semanticTokens: 0,
        inlayHint: 0,
        declaration: 0,
        definition: 0,
        typeDefinition: 0,
      ),
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
        enabled: false,
        location: DefinitionContent(
          uri: "",
          range: Range(
            start: Position(line: 0, character: 0),
            `end`: Position(line: 0, character: 0),
          ),
        ),
        locations: @[],
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

    let scenarios = sm.listScenarios()
    check scenarios.len == 2

    # Check that both scenarios are present
    var foundFirst = false
    var foundSecond = false

    for scenario in scenarios:
      if scenario.name == "scenario1":
        foundFirst = true
        check scenario.description == "First Scenario"
      elif scenario.name == "scenario2":
        foundSecond = true
        check scenario.description == "Second Scenario"

    check foundFirst == true
    check foundSecond == true

  test "createSampleConfig creates valid config file":
    let tempDir = getTempDir()
    let originalDir = getCurrentDir()

    try:
      setCurrentDir(tempDir)

      let sm = ScenarioManager()
      sm.createSampleConfig()

      configPath = tempDir / "lsp-test-config-sample.json"
      check fileExists(configPath)

      let configContent = readFile(configPath)
      let config = parseJson(configContent)

      check config.hasKey("currentScenario")
      check config.hasKey("scenarios")
      check config["currentScenario"].getStr() == "default"
      check config["scenarios"].hasKey("default")

      let defaultScenario = config["scenarios"]["default"]
      check defaultScenario.hasKey("name")
      check defaultScenario.hasKey("hover")
      check defaultScenario.hasKey("completion")
      check defaultScenario.hasKey("diagnostics")
      check defaultScenario.hasKey("delays")

      # Verify diagnostics are enabled by default in sample config
      check defaultScenario["diagnostics"]["enabled"].getBool() == true
      check defaultScenario["diagnostics"]["diagnostics"].len > 0
    finally:
      setCurrentDir(originalDir)

  test "Document type initialization":
    let document = Document(content: "Test content", version: 1)

    check document.content == "Test content"
    check document.version == 1

  test "ErrorConfig initialization":
    let errorConfig = ErrorConfig(code: -32602, message: "Invalid params")

    check errorConfig.code == -32602
    check errorConfig.message == "Invalid params"

  test "DelayConfig initialization":
    let delayConfig = DelayConfig(
      hover: 150,
      completion: 100,
      diagnostics: 200,
      semanticTokens: 75,
      inlayHint: 50,
      declaration: 80,
      definition: 70,
      typeDefinition: 60,
    )

    check delayConfig.hover == 150
    check delayConfig.completion == 100
    check delayConfig.diagnostics == 200
    check delayConfig.semanticTokens == 75
    check delayConfig.inlayHint == 50
    check delayConfig.declaration == 80
    check delayConfig.definition == 70
    check delayConfig.typeDefinition == 60

  test "SemanticTokensConfig initialization":
    let semanticTokensConfig = SemanticTokensConfig(
      enabled: true,
      tokens: @[uinteger(0), uinteger(0), uinteger(8), uinteger(14), uinteger(0)],
    )

    check semanticTokensConfig.enabled == true
    check semanticTokensConfig.tokens.len == 5
    check semanticTokensConfig.tokens[0] == 0
    check semanticTokensConfig.tokens[3] == 14

  test "loadConfigFile with empty scenarios":
    let tempDir = getTempDir()
    configPath = tempDir / "empty_scenarios.json"

    let testConfig = %*{"currentScenario": "default", "scenarios": {}}

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true
    check sm.scenarios.len == 0

  test "loadConfigFile with missing currentScenario":
    let tempDir = getTempDir()
    configPath = tempDir / "no_current_scenario.json"

    let testConfig =
      %*{
        "scenarios": {
          "test": {
            "name": "Test Scenario", "hover": {"enabled": false}, "delays": {"hover": 0}
          }
        }
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()
    sm.currentScenario = "original"

    let result = sm.loadConfigFile(configPath)
    check result == true
    check sm.currentScenario == "original" # Should remain unchanged

  test "DiagnosticConfig initialization":
    let diagContent = DiagnosticContent(
      range: Range(
        start: Position(line: 1, character: 5), `end`: Position(line: 1, character: 10)
      ),
      severity: 1,
      code: some("E001"),
      source: some("test"),
      message: "Test diagnostic message",
      tags: @[1, 2],
      relatedInformation: @[],
    )

    let diagConfig = DiagnosticConfig(enabled: true, diagnostics: @[diagContent])

    check diagConfig.enabled == true
    check diagConfig.diagnostics.len == 1
    check diagConfig.diagnostics[0].message == "Test diagnostic message"
    check diagConfig.diagnostics[0].severity == 1
    check diagConfig.diagnostics[0].code.get == "E001"
    check diagConfig.diagnostics[0].source.get == "test"
    check diagConfig.diagnostics[0].tags.len == 2

  test "loadConfigFile with diagnostic configuration":
    let tempDir = getTempDir()
    configPath = tempDir / "test_diagnostic_config.json"

    let testConfig =
      %*{
        "currentScenario": "diagnostic_test",
        "scenarios": {
          "diagnostic_test": {
            "name": "Diagnostic Test Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {
              "enabled": true,
              "diagnostics": [
                {
                  "range": {
                    "start": {"line": 2, "character": 10},
                    "end": {"line": 2, "character": 20},
                  },
                  "severity": 1,
                  "code": "E001",
                  "source": "lasm",
                  "message": "Undefined variable 'testVar'",
                  "tags": [1],
                },
                {
                  "range": {
                    "start": {"line": 5, "character": 0},
                    "end": {"line": 5, "character": 5},
                  },
                  "severity": 2,
                  "code": "W001",
                  "source": "lasm",
                  "message": "Function 'oldFunc' is deprecated",
                  "tags": [2],
                  "relatedInformation": [
                    {
                      "location": {
                        "uri": "file:///related.py",
                        "range": {
                          "start": {"line": 10, "character": 0},
                          "end": {"line": 10, "character": 10},
                        },
                      },
                      "message": "New function available here",
                    }
                  ],
                },
              ],
            },
            "delays":
              {"hover": 0, "completion": 0, "diagnostics": 150, "semanticTokens": 0},
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true
    check sm.currentScenario == "diagnostic_test"
    check sm.scenarios.len == 1
    check "diagnostic_test" in sm.scenarios

    let scenario = sm.scenarios["diagnostic_test"]
    check scenario.name == "Diagnostic Test Scenario"
    check scenario.diagnostics.enabled == true
    check scenario.diagnostics.diagnostics.len == 2
    check scenario.delays.diagnostics == 150

    # Check first diagnostic
    let diag1 = scenario.diagnostics.diagnostics[0]
    check diag1.message == "Undefined variable 'testVar'"
    check diag1.severity == 1
    check diag1.code.get == "E001"
    check diag1.source.get == "lasm"
    check diag1.tags.len == 1
    check diag1.tags[0] == 1
    check diag1.range.start.line == 2
    check diag1.range.start.character == 10
    check diag1.range.`end`.line == 2
    check diag1.range.`end`.character == 20
    check diag1.relatedInformation.len == 0

    # Check second diagnostic
    let diag2 = scenario.diagnostics.diagnostics[1]
    check diag2.message == "Function 'oldFunc' is deprecated"
    check diag2.severity == 2
    check diag2.code.get == "W001"
    check diag2.source.get == "lasm"
    check diag2.tags.len == 1
    check diag2.tags[0] == 2
    check diag2.range.start.line == 5
    check diag2.range.start.character == 0
    check diag2.range.`end`.line == 5
    check diag2.range.`end`.character == 5
    check diag2.relatedInformation.len == 1
    check diag2.relatedInformation[0].message == "New function available here"
    check diag2.relatedInformation[0].location.uri == "file:///related.py"

  test "loadConfigFile with disabled diagnostics":
    let tempDir = getTempDir()
    configPath = tempDir / "test_disabled_diagnostic_config.json"

    let testConfig =
      %*{
        "currentScenario": "no_diagnostics",
        "scenarios": {
          "no_diagnostics": {
            "name": "No Diagnostics Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false},
            "delays":
              {"hover": 0, "completion": 0, "diagnostics": 0, "semanticTokens": 0},
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["no_diagnostics"]
    check scenario.diagnostics.enabled == false
    check scenario.diagnostics.diagnostics.len == 0

  test "loadConfigFile without diagnostic configuration creates default":
    let tempDir = getTempDir()
    configPath = tempDir / "test_no_diagnostic_config.json"

    let testConfig =
      %*{
        "currentScenario": "no_diag_config",
        "scenarios": {
          "no_diag_config": {
            "name": "No Diagnostic Config Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "delays":
              {"hover": 0, "completion": 0, "diagnostics": 0, "semanticTokens": 0},
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["no_diag_config"]
    check scenario.diagnostics.enabled == false
    check scenario.diagnostics.diagnostics.len == 0

  test "loadConfigFile with minimal diagnostic configuration":
    let tempDir = getTempDir()
    configPath = tempDir / "test_minimal_diagnostic_config.json"

    let testConfig =
      %*{
        "currentScenario": "minimal_diag",
        "scenarios": {
          "minimal_diag": {
            "name": "Minimal Diagnostic Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {
              "enabled": true,
              "diagnostics": [{"message": "Simple error", "severity": 1}],
            },
            "delays":
              {"hover": 0, "completion": 0, "diagnostics": 0, "semanticTokens": 0},
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["minimal_diag"]
    check scenario.diagnostics.enabled == true
    check scenario.diagnostics.diagnostics.len == 1

    let diag = scenario.diagnostics.diagnostics[0]
    check diag.message == "Simple error"
    check diag.severity == 1
    # Should have default range (0,0) to (0,1)
    check diag.range.start.line == 0
    check diag.range.start.character == 0
    check diag.range.`end`.line == 0
    check diag.range.`end`.character == 1
    # Optional fields should be none/empty
    check diag.code.isNone
    check diag.source.isNone
    check diag.tags.len == 0
    check diag.relatedInformation.len == 0

  test "loadConfigFile with semantic tokens configuration":
    let tempDir = getTempDir()
    configPath = tempDir / "test_semantic_tokens_config.json"

    let testConfig =
      %*{
        "currentScenario": "semantic_tokens_test",
        "scenarios": {
          "semantic_tokens_test": {
            "name": "Semantic Tokens Test Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {
              "enabled": true,
              "tokens": [0, 0, 8, 14, 0, 0, 9, 4, 12, 1, 1, 2, 3, 6, 0, 0, 4, 4, 15, 0],
            },
            "delays":
              {"hover": 0, "completion": 0, "diagnostics": 0, "semanticTokens": 50},
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true
    check sm.currentScenario == "semantic_tokens_test"
    check sm.scenarios.len == 1
    check "semantic_tokens_test" in sm.scenarios

    let scenario = sm.scenarios["semantic_tokens_test"]
    check scenario.name == "Semantic Tokens Test Scenario"
    check scenario.semanticTokens.enabled == true
    check scenario.semanticTokens.tokens.len == 20 # 4 tokens * 5 values each
    check scenario.delays.semanticTokens == 50

    # Check token values
    check scenario.semanticTokens.tokens[0] == 0 # deltaLine
    check scenario.semanticTokens.tokens[1] == 0 # deltaStart  
    check scenario.semanticTokens.tokens[2] == 8 # length
    check scenario.semanticTokens.tokens[3] == 14 # tokenType
    check scenario.semanticTokens.tokens[4] == 0 # tokenModifiers

  test "loadConfigFile with disabled semantic tokens":
    let tempDir = getTempDir()
    configPath = tempDir / "test_disabled_semantic_tokens_config.json"

    let testConfig =
      %*{
        "currentScenario": "no_semantic_tokens",
        "scenarios": {
          "no_semantic_tokens": {
            "name": "No Semantic Tokens Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false},
            "delays":
              {"hover": 0, "completion": 0, "diagnostics": 0, "semanticTokens": 0},
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["no_semantic_tokens"]
    check scenario.semanticTokens.enabled == false
    check scenario.semanticTokens.tokens.len == 0

  test "loadConfigFile without semantic tokens configuration creates default":
    let tempDir = getTempDir()
    configPath = tempDir / "test_no_semantic_tokens_config.json"

    let testConfig =
      %*{
        "currentScenario": "no_semantic_config",
        "scenarios": {
          "no_semantic_config": {
            "name": "No Semantic Config Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["no_semantic_config"]
    check scenario.semanticTokens.enabled == false
    check scenario.semanticTokens.tokens.len == 0

  test "InlayHintConfig initialization":
    let position = Position(line: 5, character: 10)
    let textEdit = TextEdit()
    textEdit.newText = "new text"
    textEdit.range = Range(
      start: Position(line: 1, character: 0), `end`: Position(line: 1, character: 5)
    )

    let hintContent = InlayHintContent(
      position: position,
      label: ": string",
      kind: some(1),
      tooltip: some("Type annotation"),
      paddingLeft: some(false),
      paddingRight: some(true),
      textEdits: @[textEdit],
    )

    let inlayHintConfig = InlayHintConfig(enabled: true, hints: @[hintContent])

    check inlayHintConfig.enabled == true
    check inlayHintConfig.hints.len == 1
    check inlayHintConfig.hints[0].position.line == 5
    check inlayHintConfig.hints[0].position.character == 10
    check inlayHintConfig.hints[0].label == ": string"
    check inlayHintConfig.hints[0].kind.get == 1
    check inlayHintConfig.hints[0].tooltip.get == "Type annotation"
    check inlayHintConfig.hints[0].paddingLeft.get == false
    check inlayHintConfig.hints[0].paddingRight.get == true
    check inlayHintConfig.hints[0].textEdits.len == 1
    check inlayHintConfig.hints[0].textEdits[0].newText == "new text"

  test "loadConfigFile with inlay hint configuration":
    let tempDir = getTempDir()
    configPath = tempDir / "test_inlay_hint_config.json"

    let testConfig =
      %*{
        "currentScenario": "inlay_hint_test",
        "scenarios": {
          "inlay_hint_test": {
            "name": "Inlay Hint Test Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {
              "enabled": true,
              "hints": [
                {
                  "position": {"line": 1, "character": 20},
                  "label": ": string",
                  "kind": 1,
                  "tooltip": "Type annotation for parameter",
                  "paddingLeft": false,
                  "paddingRight": false,
                  "textEdits": [
                    {
                      "range": {
                        "start": {"line": 1, "character": 15},
                        "end": {"line": 1, "character": 20},
                      },
                      "newText": "param",
                    }
                  ],
                },
                {
                  "position": {"line": 3, "character": 15},
                  "label": " -> void",
                  "kind": 1,
                  "tooltip": "Return type annotation",
                  "paddingLeft": true,
                  "paddingRight": false,
                },
              ],
            },
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 75,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true
    check sm.currentScenario == "inlay_hint_test"
    check sm.scenarios.len == 1
    check "inlay_hint_test" in sm.scenarios

    let scenario = sm.scenarios["inlay_hint_test"]
    check scenario.name == "Inlay Hint Test Scenario"
    check scenario.inlayHint.enabled == true
    check scenario.inlayHint.hints.len == 2
    check scenario.delays.inlayHint == 75

    # Check first hint
    let hint1 = scenario.inlayHint.hints[0]
    check hint1.position.line == 1
    check hint1.position.character == 20
    check hint1.label == ": string"
    check hint1.kind.get == 1
    check hint1.tooltip.get == "Type annotation for parameter"
    check hint1.paddingLeft.get == false
    check hint1.paddingRight.get == false
    check hint1.textEdits.len == 1
    check hint1.textEdits[0].newText == "param"
    check hint1.textEdits[0].range.start.line == 1
    check hint1.textEdits[0].range.start.character == 15

    # Check second hint
    let hint2 = scenario.inlayHint.hints[1]
    check hint2.position.line == 3
    check hint2.position.character == 15
    check hint2.label == " -> void"
    check hint2.kind.get == 1
    check hint2.tooltip.get == "Return type annotation"
    check hint2.paddingLeft.get == true
    check hint2.paddingRight.get == false
    check hint2.textEdits.len == 0

  test "loadConfigFile with disabled inlay hints":
    let tempDir = getTempDir()
    configPath = tempDir / "test_disabled_inlay_hint_config.json"

    let testConfig =
      %*{
        "currentScenario": "no_inlay_hints",
        "scenarios": {
          "no_inlay_hints": {
            "name": "No Inlay Hints Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false},
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["no_inlay_hints"]
    check scenario.inlayHint.enabled == false
    check scenario.inlayHint.hints.len == 0

  test "loadConfigFile without inlay hint configuration creates default":
    let tempDir = getTempDir()
    configPath = tempDir / "test_no_inlay_hint_config.json"

    let testConfig =
      %*{
        "currentScenario": "no_inlay_config",
        "scenarios": {
          "no_inlay_config": {
            "name": "No Inlay Config Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["no_inlay_config"]
    check scenario.inlayHint.enabled == false
    check scenario.inlayHint.hints.len == 0

  test "loadConfigFile with minimal inlay hint configuration":
    let tempDir = getTempDir()
    configPath = tempDir / "test_minimal_inlay_hint_config.json"

    let testConfig =
      %*{
        "currentScenario": "minimal_inlay",
        "scenarios": {
          "minimal_inlay": {
            "name": "Minimal Inlay Hint Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {
              "enabled": true,
              "hints": [{"position": {"line": 0, "character": 10}, "label": ": int"}],
            },
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["minimal_inlay"]
    check scenario.inlayHint.enabled == true
    check scenario.inlayHint.hints.len == 1

    let hint = scenario.inlayHint.hints[0]
    check hint.position.line == 0
    check hint.position.character == 10
    check hint.label == ": int"
    # Optional fields should be none/empty
    check hint.kind.isNone
    check hint.tooltip.isNone
    check hint.paddingLeft.isNone
    check hint.paddingRight.isNone
    check hint.textEdits.len == 0

  test "DeclarationConfig initialization":
    let declarationContent = DeclarationContent(
      uri: "file:///test_declaration.nim",
      range: Range(
        start: Position(line: 5, character: 10), `end`: Position(line: 5, character: 20)
      ),
    )

    let declarationConfig = DeclarationConfig(
      enabled: true, location: declarationContent, locations: @[declarationContent]
    )

    check declarationConfig.enabled == true
    check declarationConfig.location.uri == "file:///test_declaration.nim"
    check declarationConfig.location.range.start.line == 5
    check declarationConfig.location.range.start.character == 10
    check declarationConfig.location.range.`end`.line == 5
    check declarationConfig.location.range.`end`.character == 20
    check declarationConfig.locations.len == 1
    check declarationConfig.locations[0].uri == "file:///test_declaration.nim"

  test "loadConfigFile with declaration configuration":
    let tempDir = getTempDir()
    configPath = tempDir / "test_declaration_config.json"

    let testConfig =
      %*{
        "currentScenario": "declaration_test",
        "scenarios": {
          "declaration_test": {
            "name": "Declaration Test Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {
              "enabled": true,
              "location": {
                "uri": "file:///single_declaration.nim",
                "range": {
                  "start": {"line": 10, "character": 5},
                  "end": {"line": 10, "character": 15},
                },
              },
              "locations": [
                {
                  "uri": "file:///multi_declaration1.nim",
                  "range": {
                    "start": {"line": 3, "character": 0},
                    "end": {"line": 3, "character": 10},
                  },
                },
                {
                  "uri": "file:///multi_declaration2.nim",
                  "range": {
                    "start": {"line": 7, "character": 5},
                    "end": {"line": 7, "character": 15},
                  },
                },
              ],
            },
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 100,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true
    check sm.currentScenario == "declaration_test"
    check sm.scenarios.len == 1
    check "declaration_test" in sm.scenarios

    let scenario = sm.scenarios["declaration_test"]
    check scenario.name == "Declaration Test Scenario"
    check scenario.declaration.enabled == true
    check scenario.delays.declaration == 100

    # Check single location
    check scenario.declaration.location.uri == "file:///single_declaration.nim"
    check scenario.declaration.location.range.start.line == 10
    check scenario.declaration.location.range.start.character == 5
    check scenario.declaration.location.range.`end`.line == 10
    check scenario.declaration.location.range.`end`.character == 15

    # Check multiple locations
    check scenario.declaration.locations.len == 2
    let loc1 = scenario.declaration.locations[0]
    check loc1.uri == "file:///multi_declaration1.nim"
    check loc1.range.start.line == 3
    check loc1.range.start.character == 0
    check loc1.range.`end`.line == 3
    check loc1.range.`end`.character == 10

    let loc2 = scenario.declaration.locations[1]
    check loc2.uri == "file:///multi_declaration2.nim"
    check loc2.range.start.line == 7
    check loc2.range.start.character == 5
    check loc2.range.`end`.line == 7
    check loc2.range.`end`.character == 15

  test "loadConfigFile with disabled declaration":
    let tempDir = getTempDir()
    configPath = tempDir / "test_disabled_declaration_config.json"

    let testConfig =
      %*{
        "currentScenario": "no_declaration",
        "scenarios": {
          "no_declaration": {
            "name": "No Declaration Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {"enabled": false},
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["no_declaration"]
    check scenario.declaration.enabled == false
    check scenario.declaration.location.uri == ""
    check scenario.declaration.locations.len == 0

  test "loadConfigFile without declaration configuration creates default":
    let tempDir = getTempDir()
    configPath = tempDir / "test_no_declaration_config.json"

    let testConfig =
      %*{
        "currentScenario": "no_decl_config",
        "scenarios": {
          "no_decl_config": {
            "name": "No Declaration Config Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["no_decl_config"]
    check scenario.declaration.enabled == false
    check scenario.declaration.location.uri == ""
    check scenario.declaration.locations.len == 0

  test "loadConfigFile with minimal declaration configuration":
    let tempDir = getTempDir()
    configPath = tempDir / "test_minimal_declaration_config.json"

    let testConfig =
      %*{
        "currentScenario": "minimal_decl",
        "scenarios": {
          "minimal_decl": {
            "name": "Minimal Declaration Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {
              "enabled": true,
              "location": {
                "uri": "file:///minimal.nim",
                "range": {
                  "start": {"line": 0, "character": 0},
                  "end": {"line": 0, "character": 10},
                },
              },
            },
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["minimal_decl"]
    check scenario.declaration.enabled == true
    check scenario.declaration.location.uri == "file:///minimal.nim"
    check scenario.declaration.location.range.start.line == 0
    check scenario.declaration.location.range.start.character == 0
    check scenario.declaration.location.range.`end`.line == 0
    check scenario.declaration.location.range.`end`.character == 10
    # locations should be empty since not specified
    check scenario.declaration.locations.len == 0

  test "DefinitionConfig initialization":
    let definitionContent = DefinitionContent(
      uri: "file:///test_definition.nim",
      range: Range(
        start: Position(line: 15, character: 2),
        `end`: Position(line: 15, character: 12),
      ),
    )

    let definitionConfig = DefinitionConfig(
      enabled: true, location: definitionContent, locations: @[definitionContent]
    )

    check definitionConfig.enabled == true
    check definitionConfig.location.uri == "file:///test_definition.nim"
    check definitionConfig.location.range.start.line == 15
    check definitionConfig.location.range.start.character == 2
    check definitionConfig.location.range.`end`.line == 15
    check definitionConfig.location.range.`end`.character == 12
    check definitionConfig.locations.len == 1
    check definitionConfig.locations[0].uri == "file:///test_definition.nim"

  test "loadConfigFile with definition configuration":
    let tempDir = getTempDir()
    configPath = tempDir / "test_definition_config.json"

    let testConfig =
      %*{
        "currentScenario": "definition_test",
        "scenarios": {
          "definition_test": {
            "name": "Definition Test Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {"enabled": false},
            "definition": {
              "enabled": true,
              "location": {
                "uri": "file:///single_definition.nim",
                "range": {
                  "start": {"line": 25, "character": 2},
                  "end": {"line": 25, "character": 12},
                },
              },
              "locations": [
                {
                  "uri": "file:///multi_definition1.nim",
                  "range": {
                    "start": {"line": 10, "character": 4},
                    "end": {"line": 10, "character": 14},
                  },
                },
                {
                  "uri": "file:///multi_definition2.nim",
                  "range": {
                    "start": {"line": 20, "character": 8},
                    "end": {"line": 20, "character": 18},
                  },
                },
              ],
            },
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
              "definition": 90,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true
    check sm.currentScenario == "definition_test"
    check sm.scenarios.len == 1
    check "definition_test" in sm.scenarios

    let scenario = sm.scenarios["definition_test"]
    check scenario.name == "Definition Test Scenario"
    check scenario.definition.enabled == true
    check scenario.delays.definition == 90

    # Check single location
    check scenario.definition.location.uri == "file:///single_definition.nim"
    check scenario.definition.location.range.start.line == 25
    check scenario.definition.location.range.start.character == 2
    check scenario.definition.location.range.`end`.line == 25
    check scenario.definition.location.range.`end`.character == 12

    # Check multiple locations
    check scenario.definition.locations.len == 2
    let loc1 = scenario.definition.locations[0]
    check loc1.uri == "file:///multi_definition1.nim"
    check loc1.range.start.line == 10
    check loc1.range.start.character == 4
    check loc1.range.`end`.line == 10
    check loc1.range.`end`.character == 14

    let loc2 = scenario.definition.locations[1]
    check loc2.uri == "file:///multi_definition2.nim"
    check loc2.range.start.line == 20
    check loc2.range.start.character == 8
    check loc2.range.`end`.line == 20
    check loc2.range.`end`.character == 18

  test "loadConfigFile with disabled definition":
    let tempDir = getTempDir()
    configPath = tempDir / "test_disabled_definition_config.json"

    let testConfig =
      %*{
        "currentScenario": "no_definition",
        "scenarios": {
          "no_definition": {
            "name": "No Definition Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {"enabled": false},
            "definition": {"enabled": false},
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
              "definition": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["no_definition"]
    check scenario.definition.enabled == false
    check scenario.definition.location.uri == ""
    check scenario.definition.locations.len == 0

  test "loadConfigFile without definition configuration creates default":
    let tempDir = getTempDir()
    configPath = tempDir / "test_no_definition_config.json"

    let testConfig =
      %*{
        "currentScenario": "no_def_config",
        "scenarios": {
          "no_def_config": {
            "name": "No Definition Config Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {"enabled": false},
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
              "definition": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["no_def_config"]
    check scenario.definition.enabled == false
    check scenario.definition.location.uri == ""
    check scenario.definition.locations.len == 0

  test "loadConfigFile with minimal definition configuration":
    let tempDir = getTempDir()
    configPath = tempDir / "test_minimal_definition_config.json"

    let testConfig =
      %*{
        "currentScenario": "minimal_def",
        "scenarios": {
          "minimal_def": {
            "name": "Minimal Definition Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {"enabled": false},
            "definition": {
              "enabled": true,
              "location": {
                "uri": "file:///minimal.nim",
                "range": {
                  "start": {"line": 5, "character": 0},
                  "end": {"line": 5, "character": 10},
                },
              },
            },
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
              "definition": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["minimal_def"]
    check scenario.definition.enabled == true
    check scenario.definition.location.uri == "file:///minimal.nim"
    check scenario.definition.location.range.start.line == 5
    check scenario.definition.location.range.start.character == 0
    check scenario.definition.location.range.`end`.line == 5
    check scenario.definition.location.range.`end`.character == 10
    # locations should be empty since not specified
    check scenario.definition.locations.len == 0

  test "TypeDefinitionConfig initialization":
    let typeDefinitionContent = TypeDefinitionContent(
      uri: "file:///test_type_definition.nim",
      range: Range(
        start: Position(line: 8, character: 0), `end`: Position(line: 8, character: 10)
      ),
    )

    let typeDefinitionConfig = TypeDefinitionConfig(
      enabled: true,
      location: typeDefinitionContent,
      locations: @[typeDefinitionContent],
    )

    check typeDefinitionConfig.enabled == true
    check typeDefinitionConfig.location.uri == "file:///test_type_definition.nim"
    check typeDefinitionConfig.location.range.start.line == 8
    check typeDefinitionConfig.location.range.start.character == 0
    check typeDefinitionConfig.location.range.`end`.line == 8
    check typeDefinitionConfig.location.range.`end`.character == 10
    check typeDefinitionConfig.locations.len == 1
    check typeDefinitionConfig.locations[0].uri == "file:///test_type_definition.nim"

  test "loadConfigFile with typeDefinition configuration":
    let tempDir = getTempDir()
    configPath = tempDir / "test_type_definition_config.json"

    let testConfig =
      %*{
        "currentScenario": "type_definition_test",
        "scenarios": {
          "type_definition_test": {
            "name": "Type Definition Test Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {"enabled": false},
            "definition": {"enabled": false},
            "typeDefinition": {
              "enabled": true,
              "location": {
                "uri": "file:///single_type_definition.nim",
                "range": {
                  "start": {"line": 8, "character": 0},
                  "end": {"line": 8, "character": 10},
                },
              },
              "locations": [
                {
                  "uri": "file:///multi_type_definition1.nim",
                  "range": {
                    "start": {"line": 5, "character": 0},
                    "end": {"line": 5, "character": 15},
                  },
                },
                {
                  "uri": "file:///multi_type_definition2.nim",
                  "range": {
                    "start": {"line": 12, "character": 5},
                    "end": {"line": 12, "character": 20},
                  },
                },
              ],
            },
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
              "definition": 0,
              "typeDefinition": 120,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true
    check sm.currentScenario == "type_definition_test"
    check sm.scenarios.len == 1
    check "type_definition_test" in sm.scenarios

    let scenario = sm.scenarios["type_definition_test"]
    check scenario.name == "Type Definition Test Scenario"
    check scenario.typeDefinition.enabled == true
    check scenario.delays.typeDefinition == 120

    # Check single location
    check scenario.typeDefinition.location.uri == "file:///single_type_definition.nim"
    check scenario.typeDefinition.location.range.start.line == 8
    check scenario.typeDefinition.location.range.start.character == 0
    check scenario.typeDefinition.location.range.`end`.line == 8
    check scenario.typeDefinition.location.range.`end`.character == 10

    # Check multiple locations
    check scenario.typeDefinition.locations.len == 2
    let loc1 = scenario.typeDefinition.locations[0]
    check loc1.uri == "file:///multi_type_definition1.nim"
    check loc1.range.start.line == 5
    check loc1.range.start.character == 0
    check loc1.range.`end`.line == 5
    check loc1.range.`end`.character == 15

    let loc2 = scenario.typeDefinition.locations[1]
    check loc2.uri == "file:///multi_type_definition2.nim"
    check loc2.range.start.line == 12
    check loc2.range.start.character == 5
    check loc2.range.`end`.line == 12
    check loc2.range.`end`.character == 20

  test "loadConfigFile with disabled typeDefinition":
    let tempDir = getTempDir()
    configPath = tempDir / "test_disabled_type_definition_config.json"

    let testConfig =
      %*{
        "currentScenario": "no_type_definition",
        "scenarios": {
          "no_type_definition": {
            "name": "No Type Definition Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {"enabled": false},
            "definition": {"enabled": false},
            "typeDefinition": {"enabled": false},
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
              "definition": 0,
              "typeDefinition": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["no_type_definition"]
    check scenario.typeDefinition.enabled == false
    check scenario.typeDefinition.location.uri == ""
    check scenario.typeDefinition.locations.len == 0

  test "loadConfigFile without typeDefinition configuration creates default":
    let tempDir = getTempDir()
    configPath = tempDir / "test_no_type_definition_config.json"

    let testConfig =
      %*{
        "currentScenario": "no_type_def_config",
        "scenarios": {
          "no_type_def_config": {
            "name": "No Type Definition Config Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {"enabled": false},
            "definition": {"enabled": false},
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
              "definition": 0,
              "typeDefinition": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["no_type_def_config"]
    check scenario.typeDefinition.enabled == false
    check scenario.typeDefinition.location.uri == ""
    check scenario.typeDefinition.locations.len == 0

  test "loadConfigFile with minimal typeDefinition configuration":
    let tempDir = getTempDir()
    configPath = tempDir / "test_minimal_type_definition_config.json"

    let testConfig =
      %*{
        "currentScenario": "minimal_type_def",
        "scenarios": {
          "minimal_type_def": {
            "name": "Minimal Type Definition Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {"enabled": false},
            "definition": {"enabled": false},
            "typeDefinition": {
              "enabled": true,
              "location": {
                "uri": "file:///minimal_type.nim",
                "range": {
                  "start": {"line": 3, "character": 5},
                  "end": {"line": 3, "character": 15},
                },
              },
            },
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
              "definition": 0,
              "typeDefinition": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["minimal_type_def"]
    check scenario.typeDefinition.enabled == true
    check scenario.typeDefinition.location.uri == "file:///minimal_type.nim"
    check scenario.typeDefinition.location.range.start.line == 3
    check scenario.typeDefinition.location.range.start.character == 5
    check scenario.typeDefinition.location.range.`end`.line == 3
    check scenario.typeDefinition.location.range.`end`.character == 15
    # locations should be empty since not specified
    check scenario.typeDefinition.locations.len == 0

  test "DelayConfig with typeDefinition field":
    let delayConfig = DelayConfig(
      hover: 150,
      completion: 100,
      diagnostics: 200,
      semanticTokens: 75,
      inlayHint: 50,
      declaration: 80,
      definition: 70,
      typeDefinition: 60,
      implementation: 85,
    )

    check delayConfig.hover == 150
    check delayConfig.completion == 100
    check delayConfig.diagnostics == 200
    check delayConfig.semanticTokens == 75
    check delayConfig.inlayHint == 50
    check delayConfig.declaration == 80
    check delayConfig.definition == 70
    check delayConfig.typeDefinition == 60
    check delayConfig.implementation == 85

  test "ImplementationConfig initialization":
    let implementationContent = ImplementationContent(
      uri: "file:///test_implementation.nim",
      range: Range(
        start: Position(line: 12, character: 3),
        `end`: Position(line: 12, character: 13),
      ),
    )

    let implementationConfig = ImplementationConfig(
      enabled: true,
      location: implementationContent,
      locations: @[implementationContent],
    )

    check implementationConfig.enabled == true
    check implementationConfig.location.uri == "file:///test_implementation.nim"
    check implementationConfig.location.range.start.line == 12
    check implementationConfig.location.range.start.character == 3
    check implementationConfig.location.range.`end`.line == 12
    check implementationConfig.location.range.`end`.character == 13
    check implementationConfig.locations.len == 1
    check implementationConfig.locations[0].uri == "file:///test_implementation.nim"

  test "loadConfigFile with implementation configuration":
    let tempDir = getTempDir()
    configPath = tempDir / "test_implementation_config.json"

    let testConfig =
      %*{
        "currentScenario": "implementation_test",
        "scenarios": {
          "implementation_test": {
            "name": "Implementation Test Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {"enabled": false},
            "definition": {"enabled": false},
            "typeDefinition": {"enabled": false},
            "implementation": {
              "enabled": true,
              "location": {
                "uri": "file:///single_implementation.nim",
                "range": {
                  "start": {"line": 18, "character": 4},
                  "end": {"line": 18, "character": 14},
                },
              },
              "locations": [
                {
                  "uri": "file:///multi_implementation1.nim",
                  "range": {
                    "start": {"line": 6, "character": 2},
                    "end": {"line": 6, "character": 12},
                  },
                },
                {
                  "uri": "file:///multi_implementation2.nim",
                  "range": {
                    "start": {"line": 15, "character": 8},
                    "end": {"line": 15, "character": 18},
                  },
                },
              ],
            },
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
              "definition": 0,
              "typeDefinition": 0,
              "implementation": 110,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true
    check sm.currentScenario == "implementation_test"
    check sm.scenarios.len == 1
    check "implementation_test" in sm.scenarios

    let scenario = sm.scenarios["implementation_test"]
    check scenario.name == "Implementation Test Scenario"
    check scenario.implementation.enabled == true
    check scenario.delays.implementation == 110

    # Check single location
    check scenario.implementation.location.uri == "file:///single_implementation.nim"
    check scenario.implementation.location.range.start.line == 18
    check scenario.implementation.location.range.start.character == 4
    check scenario.implementation.location.range.`end`.line == 18
    check scenario.implementation.location.range.`end`.character == 14

    # Check multiple locations
    check scenario.implementation.locations.len == 2
    let loc1 = scenario.implementation.locations[0]
    check loc1.uri == "file:///multi_implementation1.nim"
    check loc1.range.start.line == 6
    check loc1.range.start.character == 2
    check loc1.range.`end`.line == 6
    check loc1.range.`end`.character == 12

    let loc2 = scenario.implementation.locations[1]
    check loc2.uri == "file:///multi_implementation2.nim"
    check loc2.range.start.line == 15
    check loc2.range.start.character == 8
    check loc2.range.`end`.line == 15
    check loc2.range.`end`.character == 18

  test "loadConfigFile with disabled implementation":
    let tempDir = getTempDir()
    configPath = tempDir / "test_disabled_implementation_config.json"

    let testConfig =
      %*{
        "currentScenario": "no_implementation",
        "scenarios": {
          "no_implementation": {
            "name": "No Implementation Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {"enabled": false},
            "definition": {"enabled": false},
            "typeDefinition": {"enabled": false},
            "implementation": {"enabled": false},
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
              "definition": 0,
              "typeDefinition": 0,
              "implementation": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["no_implementation"]
    check scenario.implementation.enabled == false
    check scenario.implementation.location.uri == ""
    check scenario.implementation.locations.len == 0

  test "loadConfigFile without implementation configuration creates default":
    let tempDir = getTempDir()
    configPath = tempDir / "test_no_implementation_config.json"

    let testConfig =
      %*{
        "currentScenario": "no_impl_config",
        "scenarios": {
          "no_impl_config": {
            "name": "No Implementation Config Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {"enabled": false},
            "definition": {"enabled": false},
            "typeDefinition": {"enabled": false},
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
              "definition": 0,
              "typeDefinition": 0,
              "implementation": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["no_impl_config"]
    check scenario.implementation.enabled == false
    check scenario.implementation.location.uri == ""
    check scenario.implementation.locations.len == 0

  test "loadConfigFile with minimal implementation configuration":
    let tempDir = getTempDir()
    configPath = tempDir / "test_minimal_implementation_config.json"

    let testConfig =
      %*{
        "currentScenario": "minimal_impl",
        "scenarios": {
          "minimal_impl": {
            "name": "Minimal Implementation Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {"enabled": false},
            "definition": {"enabled": false},
            "typeDefinition": {"enabled": false},
            "implementation": {
              "enabled": true,
              "location": {
                "uri": "file:///minimal_impl.nim",
                "range": {
                  "start": {"line": 2, "character": 0},
                  "end": {"line": 2, "character": 10},
                },
              },
            },
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
              "definition": 0,
              "typeDefinition": 0,
              "implementation": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["minimal_impl"]
    check scenario.implementation.enabled == true
    check scenario.implementation.location.uri == "file:///minimal_impl.nim"
    check scenario.implementation.location.range.start.line == 2
    check scenario.implementation.location.range.start.character == 0
    check scenario.implementation.location.range.`end`.line == 2
    check scenario.implementation.location.range.`end`.character == 10
    # locations should be empty since not specified
    check scenario.implementation.locations.len == 0

  test "ReferenceContent initialization":
    let referenceContent = ReferenceContent(
      uri: "file:///test_reference.nim",
      range: Range(
        start: Position(line: 15, character: 8),
        `end`: Position(line: 15, character: 18),
      ),
    )

    check referenceContent.uri == "file:///test_reference.nim"
    check referenceContent.range.start.line == 15
    check referenceContent.range.start.character == 8
    check referenceContent.range.`end`.line == 15
    check referenceContent.range.`end`.character == 18

  test "ReferenceConfig initialization":
    let referenceContent1 = ReferenceContent(
      uri: "file:///reference1.nim",
      range: Range(
        start: Position(line: 10, character: 5),
        `end`: Position(line: 10, character: 15),
      ),
    )
    let referenceContent2 = ReferenceContent(
      uri: "file:///reference2.nim",
      range: Range(
        start: Position(line: 20, character: 3),
        `end`: Position(line: 20, character: 13),
      ),
    )

    let referenceConfig = ReferenceConfig(
      enabled: true,
      locations: @[referenceContent1, referenceContent2],
      includeDeclaration: true,
    )

    check referenceConfig.enabled == true
    check referenceConfig.includeDeclaration == true
    check referenceConfig.locations.len == 2
    check referenceConfig.locations[0].uri == "file:///reference1.nim"
    check referenceConfig.locations[1].uri == "file:///reference2.nim"

  test "loadConfigFile with references configuration":
    let tempDir = getTempDir()
    configPath = tempDir / "test_references_config.json"

    let testConfig =
      %*{
        "currentScenario": "references_test",
        "scenarios": {
          "references_test": {
            "name": "References Test Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {"enabled": false},
            "definition": {"enabled": false},
            "typeDefinition": {"enabled": false},
            "implementation": {"enabled": false},
            "references": {
              "enabled": true,
              "includeDeclaration": true,
              "locations": [
                {
                  "uri": "file:///reference1.nim",
                  "range": {
                    "start": {"line": 15, "character": 8},
                    "end": {"line": 15, "character": 18},
                  },
                },
                {
                  "uri": "file:///reference2.nim",
                  "range": {
                    "start": {"line": 42, "character": 12},
                    "end": {"line": 42, "character": 22},
                  },
                },
                {
                  "uri": "file:///reference3.nim",
                  "range": {
                    "start": {"line": 78, "character": 0},
                    "end": {"line": 78, "character": 10},
                  },
                },
              ],
            },
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
              "definition": 0,
              "typeDefinition": 0,
              "implementation": 0,
              "references": 75,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true
    check sm.currentScenario == "references_test"
    check sm.scenarios.len == 1
    check "references_test" in sm.scenarios

    let scenario = sm.scenarios["references_test"]
    check scenario.name == "References Test Scenario"
    check scenario.references.enabled == true
    check scenario.references.includeDeclaration == true
    check scenario.delays.references == 75

    # Check reference locations
    check scenario.references.locations.len == 3
    let ref1 = scenario.references.locations[0]
    check ref1.uri == "file:///reference1.nim"
    check ref1.range.start.line == 15
    check ref1.range.start.character == 8
    check ref1.range.`end`.line == 15
    check ref1.range.`end`.character == 18

    let ref2 = scenario.references.locations[1]
    check ref2.uri == "file:///reference2.nim"
    check ref2.range.start.line == 42
    check ref2.range.start.character == 12
    check ref2.range.`end`.line == 42
    check ref2.range.`end`.character == 22

    let ref3 = scenario.references.locations[2]
    check ref3.uri == "file:///reference3.nim"
    check ref3.range.start.line == 78
    check ref3.range.start.character == 0
    check ref3.range.`end`.line == 78
    check ref3.range.`end`.character == 10

  test "loadConfigFile with disabled references":
    let tempDir = getTempDir()
    configPath = tempDir / "test_disabled_references_config.json"

    let testConfig =
      %*{
        "currentScenario": "no_references",
        "scenarios": {
          "no_references": {
            "name": "No References Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {"enabled": false},
            "definition": {"enabled": false},
            "typeDefinition": {"enabled": false},
            "implementation": {"enabled": false},
            "references": {"enabled": false},
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
              "definition": 0,
              "typeDefinition": 0,
              "implementation": 0,
              "references": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["no_references"]
    check scenario.references.enabled == false
    check scenario.references.includeDeclaration == true # Default value
    check scenario.references.locations.len == 0

  test "loadConfigFile without references configuration creates default":
    let tempDir = getTempDir()
    configPath = tempDir / "test_no_references_config.json"

    let testConfig =
      %*{
        "currentScenario": "no_ref_config",
        "scenarios": {
          "no_ref_config": {
            "name": "No References Config Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {"enabled": false},
            "definition": {"enabled": false},
            "typeDefinition": {"enabled": false},
            "implementation": {"enabled": false},
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
              "definition": 0,
              "typeDefinition": 0,
              "implementation": 0,
              "references": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["no_ref_config"]
    check scenario.references.enabled == false
    check scenario.references.includeDeclaration == true # Default value
    check scenario.references.locations.len == 0

  test "loadConfigFile with minimal references configuration":
    let tempDir = getTempDir()
    configPath = tempDir / "test_minimal_references_config.json"

    let testConfig =
      %*{
        "currentScenario": "minimal_ref",
        "scenarios": {
          "minimal_ref": {
            "name": "Minimal References Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {"enabled": false},
            "definition": {"enabled": false},
            "typeDefinition": {"enabled": false},
            "implementation": {"enabled": false},
            "references": {
              "enabled": true,
              "locations": [
                {
                  "uri": "file:///minimal_ref.nim",
                  "range": {
                    "start": {"line": 5, "character": 0},
                    "end": {"line": 5, "character": 10},
                  },
                }
              ],
            },
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
              "definition": 0,
              "typeDefinition": 0,
              "implementation": 0,
              "references": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["minimal_ref"]
    check scenario.references.enabled == true
    check scenario.references.includeDeclaration == true # Default when not specified
    check scenario.references.locations.len == 1
    check scenario.references.locations[0].uri == "file:///minimal_ref.nim"
    check scenario.references.locations[0].range.start.line == 5
    check scenario.references.locations[0].range.start.character == 0
    check scenario.references.locations[0].range.`end`.line == 5
    check scenario.references.locations[0].range.`end`.character == 10

  test "loadConfigFile with references and includeDeclaration false":
    let tempDir = getTempDir()
    configPath = tempDir / "test_references_no_decl_config.json"

    let testConfig =
      %*{
        "currentScenario": "references_no_decl",
        "scenarios": {
          "references_no_decl": {
            "name": "References Without Declaration Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {"enabled": false},
            "definition": {"enabled": false},
            "typeDefinition": {"enabled": false},
            "implementation": {"enabled": false},
            "references": {
              "enabled": true,
              "includeDeclaration": false,
              "locations": [
                {
                  "uri": "file:///reference_only.nim",
                  "range": {
                    "start": {"line": 10, "character": 5},
                    "end": {"line": 10, "character": 15},
                  },
                }
              ],
            },
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
              "definition": 0,
              "typeDefinition": 0,
              "implementation": 0,
              "references": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["references_no_decl"]
    check scenario.references.enabled == true
    check scenario.references.includeDeclaration == false
    check scenario.references.locations.len == 1

  test "DelayConfig with references field":
    let delayConfig = DelayConfig(
      hover: 150,
      completion: 100,
      diagnostics: 200,
      semanticTokens: 75,
      inlayHint: 50,
      declaration: 80,
      definition: 70,
      typeDefinition: 60,
      implementation: 85,
      references: 95,
      documentHighlight: 90,
    )

    check delayConfig.hover == 150
    check delayConfig.completion == 100
    check delayConfig.diagnostics == 200
    check delayConfig.semanticTokens == 75
    check delayConfig.inlayHint == 50
    check delayConfig.declaration == 80
    check delayConfig.definition == 70
    check delayConfig.typeDefinition == 60
    check delayConfig.implementation == 85
    check delayConfig.references == 95
    check delayConfig.documentHighlight == 90

  test "loadConfigFile with documentHighlight configuration":
    let tempDir = getTempDir()
    configPath = tempDir / "test_document_highlight_config.json"

    let testConfig =
      %*{
        "currentScenario": "highlight_test",
        "scenarios": {
          "highlight_test": {
            "name": "Document Highlight Test Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {"enabled": false},
            "definition": {"enabled": false},
            "typeDefinition": {"enabled": false},
            "implementation": {"enabled": false},
            "references":
              {"enabled": false, "locations": [], "includeDeclaration": true},
            "documentHighlight": {
              "enabled": true,
              "highlights": [
                {
                  "range": {
                    "start": {"line": 10, "character": 5},
                    "end": {"line": 10, "character": 15},
                  },
                  "kind": 1,
                },
                {
                  "range": {
                    "start": {"line": 20, "character": 8},
                    "end": {"line": 20, "character": 18},
                  },
                  "kind": 2,
                },
                {
                  "range": {
                    "start": {"line": 25, "character": 12},
                    "end": {"line": 25, "character": 22},
                  },
                  "kind": 3,
                },
              ],
            },
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
              "definition": 0,
              "typeDefinition": 0,
              "implementation": 0,
              "references": 0,
              "documentHighlight": 45,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["highlight_test"]
    check scenario.documentHighlight.enabled == true
    check scenario.documentHighlight.highlights.len == 3

    # Check first highlight
    let highlight1 = scenario.documentHighlight.highlights[0]
    check highlight1.range.start.line == 10
    check highlight1.range.start.character == 5
    check highlight1.range.`end`.line == 10
    check highlight1.range.`end`.character == 15
    check highlight1.kind.get == 1 # Text

    # Check second highlight
    let highlight2 = scenario.documentHighlight.highlights[1]
    check highlight2.range.start.line == 20
    check highlight2.range.start.character == 8
    check highlight2.range.`end`.line == 20
    check highlight2.range.`end`.character == 18
    check highlight2.kind.get == 2 # Read

    # Check third highlight
    let highlight3 = scenario.documentHighlight.highlights[2]
    check highlight3.range.start.line == 25
    check highlight3.range.start.character == 12
    check highlight3.range.`end`.line == 25
    check highlight3.range.`end`.character == 22
    check highlight3.kind.get == 3 # Write

    check scenario.delays.documentHighlight == 45

  test "loadConfigFile with disabled documentHighlight":
    let tempDir = getTempDir()
    configPath = tempDir / "test_disabled_document_highlight_config.json"

    let testConfig =
      %*{
        "currentScenario": "no_highlight",
        "scenarios": {
          "no_highlight": {
            "name": "No Document Highlight Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {"enabled": false},
            "definition": {"enabled": false},
            "typeDefinition": {"enabled": false},
            "implementation": {"enabled": false},
            "references":
              {"enabled": false, "locations": [], "includeDeclaration": true},
            "documentHighlight": {"enabled": false},
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
              "definition": 0,
              "typeDefinition": 0,
              "implementation": 0,
              "references": 0,
              "documentHighlight": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["no_highlight"]
    check scenario.documentHighlight.enabled == false
    check scenario.documentHighlight.highlights.len == 0

  test "loadConfigFile without documentHighlight configuration creates default":
    let tempDir = getTempDir()
    configPath = tempDir / "test_no_document_highlight_config.json"

    let testConfig =
      %*{
        "currentScenario": "no_highlight_config",
        "scenarios": {
          "no_highlight_config": {
            "name": "No Document Highlight Config Scenario",
            "hover": {"enabled": false},
            "completion": {"enabled": false, "items": []},
            "diagnostics": {"enabled": false, "diagnostics": []},
            "semanticTokens": {"enabled": false, "tokens": []},
            "inlayHint": {"enabled": false, "hints": []},
            "declaration": {"enabled": false},
            "definition": {"enabled": false},
            "typeDefinition": {"enabled": false},
            "implementation": {"enabled": false},
            "references":
              {"enabled": false, "locations": [], "includeDeclaration": true},
            "delays": {
              "hover": 0,
              "completion": 0,
              "diagnostics": 0,
              "semanticTokens": 0,
              "inlayHint": 0,
              "declaration": 0,
              "definition": 0,
              "typeDefinition": 0,
              "implementation": 0,
              "references": 0,
              "documentHighlight": 0,
            },
          }
        },
      }

    writeFile(configPath, pretty(testConfig))

    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    let result = sm.loadConfigFile(configPath)
    check result == true

    let scenario = sm.scenarios["no_highlight_config"]
    check scenario.documentHighlight.enabled == false
    check scenario.documentHighlight.highlights.len == 0

  test "DocumentHighlightConfig with optional kind":
    let highlightConfig = DocumentHighlightConfig(
      enabled: true,
      highlights:
        @[
          DocumentHighlightContent(
            range: Range(
              start: Position(line: 5, character: 10),
              `end`: Position(line: 5, character: 20),
            ),
            kind: none(int), # No kind specified
          ),
          DocumentHighlightContent(
            range: Range(
              start: Position(line: 10, character: 0),
              `end`: Position(line: 10, character: 5),
            ),
            kind: some(2), # Read kind
          ),
        ],
    )

    check highlightConfig.enabled == true
    check highlightConfig.highlights.len == 2
    check highlightConfig.highlights[0].kind.isNone
    check highlightConfig.highlights[1].kind.isSome
    check highlightConfig.highlights[1].kind.get == 2
