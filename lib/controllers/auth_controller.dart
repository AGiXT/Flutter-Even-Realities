import 'package:get/get.dart';
import 'package:agixtsdk/agixtsdk.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'server_config_controller.dart';

class AuthController extends GetxController {
  final Rx<AGiXTSDK?> sdk = Rx<AGiXTSDK?>(null);
  final RxBool isLoggedIn = false.obs;
  final RxBool isLoading = false.obs;
  final RxString error = ''.obs;
  final RxString otpUri = ''.obs;
  final RxString token = ''.obs;

  late final ServerConfigController _serverConfigController;
  SharedPreferences? _prefs;
  static const String _tokenKey = 'auth_token';

  @override
  void onInit() {
    super.onInit();
    _serverConfigController = Get.find<ServerConfigController>();
    // Initialize empty SDK - will configure later if valid credentials exist
    sdk.value = AGiXTSDK(baseUri: '', apiKey: '', verbose: false); // Empty credentials will be populated after login
    _initializeController();
  }

  Future<void> _initializeController() async {
    _prefs = await SharedPreferences.getInstance();
    await _restoreSavedToken();
  }

  Future<void> _restoreSavedToken() async {
    if (_prefs == null) return;
    
    final savedToken = _prefs!.getString(_tokenKey);
    if (savedToken != null) {
      final fullToken = "Bearer $savedToken";
      token.value = fullToken;
      _serverConfigController.updateWithToken(fullToken);
      isLoggedIn.value = true;
    }
  }

  Future<void> _saveToken(String token) async {
    if (_prefs == null) return;
    await _prefs!.setString(_tokenKey, token);
  }

  String? _extractTokenFromResponse(String responseUrl) {
    try {
      final uri = Uri.parse(responseUrl);
      return uri.queryParameters['token']?.trim();
    } catch (e) {
      return null;
    }
  }

  Future<bool> login(String email, String otp) async {
    try {
      // Validate inputs first
      if (!RegExp(r'^.+@.+\..+$').hasMatch(email)) {
        error.value = 'Please enter a valid email address';
        return false;
      }
      if (otp.length != 6 || !RegExp(r'^\d{6}$').hasMatch(otp)) {
        error.value = 'OTP must be 6 digits';
        return false;
      }

      if (sdk.value == null) {
        error.value = 'SDK not initialized';
        return false;
      }
      
      isLoading.value = true;
      error.value = '';
      update(); // Proper GetX update method

      final response = await sdk.value!.login(email, otp)
          .timeout(const Duration(seconds: 30));

      if (response == null) {
        error.value = 'Invalid login credentials';
        return false;
      }

      // Response should be like: "Log in at ?token=xyz"
      if (response.contains("?token=")) {
        final token = response.split("token=")[1];
        // Use the same token login flow as API key login
        return await loginWithToken(token);
      }

      error.value = 'Invalid login response';
      isLoggedIn.value = true;
      return true;
    } catch (e) {
      error.value = e.toString();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> loginWithToken(String tokenValue) async {
    try {
      if (sdk.value == null) return false;
      
      isLoading.value = true;
      error.value = '';

      final fullToken = "Bearer $tokenValue";
      token.value = fullToken;
      await _saveToken(fullToken);
      _serverConfigController.updateWithToken(tokenValue);
      isLoggedIn.value = true;
      return true;
    } catch (e) {
      error.value = e.toString();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> registerUser(String email, String firstName, String lastName) async {
    try {
      if (sdk.value == null) return false;
      
      isLoading.value = true;
      error.value = '';
      otpUri.value = '';
      
      final result = await sdk.value!.registerUser(email, firstName, lastName);
      if (result != null) {
        if (result.toString().startsWith('otpauth://')) {
          otpUri.value = result;
          return true;
        } else {
          error.value = result;
        }
      } else {
        error.value = 'Registration failed';
      }
      return false;
    } catch (e) {
      error.value = e.toString();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  void clearOtpUri() {
    otpUri.value = '';
  }

  Future<void> logout() async {
    isLoggedIn.value = false;
    otpUri.value = '';
    token.value = '';
    if (_prefs != null) {
      await _prefs!.remove(_tokenKey);
    }
    _serverConfigController.updateWithToken('');
  }
}