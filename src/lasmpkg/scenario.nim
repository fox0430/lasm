import std/[tables, os, json, options, strformat]

import logger
import protocol/types

export tables, json

type
  HoverContent* = object
    kind*: string
    message*: string
    position: Option[Position]

  HoverConfig* = object
    enabled*: bool
    content*: Option[HoverContent]
    contents*: seq[HoverContent]

  CompletionContent* = object
    label*: string
    kind*: int # CompletionItemKind
    detail*: Option[string]
    documentation*: Option[string]
    insertText*: Option[string]
    sortText*: Option[string]
    filterText*: Option[string]

  CompletionConfig* = object
    enabled*: bool
    items*: seq[CompletionContent]
    isIncomplete*: bool

  DiagnosticContent* = object
    range*: Range
    severity*: int # DiagnosticSeverity
    code*: Option[string]
    source*: Option[string]
    message*: string
    tags*: seq[int] # DiagnosticTag
    relatedInformation*: seq[DiagnosticRelatedInformation]

  DiagnosticConfig* = object
    enabled*: bool
    diagnostics*: seq[DiagnosticContent]

  SemanticTokensConfig* = object
    enabled*: bool
    tokens*: seq[uinteger]

  InlayHintContent* = object
    position*: Position
    label*: string
    kind*: Option[int] # InlayHintKind
    tooltip*: Option[string]
    paddingLeft*: Option[bool]
    paddingRight*: Option[bool]
    textEdits*: seq[TextEdit]

  InlayHintConfig* = object
    enabled*: bool
    hints*: seq[InlayHintContent]

  DeclarationContent* = object
    uri*: string
    range*: Range

  DeclarationConfig* = object
    enabled*: bool
    location*: DeclarationContent
    locations*: seq[DeclarationContent]

  DefinitionContent* = object
    uri*: string
    range*: Range

  DefinitionConfig* = object
    enabled*: bool
    location*: DefinitionContent
    locations*: seq[DefinitionContent]

  TypeDefinitionContent* = object
    uri*: string
    range*: Range

  TypeDefinitionConfig* = object
    enabled*: bool
    location*: TypeDefinitionContent
    locations*: seq[TypeDefinitionContent]

  ImplementationContent* = object
    uri*: string
    range*: Range

  ImplementationConfig* = object
    enabled*: bool
    location*: ImplementationContent
    locations*: seq[ImplementationContent]

  DelayConfig* = object
    hover*: int
    completion*: int
    diagnostics*: int
    semanticTokens*: int
    inlayHint*: int
    declaration*: int
    definition*: int
    typeDefinition*: int
    implementation*: int

  ErrorConfig* = object
    code*: int
    message*: string

  Document* = object
    content*: string
    version*: int

  Scenario* = object
    name*: string
    hover*: HoverConfig
    completion*: CompletionConfig
    diagnostics*: DiagnosticConfig
    semanticTokens*: SemanticTokensConfig
    inlayHint*: InlayHintConfig
    declaration*: DeclarationConfig
    definition*: DefinitionConfig
    typeDefinition*: TypeDefinitionConfig
    implementation*: ImplementationConfig
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

    logDebug(fmt"Loaded JSON configuration: {config}")

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

        if scenarioData.hasKey("completion"):
          # Load completion configuration
          let completionNode = scenarioData["completion"]
          var c = CompletionConfig(
            enabled: completionNode["enabled"].getBool(false),
            isIncomplete: completionNode{"isIncomplete"}.getBool(false),
          )
          if c.enabled and completionNode.contains("items"):
            c.items = @[]
            for itemNode in completionNode["items"]:
              var item = CompletionContent(
                label: itemNode["label"].getStr(""),
                kind: itemNode{"kind"}.getInt(1), # Default to Text
              )
              if itemNode.contains("detail"):
                item.detail = some(itemNode["detail"].getStr())
              if itemNode.contains("documentation"):
                item.documentation = some(itemNode["documentation"].getStr())
              if itemNode.contains("insertText"):
                item.insertText = some(itemNode["insertText"].getStr())
              if itemNode.contains("sortText"):
                item.sortText = some(itemNode["sortText"].getStr())
              if itemNode.contains("filterText"):
                item.filterText = some(itemNode["filterText"].getStr())
              c.items.add(item)
          scenario.completion = c
        else:
          # Default completion config if not specified
          scenario.completion =
            CompletionConfig(enabled: false, isIncomplete: false, items: @[])

        if scenarioData.hasKey("diagnostics"):
          # Load diagnostics configuration
          let diagnosticsNode = scenarioData["diagnostics"]
          var d = DiagnosticConfig(enabled: diagnosticsNode["enabled"].getBool(false))
          if d.enabled and diagnosticsNode.contains("diagnostics"):
            d.diagnostics = @[]
            for diagNode in diagnosticsNode["diagnostics"]:
              var diag = DiagnosticContent(
                message: diagNode["message"].getStr(""),
                severity: diagNode{"severity"}.getInt(1), # Default to Error
              )

              # Parse range
              if diagNode.contains("range"):
                let rangeNode = diagNode["range"]
                diag.range = Range(
                  start: Position(
                    line: rangeNode["start"]["line"].getInt(0),
                    character: rangeNode["start"]["character"].getInt(0),
                  ),
                  `end`: Position(
                    line: rangeNode["end"]["line"].getInt(0),
                    character: rangeNode["end"]["character"].getInt(0),
                  ),
                )
              else:
                # Default to first character
                diag.range = Range(
                  start: Position(line: 0, character: 0),
                  `end`: Position(line: 0, character: 1),
                )

              if diagNode.contains("code"):
                diag.code = some(diagNode["code"].getStr())
              if diagNode.contains("source"):
                diag.source = some(diagNode["source"].getStr())
              if diagNode.contains("tags"):
                diag.tags = @[]
                for tagNode in diagNode["tags"]:
                  diag.tags.add(tagNode.getInt())
              else:
                diag.tags = @[]

              if diagNode.contains("relatedInformation"):
                diag.relatedInformation = @[]
                for relInfoNode in diagNode["relatedInformation"]:
                  var relInfo = DiagnosticRelatedInformation(
                    message: relInfoNode["message"].getStr("")
                  )
                  if relInfoNode.contains("location"):
                    let locNode = relInfoNode["location"]
                    relInfo.location = Location(
                      uri: locNode["uri"].getStr(""),
                      range: Range(
                        start: Position(
                          line: locNode["range"]["start"]["line"].getInt(0),
                          character: locNode["range"]["start"]["character"].getInt(0),
                        ),
                        `end`: Position(
                          line: locNode["range"]["end"]["line"].getInt(0),
                          character: locNode["range"]["end"]["character"].getInt(0),
                        ),
                      ),
                    )
                  diag.relatedInformation.add(relInfo)
              else:
                diag.relatedInformation = @[]

              d.diagnostics.add(diag)
          scenario.diagnostics = d
        else:
          # Default diagnostics config if not specified
          scenario.diagnostics = DiagnosticConfig(enabled: false, diagnostics: @[])

        if scenarioData.hasKey("semanticTokens"):
          # Load semantic tokens configuration
          let semanticTokensNode = scenarioData["semanticTokens"]
          var st =
            SemanticTokensConfig(enabled: semanticTokensNode["enabled"].getBool(false))
          if st.enabled and semanticTokensNode.contains("tokens"):
            st.tokens = @[]
            for tokenNode in semanticTokensNode["tokens"]:
              st.tokens.add(uinteger(tokenNode.getInt()))
          scenario.semanticTokens = st
        else:
          # Default semantic tokens config if not specified
          scenario.semanticTokens = SemanticTokensConfig(enabled: false, tokens: @[])

        if scenarioData.hasKey("inlayHint"):
          # Load inlay hint configuration
          let inlayHintNode = scenarioData["inlayHint"]
          var ih = InlayHintConfig(enabled: inlayHintNode["enabled"].getBool(false))
          if ih.enabled and inlayHintNode.contains("hints"):
            ih.hints = @[]
            for hintNode in inlayHintNode["hints"]:
              var hint = InlayHintContent(
                label: hintNode["label"].getStr(""),
                position: Position(
                  line: uinteger(hintNode["position"]["line"].getInt(0)),
                  character: uinteger(hintNode["position"]["character"].getInt(0)),
                ),
              )

              if hintNode.contains("kind"):
                hint.kind = some(hintNode["kind"].getInt())

              if hintNode.contains("tooltip"):
                hint.tooltip = some(hintNode["tooltip"].getStr())

              if hintNode.contains("paddingLeft"):
                hint.paddingLeft = some(hintNode["paddingLeft"].getBool())

              if hintNode.contains("paddingRight"):
                hint.paddingRight = some(hintNode["paddingRight"].getBool())

              if hintNode.contains("textEdits"):
                hint.textEdits = @[]
                for editNode in hintNode["textEdits"]:
                  let textEdit = TextEdit()
                  textEdit.newText = editNode["newText"].getStr("")
                  textEdit.range = Range(
                    start: Position(
                      line: uinteger(editNode["range"]["start"]["line"].getInt(0)),
                      character:
                        uinteger(editNode["range"]["start"]["character"].getInt(0)),
                    ),
                    `end`: Position(
                      line: uinteger(editNode["range"]["end"]["line"].getInt(0)),
                      character:
                        uinteger(editNode["range"]["end"]["character"].getInt(0)),
                    ),
                  )
                  hint.textEdits.add(textEdit)

              ih.hints.add(hint)
          scenario.inlayHint = ih
        else:
          # Default inlay hint config if not specified
          scenario.inlayHint = InlayHintConfig(enabled: false, hints: @[])

        if scenarioData.hasKey("declaration"):
          # Load declaration configuration
          let declarationNode = scenarioData["declaration"]
          var dc = DeclarationConfig(enabled: declarationNode["enabled"].getBool(false))
          if dc.enabled:
            # Handle single location
            if declarationNode.contains("location"):
              let locNode = declarationNode["location"]
              dc.location = DeclarationContent(
                uri: locNode["uri"].getStr(""),
                range: Range(
                  start: Position(
                    line: uinteger(locNode["range"]["start"]["line"].getInt(0)),
                    character:
                      uinteger(locNode["range"]["start"]["character"].getInt(0)),
                  ),
                  `end`: Position(
                    line: uinteger(locNode["range"]["end"]["line"].getInt(0)),
                    character: uinteger(locNode["range"]["end"]["character"].getInt(0)),
                  ),
                ),
              )

            # Handle multiple locations
            if declarationNode.contains("locations"):
              dc.locations = @[]
              for locNode in declarationNode["locations"]:
                let declContent = DeclarationContent(
                  uri: locNode["uri"].getStr(""),
                  range: Range(
                    start: Position(
                      line: uinteger(locNode["range"]["start"]["line"].getInt(0)),
                      character:
                        uinteger(locNode["range"]["start"]["character"].getInt(0)),
                    ),
                    `end`: Position(
                      line: uinteger(locNode["range"]["end"]["line"].getInt(0)),
                      character:
                        uinteger(locNode["range"]["end"]["character"].getInt(0)),
                    ),
                  ),
                )
                dc.locations.add(declContent)
          scenario.declaration = dc
        else:
          # Default declaration config if not specified
          scenario.declaration = DeclarationConfig(
            enabled: false,
            location: DeclarationContent(
              uri: "",
              range: Range(
                start: Position(line: 0, character: 0),
                `end`: Position(line: 0, character: 0),
              ),
            ),
            locations: @[],
          )

        if scenarioData.hasKey("definition"):
          # Load definition configuration
          let definitionNode = scenarioData["definition"]
          var defc = DefinitionConfig(enabled: definitionNode["enabled"].getBool(false))
          if defc.enabled:
            # Handle single location
            if definitionNode.contains("location"):
              let locNode = definitionNode["location"]
              defc.location = DefinitionContent(
                uri: locNode["uri"].getStr(""),
                range: Range(
                  start: Position(
                    line: uinteger(locNode["range"]["start"]["line"].getInt(0)),
                    character:
                      uinteger(locNode["range"]["start"]["character"].getInt(0)),
                  ),
                  `end`: Position(
                    line: uinteger(locNode["range"]["end"]["line"].getInt(0)),
                    character: uinteger(locNode["range"]["end"]["character"].getInt(0)),
                  ),
                ),
              )
            # Handle multiple locations
            if definitionNode.contains("locations"):
              defc.locations = @[]
              for locNode in definitionNode["locations"]:
                let defContent = DefinitionContent(
                  uri: locNode["uri"].getStr(""),
                  range: Range(
                    start: Position(
                      line: uinteger(locNode["range"]["start"]["line"].getInt(0)),
                      character:
                        uinteger(locNode["range"]["start"]["character"].getInt(0)),
                    ),
                    `end`: Position(
                      line: uinteger(locNode["range"]["end"]["line"].getInt(0)),
                      character:
                        uinteger(locNode["range"]["end"]["character"].getInt(0)),
                    ),
                  ),
                )
                defc.locations.add(defContent)
          scenario.definition = defc
        else:
          # Default definition config if not specified
          scenario.definition = DefinitionConfig(
            enabled: false,
            location: DefinitionContent(
              uri: "",
              range: Range(
                start: Position(line: 0, character: 0),
                `end`: Position(line: 0, character: 0),
              ),
            ),
            locations: @[],
          )

        if scenarioData.hasKey("typeDefinition"):
          # Load type definition configuration
          let typeDefinitionNode = scenarioData["typeDefinition"]
          var tdefc =
            TypeDefinitionConfig(enabled: typeDefinitionNode["enabled"].getBool(false))
          if tdefc.enabled:
            # Handle single location
            if typeDefinitionNode.contains("location"):
              let locNode = typeDefinitionNode["location"]
              tdefc.location = TypeDefinitionContent(
                uri: locNode["uri"].getStr(""),
                range: Range(
                  start: Position(
                    line: uinteger(locNode["range"]["start"]["line"].getInt(0)),
                    character:
                      uinteger(locNode["range"]["start"]["character"].getInt(0)),
                  ),
                  `end`: Position(
                    line: uinteger(locNode["range"]["end"]["line"].getInt(0)),
                    character: uinteger(locNode["range"]["end"]["character"].getInt(0)),
                  ),
                ),
              )
            # Handle multiple locations
            if typeDefinitionNode.contains("locations"):
              tdefc.locations = @[]
              for locNode in typeDefinitionNode["locations"]:
                let tdefContent = TypeDefinitionContent(
                  uri: locNode["uri"].getStr(""),
                  range: Range(
                    start: Position(
                      line: uinteger(locNode["range"]["start"]["line"].getInt(0)),
                      character:
                        uinteger(locNode["range"]["start"]["character"].getInt(0)),
                    ),
                    `end`: Position(
                      line: uinteger(locNode["range"]["end"]["line"].getInt(0)),
                      character:
                        uinteger(locNode["range"]["end"]["character"].getInt(0)),
                    ),
                  ),
                )
                tdefc.locations.add(tdefContent)
          scenario.typeDefinition = tdefc
        else:
          # Default type definition config if not specified
          scenario.typeDefinition = TypeDefinitionConfig(
            enabled: false,
            location: TypeDefinitionContent(
              uri: "",
              range: Range(
                start: Position(line: 0, character: 0),
                `end`: Position(line: 0, character: 0),
              ),
            ),
            locations: @[],
          )

        if scenarioData.hasKey("implementation"):
          # Load implementation configuration
          let implementationNode = scenarioData["implementation"]
          var imc =
            ImplementationConfig(enabled: implementationNode["enabled"].getBool(false))
          if imc.enabled:
            # Handle single location
            if implementationNode.contains("location"):
              let locNode = implementationNode["location"]
              imc.location = ImplementationContent(
                uri: locNode["uri"].getStr(""),
                range: Range(
                  start: Position(
                    line: uinteger(locNode["range"]["start"]["line"].getInt(0)),
                    character:
                      uinteger(locNode["range"]["start"]["character"].getInt(0)),
                  ),
                  `end`: Position(
                    line: uinteger(locNode["range"]["end"]["line"].getInt(0)),
                    character: uinteger(locNode["range"]["end"]["character"].getInt(0)),
                  ),
                ),
              )
            # Handle multiple locations
            if implementationNode.contains("locations"):
              imc.locations = @[]
              for locNode in implementationNode["locations"]:
                let imcContent = ImplementationContent(
                  uri: locNode["uri"].getStr(""),
                  range: Range(
                    start: Position(
                      line: uinteger(locNode["range"]["start"]["line"].getInt(0)),
                      character:
                        uinteger(locNode["range"]["start"]["character"].getInt(0)),
                    ),
                    `end`: Position(
                      line: uinteger(locNode["range"]["end"]["line"].getInt(0)),
                      character:
                        uinteger(locNode["range"]["end"]["character"].getInt(0)),
                    ),
                  ),
                )
                imc.locations.add(imcContent)
          scenario.implementation = imc
        else:
          # Default implementation config if not specified
          scenario.implementation = ImplementationConfig(
            enabled: false,
            location: ImplementationContent(
              uri: "",
              range: Range(
                start: Position(line: 0, character: 0),
                `end`: Position(line: 0, character: 0),
              ),
            ),
            locations: @[],
          )

        if scenarioData.hasKey("delays"):
          # Load delay configuration
          let delaysNode = scenarioData["delays"]
          scenario.delays = DelayConfig(
            hover: delaysNode{"hover"}.getInt(0),
            completion: delaysNode{"completion"}.getInt(0),
            diagnostics: delaysNode{"diagnostics"}.getInt(0),
            semanticTokens: delaysNode{"semanticTokens"}.getInt(0),
            inlayHint: delaysNode{"inlayHint"}.getInt(0),
            declaration: delaysNode{"declaration"}.getInt(0),
            definition: delaysNode{"definition"}.getInt(0),
            typeDefinition: delaysNode{"typeDefinition"}.getInt(0),
            implementation: delaysNode{"implementation"}.getInt(0),
          )
        else:
          # Default delay config if not specified
          scenario.delays = DelayConfig(
            hover: 0,
            completion: 0,
            diagnostics: 0,
            semanticTokens: 0,
            inlayHint: 0,
            declaration: 0,
            definition: 0,
            typeDefinition: 0,
            implementation: 0,
          )

        if scenarioData.hasKey("errors"):
          # Load error configuration
          let errorsNode = scenarioData["errors"]
          scenario.errors = initTable[string, ErrorConfig]()
          for errorType, errorData in errorsNode.pairs():
            scenario.errors[errorType] = ErrorConfig(
              code: errorData["code"].getInt(-32603),
              message: errorData["message"].getStr("Unknown error"),
            )
        else:
          # Default empty errors table if not specified
          scenario.errors = initTable[string, ErrorConfig]()

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
          "completion": {
            "enabled": true,
            "isIncomplete": false,
            "items": [
              {
                "label": "println",
                "kind": 3,
                "detail": "func println(message: string)",
                "documentation": "Prints a message to the console",
                "insertText": "println(${1:message})",
                "sortText": "1",
              },
              {
                "label": "variable",
                "kind": 6,
                "detail": "var variable: int",
                "documentation": "A sample variable",
                "insertText": "variable",
              },
              {
                "label": "TestClass",
                "kind": 7,
                "detail": "class TestClass",
                "documentation": "A test class for completion",
                "insertText": "TestClass",
              },
            ],
          },
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
              },
            ],
          },
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
            "completion": 100,
            "diagnostics": 200,
            "hover": 50,
            "semanticTokens": 30,
            "inlayHint": 25,
            "declaration": 40,
            "definition": 35,
            "typeDefinition": 30,
            "implementation": 35,
          },
          "semanticTokens": {
            "enabled": true,
            "tokens": [0, 0, 8, 14, 0, 0, 9, 4, 12, 1, 1, 2, 3, 6, 0, 0, 4, 4, 15, 0],
          },
          "declaration": {
            "enabled": true,
            "location": {
              "uri": "file:///path/to/declaration.nim",
              "range": {
                "start": {"line": 10, "character": 5},
                "end": {"line": 10, "character": 15},
              },
            },
          },
          "definition": {
            "enabled": true,
            "location": {
              "uri": "file:///path/to/implementation.nim",
              "range": {
                "start": {"line": 25, "character": 2},
                "end": {"line": 25, "character": 12},
              },
            },
          },
          "typeDefinition": {
            "enabled": true,
            "location": {
              "uri": "file:///path/to/type.nim",
              "range": {
                "start": {"line": 8, "character": 0},
                "end": {"line": 8, "character": 10},
              },
            },
          },
          "implementation": {
            "enabled": true,
            "location": {
              "uri": "file:///path/to/implementation.nim",
              "range": {
                "start": {"line": 30, "character": 0},
                "end": {"line": 30, "character": 20},
              },
            },
          },
        },
        "multi-location-testing": {
          "name": "Multi-location Definition Testing",
          "hover": {"enabled": false},
          "completion": {"enabled": false},
          "diagnostics": {"enabled": false},
          "semanticTokens": {"enabled": false},
          "inlayHint": {"enabled": false},
          "declaration": {
            "enabled": true,
            "locations": [
              {
                "uri": "file:///path/to/interface1.nim",
                "range": {
                  "start": {"line": 5, "character": 10},
                  "end": {"line": 5, "character": 20},
                },
              },
              {
                "uri": "file:///path/to/interface2.nim",
                "range": {
                  "start": {"line": 8, "character": 2},
                  "end": {"line": 8, "character": 12},
                },
              },
            ],
          },
          "definition": {
            "enabled": true,
            "locations": [
              {
                "uri": "file:///path/to/implementation1.nim",
                "range": {
                  "start": {"line": 15, "character": 4},
                  "end": {"line": 15, "character": 14},
                },
              },
              {
                "uri": "file:///path/to/implementation2.nim",
                "range": {
                  "start": {"line": 20, "character": 6},
                  "end": {"line": 20, "character": 16},
                },
              },
            ],
          },
          "implementation": {
            "enabled": true,
            "locations": [
              {
                "uri": "file:///path/to/implementation1.nim",
                "range": {
                  "start": {"line": 25, "character": 0},
                  "end": {"line": 25, "character": 15},
                },
              },
              {
                "uri": "file:///path/to/implementation2.nim",
                "range": {
                  "start": {"line": 30, "character": 2},
                  "end": {"line": 30, "character": 17},
                },
              },
            ],
          },
          "delays": {},
        },
      },
    }

  let configPath = getCurrentDir() / "lsp-test-config-sample.json"
  writeFile(configPath, pretty(sampleConfig, 2))
  stderr.writeLine("Sample config created at " & configPath)
