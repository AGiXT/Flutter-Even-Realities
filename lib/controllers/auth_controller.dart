import 'dart:async';
import 'dart:convert';
import 'package:get/get.dart';
import 'package:agixtsdk/agixtsdk.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http; // Import http package
import 'server_config_controller.dart';
import '../services/oauth_service.dart'; // Import OAuthService

class AuthController extends GetxController {
  final Rx<AGiXTSDK?> sdk = Rx<AGiXTSDK?>(null);
  final RxBool isLoggedIn = false.obs;
  final RxBool isLoading = false.obs;
  final RxString error = ''.obs;
  final RxString otpUri = ''.obs;
  final RxString token = ''.obs; // Holds the "Bearer <token>"
  final RxList<Map<String, dynamic>> oauthProviders = <Map<String, dynamic>>[].obs;
  final RxBool isProvidersLoading = false.obs;

  late final ServerConfigController _serverConfigController;
  late final OAuthService _oauthService; // Add OAuthService instance
  SharedPreferences? _prefs;
  static const String _tokenKey = 'auth_token'; // Key for storing the raw token

  @override
  void onInit() {
    super.onInit();
    _serverConfigController = Get.find<ServerConfigController>();
    _oauthService = OAuthService(baseUri: _serverConfigController.baseUri.value); // Initialize OAuthService

    // Initialize empty SDK - will configure later
    sdk.value = AGiXTSDK(baseUri: '', apiKey: '', verbose: false);

    // Listen for server config changes to re-init SDK and fetch providers
    _serverConfigController.baseUri.listen((newUri) {
      if (newUri.isNotEmpty) {
        sdk.value = AGiXTSDK(baseUri: newUri, apiKey: token.value, verbose: false);
        fetchOAuthProviders(); // Fetch providers when URI changes
        _oauthService.updateBaseUri(newUri); // Update OAuthService URI
      } else {
        sdk.value = AGiXTSDK(baseUri: '', apiKey: '', verbose: false);
        oauthProviders.clear(); // Clear providers if URI is invalid
      }
    });
     _serverConfigController.apiKey.listen((newApiKey) {
       if (sdk.value != null && _serverConfigController.baseUri.value.isNotEmpty) {
         sdk.value = AGiXTSDK(baseUri: _serverConfigController.baseUri.value, apiKey: newApiKey, verbose: false);
       }
     });


    _initializeController();
  }

  Future<void> _initializeController() async {
    _prefs = await SharedPreferences.getInstance();
    await _restoreSavedToken();
  }

  Future<void> _restoreSavedToken() async {
    if (_prefs == null) return;
    
    final savedRawToken = _prefs!.getString(_tokenKey); // Get raw token
    if (savedRawToken != null && savedRawToken.isNotEmpty) {
      token.value = "Bearer $savedRawToken"; // Set the full token for SDK use
      _serverConfigController.updateWithToken(savedRawToken); // Update server config with raw token
      isLoggedIn.value = true;
      // Fetch providers only after confirming server config and token are potentially set
      await fetchOAuthProviders();
    } else {
      // If no token, still try fetching providers if server is configured
      if (_serverConfigController.isConfigured.value) {
        await fetchOAuthProviders();
      }
    }
  }

  // Saves the raw token (without "Bearer ")
  Future<void> _saveToken(String rawToken) async {
    if (_prefs == null) return;
    await _prefs!.setString(_tokenKey, rawToken);
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

      // Assume tokenValue is the raw token
      token.value = "Bearer $tokenValue"; // Set RxString with "Bearer " prefix
      await _saveToken(tokenValue); // Save the raw token
      _serverConfigController.updateWithToken(tokenValue); // Update server config with raw token
      // Update SDK instance with the new token
      if (sdk.value != null && _serverConfigController.baseUri.value.isNotEmpty) {
         sdk.value = AGiXTSDK(baseUri: _serverConfigController.baseUri.value, apiKey: token.value, verbose: false);
      }
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
    _serverConfigController.updateWithToken(''); // Clear token in server config
    if (sdk.value != null && _serverConfigController.baseUri.value.isNotEmpty) {
       sdk.value = AGiXTSDK(baseUri: _serverConfigController.baseUri.value, apiKey: '', verbose: false); // Update SDK
    }
  }

