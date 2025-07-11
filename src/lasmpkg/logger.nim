import std/[times, os, strformat, json, locks, strutils]

export json

type
  LogLevel* {.pure.} = enum
    Debug = "DEBUG"
    Info = "INFO"
    Warn = "WARN"
    Error = "ERROR"

  LoggerConfig* = object
    enabled*: bool
    filePath*: string
    level*: LogLevel
    maxFileSize*: int
    keepFiles*: int

  FileLogger* = ref object
    config: LoggerConfig
    file: File
    lock: Lock
    isOpen: bool

var globalLogger {.global.}: FileLogger = nil

proc `$`*(level: LogLevel): string =
  case level
  of LogLevel.Debug: "DEBUG"
  of LogLevel.Info: "INFO"
  of LogLevel.Warn: "WARN"
  of LogLevel.Error: "ERROR"

proc parseLogLevel*(s: string): LogLevel =
  case s.toUpperAscii()
  of "DEBUG": LogLevel.Debug
  of "INFO": LogLevel.Info
  of "WARN", "WARNING": LogLevel.Warn
  of "ERROR": LogLevel.Error
  else: LogLevel.Info

proc shouldLog(logger: FileLogger, level: LogLevel): bool =
  if not logger.config.enabled or not logger.isOpen:
    return false

  case logger.config.level
  of LogLevel.Debug:
    true
  of LogLevel.Info:
    level >= LogLevel.Info
  of LogLevel.Warn:
    level >= LogLevel.Warn
  of LogLevel.Error:
    level >= LogLevel.Error

proc rotateLogFile(logger: FileLogger) =
  if not logger.isOpen:
    return

  try:
    let fileSize = logger.file.getFileSize()
    if fileSize >= logger.config.maxFileSize:
      logger.file.close()

      for i in countdown(logger.config.keepFiles - 1, 1):
        let oldFile = logger.config.filePath & "." & $i
        let newFile = logger.config.filePath & "." & $(i + 1)
        if fileExists(oldFile):
          if fileExists(newFile):
            removeFile(newFile)
          moveFile(oldFile, newFile)

      if fileExists(logger.config.filePath):
        moveFile(logger.config.filePath, logger.config.filePath & ".1")

      logger.file = open(logger.config.filePath, fmWrite)
  except:
    discard

proc writeLog(logger: FileLogger, level: LogLevel, message: string) =
  if not logger.shouldLog(level):
    return

  try:
    withLock logger.lock:
      if logger.isOpen:
        let timestamp = now().format("yyyy-MM-dd HH:mm:ss.fff")
        let logLine = fmt"[{timestamp}] [{level}] {message}"
        logger.file.writeLine(logLine)
        logger.file.flushFile()

        logger.rotateLogFile()
  except:
    discard

proc newFileLogger*(config: LoggerConfig): FileLogger =
  result = FileLogger()
  result.config = config
  result.isOpen = false
  initLock(result.lock)

  if config.enabled:
    try:
      createDir(parentDir(config.filePath))
      result.file = open(config.filePath, fmAppend)
      result.isOpen = true
    except:
      discard

proc newFileLogger*(
    filePath: string = "lsp-server.log",
    level: LogLevel = LogLevel.Info,
    enabled: bool = true,
    maxFileSize: int = 10485760,
    keepFiles: int = 5,
): FileLogger =
  let config = LoggerConfig(
    enabled: enabled,
    filePath: filePath,
    level: level,
    maxFileSize: maxFileSize,
    keepFiles: keepFiles,
  )
  newFileLogger(config)

proc close*(logger: FileLogger) =
  if logger.isOpen:
    withLock logger.lock:
      logger.file.close()
      logger.isOpen = false
  deinitLock(logger.lock)

proc setGlobalLogger*(logger: FileLogger) =
  {.gcsafe.}:
    globalLogger = logger

proc getGlobalLogger*(): FileLogger =
  {.gcsafe.}:
    globalLogger

proc logDebug*(logger: FileLogger, message: string) =
  logger.writeLog(LogLevel.Debug, message)

proc logInfo*(logger: FileLogger, message: string) =
  logger.writeLog(LogLevel.Info, message)

proc logWarn*(logger: FileLogger, message: string) =
  logger.writeLog(LogLevel.Warn, message)

proc logError*(logger: FileLogger, message: string) =
  logger.writeLog(LogLevel.Error, message)

proc logDebug*(message: string) =
  {.gcsafe.}:
    if globalLogger != nil:
      globalLogger.logDebug(message)

proc logInfo*(message: string) =
  {.gcsafe.}:
    if globalLogger != nil:
      globalLogger.logInfo(message)

proc logWarn*(message: string) =
  {.gcsafe.}:
    if globalLogger != nil:
      globalLogger.logWarn(message)

proc logError*(message: string) =
  {.gcsafe.}:
    if globalLogger != nil:
      globalLogger.logError(message)

proc logMessage*(logger: FileLogger, level: LogLevel, message: string) =
  logger.writeLog(level, message)

proc logMessage*(level: LogLevel, message: string) =
  {.gcsafe.}:
    if globalLogger != nil:
      globalLogger.logMessage(level, message)

proc logLSPMessage*(logger: FileLogger, direction: string, message: JsonNode) =
  if logger.shouldLog(LogLevel.Debug):
    let content = $message
    logger.logDebug(fmt"LSP {direction}: {content}")

# Chronicles-related variables removed (no longer needed)

proc logLSPMessage*(direction: string, message: JsonNode) =
  {.gcsafe.}:
    if globalLogger != nil:
      globalLogger.logLSPMessage(direction, message)
