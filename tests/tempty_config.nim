import std/[unittest, tables, os]

import ../src/lasmpkg/[scenario, logger]

suite "empty config path tests":
  setup:
    # Initialize logger for tests - disable logging
    setGlobalLogger(newFileLogger(enabled = false))

  test "ScenarioManager with empty config path creates default scenario":
    # Create scenario manager with empty config path
    let sm = newScenarioManager("")

    # Verify default scenario exists
    check sm.scenarios.len == 1
    check sm.currentScenario == "default"
    check sm.scenarios.hasKey("default")

    # Get the default scenario
    let scenario = sm.getCurrentScenario()
    check scenario.name == "default"

  test "All features disabled in empty config scenario":
    # Create scenario manager with empty config path
    let sm = newScenarioManager("")
    let scenario = sm.getCurrentScenario()

    # Check all features are disabled
    check scenario.hover.enabled == false
    check scenario.completion.enabled == false
    check scenario.diagnostics.enabled == false
    check scenario.semanticTokens.enabled == false
    check scenario.inlayHint.enabled == false
    check scenario.declaration.enabled == false
    check scenario.definition.enabled == false
    check scenario.typeDefinition.enabled == false
    check scenario.implementation.enabled == false
    check scenario.references.enabled == false
    check scenario.documentHighlight.enabled == false
    check scenario.rename.enabled == false
    check scenario.formatting.enabled == false

  test "ScenarioManager with non-existent config file creates default scenario":
    # Create scenario manager with non-existent file path
    let sm = newScenarioManager("/non/existent/config.json")

    # Verify default scenario exists
    check sm.scenarios.len == 1
    check sm.currentScenario == "default"
    check sm.scenarios.hasKey("default")

    # Verify all features are disabled
    let scenario = sm.getCurrentScenario()
    check scenario.hover.enabled == false
    check scenario.completion.enabled == false

  test "ScenarioManager with valid config loads scenarios":
    # Create a temporary config file
    let configPath = getTempDir() / "test_config.json"
    let configContent =
      """{
      "currentScenario": "test",
      "scenarios": {
        "test": {
          "name": "Test Scenario",
          "hover": {
            "enabled": true
          },
          "completion": {
            "enabled": false
          }
        }
      }
    }"""

    writeFile(configPath, configContent)

    try:
      # Create scenario manager with valid config
      let sm = newScenarioManager(configPath)

      # Verify scenario was loaded
      check sm.scenarios.len == 1
      check sm.currentScenario == "test"
      check sm.scenarios.hasKey("test")

      # Verify loaded scenario has correct settings
      let scenario = sm.getCurrentScenario()
      check scenario.name == "Test Scenario"
      check scenario.hover.enabled == true
      check scenario.completion.enabled == false
    finally:
      removeFile(configPath)

  test "createEmptyScenario creates scenario with all features disabled":
    let scenario = createEmptyScenario("custom")

    check scenario.name == "custom"
    check scenario.hover.enabled == false
    check scenario.completion.enabled == false
    check scenario.diagnostics.enabled == false
    check scenario.semanticTokens.enabled == false
    check scenario.inlayHint.enabled == false
    check scenario.declaration.enabled == false
    check scenario.definition.enabled == false
    check scenario.typeDefinition.enabled == false
    check scenario.implementation.enabled == false
    check scenario.references.enabled == false
    check scenario.documentHighlight.enabled == false
    check scenario.rename.enabled == false
    check scenario.formatting.enabled == false

    # Check delays are initialized (default values)
    check scenario.delays.hover == 0
    check scenario.delays.completion == 0

    # Check errors table is empty
    check scenario.errors.len == 0

  test "loadConfigFile returns false for empty path":
    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()

    # Test loading with empty path
    let result = sm.loadConfigFile("")

    check result == false
    check sm.scenarios.len == 0 # No scenarios loaded

  test "getCurrentScenario fallback behavior":
    let sm = ScenarioManager()
    sm.scenarios = initTable[string, Scenario]()
    sm.currentScenario = "non-existent"

    # Add a default scenario
    sm.scenarios["default"] = createEmptyScenario("default")

    # Should fall back to default scenario
    let scenario = sm.getCurrentScenario()
    check scenario.name == "default"
