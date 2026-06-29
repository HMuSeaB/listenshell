import 'dart:developer' as developer;

class LogCollector {
  static final LogCollector instance = LogCollector._();
  LogCollector._();

  final List<String> logs = [];
  final int maxLogs = 500;
  void Function()? onLog;

  void log(String message, {Object? error, StackTrace? stackTrace}) {
    final time = DateTime.now().toLocal().toString().substring(11, 19);
    var fullMsg = '[$time] $message';
    if (error != null) {
      fullMsg += '\nError: $error';
    }
    if (stackTrace != null) {
      fullMsg += '\nStackTrace: $stackTrace';
    }

    logs.add(fullMsg);
    if (logs.length > maxLogs) {
      logs.removeAt(0);
    }

    // 同时输出到原生控制台
    developer.log(message, error: error, stackTrace: stackTrace, name: 'ListenShellLog');
    onLog?.call();
  }

  void clear() {
    logs.clear();
    onLog?.call();
  }
}
