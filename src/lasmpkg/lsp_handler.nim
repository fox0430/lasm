import std/[sequtils, strutils, strformat, json, options, tables]

import pkg/chronos

import scenario, logger
import protocol/types

type LSPHandler* = ref object
  documents*: Table[string, Document]
  scenarioManager*: ScenarioManager

proc newLSPHandler*(scenarioManager: ScenarioManager): LSPHandler =
  result = LSPHandler()
  result.documents = initTable[string, Document]()
  result.scenarioManager = scenarioManager

proc handleInitialize*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  # Parse the InitializeParams from JSON
  let initParams = InitializeParams()

  # Extract process ID
  if params.hasKey("processId") and params["processId"].kind != JNull:
    initParams.processId = some(params["processId"])
    logInfo("Handling initialize request from client PID: " & $params["processId"])
  else:
    logInfo("Handling initialize request without client PID")

  # Create server capabilities using the protocol types
  let serverCapabilities = ServerCapabilities()

  # Set text document sync options
  let textDocSyncOptions = TextDocumentSyncOptions()
  textDocSyncOptions.openClose = some(true)
  textDocSyncOptions.change = some(2) # Incremental
  textDocSyncOptions.save = some(SaveOptions(includeText: some(true)))
  serverCapabilities.textDocumentSync = some(%textDocSyncOptions)

  # Set completion provider
  let completionOptions = CompletionOptions()
  completionOptions.triggerCharacters = some(@[".", ":", "(", " "])
  serverCapabilities.completionProvider = completionOptions

  # Set hover provider
  serverCapabilities.hoverProvider = some(true)

  # Set execute command provider
  let executeCommandOptions = ExecuteCommandOptions()
  executeCommandOptions.commands = some(
    @[
      "lsptest.switchScenario", "lsptest.listScenarios", "lsptest.reloadConfig",
      "lsptest.createSampleConfig", "lsptest.listOpenFiles",
    ]
  )
  serverCapabilities.executeCommandProvider = some(executeCommandOptions)

  # Set semantic tokens provider
  let semanticTokensLegend = SemanticTokensLegend()
  semanticTokensLegend.tokenTypes =
    @[
      "namespace", "type", "class", "enum", "interface", "struct", "typeParameter",
      "parameter", "variable", "property", "enumMember", "event", "function", "method",
      "macro", "keyword", "modifier", "comment", "string", "number", "regexp",
      "operator", "decorator",
    ]
  semanticTokensLegend.tokenModifiers =
    @[
      "declaration", "definition", "readonly", "static", "deprecated", "abstract",
      "async", "modification", "documentation", "defaultLibrary",
    ]

  let semanticTokensOptions = SemanticTokensOptions()
  semanticTokensOptions.legend = semanticTokensLegend
  semanticTokensOptions.range = some(true)
  semanticTokensOptions.full = some(%*{"delta": false})

  serverCapabilities.semanticTokensProvider = some(semanticTokensOptions)

  # Set inlay hint provider
  let inlayHintOptions = InlayHintOptions(resolveProvider: some(false))
  serverCapabilities.inlayHintProvider = some(inlayHintOptions)

  # Set declaration provider
  serverCapabilities.declarationProvider = some(true)

  # Create the InitializeResult
  let initResult = InitializeResult()
  initResult.capabilities = serverCapabilities

  # Convert result to JSON
  result = newJObject()
  var capabilitiesJson = %serverCapabilities
  # Add diagnosticProvider manually since it's not in the type definition
  capabilitiesJson["diagnosticProvider"] =
    %*{"interFileDependencies": false, "workspaceDiagnostics": false}
  result["capabilities"] = capabilitiesJson
  result["serverInfo"] = %*{"name": "LSP Test Server", "version": "0.1.0"}

