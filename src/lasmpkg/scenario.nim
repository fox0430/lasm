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

  ReferenceContent* = object
    uri*: string
    range*: Range

  ReferenceConfig* = object
    enabled*: bool
    locations*: seq[ReferenceContent]
    includeDeclaration*: bool

  DocumentHighlightContent* = object
    range*: Range
    kind*: Option[int] # DocumentHighlightKind

  DocumentHighlightConfig* = object
    enabled*: bool
    highlights*: seq[DocumentHighlightContent]

  CallHierarchyItemContent* = object
    name*: string
    kind*: int
    detail*: Option[string]
    uri*: string
    range*: Range
    selectionRange*: Range

  PrepareCallHierarchyConfig* = object
    enabled*: bool
    items*: seq[CallHierarchyItemContent]

  CallHierarchyIncomingContent* = object
    `from`*: CallHierarchyItemContent
    fromRanges*: seq[Range]

  CallHierarchyIncomingConfig* = object
    enabled*: bool
    calls*: seq[CallHierarchyIncomingContent]

  CallHierarchyOutgoingContent* = object
    to*: CallHierarchyItemContent
    fromRanges*: seq[Range]

  CallHierarchyOutgoingConfig* = object
    enabled*: bool
    calls*: seq[CallHierarchyOutgoingContent]

  RenameEditChange* = object
    uri*: string
    edits*: seq[TextEdit]

  RenameDocumentChange* = object
    textDocument*: VersionedTextDocumentIdentifier
    edits*: seq[TextEdit]

  RenameWorkspaceEdit* = object
    changes*: seq[RenameEditChange]
    documentChanges*: seq[RenameDocumentChange]

  RenameConfig* = object
    enabled*: bool
    workspaceEdit*: RenameWorkspaceEdit

  FormattingContent* = object
    range*: Range
    newText*: string

  FormattingConfig* = object
    enabled*: bool
    edits*: seq[FormattingContent]

  RangeFormattingContent* = object
    range*: Range
    newText*: string

  RangeFormattingConfig* = object
    enabled*: bool
    edits*: seq[RangeFormattingContent]

  DocumentSymbolContent* = ref object
    name*: string
    detail*: Option[string]
    kind*: int # SymbolKind
    tags*: seq[int] # SymbolTag
    deprecated*: Option[bool]
    range*: Range
    selectionRange*: Range
    children*: seq[DocumentSymbolContent]

  DocumentSymbolConfig* = object
    enabled*: bool
    symbols*: seq[DocumentSymbolContent]

  ParameterInformationContent* = object
    label*: string
    documentation*: Option[string]

  SignatureInformationContent* = object
    label*: string
    documentation*: Option[string]
    parameters*: seq[ParameterInformationContent]
    activeParameter*: Option[int]

  SignatureHelpConfig* = object
    enabled*: bool
    signatures*: seq[SignatureInformationContent]
    activeSignature*: Option[int]
    activeParameter*: Option[int]
    triggerCharacters*: seq[string]
    retriggerCharacters*: seq[string]

  DocumentLinkContent* = object
    range*: Range
    target*: Option[string]
    tooltip*: Option[string]

  DocumentLinkConfig* = object
    enabled*: bool
    links*: seq[DocumentLinkContent]

  ProgressNotificationContent* = object
    kind*: string # "begin" | "report" | "end"
    title*: Option[string]
    message*: Option[string]
    percentage*: Option[int]
    cancellable*: Option[bool]
    delay*: int # ms to wait before sending this notification

  ProgressConfig* = object
    enabled*: bool
    token*: string
    notifications*: seq[ProgressNotificationContent]

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
    references*: int
    documentHighlight*: int
    rename*: int
    formatting*: int
    rangeFormatting*: int
    prepareCallHierarchy*: int
    callHierarchyIncoming*: int
    callHierarchyOutgoing*: int
    documentSymbol*: int
    documentLink*: int
    signatureHelp*: int
    progress*: int

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
    references*: ReferenceConfig
    documentHighlight*: DocumentHighlightConfig
    rename*: RenameConfig
    formatting*: FormattingConfig
    rangeFormatting*: RangeFormattingConfig
    prepareCallHierarchy*: PrepareCallHierarchyConfig
    callHierarchyIncoming*: CallHierarchyIncomingConfig
    callHierarchyOutgoing*: CallHierarchyOutgoingConfig
    documentSymbol*: DocumentSymbolConfig
    documentLink*: DocumentLinkConfig
    signatureHelp*: SignatureHelpConfig
    progress*: ProgressConfig
    delays*: DelayConfig
    errors*: Table[string, ErrorConfig]

  ScenarioManager* = ref object
    scenarios*: Table[string, Scenario]
    currentScenario*: string
    configPath*: string

