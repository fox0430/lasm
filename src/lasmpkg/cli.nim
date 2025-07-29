import std/[os, pegs, strformat]

import server

type AppConfig* = object
  configPath*: string
  enableFileLog*: bool
  logPath*: string

proc staticReadVersionFromNimble(): string {.compileTime.} =
  ## Get the version from nimble file.

  let
    peg = """@ "version" \s* "=" \s* \" {[0-9.]+} \" @ $""".peg

    nimblePath = currentSourcePath.parentDir() / "../../lasm.nimble"
    nimbleSpec = staticRead(nimblePath)

  var captures: seq[string] = @[""]
  assert nimbleSpec.match(peg, captures)
  assert captures.len == 1
  return captures[0]

proc writeVersion() =
  echo staticReadVersionFromNimble()

proc writeUsage*(isErr: bool = false) =
  const Text =
    """

Usage:
  lasm --config <path>         # Start LSP server with config file
  lasm --create-sample-config  # Create sample configuration
  lasm --file-log              # Enable file logging
  lasm --file-log-path <path>  # Set log file path
  lasm --help                  # Show help
"""

  if isErr:
    stderr.writeLine(Text)
  else:
    stdout.writeLine(Text)

proc writeNoConfigError*() =
  stderr.writeLine("Error: --config requires a file path")
  writeUsage(true)

proc writeUnknownOptionError*(param: string) =
  stderr.writeLine("Error: Unknown option '" & param & "'")
  writeUsage(true)

proc unknownOptionError(s: string) =
  stderr.writeLine(fmt"Unknown option argument: {s}")
  writeUsage(true)

proc parseCliParams*(): AppConfig =
  # Parse command line arguments
  var i = 1
  while i <= paramCount():
    let param = paramStr(i)
    case param
    of "--file-log":
      result.enableFileLog = true
    of "--create-sample-config":
      let sm = ScenarioManager()
      sm.createSampleConfig()
      quit(0)
    of "--config":
      if i + 1 <= paramCount():
        result.configPath = paramStr(i + 1)
        inc i
      else:
        writeNoConfigError()
        quit(1)
    of "-h", "--help":
      writeUsage()
      quit(0)
    of "-v", "--version":
      writeVersion()
      quit(0)
    else:
      unknownOptionError(param)
      quit(1)
    inc i