proc handleExecuteCommand*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[tuple[response: JsonNode, notifications: seq[JsonNode]]] {.async.} =
  let command = params["command"].getStr()
  let args =
    if params.hasKey("arguments"):
      params["arguments"]
    else:
      newJArray()

  var notifications: seq[JsonNode] = @[]

  case command
  of "lsptest.switchScenario":
    if args.len > 0:
      let scenarioName = args[0].getStr()
      if handler.scenarioManager.setScenario(scenarioName):
        let response = %*{"success": true}
        notifications.add(
          %*{
            "method": "window/showMessage",
            "params": {"type": 3, "message": "Switched to scenario: " & scenarioName},
          }
        )
        return (response, notifications)
      else:
        raise newException(LSPError, "Unknown scenario: " & scenarioName)
    else:
      raise newException(LSPError, "Missing scenario name argument")
  of "lsptest.listScenarios":
    let scenarios = handler.scenarioManager.listScenarios()
    let scenarioList = scenarios.map(
      proc(s: auto): JsonNode =
        %*{"name": s.name, "description": s.description}
    )
    let response = %scenarioList
    let names = scenarios
      .map(
        proc(s: auto): string =
          s.name
      )
      .join(", ")
    notifications.add(
      %*{
        "method": "window/showMessage",
        "params": {"type": 3, "message": "Available scenarios: " & names},
      }
    )
    return (response, notifications)
  of "lsptest.reloadConfig":
    if handler.scenarioManager.loadConfigFile(handler.scenarioManager.configPath):
      let response = %*{"success": true}
      notifications.add(
        %*{
          "method": "window/showMessage",
          "params": {"type": 3, "message": "Configuration reloaded"},
        }
      )
      return (response, notifications)
    else:
      raise newException(LSPError, "Failed to reload configuration")
  of "lsptest.createSampleConfig":
    handler.scenarioManager.createSampleConfig()
    let response = %*{"success": true}
    notifications.add(
      %*{
        "method": "window/showMessage",
        "params": {"type": 3, "message": "Sample configuration file created"},
      }
    )
    return (response, notifications)
  of "lsptest.listOpenFiles":
    let openFiles = toSeq(handler.documents.keys()).map(
        proc(uri: string): JsonNode =
          let fileName = uri.split("/")[^1]
          let doc = handler.documents[uri]
          %*{
            "uri": uri,
            "fileName": fileName,
            "version": doc.version,
            "contentLength": doc.content.len,
          }
      )
    let response = %openFiles
    let fileNames = toSeq(handler.documents.keys())
      .map(
        proc(uri: string): string =
          uri.split("/")[^1]
      )
      .join(", ")
    let message =
      if handler.documents.len == 0:
        "No files currently open"
      else:
        fmt"Open files ({handler.documents.len}): {fileNames}"
    notifications.add(
      %*{"method": "window/showMessage", "params": {"type": 3, "message": message}}
    )
    return (response, notifications)
  else:
    raise newException(LSPError, "Unknown command: " & command)

proc publishDiagnostics*(
    handler: LSPHandler, uri: string
): Future[seq[JsonNode]] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  var notifications: seq[JsonNode] = @[]

  # Apply delay if configured
  if scenario.delays.diagnostics > 0:
    await sleepAsync(scenario.delays.diagnostics.milliseconds)

  # Check if diagnostics are enabled
  if not scenario.diagnostics.enabled:
    # Clear diagnostics if disabled
    let publishParams = PublishDiagnosticsParams()
    publishParams.uri = uri
    publishParams.diagnostics = some(newSeq[Diagnostic]())

    let notification = newJObject()
    notification["method"] = %"textDocument/publishDiagnostics"
    notification["params"] = %publishParams
    notifications.add(notification)
    return notifications

  # Check for error injection
  if "diagnostics" in scenario.errors:
    let error = scenario.errors["diagnostics"]
    logError("Error injected for diagnostics: " & error.message)
    # Don't publish diagnostics on error
    return @[]

  # Create diagnostics from scenario configuration
  let publishParams = PublishDiagnosticsParams()
  publishParams.uri = uri
  var diagnostics: seq[Diagnostic] = @[]

  for diagContent in scenario.diagnostics.diagnostics:
    let diagnostic = Diagnostic()
    diagnostic.range = diagContent.range
    diagnostic.severity = some(diagContent.severity)
    diagnostic.message = diagContent.message

    if diagContent.code.isSome:
      diagnostic.code = some(%diagContent.code.get)

    if diagContent.source.isSome:
      diagnostic.source = diagContent.source

    if diagContent.relatedInformation.len > 0:
      diagnostic.relatedInformation = some(diagContent.relatedInformation)

    diagnostics.add(diagnostic)

  publishParams.diagnostics = some(diagnostics)

  let notification = newJObject()
  notification["method"] = %"textDocument/publishDiagnostics"
  notification["params"] = %publishParams

  notifications.add(notification)

  # Log diagnostic publishing
  let logParams = LogMessageParams()
  logParams.`type` = 5 # Log message
  logParams.message =
    fmt"Published {diagnostics.len} diagnostics for {uri.split('/')[^1]}"

  let logNotification = newJObject()
  logNotification["method"] = %"window/logMessage"
  logNotification["params"] = %logParams
  notifications.add(logNotification)

  return notifications

