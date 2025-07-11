import std/os

import pkg/chronos

import lasmpkg/[server, cli, logger]

proc main() =
  if paramCount() == 0:
    stderr.writeLine("Error: No configuration file specified")
    writeUsage()
    quit(1)

  var
    configPath = ""
    enableFileLog = false

  # Parse command line arguments
  var i = 1
  while i <= paramCount():
    let param = paramStr(i)
    case param
    of "--file-log":
      enableFileLog = true
    of "--create-sample-config":
      let sm = ScenarioManager()
      sm.createSampleConfig()
      return
    of "--config":
      if i + 1 <= paramCount():
        configPath = paramStr(i + 1)
        inc i
      else:
        return
    of "-h", "--help":
      writeUsage()
      return
    else:
      return
    inc i

  # Initialize file logger if requested
  if enableFileLog:
    let fileLogger = newFileLogger(level = LogLevel.Debug)
    setGlobalLogger(fileLogger)

  # Handle main execution
  if configPath != "":
    if enableFileLog:
      logInfo("Starting LSP server initialization")
    let server = newLSPServer(configPath)
    if enableFileLog:
      logInfo(
        "LSP server created with scenario: " & server.scenarioManager.currentScenario
      )
      logInfo("Starting server main loop")
    waitFor server.startServer

when isMainModule:
  main()
