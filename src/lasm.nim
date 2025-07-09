import std/os

import pkg/chronos

import lasmpkg/[server, cli]

proc main() =
  # Handle command line arguments
  if paramCount() == 0:
    writeNoConfigError()
    return

  if paramStr(1) == "--create-sample-config":
    let sm = ScenarioManager()
    sm.createSampleConfig()
    stderr.writeLine("Sample configuration created. Exiting.")
    return

  if paramStr(1) == "--config":
    if paramCount() < 2:
      writeNoConfigError()
      return

    let configPath = paramStr(2)
    let server = newLSPServer(configPath)
    stderr.writeLine(
      "Starting LSP Server with scenario: " &
        server.scenarioManager.currentScenario
    )
    waitFor server.startServer
  elif paramStr(1) == "-h" or paramStr(1) == "--help":
    writeUsage()
    return
  else:
    writeUnknownOptionError(paramStr(1))
    return

when isMainModule:
  main()
