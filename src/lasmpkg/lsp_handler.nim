import std/[sequtils, strutils, strformat, json, options, tables, unicode]

import pkg/chronos

import scenario, logger
import protocol/types

type
  SendNotificationProc* =
    proc(methodName: string, params: JsonNode): Future[void] {.async.}

  LSPHandler* = ref object
    documents*: Table[string, Document]
    scenarioManager*: ScenarioManager
    sendNotification*: SendNotificationProc

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

  let currentScenario = handler.scenarioManager.getCurrentScenario()

  # Set completion provider
  let completionOptions = CompletionOptions()
  completionOptions.triggerCharacters = some(@[".", ":", "(", " "])
  if currentScenario.completionResolve.enabled:
    completionOptions.resolveProvider = some(true)
  serverCapabilities.completionProvider = completionOptions

  # Set hover provider
  serverCapabilities.hoverProvider = some(true)

  # Set signature help provider
  let signatureHelpOptions = SignatureHelpOptions()
  if currentScenario.signatureHelp.triggerCharacters.len > 0:
    signatureHelpOptions.triggerCharacters =
      some(currentScenario.signatureHelp.triggerCharacters)
  else:
    signatureHelpOptions.triggerCharacters = some(@["(", ","])
  serverCapabilities.signatureHelpProvider = signatureHelpOptions

  # Set execute command provider
  let executeCommandOptions = ExecuteCommandOptions()
  executeCommandOptions.commands = some(
    @[
      "lsptest.switchScenario", "lsptest.listScenarios", "lsptest.reloadConfig",
      "lsptest.createSampleConfig", "lsptest.listOpenFiles", "lsptest.sendProgress",
    ]
  )
  serverCapabilities.executeCommandProvider = some(executeCommandOptions)

  # Set semantic tokens provider
  let semanticTokensLegend = SemanticTokensLegend()
  semanticTokensLegend.tokenTypes = @[
    "namespace", "type", "class", "enum", "interface", "struct", "typeParameter",
    "parameter", "variable", "property", "enumMember", "event", "function", "method",
    "macro", "keyword", "modifier", "comment", "string", "number", "regexp", "operator",
    "decorator",
  ]
  semanticTokensLegend.tokenModifiers = @[
    "declaration", "definition", "readonly", "static", "deprecated", "abstract",
    "async", "modification", "documentation", "defaultLibrary",
  ]

  let semanticTokensOptions = SemanticTokensOptions()
  semanticTokensOptions.legend = semanticTokensLegend
  semanticTokensOptions.range = some(true)
  semanticTokensOptions.full = some(%*{"delta": true})

  serverCapabilities.semanticTokensProvider = some(semanticTokensOptions)

  # Set inlay hint provider
  let inlayHintOptions = InlayHintOptions(resolveProvider: some(false))
  serverCapabilities.inlayHintProvider = some(inlayHintOptions)

  # Set declaration provider
  serverCapabilities.declarationProvider = some(true)

  # Set definition provider
  serverCapabilities.definitionProvider = some(true)

  # Set type definition provider
  serverCapabilities.typeDefinitionProvider = some(true)

  # Set implementation provider
  serverCapabilities.implementationProvider = some(%true)

  # Set references provider
  serverCapabilities.referencesProvider = some(true)

  # Set document highlight provider
  serverCapabilities.documentHighlightProvider = some(true)

  # Set rename provider
  if currentScenario.prepareRename.enabled:
    serverCapabilities.renameProvider = %*{"prepareProvider": true}
  else:
    serverCapabilities.renameProvider = %true

  # Set document formatting provider
  serverCapabilities.documentFormattingProvider = some(true)

  # Set document range formatting provider
  serverCapabilities.documentRangeFormattingProvider = some(true)

  # Set call hierarchy provider
  serverCapabilities.callHierarchyProvider = some(true)

  # Set document symbol provider
  serverCapabilities.documentSymbolProvider = some(true)

  # Set workspace symbol provider
  serverCapabilities.workspaceSymbolProvider = some(true)

  # Set document link provider
  let documentLinkOptions = DocumentLinkOptions(resolveProvider: some(false))
  serverCapabilities.documentLinkProvider = some(documentLinkOptions)

  # Set selection range provider
  serverCapabilities.selectionRangeProvider = some(SelectionRangeOptions())

  # Set folding range provider
  serverCapabilities.foldingRangeProvider = some(FoldingRangeOptions())

  # Set code lens provider
  serverCapabilities.codeLensProvider = CodeLensOptions(resolveProvider: some(false))

  # Set code action provider
  let codeActionOptions = CodeActionOptions(resolveProvider: some(false))
  if currentScenario.codeAction.codeActionKinds.len > 0:
    codeActionOptions.codeActionKinds = some(currentScenario.codeAction.codeActionKinds)
  serverCapabilities.codeActionProvider = some(%codeActionOptions)

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

proc toProgressValueJson(c: ProgressNotificationContent): JsonNode =
  ## Builds the WorkDoneProgress{Begin,Report,End} value payload for a
  ## configured progress notification entry.
  result = newJObject()
  result["kind"] = %c.kind
  if c.kind == "begin":
    result["title"] = %(if c.title.isSome: c.title.get else: "")
  if c.cancellable.isSome and c.kind != "end":
    result["cancellable"] = %c.cancellable.get
  if c.message.isSome:
    result["message"] = %c.message.get
  if c.percentage.isSome and c.kind != "end":
    result["percentage"] = %c.percentage.get