proc handleDidOpen*(
    handler: LSPHandler, params: JsonNode
): Future[seq[JsonNode]] {.async.} =
  # Parse the DidOpenTextDocumentParams from JSON
  let didOpenParams = DidOpenTextDocumentParams()

  # Extract TextDocumentItem
  let textDocJson = params["textDocument"]
  let textDocItem = TextDocumentItem()
  textDocItem.uri = textDocJson["uri"].getStr
  textDocItem.languageId = textDocJson["languageId"].getStr
  textDocItem.version = textDocJson["version"].getInt
  textDocItem.text = textDocJson["text"].getStr

  didOpenParams.textDocument = textDocItem

  # Store the document
  handler.documents[textDocItem.uri] =
    Document(content: textDocItem.text, version: textDocItem.version)

  let documentCount = handler.documents.len
  let fileName = textDocItem.uri.split("/")[^1]

  # Create LogMessageParams for the notification
  let logParams = LogMessageParams()
  logParams.`type` = 5 # Log message
  logParams.message = fmt"Opened document: {fileName} (total: {documentCount} files)"

  let notification = newJObject()
  notification["method"] = %"window/logMessage"
  notification["params"] = %logParams

  var notifications = @[notification]

  # Publish diagnostics for the opened document
  let diagnosticNotifications = await handler.publishDiagnostics(textDocItem.uri)
  notifications.add(diagnosticNotifications)

  return notifications

