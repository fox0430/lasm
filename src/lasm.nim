import pkg/chronos

import lasmpkg/[server, cli, logger, lsp_handler]

proc main() =
  let appConfig = parseCliParams()

  logInfo("Starting LSP server initialization")

  if appConfig.enableFileLog:
    # Initialize file logger if requested
    let
      path = if appConfig.logPath.len > 0: appConfig.logPath else: "lasm.log"
      fileLogger = newFileLogger(path, level = LogLevel.Debug)
    setGlobalLogger(fileLogger)

  let server = newLSPServer(appConfig.configPath)
  if appConfig.enableFileLog:
    logInfo(
      "LSP server created with scenario: " &
        server.lspHandler.scenarioManager.currentScenario
    )
    logInfo("Starting server main loop")

  waitFor server.startServer

when isMainModule:
  main()
