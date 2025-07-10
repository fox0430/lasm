# lasm

A configurable LSP server for debugging/testing LSP clients.

## Quick Start

```bash
# Build
nimble build

# Create example config
./lasm --create-sample-config

# Start server
./lasm
```

## Usage

```bash
Usage:
  lasm --config <path>         # Start LSP server with config file
  lasm --create-sample-config  # Create sample configuration
  lasm --help                  # Show help
```

## Config

Configure scenarios in JSON to control LSP behavior:
- Hover responses and delays
- Error injection
- Feature toggles

See `lsp-test-config-sample.json` for examples.
