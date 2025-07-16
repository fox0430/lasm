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
