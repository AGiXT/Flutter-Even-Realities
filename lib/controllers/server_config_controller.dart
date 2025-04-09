import 'package:get/get.dart';
import 'package:agixtsdk/agixtsdk.dart';
import '../controllers/auth_controller.dart';

class ServerConfigController extends GetxController {
  final RxBool isConfigured = false.obs;
  final RxString baseUri = 'http://localhost:7437'.obs;
  final RxString apiKey = ''.obs;
  final RxString error = ''.obs;
  final RxString currentUserEmail = ''.obs; // Single declaration
  final RxList<Map<String, dynamic>> availableAgents = <Map<String, dynamic>>[].obs;
  final RxString selectedAgent = 'AGiXT'.obs; // Default agent

  final Rx<AGiXTSDK?> sdk = Rx<AGiXTSDK?>(null); // SDK instance as Rx

  @override
  void onInit() {
    super.onInit();
    // Initialize SDK with default settings but don't mark as configured yet
    _initializeSDK(baseUri.value, apiKey.value);
  }

  void _initializeSDK(String uri, String? key) {
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

      _initializeSDK(cleanUri, key); // Re-initialize SDK with new config
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
      // Fetch agents once connection is confirmed
      await fetchAgents();
    } catch (e) {
      error.value = 'Failed to connect to server. Please check server configuration. ${e.toString()}';
      isConfigured.value = false;
      availableAgents.clear(); // Clear agents on connection failure
      selectedAgent.value = 'AGiXT'; // Reset to default
    }
  }

  // Call this when auth token changes
  void updateWithToken(String token) {
    if (token.isNotEmpty) {
      _initializeSDK(baseUri.value, token);
    }
  }

  // Fetch available agents from the server
  Future<void> fetchAgents() async {
    print("[ServerConfigController] Attempting to fetch agents..."); // Log start
    if (sdk.value == null) {
      print("[ServerConfigController] SDK not initialized, cannot fetch agents.");
      availableAgents.clear();
      selectedAgent.value = 'AGiXT'; // Reset to default
      return;
    }
    try {
      final agents = await sdk.value!.getAgents();
      availableAgents.assignAll(agents);
      // If the current selection is invalid or default, select the first available one
      if (availableAgents.isNotEmpty &&
          (selectedAgent.value == 'AGiXT' || !availableAgents.any((agent) => agent['name'] == selectedAgent.value))) {
        selectedAgent.value = availableAgents.first['name'];
      } else if (availableAgents.isEmpty) {
        selectedAgent.value = 'AGiXT'; // Reset if no agents found
      }
      print("[ServerConfigController] Successfully fetched ${availableAgents.length} agents.");
      if (availableAgents.isNotEmpty) {
        print("[ServerConfigController] Agents found: ${availableAgents.map((a) => a['name']).toList()}");
        print("[ServerConfigController] Selected agent after fetch: ${selectedAgent.value}");
      } else {
        print("[ServerConfigController] No agents found on the server.");
      }
    } catch (e) {
      print("[ServerConfigController] Error fetching agents: $e"); // Log error details
      error.value = 'Failed to fetch agents: ${e.toString()}';
      availableAgents.clear();
      selectedAgent.value = 'AGiXT'; // Reset to default on error
    }
  }

  // Update the selected agent
  void selectAgent(String agentName) {
    if (availableAgents.any((agent) => agent['name'] == agentName)) {
      selectedAgent.value = agentName;
      print("Selected agent: $agentName");
    } else {
      print("Attempted to select invalid agent: $agentName");
    }
  }
  // End of class ServerConfigController
}