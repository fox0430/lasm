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
      delays: DelayConfig(
        hover: 100, completion: 0, diagnostics: 0, semanticTokens: 0, inlayHint: 0
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
      delays: DelayConfig(
        hover: 0, completion: 0, diagnostics: 0, semanticTokens: 0, inlayHint: 0
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
      delays: DelayConfig(
        hover: 100, completion: 0, diagnostics: 0, semanticTokens: 0, inlayHint: 0
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
      delays: DelayConfig(
        hover: 100, completion: 0, diagnostics: 0, semanticTokens: 0, inlayHint: 0
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
      delays: DelayConfig(
        hover: 50, completion: 0, diagnostics: 0, semanticTokens: 0, inlayHint: 0
      ),
      errors: initTable[string, ErrorConfig](),
    )

    sm.scenarios["scenario2"] = Scenario(
      name: "Second Scenario",
      hover: HoverConfig(enabled: false),
      completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
      diagnostics: DiagnosticConfig(enabled: false, diagnostics: @[]),
      semanticTokens: SemanticTokensConfig(enabled: false, tokens: @[]),
      delays: DelayConfig(
        hover: 100, completion: 0, diagnostics: 0, semanticTokens: 0, inlayHint: 0
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
      hover: 150, completion: 100, diagnostics: 200, semanticTokens: 75, inlayHint: 50
    )

    check delayConfig.hover == 150
    check delayConfig.completion == 100
    check delayConfig.diagnostics == 200
    check delayConfig.semanticTokens == 75
    check delayConfig.inlayHint == 50

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