proc handleDidChange*(
    handler: LSPHandler, params: JsonNode
): Future[seq[JsonNode]] {.async.} =
  # Parse the DidChangeTextDocumentParams from JSON
  let didChangeParams = DidChangeTextDocumentParams()

  # Extract VersionedTextDocumentIdentifier
  let textDocJson = params["textDocument"]
  let versionedTextDoc = VersionedTextDocumentIdentifier()
  versionedTextDoc.uri = textDocJson["uri"].getStr()
  versionedTextDoc.version = some(textDocJson["version"])
  didChangeParams.textDocument = versionedTextDoc

  # Extract content changes
  let contentChangesJson = params["contentChanges"]
  var contentChanges: seq[TextDocumentContentChangeEvent] = @[]

  for changeJson in contentChangesJson.items():
    let changeEvent = TextDocumentContentChangeEvent()
    changeEvent.text = changeJson["text"].getStr()

    if changeJson.hasKey("range"):
      let rangeJson = changeJson["range"]
      let startJson = rangeJson["start"]
      let endJson = rangeJson["end"]

      let startPos = Position(
        line: uinteger(startJson["line"].getInt),
        character: uinteger(startJson["character"].getInt),
      )
      let endPos = Position(
        line: uinteger(endJson["line"].getInt),
        character: uinteger(endJson["character"].getInt),
      )
      changeEvent.range = some(Range(start: startPos, `end`: endPos))

      if changeJson.hasKey("rangeLength"):
        changeEvent.rangeLength = some(changeJson["rangeLength"].getInt)

    contentChanges.add(changeEvent)

  didChangeParams.contentChanges = contentChanges

  # Apply changes to the document
  let version = textDocJson["version"].getInt()

  if versionedTextDoc.uri in handler.documents:
    # Apply all content changes
    for change in contentChanges:
      # For now, we just replace the entire content (simplified)
      handler.documents[versionedTextDoc.uri].content = change.text

    handler.documents[versionedTextDoc.uri].version = version

    let fileName = versionedTextDoc.uri.split("/")[^1]
    let contentLength = handler.documents[versionedTextDoc.uri].content.len

    # Create LogMessageParams for the notification
    let logParams = LogMessageParams()
    logParams.`type` = 5 # Log message
    logParams.message =
      fmt"Updated document: {fileName} (v{version}, {contentLength} chars)"

    let notification = newJObject()
    notification["method"] = %"window/logMessage"
    notification["params"] = %logParams

    var notifications = @[notification]

    # Publish diagnostics for the changed document
    let diagnosticNotifications = await handler.publishDiagnostics(versionedTextDoc.uri)
    notifications.add(diagnosticNotifications)

    return notifications
  else:
    let fileName = versionedTextDoc.uri.split("/")[^1]

    # Create LogMessageParams for the warning
    let logParams = LogMessageParams()
    logParams.`type` = 2 # Warning
    logParams.message = fmt"Warning: Attempted to update unopened document: {fileName}"

    let notification = newJObject()
    notification["method"] = %"window/logMessage"
    notification["params"] = %logParams

    return @[notification]

proc handleDidClose*(
    handler: LSPHandler, params: JsonNode
): Future[seq[JsonNode]] {.async.} =
  # Parse the DidCloseTextDocumentParams from JSON
  let didCloseParams = DidCloseTextDocumentParams()

  # Extract TextDocumentIdentifier
  let textDocJson = params["textDocument"]
  let textDocIdentifier = TextDocumentIdentifier()
  textDocIdentifier.uri = textDocJson["uri"].getStr()
  didCloseParams.textDocument = textDocIdentifier

  if textDocIdentifier.uri in handler.documents:
    handler.documents.del(textDocIdentifier.uri)
    let fileName = textDocIdentifier.uri.split("/")[^1]
    let remainingCount = handler.documents.len

    # Create LogMessageParams for the notification
    let logParams = LogMessageParams()
    logParams.`type` = 5 # Log message
    logParams.message =
      fmt"Closed document: {fileName} (remaining: {remainingCount} files)"

    let notification = newJObject()
    notification["method"] = %"window/logMessage"
    notification["params"] = %logParams

    var notifications = @[notification]

    # Clear diagnostics for the closed document
    let clearParams = PublishDiagnosticsParams()
    clearParams.uri = textDocIdentifier.uri
    clearParams.diagnostics = some(newSeq[Diagnostic]())

    let clearNotification = newJObject()
    clearNotification["method"] = %"textDocument/publishDiagnostics"
    clearNotification["params"] = %clearParams
    notifications.add(clearNotification)

    return notifications
  else:
    let fileName = textDocIdentifier.uri.split("/")[^1]

    # Create LogMessageParams for the warning
    let logParams = LogMessageParams()
    logParams.`type` = 2 # Warning
    logParams.message = fmt"Warning: Attempted to close unopened document: {fileName}"

    let notification = newJObject()
    notification["method"] = %"window/logMessage"
    notification["params"] = %logParams

    return @[notification]