proc sendProgress*(handler: LSPHandler): Future[void] {.async.} =
  ## Sends the configured `$/progress` notifications for the current
  ## scenario, honoring per-notification delays.
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply base delay if configured
  if scenario.delays.progress > 0:
    await sleepAsync(scenario.delays.progress.milliseconds)

  if not scenario.progress.enabled:
    return

  # Check for error injection
  if "progress" in scenario.errors:
    let error = scenario.errors["progress"]
    raise newException(LSPError, error.message)

  if handler.sendNotification == nil:
    logWarn("sendProgress called but no sendNotification callback is set")
    return

  let token = scenario.progress.token
  for notif in scenario.progress.notifications:
    if notif.delay > 0:
      await sleepAsync(notif.delay.milliseconds)
    let params = %*{"token": token, "value": toProgressValueJson(notif)}
    await handler.sendNotification("$/progress", params)

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
  of "lsptest.sendProgress":
    let scenario = handler.scenarioManager.getCurrentScenario()
    if not scenario.progress.enabled:
      raise newException(LSPError, "Progress is not enabled in current scenario")
    await handler.sendProgress()
    let response = %*{"success": true, "token": scenario.progress.token}
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

  # Create LogMessageParams for the notification
  var notifications: seq[JsonNode] = @[]
  notifications.add(
    %*{
      "method": "window/logMessage",
      "params": {
        "type": 5, "message": fmt"Received textDocument/didOpen notification: {params}"
      },
    }
  )

  # Publish diagnostics for the opened document
  let diagnosticNotifications = await handler.publishDiagnostics(textDocItem.uri)
  notifications.add(diagnosticNotifications)

  return notifications

proc byteOffsetOfPosition(content: string, line, character: int): int =
  ## Convert an LSP Position (0-based line, 0-based UTF-16 code unit
  ## `character`) into a byte offset in `content`. Positions past
  ## end-of-line clamp to the end of that line; positions past
  ## end-of-document clamp to end-of-document. Lines are split on `\n`;
  ## any trailing `\r` is treated as part of the line.
  var
    currentLine = 0
    lineStart = 0
    i = 0
  while i < content.len and currentLine < line:
    if content[i] == '\n':
      inc currentLine
      lineStart = i + 1
    inc i
  if currentLine < line:
    return content.len
  var lineEnd = lineStart
  while lineEnd < content.len and content[lineEnd] != '\n':
    inc lineEnd
  var
    codeUnits = 0
    j = lineStart
  while j < lineEnd and codeUnits < character:
    let r = content.runeAt(j)
    let byteLen = content.runeLenAt(j)
    codeUnits += (if r.int32 >= 0x10000: 2 else: 1)
    j += byteLen
  return j

proc applyContentChange*(
    content: string, change: TextDocumentContentChangeEvent
): string =
  ## Apply a single LSP `TextDocumentContentChangeEvent` to `content`.
  ## When `change.range` is absent the change is a full sync and
  ## `change.text` replaces the whole document; otherwise the range is
  ## spliced with `change.text`.
  if change.range.isNone:
    return change.text
  let r = change.range.get
  let startByte = byteOffsetOfPosition(content, r.start.line.int, r.start.character.int)
  let endByte = byteOffsetOfPosition(content, r.`end`.line.int, r.`end`.character.int)
  return content[0 ..< startByte] & change.text & content[endByte .. ^1]

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

    if changeJson.hasKey("range") and changeJson["range"].kind != JNull:
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

      if changeJson.hasKey("rangeLength") and changeJson["rangeLength"].kind != JNull:
        changeEvent.rangeLength = some(changeJson["rangeLength"].getInt)

    contentChanges.add(changeEvent)

  didChangeParams.contentChanges = contentChanges

  # Apply changes to the document
  let version = textDocJson["version"].getInt()

  if versionedTextDoc.uri in handler.documents:
    for change in contentChanges:
      handler.documents[versionedTextDoc.uri].content =
        applyContentChange(handler.documents[versionedTextDoc.uri].content, change)
    handler.documents[versionedTextDoc.uri].version = version

    let fileName = versionedTextDoc.uri.split("/")[^1]
    let contentLength = handler.documents[versionedTextDoc.uri].content.len

    # Create LogMessageParams for the notification
    let logParams = LogMessageParams()
    logParams.`type` = 5 # Log message
    logParams.message =
      fmt"Updated document: {fileName} (v{version}, {contentLength} chars)"

    var notifications: seq[JsonNode] = @[]
    notifications.add(
      %*{
        "method": "window/logMessage",
        "params": {
          "type": 5,
          "message": fmt"Received textDocument/didChange notification: {params}",
        },
      }
    )

    # Publish diagnostics for the changed document
    let diagnosticNotifications = await handler.publishDiagnostics(versionedTextDoc.uri)
    notifications.add(diagnosticNotifications)

    return notifications
  else:
    let fileName = versionedTextDoc.uri.split("/")[^1]

    var notifications: seq[JsonNode] = @[]

    # Create LogMessageParams for the notification
    notifications.add(
      %*{
        "method": "window/logMessage",
        "params": {
          "type": 5,
          "message": fmt"Received textDocument/didChange notification: {params}",
        },
      }
    )

    # Create LogMessageParams for the warning
    let logParams = LogMessageParams()
    logParams.`type` = 2 # Warning
    logParams.message = fmt"Warning: Attempted to update unopened document: {fileName}"

    let warningNotification = newJObject()
    warningNotification["method"] = %"window/logMessage"
    warningNotification["params"] = %logParams
    notifications.add(warningNotification)

    return notifications

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

    var notifications: seq[JsonNode] = @[]

    # Create LogMessageParams for the notification
    notifications.add(
      %*{
        "method": "window/logMessage",
        "params": {
          "type": 5,
          "message": fmt"Received textDocument/didClose notification: {params}",
        },
      }
    )

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

    var notifications: seq[JsonNode] = @[]

    # Create LogMessageParams for the notification
    notifications.add(
      %*{
        "method": "window/logMessage",
        "params": {
          "type": 5,
          "message": fmt"Received textDocument/didClose notification: {params}",
        },
      }
    )

    # Create LogMessageParams for the warning
    let logParams = LogMessageParams()
    logParams.`type` = 2 # Warning
    logParams.message = fmt"Warning: Attempted to close unopened document: {fileName}"

    let warningNotification = newJObject()
    warningNotification["method"] = %"window/logMessage"
    warningNotification["params"] = %logParams
    notifications.add(warningNotification)

    return notifications

