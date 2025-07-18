import std/[strformat]
import pkg/chronos
import pkg/chronos/transports/stream

import logger

type
  Transport* = ref object of RootObj
    ## Abstract transport interface for LSP communication

  LSPTransport* = ref object of Transport ## Real transport using stdin/stdout streams
    input*: StreamTransport
    output*: StreamTransport

  MockTransport* = ref object of Transport ## Mock transport for testing
    inputBuffer*: string
    outputBuffer*: string
    readPos*: int
    shouldFailRead*: bool
    shouldFailWrite*: bool

# Base transport methods (must be overridden)
method read*(transport: Transport): Future[char] {.async, base.} =
  raise newException(CatchableError, "Transport.read() not implemented")

method write*(transport: Transport, data: string): Future[void] {.async, base.} =
  raise newException(CatchableError, "Transport.write() not implemented")

method close*(transport: Transport) {.base.} =
  discard # Default implementation does nothing

# LSPTransport implementation for real I/O
method read*(transport: LSPTransport): Future[char] {.async.} =
  let r = await transport.input.read(1)
  return char(r[0])

method write*(transport: LSPTransport, data: string): Future[void] {.async.} =
  let r = await transport.output.write(data)
  if r == -1:
    raise newException(IOError, "Failed to write to transport")

method close*(transport: LSPTransport) =
  if transport.input != nil:
    transport.input.close()
  if transport.output != nil:
    transport.output.close()

# MockTransport implementation for testing
method read*(transport: MockTransport): Future[char] {.async.} =
  if transport.shouldFailRead:
    raise newException(IOError, "Mock read failure")

  if transport.readPos >= transport.inputBuffer.len:
    raise newException(EOFError, "End of mock buffer")

  let ch = transport.inputBuffer[transport.readPos]
  transport.readPos += 1
  return ch

method write*(transport: MockTransport, data: string): Future[void] {.async.} =
  if transport.shouldFailWrite:
    raise newException(IOError, "Mock write failure")

  transport.outputBuffer.add(data)
  logDebug(fmt"MockTransport wrote: {data}")

method close*(transport: MockTransport) =
  # Nothing to close for mock transport
  discard

# Factory functions
proc newLSPTransport*(): LSPTransport =
  ## Create a new LSP transport using stdin/stdout
  result = LSPTransport()
  try:
    const
      STDIN_FD = 0
      STDOUT_FD = 1
    result.input = fromPipe(AsyncFD(STDIN_FD))
    result.output = fromPipe(AsyncFD(STDOUT_FD))
    logDebug("Created new LSP transport with stdin/stdout")
  except Exception as e:
    logError("Failed to create LSP transport: " & e.msg)
    raise newException(IOError, "Cannot create LSP transport: " & e.msg)

proc newMockTransport*(inputData: string = ""): MockTransport =
  ## Create a new mock transport for testing
  result = MockTransport(
    inputBuffer: inputData,
    outputBuffer: "",
    readPos: 0,
    shouldFailRead: false,
    shouldFailWrite: false,
  )
  logDebug(fmt"Created new mock transport with input: {inputData}")

# Helper methods for MockTransport
proc setInputData*(transport: MockTransport, data: string) =
  ## Set new input data and reset read position
  transport.inputBuffer = data
  transport.readPos = 0

proc getOutputData*(transport: MockTransport): string =
  ## Get all data written to the mock transport
  return transport.outputBuffer

proc clearOutput*(transport: MockTransport) =
  ## Clear the output buffer
  transport.outputBuffer = ""

proc setFailureMode*(
    transport: MockTransport, failRead: bool = false, failWrite: bool = false
) =
  ## Configure the mock transport to simulate failures
  transport.shouldFailRead = failRead
  transport.shouldFailWrite = failWrite

proc hasMoreInput*(transport: MockTransport): bool =
  ## Check if there's more input data to read
  return transport.readPos < transport.inputBuffer.len
