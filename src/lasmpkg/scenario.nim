import std/[tables, os, json]

export tables, json

type
  HoverConfig* = object
    enabled*: bool
    message*: string

  DelayConfig* = object
    hover*: int

  ErrorConfig* = object
    code*: int
    message*: string

  Document* = object
    content*: string
    version*: int

  Scenario* = object
    name*: string
    hover*: HoverConfig
    delays*: DelayConfig
    errors*: Table[string, ErrorConfig]

  ScenarioManager* = ref object
    scenarios*: Table[string, Scenario]
    currentScenario*: string
    configPath*: string

proc loadConfigFile*(sm: ScenarioManager, configPath: string = ""): bool =
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

proc newScenarioManager*(configPath: string = ""): ScenarioManager =
  result = ScenarioManager()
  result.currentScenario = "default"
  result.configPath = if configPath == "":
    getCurrentDir() / "lsp-test-config.json"
  else:
    configPath
  if not result.loadConfigFile(result.configPath):
    quit(1)

proc getCurrentScenario*(sm: ScenarioManager): Scenario =
  if sm.currentScenario in sm.scenarios:
    return sm.scenarios[sm.currentScenario]
  else:
    return sm.scenarios["default"]

proc setScenario*(sm: ScenarioManager, scenarioName: string): bool =
  if scenarioName in sm.scenarios:
    sm.currentScenario = scenarioName
    stderr.writeLine("Switched to scenario: " & scenarioName)
    return true
  return false

proc listScenarios*(sm: ScenarioManager): seq[tuple[name: string, description: string]] =
  for name, scenario in sm.scenarios.pairs():
    result.add((name: name, description: scenario.name))

proc createSampleConfig*(sm: ScenarioManager) =
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