proc parseRange(rangeNode: JsonNode): Range =
  ## Parses a Range from a JSON node with the standard
  ## {"start": {...}, "end": {...}} shape.
  Range(
    start: Position(
      line: uinteger(rangeNode["start"]["line"].getInt(0)),
      character: uinteger(rangeNode["start"]["character"].getInt(0)),
    ),
    `end`: Position(
      line: uinteger(rangeNode["end"]["line"].getInt(0)),
      character: uinteger(rangeNode["end"]["character"].getInt(0)),
    ),
  )

proc parseCallHierarchyItem(itemNode: JsonNode): CallHierarchyItemContent =
  ## Parses a CallHierarchyItem from a JSON node.
  result = CallHierarchyItemContent(
    name: itemNode["name"].getStr(""),
    kind: itemNode{"kind"}.getInt(0),
    uri: itemNode["uri"].getStr(""),
    range: parseRange(itemNode["range"]),
    selectionRange: parseRange(itemNode["selectionRange"]),
  )
  if itemNode.hasKey("detail"):
    result.detail = some(itemNode["detail"].getStr(""))

proc parseFromRanges(callNode: JsonNode): seq[Range] =
  ## Parses the fromRanges array of a call hierarchy call.
  result = @[]
  if callNode.contains("fromRanges"):
    for rangeNode in callNode["fromRanges"]:
      result.add(parseRange(rangeNode))

proc parseDocumentLink(linkNode: JsonNode): DocumentLinkContent =
  ## Parses a DocumentLink from a JSON node.
  result = DocumentLinkContent(range: parseRange(linkNode["range"]))
  if linkNode.hasKey("target"):
    result.target = some(linkNode["target"].getStr(""))
  if linkNode.hasKey("tooltip"):
    result.tooltip = some(linkNode["tooltip"].getStr(""))

proc parseProgressNotification(notifNode: JsonNode): ProgressNotificationContent =
  ## Parses a progress notification entry from a JSON node.
  result = ProgressNotificationContent(
    kind: notifNode{"kind"}.getStr("report"), delay: notifNode{"delay"}.getInt(0)
  )
  if notifNode.hasKey("title"):
    result.title = some(notifNode["title"].getStr(""))
  if notifNode.hasKey("message"):
    result.message = some(notifNode["message"].getStr(""))
  if notifNode.hasKey("percentage"):
    result.percentage = some(notifNode["percentage"].getInt(0))
  if notifNode.hasKey("cancellable"):
    result.cancellable = some(notifNode["cancellable"].getBool(false))

proc parseParameterInformation(paramNode: JsonNode): ParameterInformationContent =
  ## Parses a ParameterInformation from a JSON node.
  result = ParameterInformationContent(label: paramNode["label"].getStr(""))
  if paramNode.hasKey("documentation"):
    result.documentation = some(paramNode["documentation"].getStr(""))

proc parseSignatureInformation(sigNode: JsonNode): SignatureInformationContent =
  ## Parses a SignatureInformation from a JSON node.
  result =
    SignatureInformationContent(label: sigNode["label"].getStr(""), parameters: @[])
  if sigNode.hasKey("documentation"):
    result.documentation = some(sigNode["documentation"].getStr(""))
  if sigNode.hasKey("activeParameter"):
    result.activeParameter = some(sigNode["activeParameter"].getInt(0))
  if sigNode.contains("parameters"):
    for paramNode in sigNode["parameters"]:
      result.parameters.add(parseParameterInformation(paramNode))

