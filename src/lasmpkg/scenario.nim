import std/[tables, os, json, options, strformat]

import logger
import protocol/types

export tables, json

type
  HoverContent = object
    kind*: string
    message*: string
    position: Option[Position]

  HoverConfig* = object
    enabled*: bool
    content*: Option[HoverContent]
    contents*: seq[HoverContent]

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
  let actualPath =
    if configPath == "":
      getCurrentDir() / "lsp-test-config.json"
    else:
      configPath

  logInfo("Loading configuration file: " & actualPath)

  if not fileExists(actualPath):
    logError("Configuration file not found: " & actualPath)
    return false

  try:
    logInfo("Reading configuration file content")
    let configContent = readFile(actualPath)
    logDebug("Parsing JSON configuration (size: " & $configContent.len & " bytes)")
    let config = parseJson(configContent)

    logDebug(fmt"Loaded JSON configuration: ${config}")

    if config.hasKey("currentScenario"):
      sm.currentScenario = config["currentScenario"].getStr()

    if config.hasKey("scenarios"):
      let scenariosNode = config["scenarios"]
      for scenarioName, scenarioData in scenariosNode.pairs():
        var scenario = Scenario()
        scenario.name = scenarioData{"name"}.getStr(scenarioName)

        if scenarioData.hasKey("hover"):
          # Load hover configuration
          let hoverNode = scenarioData["hover"]

          var h = HoverConfig(enabled: hoverNode["enabled"].getBool(false))

          if h.enabled:
            if hoverNode.contains("content"):
              # Handle single content field
              let
                kind =
                  if hoverNode["content"].contains("kind"):
                    hoverNode["content"]["kind"].getStr
                  else:
                    "plaintext"
                message =
                  if hoverNode["content"].contains("message"):
                    hoverNode["content"]["message"].getStr
                  else:
                    ""

              var hoverContent = HoverContent(kind: kind, message: message)
              if hoverNode["content"].contains("position"):
                let
                  line =
                    if hoverNode["content"]["position"].contains("line"):
                      hoverNode["content"]["position"]["line"].getInt
                    else:
                      0
                  character =
                    if hoverNode["content"]["position"].contains("character"):
                      hoverNode["content"]["position"]["character"].getInt(0)
                    else:
                      0

                hoverContent.position = some(Position(line: line, character: character))
              h.content = some(hoverContent)
            elif hoverNode.contains("contents"):
              # Handle contents array field
              h.contents = @[]
              for hoverContentNode in hoverNode["contents"]:
                let
                  kind =
                    if hoverContentNode.contains("kind"):
                      hoverContentNode["kind"].getStr
                    else:
                      "plaintext"
                  message =
                    if hoverContentNode.contains("message"):
                      hoverContentNode["message"].getStr
                    else:
                      ""

                var hoverContent = HoverContent(kind: kind, message: message)
                if hoverContentNode.contains("position"):
                  let
                    line =
                      if hoverContentNode["position"].contains("line"):
                        hoverContentNode["position"]["line"].getInt
                      else:
                        0
                    character =
                      if hoverContentNode["position"].contains("character"):
                        hoverContentNode["position"]["character"].getInt(0)
                      else:
                        0

                  hoverContent.position =
                    some(Position(line: line, character: character))
                h.contents.add(hoverContent)

          scenario.hover = h

        if scenarioData.hasKey("delays"):
          # Load delay configuration
          let delaysNode = scenarioData["delays"]
          scenario.delays = DelayConfig(hover: delaysNode["hover"].getInt(0))

        if scenarioData.hasKey("errors"):
          # Load error configuration
          let errorsNode = scenarioData["errors"]
          for errorType, errorData in errorsNode.pairs():
            scenario.errors[errorType] = ErrorConfig(
              code: errorData["code"].getInt(-32603),
              message: errorData["message"].getStr("Unknown error"),
            )

        sm.scenarios[scenarioName] = scenario

    logInfo(
      "Configuration loaded successfully from: " & actualPath & " (" & $sm.scenarios.len &
        " scenarios)"
    )
    return true
  except Catchableerror as e:
    logError("Error loading configuration from: " & actualPath & " - " & e.msg)
    return false

proc newScenarioManager*(configPath: string = ""): ScenarioManager =
  result = ScenarioManager()
  result.currentScenario = "default"
  result.configPath =
    if configPath == "":
      getCurrentDir() / "lsp-test-config.json"
    else:
      configPath
  if not result.loadConfigFile(result.configPath):
    logError("Failed to load configuration file, exiting: " & result.configPath)
    quit(1)

proc getCurrentScenario*(sm: ScenarioManager): Scenario =
  if sm.currentScenario in sm.scenarios:
    return sm.scenarios[sm.currentScenario]
  else:
    return sm.scenarios["default"]

proc setScenario*(sm: ScenarioManager, scenarioName: string): bool =
  if scenarioName in sm.scenarios:
    sm.currentScenario = scenarioName
    logInfo("Switched to scenario: " & scenarioName)
    return true
  else:
    logWarn("Attempted to switch to unknown scenario: " & scenarioName)
    return false

proc listScenarios*(
    sm: ScenarioManager
): seq[tuple[name: string, description: string]] =
  for name, scenario in sm.scenarios.pairs():
    result.add((name: name, description: scenario.name))

proc createSampleConfig*(sm: ScenarioManager) =
  let sampleConfig =
    %*{
      "currentScenario": "default",
      "scenarios": {
        "default": {
          "name": "Default Testing",
          "hover": {
            "enabled": true,
            "contents": [
              {
                "kind": "markdown",
                "message": "**Default Symbol**\n\nThis is a default test symbol.",
                "position": {"line": 0, "character": 0},
              }
            ],
          },
          "delays": {"completion": 100, "diagnostics": 200, "hover": 50},
        }
      },
    }

  let configPath = getCurrentDir() / "lsp-test-config-sample.json"
  writeFile(configPath, pretty(sampleConfig, 2))
  stderr.writeLine("Sample config created at " & configPath)
