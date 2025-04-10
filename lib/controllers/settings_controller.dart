import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsController extends GetxController {
  final RxBool isDebugLoggingEnabled = false.obs;
  SharedPreferences? _prefs;
  static const String _debugLogKey = 'debug_logging_enabled';

  @override
  void onInit() {
    super.onInit();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    isDebugLoggingEnabled.value = _prefs?.getBool(_debugLogKey) ?? false;
    print("[SettingsController] Debug logging loaded: ${isDebugLoggingEnabled.value}");
  }

  Future<void> setDebugLogging(bool enabled) async {
    isDebugLoggingEnabled.value = enabled;
    await _prefs?.setBool(_debugLogKey, enabled);
    print("[SettingsController] Debug logging set to: ${enabled}");
  }
}