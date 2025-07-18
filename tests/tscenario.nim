import std/[unittest, json, os, tables, options]

import ../src/lasmpkg/[scenario, logger]

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
      delays: DelayConfig(hover: 100),
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
            "delays": {"hover": 50},
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
            "delays": {"hover": 25},
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
      delays: DelayConfig(hover: 0),
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
      delays: DelayConfig(hover: 100),
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
      delays: DelayConfig(hover: 100),
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
      delays: DelayConfig(hover: 50),
      errors: initTable[string, ErrorConfig](),
    )

    sm.scenarios["scenario2"] = Scenario(
      name: "Second Scenario",
      hover: HoverConfig(enabled: false),
      delays: DelayConfig(hover: 100),
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
      check defaultScenario.hasKey("delays")
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
    let delayConfig = DelayConfig(hover: 150)

    check delayConfig.hover == 150

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
