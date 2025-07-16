import std/os

import pkg/chronos

import lasmpkg/[server, cli, logger, lsp_handler]

proc main() =
  if paramCount() == 0:
    writeNoConfigError()
    return

  var
    configPath = ""
    enableFileLog = false
    logPath = ""

  # Parse command line arguments
  var i = 1
  while i <= paramCount():
    let param = paramStr(i)
    case param
    of "--file-log":
      enableFileLog = true
    of "--file-log-path":
      logPath = paramStr(i + 1)
      i.inc
    of "--create-sample-config":
      let sm = ScenarioManager()
      sm.createSampleConfig()
      return
    of "--config":
      if i + 1 <= paramCount():
        configPath = paramStr(i + 1)
        i.inc
      else:
        return
    of "-h", "--help":
      writeUsage()
      return
    else:
      return
    i.inc

  if enableFileLog:
    # Initialize file logger if requested
    let
      path = if logPath.len > 0: logPath else: "lasm.log"
      fileLogger = newFileLogger(path, level = LogLevel.Debug)
    setGlobalLogger(fileLogger)

  # Handle main execution
  if configPath != "":
    if enableFileLog:
      logInfo("Starting LSP server initialization")
    let server = newLSPServer(configPath)
    if enableFileLog:
      logInfo(
        "LSP server created with scenario: " &
          server.lspHandler.scenarioManager.currentScenario
      )
      logInfo("Starting server main loop")
    waitFor server.startServer

when isMainModule:
  main()