proc parseDocumentSymbol(symbolNode: JsonNode): DocumentSymbolContent =
  ## Parses a DocumentSymbol from a JSON node.
  result = DocumentSymbolContent(
    name: symbolNode["name"].getStr(""),
    kind: symbolNode{"kind"}.getInt(0),
    range: parseRange(symbolNode["range"]),
    selectionRange: parseRange(symbolNode["selectionRange"]),
    tags: @[],
    children: @[],
  )
  if symbolNode.hasKey("detail"):
    result.detail = some(symbolNode["detail"].getStr(""))
  if symbolNode.hasKey("deprecated"):
    result.deprecated = some(symbolNode["deprecated"].getBool(false))
  if symbolNode.contains("tags"):
    for tagNode in symbolNode["tags"]:
      result.tags.add(tagNode.getInt(0))
  if symbolNode.contains("children"):
    for childNode in symbolNode["children"]:
      result.children.add(parseDocumentSymbol(childNode))

proc loadConfigFile*(sm: ScenarioManager, configPath: string = ""): bool =
  # If configPath is empty, don't try to load any file
  if configPath == "":
    logInfo("No configuration file specified, using empty default scenario")
    return false

  let actualPath = configPath

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

              if diagNode.contains("range"):
                diag.range = parseRange(diagNode["range"])
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

        if scenarioData.hasKey("references"):
          # Load references configuration
          let referencesNode = scenarioData["references"]
          var rc = ReferenceConfig(enabled: referencesNode["enabled"].getBool(false))
          # Set includeDeclaration regardless of enabled status (defaults to true)
          rc.includeDeclaration = referencesNode{"includeDeclaration"}.getBool(true)
          if rc.enabled:
            # Handle multiple locations
            if referencesNode.contains("locations"):
              rc.locations = @[]
              for locNode in referencesNode["locations"]:
                let refContent = ReferenceContent(
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
                rc.locations.add(refContent)
          scenario.references = rc
        else:
          # Default references config if not specified
          scenario.references =
            ReferenceConfig(enabled: false, locations: @[], includeDeclaration: true)

        if scenarioData.hasKey("documentHighlight"):
          # Load document highlight configuration
          let documentHighlightNode = scenarioData["documentHighlight"]
          var dhc = DocumentHighlightConfig(
            enabled: documentHighlightNode["enabled"].getBool(false)
          )
          if dhc.enabled:
            # Handle multiple highlights
            if documentHighlightNode.contains("highlights"):
              dhc.highlights = @[]
              for highlightNode in documentHighlightNode["highlights"]:
                let highlightContent = DocumentHighlightContent(
                  range: Range(
                    start: Position(
                      line: uinteger(highlightNode["range"]["start"]["line"].getInt(0)),
                      character:
                        uinteger(highlightNode["range"]["start"]["character"].getInt(0)),
                    ),
                    `end`: Position(
                      line: uinteger(highlightNode["range"]["end"]["line"].getInt(0)),
                      character:
                        uinteger(highlightNode["range"]["end"]["character"].getInt(0)),
                    ),
                  ),
                  kind:
                    if highlightNode.hasKey("kind"):
                      some(highlightNode["kind"].getInt())
                    else:
                      none(int),
                )
                dhc.highlights.add(highlightContent)
          scenario.documentHighlight = dhc
        else:
          # Default document highlight config if not specified
          scenario.documentHighlight =
            DocumentHighlightConfig(enabled: false, highlights: @[])

        if scenarioData.hasKey("rename"):
          # Load rename configuration
          let renameNode = scenarioData["rename"]
          var rc = RenameConfig(enabled: renameNode["enabled"].getBool(false))
          if rc.enabled:
            # Initialize workspace edit
            rc.workspaceEdit = RenameWorkspaceEdit(changes: @[], documentChanges: @[])

            # Handle changes
            if renameNode.contains("workspaceEdit") and
                renameNode["workspaceEdit"].contains("changes"):
              for changeNode in renameNode["workspaceEdit"]["changes"]:
                var change =
                  RenameEditChange(uri: changeNode["uri"].getStr(""), edits: @[])
                if changeNode.contains("edits"):
                  for editNode in changeNode["edits"]:
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
                    change.edits.add(textEdit)
                rc.workspaceEdit.changes.add(change)

            # Handle documentChanges
            if renameNode.contains("workspaceEdit") and
                renameNode["workspaceEdit"].contains("documentChanges"):
              for docChangeNode in renameNode["workspaceEdit"]["documentChanges"]:
                var docChange = RenameDocumentChange(edits: @[])
                docChange.textDocument = VersionedTextDocumentIdentifier()
                docChange.textDocument.uri =
                  docChangeNode["textDocument"]["uri"].getStr("")
                docChange.textDocument.version =
                  some(%docChangeNode["textDocument"]["version"].getInt(1))

                if docChangeNode.contains("edits"):
                  for editNode in docChangeNode["edits"]:
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
                    docChange.edits.add(textEdit)
                rc.workspaceEdit.documentChanges.add(docChange)
          scenario.rename = rc
        else:
          # Default rename config if not specified
          scenario.rename = RenameConfig(
            enabled: false,
            workspaceEdit: RenameWorkspaceEdit(changes: @[], documentChanges: @[]),
          )

        if scenarioData.hasKey("formatting"):
          # Load formatting configuration
          let formattingNode = scenarioData["formatting"]
          var fc = FormattingConfig(enabled: formattingNode["enabled"].getBool(false))
          if fc.enabled:
            # Handle edits
            if formattingNode.contains("edits"):
              fc.edits = @[]
              for editNode in formattingNode["edits"]:
                let formattingContent = FormattingContent(
                  newText: editNode["newText"].getStr(""),
                  range: Range(
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
                  ),
                )
                fc.edits.add(formattingContent)
          scenario.formatting = fc
        else:
          # Default formatting config if not specified
          scenario.formatting = FormattingConfig(enabled: false, edits: @[])

        if scenarioData.hasKey("rangeFormatting"):
          # Load rangeFormatting configuration
          let rangeFormattingNode = scenarioData["rangeFormatting"]
          var rfc = RangeFormattingConfig(
            enabled: rangeFormattingNode["enabled"].getBool(false)
          )
          if rfc.enabled:
            # Handle edits
            if rangeFormattingNode.contains("edits"):
              rfc.edits = @[]
              for editNode in rangeFormattingNode["edits"]:
                let rangeFormattingContent = RangeFormattingContent(
                  newText: editNode["newText"].getStr(""),
                  range: parseRange(editNode["range"]),
                )
                rfc.edits.add(rangeFormattingContent)
          scenario.rangeFormatting = rfc
        else:
          # Default rangeFormatting config if not specified
          scenario.rangeFormatting = RangeFormattingConfig(enabled: false, edits: @[])

        if scenarioData.hasKey("prepareCallHierarchy"):
          # Load prepare call hierarchy configuration
          let prepareNode = scenarioData["prepareCallHierarchy"]
          var pc =
            PrepareCallHierarchyConfig(enabled: prepareNode["enabled"].getBool(false))
          if pc.enabled and prepareNode.contains("items"):
            pc.items = @[]
            for itemNode in prepareNode["items"]:
              pc.items.add(parseCallHierarchyItem(itemNode))
          scenario.prepareCallHierarchy = pc
        else:
          # Default prepare call hierarchy config if not specified
          scenario.prepareCallHierarchy =
            PrepareCallHierarchyConfig(enabled: false, items: @[])

        if scenarioData.hasKey("callHierarchyIncoming"):
          # Load incoming calls configuration
          let incomingNode = scenarioData["callHierarchyIncoming"]
          var ic =
            CallHierarchyIncomingConfig(enabled: incomingNode["enabled"].getBool(false))
          if ic.enabled and incomingNode.contains("calls"):
            ic.calls = @[]
            for callNode in incomingNode["calls"]:
              ic.calls.add(
                CallHierarchyIncomingContent(
                  `from`: parseCallHierarchyItem(callNode["from"]),
                  fromRanges: parseFromRanges(callNode),
                )
              )
          scenario.callHierarchyIncoming = ic
        else:
          # Default incoming calls config if not specified
          scenario.callHierarchyIncoming =
            CallHierarchyIncomingConfig(enabled: false, calls: @[])

        if scenarioData.hasKey("callHierarchyOutgoing"):
          # Load outgoing calls configuration
          let outgoingNode = scenarioData["callHierarchyOutgoing"]
          var oc =
            CallHierarchyOutgoingConfig(enabled: outgoingNode["enabled"].getBool(false))
          if oc.enabled and outgoingNode.contains("calls"):
            oc.calls = @[]
            for callNode in outgoingNode["calls"]:
              oc.calls.add(
                CallHierarchyOutgoingContent(
                  to: parseCallHierarchyItem(callNode["to"]),
                  fromRanges: parseFromRanges(callNode),
                )
              )
          scenario.callHierarchyOutgoing = oc
        else:
          # Default outgoing calls config if not specified
          scenario.callHierarchyOutgoing =
            CallHierarchyOutgoingConfig(enabled: false, calls: @[])

        if scenarioData.hasKey("documentSymbol"):
          # Load document symbol configuration
          let documentSymbolNode = scenarioData["documentSymbol"]
          var ds =
            DocumentSymbolConfig(enabled: documentSymbolNode["enabled"].getBool(false))
          if ds.enabled and documentSymbolNode.contains("symbols"):
            ds.symbols = @[]
            for symbolNode in documentSymbolNode["symbols"]:
              ds.symbols.add(parseDocumentSymbol(symbolNode))
          scenario.documentSymbol = ds
        else:
          # Default document symbol config if not specified
          scenario.documentSymbol = DocumentSymbolConfig(enabled: false, symbols: @[])

        if scenarioData.hasKey("documentLink"):
          # Load document link configuration
          let documentLinkNode = scenarioData["documentLink"]
          var dl =
            DocumentLinkConfig(enabled: documentLinkNode["enabled"].getBool(false))
          if dl.enabled and documentLinkNode.contains("links"):
            dl.links = @[]
            for linkNode in documentLinkNode["links"]:
              dl.links.add(parseDocumentLink(linkNode))
          scenario.documentLink = dl
        else:
          # Default document link config if not specified
          scenario.documentLink = DocumentLinkConfig(enabled: false, links: @[])

        if scenarioData.hasKey("signatureHelp"):
          # Load signature help configuration
          let signatureHelpNode = scenarioData["signatureHelp"]
          var sh = SignatureHelpConfig(
            enabled: signatureHelpNode["enabled"].getBool(false),
            signatures: @[],
            triggerCharacters: @[],
            retriggerCharacters: @[],
          )
          if signatureHelpNode.hasKey("activeSignature"):
            sh.activeSignature = some(signatureHelpNode["activeSignature"].getInt(0))
          if signatureHelpNode.hasKey("activeParameter"):
            sh.activeParameter = some(signatureHelpNode["activeParameter"].getInt(0))
          if signatureHelpNode.contains("triggerCharacters"):
            for charNode in signatureHelpNode["triggerCharacters"]:
              sh.triggerCharacters.add(charNode.getStr(""))
          if signatureHelpNode.contains("retriggerCharacters"):
            for charNode in signatureHelpNode["retriggerCharacters"]:
              sh.retriggerCharacters.add(charNode.getStr(""))
          if sh.enabled and signatureHelpNode.contains("signatures"):
            for sigNode in signatureHelpNode["signatures"]:
              sh.signatures.add(parseSignatureInformation(sigNode))
          scenario.signatureHelp = sh
        else:
          # Default signature help config if not specified
          scenario.signatureHelp = SignatureHelpConfig(
            enabled: false,
            signatures: @[],
            triggerCharacters: @[],
            retriggerCharacters: @[],
          )

        if scenarioData.hasKey("progress"):
          # Load progress configuration
          let progressNode = scenarioData["progress"]
          var pg = ProgressConfig(
            enabled: progressNode["enabled"].getBool(false),
            token: progressNode{"token"}.getStr(""),
          )
          if pg.enabled and progressNode.contains("notifications"):
            pg.notifications = @[]
            for notifNode in progressNode["notifications"]:
              pg.notifications.add(parseProgressNotification(notifNode))
          scenario.progress = pg
        else:
          # Default progress config if not specified
          scenario.progress =
            ProgressConfig(enabled: false, token: "", notifications: @[])

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
            references: delaysNode{"references"}.getInt(0),
            documentHighlight: delaysNode{"documentHighlight"}.getInt(0),
            rename: delaysNode{"rename"}.getInt(0),
            formatting: delaysNode{"formatting"}.getInt(0),
            rangeFormatting: delaysNode{"rangeFormatting"}.getInt(0),
            prepareCallHierarchy: delaysNode{"prepareCallHierarchy"}.getInt(0),
            callHierarchyIncoming: delaysNode{"callHierarchyIncoming"}.getInt(0),
            callHierarchyOutgoing: delaysNode{"callHierarchyOutgoing"}.getInt(0),
            documentSymbol: delaysNode{"documentSymbol"}.getInt(0),
            documentLink: delaysNode{"documentLink"}.getInt(0),
            signatureHelp: delaysNode{"signatureHelp"}.getInt(0),
            progress: delaysNode{"progress"}.getInt(0),
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
            references: 0,
            documentHighlight: 0,
            rename: 0,
            formatting: 0,
            rangeFormatting: 0,
            prepareCallHierarchy: 0,
            callHierarchyIncoming: 0,
            callHierarchyOutgoing: 0,
            documentSymbol: 0,
            documentLink: 0,
            signatureHelp: 0,
            progress: 0,
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

proc createEmptyScenario*(name: string = "default"): Scenario =
  ## Creates an empty scenario with all features disabled
  result = Scenario(
    name: name,
    hover: HoverConfig(enabled: false),
    completion: CompletionConfig(enabled: false),
    diagnostics: DiagnosticConfig(enabled: false),
    semanticTokens: SemanticTokensConfig(enabled: false),
    inlayHint: InlayHintConfig(enabled: false),
    declaration: DeclarationConfig(enabled: false),
    definition: DefinitionConfig(enabled: false),
    typeDefinition: TypeDefinitionConfig(enabled: false),
    implementation: ImplementationConfig(enabled: false),
    references: ReferenceConfig(enabled: false),
    documentHighlight: DocumentHighlightConfig(enabled: false),
    rename: RenameConfig(enabled: false),
    formatting: FormattingConfig(enabled: false),
    rangeFormatting: RangeFormattingConfig(enabled: false),
    prepareCallHierarchy: PrepareCallHierarchyConfig(enabled: false),
    callHierarchyIncoming: CallHierarchyIncomingConfig(enabled: false),
    callHierarchyOutgoing: CallHierarchyOutgoingConfig(enabled: false),
    documentSymbol: DocumentSymbolConfig(enabled: false),
    documentLink: DocumentLinkConfig(enabled: false),
    signatureHelp: SignatureHelpConfig(enabled: false),
    progress: ProgressConfig(enabled: false),
    delays: DelayConfig(),
    errors: initTable[string, ErrorConfig](),
  )

proc newScenarioManager*(configPath: string = ""): ScenarioManager =
  result = ScenarioManager()
  result.currentScenario = "default"
  result.configPath = configPath

  if not result.loadConfigFile(result.configPath):
    logInfo("Start without a configuration file")
    # Create an empty default scenario with all features disabled
    result.scenarios["default"] = createEmptyScenario("default")

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
  let sampleConfig = %*{
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
                "start": {"line": 5, "character": 0}, "end": {"line": 5, "character": 5}
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
          "references": 50,
          "documentHighlight": 45,
          "rename": 60,
          "formatting": 40,
          "rangeFormatting": 40,
          "prepareCallHierarchy": 40,
          "callHierarchyIncoming": 45,
          "callHierarchyOutgoing": 45,
          "documentSymbol": 40,
          "documentLink": 40,
          "signatureHelp": 30,
          "progress": 0,
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
              "start": {"line": 8, "character": 0}, "end": {"line": 8, "character": 10}
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
        "references": {
          "enabled": true,
          "includeDeclaration": true,
          "locations": [
            {
              "uri": "file:///path/to/reference1.nim",
              "range": {
                "start": {"line": 15, "character": 8},
                "end": {"line": 15, "character": 18},
              },
            },
            {
              "uri": "file:///path/to/reference2.nim",
              "range": {
                "start": {"line": 42, "character": 12},
                "end": {"line": 42, "character": 22},
              },
            },
          ],
        },
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
        "prepareCallHierarchy": {
          "enabled": true,
          "items": [
            {
              "name": "myFunction",
              "kind": 12,
              "detail": "proc myFunction()",
              "uri": "file:///path/to/file.nim",
              "range": {
                "start": {"line": 10, "character": 5},
                "end": {"line": 10, "character": 15},
              },
              "selectionRange": {
                "start": {"line": 10, "character": 5},
                "end": {"line": 10, "character": 15},
              },
            }
          ],
        },
        "callHierarchyIncoming": {
          "enabled": true,
          "calls": [
            {
              "from": {
                "name": "callerFunction",
                "kind": 12,
                "detail": "proc callerFunction()",
                "uri": "file:///path/to/caller.nim",
                "range": {
                  "start": {"line": 5, "character": 0},
                  "end": {"line": 8, "character": 1},
                },
                "selectionRange": {
                  "start": {"line": 5, "character": 5},
                  "end": {"line": 5, "character": 19},
                },
              },
              "fromRanges": [
                {
                  "start": {"line": 6, "character": 2},
                  "end": {"line": 6, "character": 12},
                }
              ],
            }
          ],
        },
        "callHierarchyOutgoing": {
          "enabled": true,
          "calls": [
            {
              "to": {
                "name": "calleeFunction",
                "kind": 12,
                "detail": "proc calleeFunction()",
                "uri": "file:///path/to/callee.nim",
                "range": {
                  "start": {"line": 20, "character": 0},
                  "end": {"line": 23, "character": 1},
                },
                "selectionRange": {
                  "start": {"line": 20, "character": 5},
                  "end": {"line": 20, "character": 19},
                },
              },
              "fromRanges": [
                {
                  "start": {"line": 11, "character": 2},
                  "end": {"line": 11, "character": 16},
                }
              ],
            }
          ],
        },
        "rename": {
          "enabled": true,
          "workspaceEdit": {
            "changes": [
              {
                "uri": "file:///path/to/file.nim",
                "edits": [
                  {
                    "range": {
                      "start": {"line": 5, "character": 10},
                      "end": {"line": 5, "character": 18},
                    },
                    "newText": "${newName}",
                  },
                  {
                    "range": {
                      "start": {"line": 12, "character": 5},
                      "end": {"line": 12, "character": 13},
                    },
                    "newText": "${newName}",
                  },
                ],
              }
            ],
            "documentChanges": [
              {
                "textDocument": {"uri": "file:///path/to/other.nim", "version": 1},
                "edits": [
                  {
                    "range": {
                      "start": {"line": 3, "character": 8},
                      "end": {"line": 3, "character": 16},
                    },
                    "newText": "${newName}",
                  }
                ],
              }
            ],
          },
        },
        "formatting": {
          "enabled": true,
          "edits": [
            {
              "range": {
                "start": {"line": 1, "character": 0},
                "end": {"line": 1, "character": 20},
              },
              "newText": "function formattedFunction() {",
            },
            {
              "range": {
                "start": {"line": 5, "character": 2},
                "end": {"line": 5, "character": 10},
              },
              "newText": "    return;",
            },
          ],
        },
        "rangeFormatting": {
          "enabled": true,
          "edits": [
            {
              "range": {
                "start": {"line": 2, "character": 0},
                "end": {"line": 2, "character": 15},
              },
              "newText": "    formattedLine",
            }
          ],
        },
        "documentSymbol": {
          "enabled": true,
          "symbols": [
            {
              "name": "MyClass",
              "detail": "class MyClass",
              "kind": 5,
              "range": {
                "start": {"line": 0, "character": 0},
                "end": {"line": 20, "character": 1},
              },
              "selectionRange": {
                "start": {"line": 0, "character": 6},
                "end": {"line": 0, "character": 13},
              },
              "children": [
                {
                  "name": "myMethod",
                  "detail": "proc myMethod()",
                  "kind": 6,
                  "range": {
                    "start": {"line": 5, "character": 2},
                    "end": {"line": 10, "character": 3},
                  },
                  "selectionRange": {
                    "start": {"line": 5, "character": 7},
                    "end": {"line": 5, "character": 15},
                  },
                },
                {
                  "name": "myField",
                  "detail": "field: int",
                  "kind": 8,
                  "range": {
                    "start": {"line": 2, "character": 2},
                    "end": {"line": 2, "character": 12},
                  },
                  "selectionRange": {
                    "start": {"line": 2, "character": 2},
                    "end": {"line": 2, "character": 9},
                  },
                },
              ],
            }
          ],
        },
        "documentLink": {
          "enabled": true,
          "links": [
            {
              "range": {
                "start": {"line": 0, "character": 4},
                "end": {"line": 0, "character": 24},
              },
              "target": "https://example.com/docs",
              "tooltip": "Open documentation",
            },
            {
              "range": {
                "start": {"line": 3, "character": 10},
                "end": {"line": 3, "character": 30},
              },
              "target": "file:///path/to/other.nim",
            },
          ],
        },
        "signatureHelp": {
          "enabled": true,
          "triggerCharacters": ["(", ","],
          "retriggerCharacters": [","],
          "activeSignature": 0,
          "activeParameter": 0,
          "signatures": [
            {
              "label": "func println(message: string): void",
              "documentation": "Prints a message to the console",
              "activeParameter": 0,
              "parameters":
                [{"label": "message: string", "documentation": "The message to print"}],
            },
            {
              "label": "func add(a: int, b: int): int",
              "documentation": "Adds two integers",
              "parameters": [
                {"label": "a: int", "documentation": "The first integer"},
                {"label": "b: int", "documentation": "The second integer"},
              ],
            },
          ],
        },
        "progress": {
          "enabled": true,
          "token": "lasm-progress-1",
          "notifications": [
            {
              "kind": "begin",
              "title": "Indexing",
              "message": "Starting",
              "percentage": 0,
              "cancellable": false,
              "delay": 0,
            },
            {
              "kind": "report",
              "message": "Halfway there",
              "percentage": 50,
              "delay": 200,
            },
            {"kind": "end", "message": "Done", "delay": 200},
          ],
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
        "references": {
          "enabled": true,
          "includeDeclaration": false,
          "locations": [
            {
              "uri": "file:///path/to/multi-ref1.nim",
              "range": {
                "start": {"line": 10, "character": 5},
                "end": {"line": 10, "character": 15},
              },
            },
            {
              "uri": "file:///path/to/multi-ref2.nim",
              "range": {
                "start": {"line": 22, "character": 3},
                "end": {"line": 22, "character": 13},
              },
            },
            {
              "uri": "file:///path/to/multi-ref3.nim",
              "range": {
                "start": {"line": 35, "character": 7},
                "end": {"line": 35, "character": 17},
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
