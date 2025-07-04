# lasm

A configurable LSP test server for testing LSP clients.

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
./lasm                           # Use lsp-test-config.json
./lasm --config custom.json      # Use custom config file
./lasm --create-sample-config    # Generate sample config
```

## Config

Configure scenarios in JSON to control LSP behavior:
- Hover responses and delays
- Error injection
- Feature toggles

See `lsp-test-config-sample.json` for examples.