  // --- OAuth Methods ---

  Future<void> fetchOAuthProviders() async {
    if (sdk.value == null || _serverConfigController.baseUri.value.isEmpty) {
      print("SDK not ready or server not configured to fetch OAuth providers.");
      oauthProviders.clear();
      return;
    }

    isProvidersLoading.value = true;
    error.value = '';
    // Use http package directly as SDK method is unavailable
    final url = Uri.parse('${_serverConfigController.baseUri.value}/v1/oauth');
    final Map<String, String> headers = {
       'Accept': 'application/json',
       // Add Authorization header if needed, though this endpoint might be public
       if (token.value.isNotEmpty) 'Authorization': token.value,
     };

    try {
       print("Fetching OAuth providers from: $url");
       final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 15));

       print("OAuth providers response status: ${response.statusCode}");
       // print("OAuth providers response body: ${response.body}"); // Uncomment for debugging

       if (response.statusCode == 200) {
         final decodedBody = jsonDecode(response.body);

         if (decodedBody is Map<String, dynamic> &&
             decodedBody.containsKey('providers') &&
             decodedBody['providers'] is List) {

           final List<Map<String, dynamic>> providers = List<Map<String, dynamic>>.from(
             decodedBody['providers'].map((item) {
               if (item is Map<String, dynamic>) {
                 // Ensure all expected fields are present
                 // Always require PKCE for Google OAuth
                 bool pkceRequired = item["pkce_required"] ?? false;
                 if (item["name"]?.toLowerCase() == "google") {
                   pkceRequired = true;
                 }
                 return {
                   "name": item["name"] ?? "",
                   "scopes": item["scopes"] ?? "",
                   "authorize": item["authorize"] ?? "",
                   "client_id": item["client_id"] ?? "",
                   "pkce_required": pkceRequired,
                 };
               } else {
                 print("Warning: Unexpected item type in OAuth providers list: $item");
                 return <String, dynamic>{}; // Return empty map for invalid items
               }
             }).where((item) => item.isNotEmpty && (item['client_id']?.isNotEmpty ?? false)) // Filter out invalid/empty entries AND those without client_id
           );
            oauthProviders.assignAll(providers);
            print("Loaded ${providers.length} OAuth providers.");
         } else {
           throw Exception("Unexpected response format for OAuth providers. Expected {'providers': [...]}. Got: ${response.body}");
         }
       } else {
          throw Exception("Failed to load OAuth providers: ${response.statusCode} ${response.reasonPhrase}");
       }
    } catch (e) {
      print("Error fetching OAuth providers: $e");
      error.value = 'Failed to load OAuth providers: ${e.toString()}';
      oauthProviders.clear();
    } finally {
      isProvidersLoading.value = false;
    }
  }

  Future<bool> loginWithOAuth(Map<String, dynamic> provider) async {
    if (sdk.value == null || _serverConfigController.baseUri.value.isEmpty) {
      error.value = 'Server not configured.';
      return false;
    }
    
    // Reset state before starting OAuth flow
    error.value = '';
    isLoading.value = true;

    try {
      // Validate provider configuration
      if (provider.isEmpty) {
        throw Exception('Invalid OAuth provider configuration.');
      }
      
      final String providerName = provider['name'] ?? 'unknown';
      final String authorizationUrl = provider['authorize'] ?? '';
      final String clientId = provider['client_id'] ?? '';
      final String scopes = provider['scopes'] ?? '';
      final bool pkceRequired = provider['pkce_required'] ?? false;

      if (authorizationUrl.isEmpty || clientId.isEmpty) {
        throw Exception('Provider configuration is missing authorize URL or client ID.');
      }

      // Define additional parameters for Google OAuth
      Map<String, String> additionalParams = {};
      if (providerName.toLowerCase() == 'google') {
        additionalParams['access_type'] = 'offline';
        additionalParams['prompt'] = 'consent'; // Force consent screen to get refresh token
      }

      // Start OAuth flow
      final OAuthResult oauthResult = await _oauthService.authenticate(
        authorizationUrl: authorizationUrl,
        clientId: clientId,
        scopes: scopes,
        providerName: providerName,
        pkceRequired: pkceRequired,
        additionalParams: additionalParams,
      );

      // Exchange code with backend
      final backendUrl = Uri.parse('${_serverConfigController.baseUri.value}/v1/oauth2/${oauthResult.providerName}');
      final Map<String, String> headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        // Include existing token if user is linking account, otherwise backend handles new login
        if (token.value.isNotEmpty) 'Authorization': token.value,
        'X-OAuth-Provider': oauthResult.providerName.toLowerCase(),
      };

      // Use the state and redirect_uri from the OAuthResult
      final bodyMap = {
        'code': oauthResult.code,
        'state': oauthResult.state,
        'redirect_uri': oauthResult.redirectUri, // Use redirectUri from the result
        'referrer': oauthResult.redirectUri, // Send the actual redirect URI as the referrer
      };
      final body = jsonEncode(bodyMap);
      
      print("[AuthController] Exchanging OAuth code with backend");
      print("[AuthController] State JWT length: ${oauthResult.state.length}");
      print("[AuthController] URL: $backendUrl");
      print("[AuthController] Request body: $body");
      
      final response = await http.post(backendUrl, headers: headers, body: body)
          .timeout(const Duration(seconds: 45));

      // Reset error state before processing response
      error.value = '';

      print("Backend response status: ${response.statusCode}");
      print("Backend response body: ${response.body}");
      
      // Try to get more details from error response
      if (response.statusCode != 200) {
        try {
          final errorData = jsonDecode(response.body);
          print("Detailed error: ${errorData['detail']}");
          // Check if there's more error context
          if (errorData['error'] != null) {
            print("Error context: ${errorData['error']}");
          }
        } catch (e) {
          print("Could not parse error response: $e");
        }
      }


      if (response.statusCode >= 200 && response.statusCode < 300) {
        final responseData = jsonDecode(response.body);

        // Check if user was already logged in (linking account)
         if (token.value.isNotEmpty && responseData.containsKey('detail') && responseData['detail'].contains("connected successfully")) {
           print("OAuth provider ${oauthResult.providerName} linked successfully.");
           error.value = 'Account linked successfully!';
           isLoading.value = false;
           return true;
         }

         // Clear existing token for new OAuth login
         if (token.value.isNotEmpty) {
           await logout();
         }


        // Handle new login or token refresh
        String? extractedToken;
        if (responseData.containsKey('token') && responseData['token'] != null) {
          extractedToken = responseData['token'];
           // Check if the token includes "Bearer " prefix from backend
           if (extractedToken!.startsWith('Bearer ')) {
             extractedToken = extractedToken.substring(7);
           }
        } else if (responseData.containsKey('detail') && responseData['detail'] != null) {
          // Try extracting from magic link in 'detail'
          extractedToken = _extractTokenFromResponse(responseData['detail']);
        }


        if (extractedToken != null && extractedToken.isNotEmpty) {
          return await loginWithToken(extractedToken); // Use existing token login flow
        } else {
          throw Exception('Token not found in backend response.');
        }
      } else {
        // Handle backend error
        String errorMessage = 'Failed to exchange OAuth code with backend.';
        try {
          final errorData = jsonDecode(response.body);
          errorMessage = errorData['detail'] ?? errorMessage;
        } catch (_) {
          // Ignore JSON decode error, use default message
           errorMessage = "${response.statusCode}: ${response.reasonPhrase ?? 'Unknown backend error'}";
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      print("OAuth Error: $e");
      error.value = e.toString();
      // Ensure token is cleared on OAuth failure if not linking
      if (!token.value.isEmpty) {
        await logout();
      }
      return false;
    } finally {
      isLoading.value = false;
      // Clean up any dangling OAuth state
      _oauthService.dispose();
    }
  }

  @override
  void onClose() {
    _oauthService.dispose(); // Dispose the OAuth service and server
    super.onClose();
  }
}