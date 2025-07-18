import std/unittest

import pkg/chronos

import ../src/lasmpkg/[transport, logger]

# This test avoids creating actual servers and just tests the working parts

suite "working server components":
  setup:
    setGlobalLogger(newFileLogger(enabled = false))

  test "Mock transport read functionality":
    let mockTransport = newMockTransport("ABC")

    let ch1 = waitFor mockTransport.read()
    let ch2 = waitFor mockTransport.read()
    let ch3 = waitFor mockTransport.read()

    check ch1 == 'A'
    check ch2 == 'B'
    check ch3 == 'C'

  test "Mock transport write functionality":
    let mockTransport = newMockTransport()

    waitFor mockTransport.write("Hello")
    waitFor mockTransport.write(" World")

    check mockTransport.getOutputData() == "Hello World"

  test "Mock transport failure simulation":
    let mockTransport = newMockTransport()
    mockTransport.setFailureMode(failRead = true)

    expect IOError:
      discard waitFor mockTransport.read()

  test "Mock transport EOF simulation":
    let mockTransport = newMockTransport("") # Empty

    expect EOFError:
      discard waitFor mockTransport.read()

  test "Transport polymorphism":
    let mockTransport1 = newMockTransport("X")
    let mockTransport2 = newMockTransport("Y")

    let transport1: Transport = mockTransport1
    let transport2: Transport = mockTransport2

    let ch1 = waitFor transport1.read()
    let ch2 = waitFor transport2.read()

    check ch1 == 'X'
    check ch2 == 'Y'