proc handleDidSave*(
    handler: LSPHandler, params: JsonNode
): Future[seq[JsonNode]] {.async.} =
  # Parse the DidSaveTextDocumentParams from JSON
  let didSaveParams = DidSaveTextDocumentParams()

  # Extract TextDocumentIdentifier
  let textDocJson = params["textDocument"]
  let textDocIdentifier = TextDocumentIdentifier()
  textDocIdentifier.uri = textDocJson["uri"].getStr()
  didSaveParams.textDocument = textDocIdentifier

  # Extract optional text content if provided
  if params.hasKey("text"):
    didSaveParams.text = some(params["text"].getStr())

  var notifications: seq[JsonNode] = @[]

  # Create LogMessageParams for the notification
  notifications.add(
    %*{
      "method": "window/logMessage",
      "params": {
        "type": 5, "message": fmt"Received textDocument/didSave notification: {params}"
      },
    }
  )

  # Update the document content if text was provided
  if didSaveParams.text.isSome and textDocIdentifier.uri in handler.documents:
    handler.documents[textDocIdentifier.uri].content = didSaveParams.text.get()

    let fileName = textDocIdentifier.uri.split("/")[^1]
    let contentLength = handler.documents[textDocIdentifier.uri].content.len

    # Log the update
    let logParams = LogMessageParams()
    logParams.`type` = 5 # Log message
    logParams.message = fmt"Saved document: {fileName} ({contentLength} chars)"

    let logNotification = newJObject()
    logNotification["method"] = %"window/logMessage"
    logNotification["params"] = %logParams
    notifications.add(logNotification)
  elif textDocIdentifier.uri in handler.documents:
    # Document exists but no text provided
    let fileName = textDocIdentifier.uri.split("/")[^1]

    let logParams = LogMessageParams()
    logParams.`type` = 5 # Log message
    logParams.message = fmt"Saved document: {fileName} (no text included)"

    let logNotification = newJObject()
    logNotification["method"] = %"window/logMessage"
    logNotification["params"] = %logParams
    notifications.add(logNotification)
  else:
    # Document not tracked
    let fileName = textDocIdentifier.uri.split("/")[^1]

    let logParams = LogMessageParams()
    logParams.`type` = 2 # Warning
    logParams.message = fmt"Warning: Saved unknown document: {fileName}"

    let warningNotification = newJObject()
    warningNotification["method"] = %"window/logMessage"
    warningNotification["params"] = %logParams
    notifications.add(warningNotification)

  # Optionally publish diagnostics after save
  if textDocIdentifier.uri in handler.documents:
    let diagnosticNotifications =
      await handler.publishDiagnostics(textDocIdentifier.uri)
    notifications.add(diagnosticNotifications)

  return notifications

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

