enum LogLevel {
  debug,
  info,
  warning,
  error,
}

class Logger {
  bool     isEnabled   = true;
  LogLevel filterLevel = LogLevel.info;

  void debug(String message) {
    _log(LogLevel.debug, message);
  }

  void info(String message) {
    _log(LogLevel.info, message);
  }

  void warning(String message) {
    _log(LogLevel.warning, message);
  }

  void error(String message) {
    _log(LogLevel.error, message);
  }

  void _log(LogLevel level, String message) {
    if (isEnabled && level.index >= filterLevel.index) {
      String logLevelString = _getLogLevelString(level);
      String formattedMessage = 'WebSocket [$logLevelString] $message';
      print(formattedMessage); // ignore: avoid_print
    }
  }

  String _getLogLevelString(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARNING';
      case LogLevel.error:
        return 'ERROR';
      default:
        assert(false, "unreachable");
        return 'UNKNOWN';
    }
  }
}