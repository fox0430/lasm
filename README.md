# lasm

A configurable LSP server for debugging/testing LSP clients.

## Quick Start

```bash
# Build
nimble build

# Create example config
./lasm --create-sample-config

# Start server
./lasm --config ./lsp-test-config-sample.json
```

## Usage

```bash
Usage:
  lasm --config <path>         # Start LSP server with config file
  lasm --create-sample-config  # Create sample configuration
  lasm --file-log              # Enable file logging
  lasm --file-log-path <path>  # Set log file path
  lasm --help                  # Show help
```

## Config

Configure scenarios in JSON to control LSP behavior:
- Responses and delays
- Error injection
- Feature toggles

See `lsp-test-config-sample.json` for examples.

## Supported LSP methods

| Name | Note |
|--|--|
| initialize | |
| initialized | |
| workspace/didChangeConfiguration | |
| textDocument/didOpen | |
| textDocument/didChange | |
| textDocument/didClose | |
| textDocument/hover | |
| textDocument/completion | |
| textDocument/publishDiagnostics | |
| textDocument/inlayHint | |
| textDocument/shutdown | |

## Commands

LASM provides several commands that can be executed through the LSP client:

- `lsptest.switchScenario` - Switch to a different test scenario
- `lsptest.listScenarios` - List all available scenarios
- `lsptest.reloadConfig` - Reload configuration file
- `lsptest.createSampleConfig` - Create a sample configuration file
- `lsptest.listOpenFiles` - List all currently open files with details
