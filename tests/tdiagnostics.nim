import std/[unittest, json, tables, options, times, strutils]

import pkg/chronos

import ../src/lasmpkg/[lsp_handler, scenario, logger]
import ../src/lasmpkg/protocol/types

proc createTestScenarioManager(): ScenarioManager =
  result = ScenarioManager()
  result.currentScenario = "default"
  result.scenarios = initTable[string, Scenario]()
  result.configPath = "test_config.json"

  # Add default scenario
  result.scenarios["default"] = Scenario(
    name: "Default Test",
    hover: HoverConfig(enabled: false),
    completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
    diagnostics: DiagnosticConfig(enabled: false, diagnostics: @[]),
    delays: DelayConfig(hover: 0, completion: 0, diagnostics: 0),
    errors: initTable[string, ErrorConfig](),
  )

suite "diagnostic functionality tests":
  setup:
    # Initialize logger for tests - disable logging
    setGlobalLogger(newFileLogger(enabled = false))

  test "publishDiagnostics with enabled diagnostics":
    let sm = createTestScenarioManager()
    # Create scenario with diagnostics enabled
    sm.scenarios["diagnostic_test"] = Scenario(
      name: "Diagnostic Test",
      hover: HoverConfig(enabled: false),
      completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
      diagnostics: DiagnosticConfig(
        enabled: true,
        diagnostics:
          @[
            DiagnosticContent(
              range: Range(
                start: Position(line: 2, character: 10),
                `end`: Position(line: 2, character: 20),
              ),
              severity: 1, # Error
              code: some("E001"),
              source: some("lasm"),
              message: "Undefined variable 'testVar'",
              tags: @[1],
              relatedInformation: @[],
            ),
            DiagnosticContent(
              range: Range(
                start: Position(line: 5, character: 0),
                `end`: Position(line: 5, character: 5),
              ),
              severity: 2, # Warning
              code: some("W001"),
              source: some("lasm"),
              message: "Function 'oldFunc' is deprecated",
              tags: @[2],
              relatedInformation: @[],
            ),
          ],
      ),
      delays: DelayConfig(hover: 0, completion: 0, diagnostics: 0),
      errors: initTable[string, ErrorConfig](),
    )
    sm.currentScenario = "diagnostic_test"
    let handler = newLSPHandler(sm)

    let notifications = waitFor handler.publishDiagnostics("file:///test.py")

    check notifications.len == 2 # publishDiagnostics + log message

    # Check diagnostic notification
    var diagNotification: JsonNode
    var logNotification: JsonNode
    for notif in notifications:
      if notif["method"].getStr() == "textDocument/publishDiagnostics":
        diagNotification = notif
      elif notif["method"].getStr() == "window/logMessage":
        logNotification = notif

    check diagNotification != nil
    check logNotification != nil

    # Verify diagnostic content
    let params = diagNotification["params"]
    check params["uri"].getStr() == "file:///test.py"

    let diagnostics = params["diagnostics"]
    check diagnostics.len == 2

    # Check first diagnostic (error)
    let diag1 = diagnostics[0]
    check diag1["message"].getStr() == "Undefined variable 'testVar'"
    check diag1["severity"].getInt() == 1
    check diag1["code"].getStr() == "E001"
    check diag1["source"].getStr() == "lasm"
    check diag1["range"]["start"]["line"].getInt() == 2
    check diag1["range"]["start"]["character"].getInt() == 10
    check diag1["range"]["end"]["line"].getInt() == 2
    check diag1["range"]["end"]["character"].getInt() == 20

    # Check second diagnostic (warning)
    let diag2 = diagnostics[1]
    check diag2["message"].getStr() == "Function 'oldFunc' is deprecated"
    check diag2["severity"].getInt() == 2
    check diag2["code"].getStr() == "W001"
    check diag2["source"].getStr() == "lasm"
    check diag2["range"]["start"]["line"].getInt() == 5
    check diag2["range"]["start"]["character"].getInt() == 0

    # Check log message
    check logNotification["params"]["message"].getStr().contains(
      "Published 2 diagnostics"
    )

  test "publishDiagnostics with disabled diagnostics":
    let sm = createTestScenarioManager()
    # Create scenario with diagnostics disabled
    sm.scenarios["no_diagnostics"] = Scenario(
      name: "No Diagnostics",
      hover: HoverConfig(enabled: false),
      completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
      diagnostics: DiagnosticConfig(enabled: false, diagnostics: @[]),
      delays: DelayConfig(hover: 0, completion: 0, diagnostics: 0),
      errors: initTable[string, ErrorConfig](),
    )
    sm.currentScenario = "no_diagnostics"
    let handler = newLSPHandler(sm)

    let notifications = waitFor handler.publishDiagnostics("file:///test.py")

    check notifications.len == 1 # Only clear diagnostics notification

    let notification = notifications[0]
    check notification["method"].getStr() == "textDocument/publishDiagnostics"

    let params = notification["params"]
    check params["uri"].getStr() == "file:///test.py"
    check params["diagnostics"].len == 0

  test "publishDiagnostics with error injection":
    let sm = createTestScenarioManager()
    # Add error scenario
    sm.scenarios["error"] = Scenario(
      name: "Error Test",
      hover: HoverConfig(enabled: false),
      completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
      diagnostics: DiagnosticConfig(enabled: true, diagnostics: @[]),
      delays: DelayConfig(hover: 0, completion: 0, diagnostics: 0),
      errors:
        {"diagnostics": ErrorConfig(code: -32603, message: "Diagnostic error")}.toTable,
    )
    sm.currentScenario = "error" # Has diagnostic error configured
    let handler = newLSPHandler(sm)

    let notifications = waitFor handler.publishDiagnostics("file:///test.py")

    # Should return empty notifications due to error injection
    check notifications.len == 0

  test "publishDiagnostics with delay":
    let sm = createTestScenarioManager()
    # Create scenario with diagnostic delay
    sm.scenarios["delayed_diagnostics"] = Scenario(
      name: "Delayed Diagnostics",
      hover: HoverConfig(enabled: false),
      completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
      diagnostics: DiagnosticConfig(
        enabled: true,
        diagnostics:
          @[
            DiagnosticContent(
              range: Range(
                start: Position(line: 0, character: 0),
                `end`: Position(line: 0, character: 5),
              ),
              severity: 1,
              code: none(string),
              source: none(string),
              message: "Test diagnostic",
              tags: @[],
              relatedInformation: @[],
            )
          ],
      ),
      delays: DelayConfig(hover: 0, completion: 0, diagnostics: 50), # 50ms delay
      errors: initTable[string, ErrorConfig](),
    )
    sm.currentScenario = "delayed_diagnostics"
    let handler = newLSPHandler(sm)

    let startTime = getTime()
    let notifications = waitFor handler.publishDiagnostics("file:///test.py")
    let endTime = getTime()

    # Check that delay occurred (should be at least 40ms due to 50ms delay)
    let duration = (endTime - startTime).inMilliseconds
    check duration >= 40

    check notifications.len == 2 # publishDiagnostics + log message

  test "handleDidOpen publishes diagnostics automatically":
    let sm = createTestScenarioManager()
    # Create scenario with diagnostics enabled
    sm.scenarios["auto_diag"] = Scenario(
      name: "Auto Diagnostics",
      hover: HoverConfig(enabled: false),
      completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
      diagnostics: DiagnosticConfig(
        enabled: true,
        diagnostics:
          @[
            DiagnosticContent(
              range: Range(
                start: Position(line: 1, character: 0),
                `end`: Position(line: 1, character: 5),
              ),
              severity: 1,
              code: some("E123"),
              source: some("lasm"),
              message: "Auto diagnostic message",
              tags: @[],
              relatedInformation: @[],
            )
          ],
      ),
      delays: DelayConfig(hover: 0, completion: 0, diagnostics: 0),
      errors: initTable[string, ErrorConfig](),
    )
    sm.currentScenario = "auto_diag"
    let handler = newLSPHandler(sm)

    let params =
      %*{
        "textDocument": {
          "uri": "file:///test.nim",
          "languageId": "nim",
          "version": 1,
          "text": "echo \"hello\"",
        }
      }

    let notifications = waitFor handler.handleDidOpen(params)

    # Should have: log message, publishDiagnostics, and diagnostic log message
    check notifications.len == 3

    # Verify document was added
    check handler.documents.len == 1
    check "file:///test.nim" in handler.documents

    # Find diagnostic notification
    var diagNotification: JsonNode = nil
    for notif in notifications:
      if notif["method"].getStr() == "textDocument/publishDiagnostics":
        diagNotification = notif
        break

    check diagNotification != nil
    check diagNotification["params"]["diagnostics"].len == 1
    check diagNotification["params"]["diagnostics"][0]["message"].getStr() ==
      "Auto diagnostic message"

  test "handleDidChange publishes diagnostics automatically":
    let sm = createTestScenarioManager()
    # Create scenario with diagnostics enabled
    sm.scenarios["change_diag"] = Scenario(
      name: "Change Diagnostics",
      hover: HoverConfig(enabled: false),
      completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
      diagnostics: DiagnosticConfig(
        enabled: true,
        diagnostics:
          @[
            DiagnosticContent(
              range: Range(
                start: Position(line: 0, character: 0),
                `end`: Position(line: 0, character: 3),
              ),
              severity: 2, # Warning
              code: some("W123"),
              source: some("lasm"),
              message: "Change diagnostic message",
              tags: @[],
              relatedInformation: @[],
            )
          ],
      ),
      delays: DelayConfig(hover: 0, completion: 0, diagnostics: 0),
      errors: initTable[string, ErrorConfig](),
    )
    sm.currentScenario = "change_diag"
    let handler = newLSPHandler(sm)

    # First add a document
    handler.documents["file:///test.nim"] = Document(content: "old content", version: 1)

    let params =
      %*{
        "textDocument": {"uri": "file:///test.nim", "version": 2},
        "contentChanges": [{"text": "new content"}],
      }

    let notifications = waitFor handler.handleDidChange(params)

    # Should have: log message, publishDiagnostics, and diagnostic log message  
    check notifications.len == 3

    # Verify document was updated
    check handler.documents["file:///test.nim"].content == "new content"
    check handler.documents["file:///test.nim"].version == 2

    # Find diagnostic notification
    var diagNotification: JsonNode = nil
    for notif in notifications:
      if notif["method"].getStr() == "textDocument/publishDiagnostics":
        diagNotification = notif
        break

    check diagNotification != nil
    check diagNotification["params"]["diagnostics"].len == 1
    check diagNotification["params"]["diagnostics"][0]["message"].getStr() ==
      "Change diagnostic message"
    check diagNotification["params"]["diagnostics"][0]["severity"].getInt() == 2

  test "handleDidClose clears diagnostics":
    let sm = createTestScenarioManager()
    let handler = newLSPHandler(sm)

    # First add a document
    handler.documents["file:///test.nim"] =
      Document(content: "test content", version: 1)

    let params = %*{"textDocument": {"uri": "file:///test.nim"}}

    let notifications = waitFor handler.handleDidClose(params)

    # Should have: log message and clear diagnostics notification
    check notifications.len == 2

    # Verify document was removed
    check handler.documents.len == 0
    check "file:///test.nim" notin handler.documents

    # Find diagnostic clearing notification
    var diagNotification: JsonNode = nil
    for notif in notifications:
      if notif["method"].getStr() == "textDocument/publishDiagnostics":
        diagNotification = notif
        break

    check diagNotification != nil
    check diagNotification["params"]["uri"].getStr() == "file:///test.nim"
    check diagNotification["params"]["diagnostics"].len == 0

  test "DiagnosticContent with related information":
    let sm = createTestScenarioManager()
    # Create scenario with diagnostics that have related information
    sm.scenarios["related_info"] = Scenario(
      name: "Related Info Diagnostics",
      hover: HoverConfig(enabled: false),
      completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
      diagnostics: DiagnosticConfig(
        enabled: true,
        diagnostics:
          @[
            DiagnosticContent(
              range: Range(
                start: Position(line: 0, character: 0),
                `end`: Position(line: 0, character: 10),
              ),
              severity: 1,
              code: some("E002"),
              source: some("lasm"),
              message: "Main diagnostic with related info",
              tags: @[],
              relatedInformation:
                @[
                  DiagnosticRelatedInformation(
                    location: Location(
                      uri: "file:///related.nim",
                      range: Range(
                        start: Position(line: 5, character: 0),
                        `end`: Position(line: 5, character: 10),
                      ),
                    ),
                    message: "Related issue here",
                  )
                ],
            )
          ],
      ),
      delays: DelayConfig(hover: 0, completion: 0, diagnostics: 0),
      errors: initTable[string, ErrorConfig](),
    )
    sm.currentScenario = "related_info"
    let handler = newLSPHandler(sm)

    let notifications = waitFor handler.publishDiagnostics("file:///test.nim")

    check notifications.len == 2 # publishDiagnostics + log message

    # Find diagnostic notification
    var diagNotification: JsonNode = nil
    for notif in notifications:
      if notif["method"].getStr() == "textDocument/publishDiagnostics":
        diagNotification = notif
        break

    check diagNotification != nil
    let diagnostics = diagNotification["params"]["diagnostics"]
    check diagnostics.len == 1

    let diag = diagnostics[0]
    check diag["message"].getStr() == "Main diagnostic with related info"
    check diag.hasKey("relatedInformation")

    let relatedInfo = diag["relatedInformation"]
    check relatedInfo.len == 1
    check relatedInfo[0]["message"].getStr() == "Related issue here"
    check relatedInfo[0]["location"]["uri"].getStr() == "file:///related.nim"

  test "publishDiagnostics with minimal diagnostic (no optional fields)":
    let sm = createTestScenarioManager()
    # Create scenario with minimal diagnostic
    sm.scenarios["minimal_diag"] = Scenario(
      name: "Minimal Diagnostic",
      hover: HoverConfig(enabled: false),
      completion: CompletionConfig(enabled: false, isIncomplete: false, items: @[]),
      diagnostics: DiagnosticConfig(
        enabled: true,
        diagnostics:
          @[
            DiagnosticContent(
              range: Range(
                start: Position(line: 1, character: 5),
                `end`: Position(line: 1, character: 15),
              ),
              severity: 3, # Information
              code: none(string),
              source: none(string),
              message: "Minimal diagnostic message",
              tags: @[],
              relatedInformation: @[],
            )
          ],
      ),
      delays: DelayConfig(hover: 0, completion: 0, diagnostics: 0),
      errors: initTable[string, ErrorConfig](),
    )
    sm.currentScenario = "minimal_diag"
    let handler = newLSPHandler(sm)

    let notifications = waitFor handler.publishDiagnostics("file:///test.nim")

    check notifications.len == 2 # publishDiagnostics + log message

    # Find diagnostic notification
    var diagNotification: JsonNode = nil
    for notif in notifications:
      if notif["method"].getStr() == "textDocument/publishDiagnostics":
        diagNotification = notif
        break

    check diagNotification != nil
    let diagnostics = diagNotification["params"]["diagnostics"]
    check diagnostics.len == 1

    let diag = diagnostics[0]
    check diag["message"].getStr() == "Minimal diagnostic message"
    check diag["severity"].getInt() == 3
    check diag["range"]["start"]["line"].getInt() == 1
    check diag["range"]["start"]["character"].getInt() == 5
    # Optional fields should not be present or be null
    check not diag.hasKey("code") or diag["code"].kind == JNull
    check not diag.hasKey("source") or diag["source"].kind == JNull