proc handleHover*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  if scenario.delays.hover > 0:
    await sleepAsync(scenario.delays.hover.milliseconds)

  if not scenario.hover.enabled:
    return newJNull()

  if "hover" in scenario.errors:
    let error = scenario.errors["hover"]
    raise newException(LSPError, error.message)

  let position = params["position"]

  let hover = Hover()
  if scenario.hover.content.isSome:
    hover.contents = some(
      %*{
        "kind": scenario.hover.content.get.kind,
        "value": scenario.hover.content.get.message,
      }
    )
  elif scenario.hover.contents.len > 0:
    var contentsArray = newJArray()
    for hoverContent in scenario.hover.contents:
      contentsArray.add(%*{"kind": hoverContent.kind, "value": hoverContent.message})
    hover.contents = some(%contentsArray)
  else:
    hover.contents =
      some(%*{"kind": "plaintext", "value": "No hover information available"})
  hover.range = some(
    Range(
      start: Position(
        line: uinteger(position["line"].getInt),
        character: uinteger(position["character"].getInt),
      ),
      `end`: Position(
        line: uinteger(position["line"].getInt),
        character: uinteger(position["character"].getInt),
      ),
    )
  )

  return %hover

proc handleCompletion*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.completion > 0:
    await sleepAsync(scenario.delays.completion.milliseconds)

  # Check if completion is enabled
  if not scenario.completion.enabled:
    return newJNull()

  # Check for error injection
  if "completion" in scenario.errors:
    let error = scenario.errors["completion"]
    raise newException(LSPError, error.message)

  # Create completion list
  let completionList = CompletionList()
  completionList.isIncomplete = scenario.completion.isIncomplete
  completionList.items = some(newSeq[CompletionItem]())

  # Convert scenario items to LSP CompletionItems
  for item in scenario.completion.items:
    let completionItem = CompletionItem()
    completionItem.label = item.label
    completionItem.kind = some(item.kind)

    if item.detail.isSome:
      completionItem.detail = item.detail

    if item.documentation.isSome:
      completionItem.documentation = some(%item.documentation.get)

    if item.insertText.isSome:
      completionItem.insertText = item.insertText
    else:
      # Default to label if no insertText specified
      completionItem.insertText = some(item.label)

    if item.sortText.isSome:
      completionItem.sortText = item.sortText

    if item.filterText.isSome:
      completionItem.filterText = item.filterText

    completionList.items.get.add(completionItem)

  return %completionList

proc handleInitialized*(handler: LSPHandler): seq[JsonNode] =
  # Create the ShowMessageParams using protocol types
  let showMessageParams = ShowMessageParams()
  showMessageParams.`type` = 3 # Info message
  showMessageParams.message =
    "LSP Server ready! Current scenario: " & handler.scenarioManager.currentScenario

  # Create the notification
  let notification = newJObject()
  notification["method"] = %"window/showMessage"
  notification["params"] = %showMessageParams

  return @[notification]

proc handleDidChangeConfiguration*(
    handler: LSPHandler, params: JsonNode
): Future[seq[JsonNode]] {.async.} =
  logInfo("Received workspace/didChangeConfiguration with settings: " & $params)

  var notifications: seq[JsonNode] = @[]

  # Log the configuration change
  notifications.add(
    %*{
      "method": "window/logMessage",
      "params":
        {"type": 5, "message": "Received workspace/didChangeConfiguration notification"},
    }
  )

  return notifications