proc handleCompletionItemResolve*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.completionResolve > 0:
    await sleepAsync(scenario.delays.completionResolve.milliseconds)

  # Check for error injection
  if "completionResolve" in scenario.errors:
    let error = scenario.errors["completionResolve"]
    raise newException(LSPError, error.message)

  # Start from the item the client sent so unrecognised fields survive
  # the round-trip (e.g. sortText/filterText/data).
  var resolved = params
  if resolved.kind != JObject:
    resolved = newJObject()

  # If resolve is disabled, return the item unchanged.
  if not scenario.completionResolve.enabled:
    return resolved

  let label = resolved{"label"}.getStr("")
  for item in scenario.completionResolve.items:
    if item.label == label:
      if item.detail.isSome:
        resolved["detail"] = %item.detail.get
      if item.documentation.isSome:
        resolved["documentation"] = %item.documentation.get
      break

  return resolved

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
      "params": {
        "type": 5,
        "message": fmt"Received workspace/didChangeConfiguration notification: {params}",
      },
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
    # Create semantic tokens from scenario configuration
    let semanticTokens = SemanticTokens()
    semanticTokens.resultId = some("result-" & $handler.documents.len)

    # Use configured tokens from scenario or generate sample tokens
    if scenario.semanticTokens.tokens.len > 0:
      semanticTokens.data = scenario.semanticTokens.tokens
    else:
      # Generate sample semantic tokens for demonstration
      # Format: [deltaLine, deltaStart, length, tokenType, tokenModifiers]
      semanticTokens.data = @[
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

proc toSemanticTokensEditJson(e: SemanticTokensEditContent): JsonNode =
  result = newJObject()
  result["start"] = %e.start
  result["deleteCount"] = %e.deleteCount
  if e.data.len > 0:
    result["data"] = %e.data

proc handleSemanticTokensDelta*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.semanticTokensDelta > 0:
    await sleepAsync(scenario.delays.semanticTokensDelta.milliseconds)

  # Check if semantic tokens delta is enabled
  if not scenario.semanticTokensDelta.enabled:
    return newJNull()

  # Check for error injection
  if "semanticTokensDelta" in scenario.errors:
    let error = scenario.errors["semanticTokensDelta"]
    raise newException(LSPError, error.message)

  # Extract document information
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()

  if uri notin handler.documents:
    return newJNull()

  # Build SemanticTokensDelta response from scenario configuration
  result = newJObject()
  if scenario.semanticTokensDelta.resultId.isSome:
    result["resultId"] = %scenario.semanticTokensDelta.resultId.get
  else:
    result["resultId"] = %("delta-" & $handler.documents.len)
  var edits = newJArray()
  for edit in scenario.semanticTokensDelta.edits:
    edits.add(toSemanticTokensEditJson(edit))
  result["edits"] = edits

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

  # Get document content if available
  if uri in handler.documents:
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

  # Get document content if available
  if uri in handler.documents:
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

proc handleDefinition*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.definition > 0:
    await sleepAsync(scenario.delays.definition.milliseconds)

  # Check if definition is enabled
  if not scenario.definition.enabled:
    return newJNull()

  # Check for error injection
  if "definition" in scenario.errors:
    let error = scenario.errors["definition"]
    raise newException(LSPError, error.message)

  # Extract position information
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()

  # Get document content if available
  if uri in handler.documents:
    # Create definition response from scenario configuration
    if scenario.definition.locations.len > 0:
      # Return array of locations
      var locations: seq[JsonNode] = @[]
      for loc in scenario.definition.locations:
        let location = Location()
        location.uri = loc.uri
        location.range = loc.range
        locations.add(%location)
      return %locations
    elif scenario.definition.location.uri != "":
      # Return single location
      let location = Location()
      location.uri = scenario.definition.location.uri
      location.range = scenario.definition.location.range
      return %location
    else:
      # No definition found
      return newJNull()
  else:
    # Document not found
    return newJNull()

proc handleTypeDefinition*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.typeDefinition > 0:
    await sleepAsync(scenario.delays.typeDefinition.milliseconds)

  # Check if type definition is enabled
  if not scenario.typeDefinition.enabled:
    return newJNull()

  # Check for error injection
  if "typeDefinition" in scenario.errors:
    let error = scenario.errors["typeDefinition"]
    raise newException(LSPError, error.message)

  # Extract position information
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()

  # Get document content if available
  if uri in handler.documents:
    # Create type definition response from scenario configuration
    if scenario.typeDefinition.locations.len > 0:
      # Return array of locations
      var locations: seq[JsonNode] = @[]
      for loc in scenario.typeDefinition.locations:
        let location = Location()
        location.uri = loc.uri
        location.range = loc.range
        locations.add(%location)
      return %locations
    elif scenario.typeDefinition.location.uri != "":
      # Return single location
      let location = Location()
      location.uri = scenario.typeDefinition.location.uri
      location.range = scenario.typeDefinition.location.range
      return %location
    else:
      # No type definition found
      return newJNull()
  else:
    # Document not found
    return newJNull()

proc handleImplementation*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.implementation > 0:
    await sleepAsync(scenario.delays.implementation.milliseconds)

  # Check if implementation is enabled
  if not scenario.implementation.enabled:
    return newJNull()

  # Check for error injection
  if "implementation" in scenario.errors:
    let error = scenario.errors["implementation"]
    raise newException(LSPError, error.message)

  # Extract position information
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()

  # Get document content if available
  if uri in handler.documents:
    # Create implementation response from scenario configuration
    if scenario.implementation.locations.len > 0:
      # Return array of locations
      var locations: seq[JsonNode] = @[]
      for loc in scenario.implementation.locations:
        let location = Location()
        location.uri = loc.uri
        location.range = loc.range
        locations.add(%location)
      return %locations
    elif scenario.implementation.location.uri != "":
      # Return single location
      let location = Location()
      location.uri = scenario.implementation.location.uri
      location.range = scenario.implementation.location.range
      return %location
    else:
      # No implementation found
      return newJNull()
  else:
    # Document not found
    return newJNull()

proc handleReferences*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.references > 0:
    await sleepAsync(scenario.delays.references.milliseconds)

  # Check if references is enabled
  if not scenario.references.enabled:
    return %(@[])

  # Check for error injection
  if "references" in scenario.errors:
    let error = scenario.errors["references"]
    raise newException(LSPError, error.message)

  # Extract position information
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()
  let context = params["context"]
  let includeDeclaration = context["includeDeclaration"].getBool(true)

  # Get document content if available
  if uri in handler.documents:
    # Create references response from scenario configuration
    var locations: seq[JsonNode] = @[]

    # Add configured reference locations
    for refLoc in scenario.references.locations:
      let location = Location()
      location.uri = refLoc.uri
      location.range = refLoc.range
      locations.add(%location)

    # If includeDeclaration is true and we have declaration info, add it
    if includeDeclaration and scenario.references.includeDeclaration:
      # Check if we have declaration configured in the scenario
      if scenario.declaration.enabled:
        if scenario.declaration.locations.len > 0:
          # Add all declaration locations
          for declLoc in scenario.declaration.locations:
            let location = Location()
            location.uri = declLoc.uri
            location.range = declLoc.range
            locations.add(%location)
        elif scenario.declaration.location.uri != "":
          # Add single declaration location
          let location = Location()
          location.uri = scenario.declaration.location.uri
          location.range = scenario.declaration.location.range
          locations.add(%location)

    return %locations
  else:
    # Document not found, return empty array
    return %(@[])

proc handleDocumentHighlight*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.documentHighlight > 0:
    await sleepAsync(scenario.delays.documentHighlight.milliseconds)

  # Check if document highlight is enabled
  if not scenario.documentHighlight.enabled:
    return %(@[])

  # Check for error injection
  if "documentHighlight" in scenario.errors:
    let error = scenario.errors["documentHighlight"]
    raise newException(LSPError, error.message)

  # Extract position information
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()

  # Get document content if available
  if uri in handler.documents:
    # Create document highlights from scenario configuration
    var highlights: seq[JsonNode] = @[]

    for highlightContent in scenario.documentHighlight.highlights:
      let highlight = DocumentHighlight()
      highlight.range = highlightContent.range

      if highlightContent.kind.isSome:
        highlight.kind = highlightContent.kind

      highlights.add(%highlight)

    return %highlights
  else:
    # Document not found, return empty array
    return %(@[])

proc toCallHierarchyItem(c: CallHierarchyItemContent): CallHierarchyItem =
  result = CallHierarchyItem(
    name: c.name,
    kind: c.kind,
    detail: c.detail,
    uri: c.uri,
    range: c.range,
    selectionRange: c.selectionRange,
  )

proc handlePrepareCallHierarchy*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.prepareCallHierarchy > 0:
    await sleepAsync(scenario.delays.prepareCallHierarchy.milliseconds)

  # Check if prepare call hierarchy is enabled
  if not scenario.prepareCallHierarchy.enabled:
    return newJNull()

  # Check for error injection
  if "prepareCallHierarchy" in scenario.errors:
    let error = scenario.errors["prepareCallHierarchy"]
    raise newException(LSPError, error.message)

  # Extract position information
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()

  # Get document content if available
  if uri in handler.documents:
    # Create call hierarchy items from scenario configuration
    var items: seq[JsonNode] = @[]
    for itemContent in scenario.prepareCallHierarchy.items:
      items.add(%toCallHierarchyItem(itemContent))
    return %items
  else:
    # Document not found
    return newJNull()

proc handleIncomingCalls*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.callHierarchyIncoming > 0:
    await sleepAsync(scenario.delays.callHierarchyIncoming.milliseconds)

  # Check if incoming calls is enabled
  if not scenario.callHierarchyIncoming.enabled:
    return %(@[])

  # Check for error injection
  if "callHierarchyIncoming" in scenario.errors:
    let error = scenario.errors["callHierarchyIncoming"]
    raise newException(LSPError, error.message)

  # Create incoming calls from scenario configuration
  var calls: seq[JsonNode] = @[]
  for callContent in scenario.callHierarchyIncoming.calls:
    let incoming = CallHierarchyIncomingCall(
      `from`: toCallHierarchyItem(callContent.`from`),
      fromRanges: callContent.fromRanges,
    )
    calls.add(%incoming)
  return %calls

proc handleOutgoingCalls*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.callHierarchyOutgoing > 0:
    await sleepAsync(scenario.delays.callHierarchyOutgoing.milliseconds)

  # Check if outgoing calls is enabled
  if not scenario.callHierarchyOutgoing.enabled:
    return %(@[])

  # Check for error injection
  if "callHierarchyOutgoing" in scenario.errors:
    let error = scenario.errors["callHierarchyOutgoing"]
    raise newException(LSPError, error.message)

  # Create outgoing calls from scenario configuration
  var calls: seq[JsonNode] = @[]
  for callContent in scenario.callHierarchyOutgoing.calls:
    let outgoing = CallHierarchyOutgoingCall(
      to: toCallHierarchyItem(callContent.to), fromRanges: callContent.fromRanges
    )
    calls.add(%outgoing)
  return %calls

proc handleTextDocumentRename*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.rename > 0:
    await sleepAsync(scenario.delays.rename.milliseconds)

  # Check if rename is enabled
  if not scenario.rename.enabled:
    return newJNull()

  # Check for error injection
  if "rename" in scenario.errors:
    let error = scenario.errors["rename"]
    raise newException(LSPError, error.message)

  # Extract position and new name information
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()
  let newName = params["newName"].getStr()

  # Get document content if available
  if uri in handler.documents:
    # Create workspace edit response from scenario configuration
    if scenario.rename.workspaceEdit.changes.len > 0 or
        scenario.rename.workspaceEdit.documentChanges.len > 0:
      let workspaceEdit = WorkspaceEdit()

      # Handle changes (uri -> TextEdit[])
      if scenario.rename.workspaceEdit.changes.len > 0:
        var changesObj = newJObject()
        for change in scenario.rename.workspaceEdit.changes:
          var editsArray = newJArray()
          for edit in change.edits:
            let textEdit = TextEdit()
            textEdit.range = edit.range
            textEdit.newText = edit.newText.replace("${newName}", newName)
            editsArray.add(%textEdit)
          changesObj[change.uri] = editsArray
        workspaceEdit.changes = some(%changesObj)

      # Handle documentChanges
      if scenario.rename.workspaceEdit.documentChanges.len > 0:
        var docChanges: seq[TextDocumentEdit] = @[]
        for docChange in scenario.rename.workspaceEdit.documentChanges:
          let textDocEdit = TextDocumentEdit()
          textDocEdit.textDocument = VersionedTextDocumentIdentifier()
          textDocEdit.textDocument.uri = docChange.textDocument.uri
          textDocEdit.textDocument.version = docChange.textDocument.version

          var edits: seq[TextEdit] = @[]
          for edit in docChange.edits:
            let textEdit = TextEdit()
            textEdit.range = edit.range
            textEdit.newText = edit.newText.replace("${newName}", newName)
            edits.add(textEdit)
          textDocEdit.edits = some(edits)
          docChanges.add(textDocEdit)
        workspaceEdit.documentChanges = some(docChanges)

      return %workspaceEdit
    else:
      # No rename edits configured
      return newJNull()
  else:
    # Document not found
    return newJNull()

proc handleTextDocumentPrepareRename*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.prepareRename > 0:
    await sleepAsync(scenario.delays.prepareRename.milliseconds)

  # Check if prepareRename is enabled
  if not scenario.prepareRename.enabled:
    return newJNull()

  # Check for error injection
  if "prepareRename" in scenario.errors:
    let error = scenario.errors["prepareRename"]
    raise newException(LSPError, error.message)

  # Require an open document, otherwise there is nothing to rename
  let uri = params["textDocument"]["uri"].getStr()
  if uri notin handler.documents:
    return newJNull()

  # Response variants (in priority order):
  #   { "defaultBehavior": bool }
  #   { "range": Range, "placeholder": string }
  #   Range
  #   null
  if scenario.prepareRename.defaultBehavior.isSome:
    return %*{"defaultBehavior": scenario.prepareRename.defaultBehavior.get}

  if scenario.prepareRename.range.isSome:
    let range = scenario.prepareRename.range.get
    if scenario.prepareRename.placeholder.isSome:
      return %*{"range": range, "placeholder": scenario.prepareRename.placeholder.get}
    return %range

  return newJNull()

proc handleDocumentFormatting*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.formatting > 0:
    await sleepAsync(scenario.delays.formatting.milliseconds)

  # Check if formatting is enabled
  if not scenario.formatting.enabled:
    return newJNull()

  # Check for error injection
  if "formatting" in scenario.errors:
    let error = scenario.errors["formatting"]
    raise newException(LSPError, error.message)

  # Extract document information
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()

  # Get document content if available
  if uri in handler.documents:
    # Create formatting response from scenario configuration
    var edits: seq[JsonNode] = @[]

    for editContent in scenario.formatting.edits:
      let textEdit = TextEdit()
      textEdit.range = editContent.range
      textEdit.newText = editContent.newText
      edits.add(%textEdit)

    return %edits
  else:
    # Document not found, return empty edits
    return %(@[])

proc handleDocumentRangeFormatting*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.rangeFormatting > 0:
    await sleepAsync(scenario.delays.rangeFormatting.milliseconds)

  # Check if range formatting is enabled
  if not scenario.rangeFormatting.enabled:
    return newJNull()

  # Check for error injection
  if "rangeFormatting" in scenario.errors:
    let error = scenario.errors["rangeFormatting"]
    raise newException(LSPError, error.message)

  # Extract document information
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()

  # Get document content if available
  if uri in handler.documents:
    # Create range formatting response from scenario configuration
    var edits: seq[JsonNode] = @[]

    for editContent in scenario.rangeFormatting.edits:
      let textEdit = TextEdit()
      textEdit.range = editContent.range
      textEdit.newText = editContent.newText
      edits.add(%textEdit)

    return %edits
  else:
    # Document not found, return empty edits
    return %(@[])

proc toDocumentSymbolJson(c: DocumentSymbolContent): JsonNode =
  result = newJObject()
  result["name"] = %c.name
  result["kind"] = %c.kind
  result["range"] = %c.range
  result["selectionRange"] = %c.selectionRange
  if c.detail.isSome:
    result["detail"] = %c.detail.get
  if c.deprecated.isSome:
    result["deprecated"] = %c.deprecated.get
  if c.tags.len > 0:
    result["tags"] = %c.tags
  if c.children.len > 0:
    var childrenJson = newJArray()
    for child in c.children:
      childrenJson.add(toDocumentSymbolJson(child))
    result["children"] = childrenJson

proc handleDocumentSymbol*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.documentSymbol > 0:
    await sleepAsync(scenario.delays.documentSymbol.milliseconds)

  # Check if document symbol is enabled
  if not scenario.documentSymbol.enabled:
    return newJNull()

  # Check for error injection
  if "documentSymbol" in scenario.errors:
    let error = scenario.errors["documentSymbol"]
    raise newException(LSPError, error.message)

  # Extract document information
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()

  # Get document content if available
  if uri in handler.documents:
    # Create document symbols response from scenario configuration
    var symbols: seq[JsonNode] = @[]
    for symbolContent in scenario.documentSymbol.symbols:
      symbols.add(toDocumentSymbolJson(symbolContent))
    return %symbols
  else:
    # Document not found
    return newJNull()

proc toWorkspaceSymbolJson(c: WorkspaceSymbolContent): JsonNode =
  result = newJObject()
  result["name"] = %c.name
  result["kind"] = %c.kind
  result["location"] = %*{"uri": c.uri, "range": %c.range}
  if c.deprecated.isSome:
    result["deprecated"] = %c.deprecated.get
  if c.containerName.isSome:
    result["containerName"] = %c.containerName.get
  if c.tags.len > 0:
    result["tags"] = %c.tags

proc handleWorkspaceSymbol*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.workspaceSymbol > 0:
    await sleepAsync(scenario.delays.workspaceSymbol.milliseconds)

  # Check if workspace symbol is enabled
  if not scenario.workspaceSymbol.enabled:
    return newJNull()

  # Check for error injection
  if "workspaceSymbol" in scenario.errors:
    let error = scenario.errors["workspaceSymbol"]
    raise newException(LSPError, error.message)

  let query =
    if params.hasKey("query"):
      params["query"].getStr("")
    else:
      ""

  # Filter symbols by query (case-insensitive substring match).
  # An empty query returns all configured symbols.
  var symbols: seq[JsonNode] = @[]
  let lowerQuery = query.toLowerAscii()
  for symbolContent in scenario.workspaceSymbol.symbols:
    if lowerQuery.len == 0 or symbolContent.name.toLowerAscii().contains(lowerQuery):
      symbols.add(toWorkspaceSymbolJson(symbolContent))
  return %symbols

proc toDocumentLinkJson(c: DocumentLinkContent): JsonNode =
  result = newJObject()
  result["range"] = %c.range
  if c.target.isSome:
    result["target"] = %c.target.get
  if c.tooltip.isSome:
    result["tooltip"] = %c.tooltip.get

proc handleDocumentLink*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.documentLink > 0:
    await sleepAsync(scenario.delays.documentLink.milliseconds)

  # Check if document link is enabled
  if not scenario.documentLink.enabled:
    return newJNull()

  # Check for error injection
  if "documentLink" in scenario.errors:
    let error = scenario.errors["documentLink"]
    raise newException(LSPError, error.message)

  # Extract document information
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()

  # Get document content if available
  if uri in handler.documents:
    # Create document links response from scenario configuration
    var links: seq[JsonNode] = @[]
    for linkContent in scenario.documentLink.links:
      links.add(toDocumentLinkJson(linkContent))
    return %links
  else:
    # Document not found
    return newJNull()

proc toParameterInformationJson(c: ParameterInformationContent): JsonNode =
  result = newJObject()
  result["label"] = %c.label
  if c.documentation.isSome:
    result["documentation"] = %c.documentation.get

proc toSignatureInformationJson(c: SignatureInformationContent): JsonNode =
  result = newJObject()
  result["label"] = %c.label
  if c.documentation.isSome:
    result["documentation"] = %c.documentation.get
  if c.activeParameter.isSome:
    result["activeParameter"] = %c.activeParameter.get
  var paramsJson = newJArray()
  for param in c.parameters:
    paramsJson.add(toParameterInformationJson(param))
  result["parameters"] = paramsJson

proc handleSignatureHelp*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.signatureHelp > 0:
    await sleepAsync(scenario.delays.signatureHelp.milliseconds)

  # Check if signature help is enabled
  if not scenario.signatureHelp.enabled:
    return newJNull()

  # Check for error injection
  if "signatureHelp" in scenario.errors:
    let error = scenario.errors["signatureHelp"]
    raise newException(LSPError, error.message)

  # Extract document information
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()

  # Get document content if available
  if uri in handler.documents:
    # Create signature help response from scenario configuration
    result = newJObject()
    var signaturesJson = newJArray()
    for sigContent in scenario.signatureHelp.signatures:
      signaturesJson.add(toSignatureInformationJson(sigContent))
    result["signatures"] = signaturesJson
    if scenario.signatureHelp.activeSignature.isSome:
      result["activeSignature"] = %scenario.signatureHelp.activeSignature.get
    if scenario.signatureHelp.activeParameter.isSome:
      result["activeParameter"] = %scenario.signatureHelp.activeParameter.get
  else:
    # Document not found
    return newJNull()

proc toSelectionRangeJson(c: SelectionRangeContent): JsonNode =
  result = newJObject()
  result["range"] = %c.range
  if c.parent.isSome:
    result["parent"] = toSelectionRangeJson(c.parent.get)

proc handleSelectionRange*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.selectionRange > 0:
    await sleepAsync(scenario.delays.selectionRange.milliseconds)

  # Check if selection range is enabled
  if not scenario.selectionRange.enabled:
    return newJNull()

  # Check for error injection
  if "selectionRange" in scenario.errors:
    let error = scenario.errors["selectionRange"]
    raise newException(LSPError, error.message)

  # Extract document information
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()

  # Get document content if available
  if uri in handler.documents:
    # LSP returns one SelectionRange per input position. Fall back to a
    # single-element position array when the client sends none so the
    # response is still well-formed.
    let positionsLen =
      if params.hasKey("positions") and params["positions"].kind == JArray:
        max(params["positions"].len, 1)
      else:
        1

    let configuredRanges = scenario.selectionRange.ranges
    result = newJArray()
    for i in 0 ..< positionsLen:
      if configuredRanges.len == 0:
        result.add(newJNull())
      else:
        let content = configuredRanges[min(i, configuredRanges.len - 1)]
        result.add(toSelectionRangeJson(content))
  else:
    # Document not found
    return newJNull()

proc toFoldingRangeJson(c: FoldingRangeContent): JsonNode =
  result = newJObject()
  result["startLine"] = %c.startLine
  result["endLine"] = %c.endLine
  if c.startCharacter.isSome:
    result["startCharacter"] = %c.startCharacter.get
  if c.endCharacter.isSome:
    result["endCharacter"] = %c.endCharacter.get
  if c.kind.isSome:
    result["kind"] = %c.kind.get
  if c.collapsedText.isSome:
    result["collapsedText"] = %c.collapsedText.get

proc handleFoldingRange*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.foldingRange > 0:
    await sleepAsync(scenario.delays.foldingRange.milliseconds)

  # Check if folding range is enabled
  if not scenario.foldingRange.enabled:
    return newJNull()

  # Check for error injection
  if "foldingRange" in scenario.errors:
    let error = scenario.errors["foldingRange"]
    raise newException(LSPError, error.message)

  # Extract document information
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()

  # Get document content if available
  if uri in handler.documents:
    # Create folding ranges response from scenario configuration
    result = newJArray()
    for rangeContent in scenario.foldingRange.ranges:
      result.add(toFoldingRangeJson(rangeContent))
  else:
    # Document not found
    return newJNull()

proc toCodeLensJson(c: CodeLensContent): JsonNode =
  result = newJObject()
  result["range"] = %c.range
  if c.command.isSome:
    let cmd = c.command.get
    var cmdJson = newJObject()
    cmdJson["title"] = %cmd.title
    cmdJson["command"] = %cmd.command
    if cmd.arguments.isSome:
      cmdJson["arguments"] = cmd.arguments.get
    result["command"] = cmdJson
  if c.data.isSome:
    result["data"] = c.data.get

proc handleCodeLens*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.codeLens > 0:
    await sleepAsync(scenario.delays.codeLens.milliseconds)

  # Check if code lens is enabled
  if not scenario.codeLens.enabled:
    return newJNull()

  # Check for error injection
  if "codeLens" in scenario.errors:
    let error = scenario.errors["codeLens"]
    raise newException(LSPError, error.message)

  # Extract document information
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()

  # Get document content if available
  if uri in handler.documents:
    # Create code lens response from scenario configuration
    result = newJArray()
    for lensContent in scenario.codeLens.lenses:
      result.add(toCodeLensJson(lensContent))
  else:
    # Document not found
    return newJNull()

proc toTextEditJson(edit: TextEdit): JsonNode =
  result = newJObject()
  result["range"] = %edit.range
  result["newText"] = %edit.newText

proc toCodeActionWorkspaceEditJson(we: CodeActionWorkspaceEdit): JsonNode =
  result = newJObject()
  if we.changes.len > 0:
    var changesJson = newJObject()
    for change in we.changes:
      var editsJson = newJArray()
      for edit in change.edits:
        editsJson.add(toTextEditJson(edit))
      changesJson[change.uri] = editsJson
    result["changes"] = changesJson
  if we.documentChanges.len > 0:
    var documentChangesJson = newJArray()
    for docChange in we.documentChanges:
      var docChangeJson = newJObject()
      var textDocumentJson = newJObject()
      textDocumentJson["uri"] = %docChange.textDocument.uri
      if docChange.textDocument.version.isSome:
        textDocumentJson["version"] = docChange.textDocument.version.get
      else:
        textDocumentJson["version"] = newJNull()
      docChangeJson["textDocument"] = textDocumentJson
      var editsJson = newJArray()
      for edit in docChange.edits:
        editsJson.add(toTextEditJson(edit))
      docChangeJson["edits"] = editsJson
      documentChangesJson.add(docChangeJson)
    result["documentChanges"] = documentChangesJson

proc toCodeActionJson(a: CodeActionContent): JsonNode =
  result = newJObject()
  result["title"] = %a.title
  if a.kind.isSome:
    result["kind"] = %a.kind.get
  if a.diagnostics.isSome:
    result["diagnostics"] = a.diagnostics.get
  if a.isPreferred.isSome:
    result["isPreferred"] = %a.isPreferred.get
  if a.disabled.isSome:
    result["disabled"] = %*{"reason": a.disabled.get}
  if a.edit.isSome:
    result["edit"] = toCodeActionWorkspaceEditJson(a.edit.get)
  if a.command.isSome:
    let cmd = a.command.get
    var cmdJson = newJObject()
    cmdJson["title"] = %cmd.title
    cmdJson["command"] = %cmd.command
    if cmd.arguments.isSome:
      cmdJson["arguments"] = cmd.arguments.get
    result["command"] = cmdJson
  if a.data.isSome:
    result["data"] = a.data.get

proc handleCodeAction*(
    handler: LSPHandler, id: JsonNode, params: JsonNode
): Future[JsonNode] {.async.} =
  let scenario = handler.scenarioManager.getCurrentScenario()

  # Apply delay if configured
  if scenario.delays.codeAction > 0:
    await sleepAsync(scenario.delays.codeAction.milliseconds)

  # Check if code action is enabled
  if not scenario.codeAction.enabled:
    return newJNull()

  # Check for error injection
  if "codeAction" in scenario.errors:
    let error = scenario.errors["codeAction"]
    raise newException(LSPError, error.message)

  # Extract document information
  let textDocument = params["textDocument"]
  let uri = textDocument["uri"].getStr()

  # Get document content if available
  if uri in handler.documents:
    # Create code action response from scenario configuration
    result = newJArray()
    for actionContent in scenario.codeAction.actions:
      result.add(toCodeActionJson(actionContent))
  else:
    # Document not found
    return newJNull()
