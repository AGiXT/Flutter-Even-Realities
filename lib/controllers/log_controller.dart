import 'package:get/get.dart';
import 'settings_controller.dart'; // To check if logging is enabled

class LogEntry {
  final DateTime timestamp;
  final String message;

  LogEntry({required this.message}) : timestamp = DateTime.now();

  @override
  String toString() {
    // Simple timestamp format
    final timeStr = "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}";
    return "[$timeStr] $message";
  }
}

class LogController extends GetxController {
  final RxList<LogEntry> logMessages = <LogEntry>[].obs;
  final int maxLogEntries = 100; // Limit the number of stored logs

  // Lazy load SettingsController only when needed
  SettingsController? _settingsController;
  SettingsController get settings {
    _settingsController ??= Get.find<SettingsController>();
    return _settingsController!;
  }

  void addLog(String message) {
    // Only add log if debug logging is enabled
    if (settings.isDebugLoggingEnabled.value) {
      final entry = LogEntry(message: message);
      if (logMessages.length >= maxLogEntries) {
        logMessages.removeAt(0); // Remove oldest log if limit reached
      }
      logMessages.add(entry);
      print(entry.toString()); // Also print to debug console for redundancy
    }
  }

  void clearLogs() {
    logMessages.clear();
  }
}