proc handleSemanticTokensFull*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.semanticTokens > 0:
    await sleepAsync(scenario.delays.semanticTokens.milliseconds)

  # Check if semantic tokens are enabled
  if not scenario.semanticTokens.enabled:
    return newJNull()

  # Check for error injection
  if "semanticTokens" in scenario.errors:
    let error = scenario.errors["semanticTokens"]
    raise newException(LSPError, error.message)

  # Extract text document URI
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()

  # Get document content if available
  if uri in handler.documents:
    let doc = handler.documents[uri]

    # Create semantic tokens from scenario configuration
    let semanticTokens = SemanticTokens()
    semanticTokens.resultId = some("result-" & $handler.documents.len)

    # Use configured tokens from scenario or generate sample tokens
    if scenario.semanticTokens.tokens.len > 0:
      semanticTokens.data = scenario.semanticTokens.tokens
    else:
      # Generate sample semantic tokens for demonstration
      # Format: [deltaLine, deltaStart, length, tokenType, tokenModifiers]
      semanticTokens.data =
        @[
          uinteger(0),
          uinteger(0),
          uinteger(8),
          uinteger(14),
          uinteger(0), # "function" keyword
          uinteger(0),
          uinteger(9),
          uinteger(4),
          uinteger(12),
          uinteger(1), # function name
          uinteger(1),
          uinteger(2),
          uinteger(3),
          uinteger(6),
          uinteger(0), # variable "var"
          uinteger(0),
          uinteger(4),
          uinteger(4),
          uinteger(15),
          uinteger(0), # type keyword
        ]

    return %semanticTokens
  else:
    # Document not found, return empty tokens
    let semanticTokens = SemanticTokens()
    semanticTokens.resultId = some("empty")
    semanticTokens.data = @[]
    return %semanticTokens

proc handleSemanticTokensRange*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.semanticTokens > 0:
    await sleepAsync(scenario.delays.semanticTokens.milliseconds)

  # Check if semantic tokens are enabled
  if not scenario.semanticTokens.enabled:
    return newJNull()

  # Check for error injection
  if "semanticTokens" in scenario.errors:
    let error = scenario.errors["semanticTokens"]
    raise newException(LSPError, error.message)

  # For simplicity, return the same as full semantic tokens
  # In a real implementation, this would filter tokens by range
  return await handler.handleSemanticTokensFull(id, params)

proc handleInlayHint*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.inlayHint > 0:
    await sleepAsync(scenario.delays.inlayHint.milliseconds)

  # Check if inlay hints are enabled
  if not scenario.inlayHint.enabled:
    return %(@[])

  # Check for error injection
  if "inlayHint" in scenario.errors:
    let error = scenario.errors["inlayHint"]
    raise newException(LSPError, error.message)

  # Extract text document URI and range
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()
  let rangeNode = params["range"]

  # Get document content if available
  if uri in handler.documents:
    let doc = handler.documents[uri]

    # Create inlay hints from scenario configuration
    var hints: seq[JsonNode] = @[]

    for hintContent in scenario.inlayHint.hints:
      let hint = InlayHint()
      hint.position = hintContent.position
      hint.label = hintContent.label

      if hintContent.kind.isSome:
        hint.kind = hintContent.kind

      if hintContent.tooltip.isSome:
        hint.tooltip = hintContent.tooltip

      if hintContent.paddingLeft.isSome:
        hint.paddingLeft = hintContent.paddingLeft

      if hintContent.paddingRight.isSome:
        hint.paddingRight = hintContent.paddingRight

      if hintContent.textEdits.len > 0:
        hint.textEdits = some(hintContent.textEdits)

      hints.add(%hint)

    return %hints
  else:
    # Document not found, return empty hints
    return %(@[])

proc handleDeclaration*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.declaration > 0:
    await sleepAsync(scenario.delays.declaration.milliseconds)

  # Check if declaration is enabled
  if not scenario.declaration.enabled:
    return newJNull()

  # Check for error injection
  if "declaration" in scenario.errors:
    let error = scenario.errors["declaration"]
    raise newException(LSPError, error.message)

  # Extract position information
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()
  let position = params["position"]

  # Get document content if available
  if uri in handler.documents:
    let doc = handler.documents[uri]

    # Create declaration response from scenario configuration
    if scenario.declaration.locations.len > 0:
      # Return array of locations
      var locations: seq[JsonNode] = @[]
      for loc in scenario.declaration.locations:
        let location = Location()
        location.uri = loc.uri
        location.range = loc.range
        locations.add(%location)
      return %locations
    elif scenario.declaration.location.uri != "":
      # Return single location
      let location = Location()
      location.uri = scenario.declaration.location.uri
      location.range = scenario.declaration.location.range
      return %location
    else:
      # No declaration found
      return newJNull()
  else:
    # Document not found
    return newJNull()
