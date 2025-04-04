import 'package:get/get.dart';
import 'package:agixtsdk/agixtsdk.dart';
import '../controllers/auth_controller.dart';

class ServerConfigController extends GetxController {
  final RxBool isConfigured = false.obs;
  final RxString baseUri = 'http://localhost:7437'.obs;
  final RxString apiKey = ''.obs;
  final RxString error = ''.obs;
  final RxString currentUserEmail = ''.obs; // Single declaration

  final Rx<AGiXTSDK?> sdk = Rx<AGiXTSDK?>(null); // SDK instance as Rx

  @override
  void onInit() {
    super.onInit();
    // Initialize SDK with default settings but don't mark as configured yet
    initializeSDK(baseUri.value, apiKey.value);
  }

  void initializeSDK(String uri, String? key) {
    // Try to get AuthController if it exists
    AuthController? authController;
    try {
      authController = Get.find<AuthController>();
    } catch (_) {
      // AuthController not found, which is fine
    }

    // If we have an auth controller and it has a token, use that instead of the provided key
    final token = authController?.token.value;
    final effectiveKey = token?.isNotEmpty == true ? token : key;

    // Configure the SDK globally
    final newSdk = AGiXTSDK(
      baseUri: uri,
      apiKey: effectiveKey,
      verbose: true,
    );

    // Update our Rx SDK instance
    sdk.value = newSdk;

    // Put new SDK instance globally
    if (Get.isRegistered<AGiXTSDK>()) {
      Get.delete<AGiXTSDK>();
    }
    Get.put(newSdk, permanent: true);

    // If we're reinitializing with an auth token, make sure auth controller uses this instance
    if (authController != null) {
      authController.sdk.value = newSdk;
    }
  }

  bool configureServer(String uri, String? key) {
    try {
      if (uri.isEmpty) {
        error.value = 'Base URI is required';
        return false;
      }

      // Remove trailing slash if present
      final cleanUri = uri.replaceAll(RegExp(r'/$'), '');
      baseUri.value = cleanUri;
      apiKey.value = key ?? '';

      initializeSDK(cleanUri, key); // Re-initialize SDK with new config
      checkServerConnection(); // Check connection after config
      return true;
    } catch (e) {
      error.value = e.toString();
      return false;
    }
  }

  Future<void> checkServerConnection() async {
    isConfigured.value = false; // Reset to false while checking
    try {
      if (sdk.value == null) {
        error.value = 'SDK not initialized';
        return;
      }
      
      isConfigured.value = true;
      
      // Initialize auth controller if needed
      if (!Get.isRegistered<AuthController>()) {
        final authController = AuthController();
        Get.put(authController);
        authController.sdk.value = sdk.value;
      }
    } catch (e) {
      error.value = 'Failed to connect to server. Please check server configuration.';
      isConfigured.value = false;
    }
  }

  // Call this when auth token changes
  void updateWithToken(String token) {
    if (token.isNotEmpty) {
      initializeSDK(baseUri.value, token);
    }
  }

  // Call this to clear the token/API key
  void clearToken() {
    apiKey.value = ''; // Clear local state
    initializeSDK(baseUri.value, null); // Re-initialize SDK without a key
  }

}