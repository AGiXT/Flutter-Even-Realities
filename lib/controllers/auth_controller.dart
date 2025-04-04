import 'package:dio/dio.dart';
import 'dart:io'; // For HttpServer
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart'; // Keep this as is
import 'package:shelf/shelf.dart' as shelf; // Add prefix for shelf Response
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:agixtsdk/agixtsdk.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'server_config_controller.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:uuid/uuid.dart'; // Add uuid import
import 'dart:convert'; // For jsonEncode/Decode


class AuthController extends GetxController {
  final Rx<AGiXTSDK?> sdk = Rx<AGiXTSDK?>(null);
  final RxBool isLoggedIn = false.obs;
  final RxBool isLoading = false.obs;
  final RxString error = ''.obs;
  final RxString token = ''.obs;
  final RxString apiKey = ''.obs;
  final RxString otpUri = ''.obs; // Added missing field
  final RxList<Map<String, dynamic>> oauthProviders = RxList<Map<String, dynamic>>([]);
  final RxString pkceState = ''.obs;
  final RxString pkceCodeChallenge = ''.obs;
  final RxString _currentOAuthProvider = ''.obs; // Keep for logging/compatibility if needed
  late final ServerConfigController _serverConfigController;
  SharedPreferences? _prefs;
  static const String _tokenKey = 'auth_token';
  final Map<String, String> _stateToProvider = {}; // Add state-to-provider map
  static const String _oauthStateKey = 'oauth_state_map'; // Key for SharedPreferences

  final _appLinks = AppLinks();
  StreamSubscription? _uriLinkSubscription;
  // --- Local HTTP Server for OAuth Callback ---
  HttpServer? _localServer;
  final int _localServerPort = 8989; // Or choose dynamically
  Completer<Uri>? _callbackCompleter; // To wait for the callback

  // Getter for the port used by the local server
  int getLocalServerPort() => _localServerPort;

  @override
  void onInit() {
    super.onInit();
    _serverConfigController = Get.find<ServerConfigController>();
    _initializeController().then((_) => fetchOAuthProviders());
    sdk.value = AGiXTSDK(baseUri: '', apiKey: '', verbose: false);
    _initAppLinks();
  }

  @override
  void onClose() {
    _uriLinkSubscription?.cancel();
    stopLocalServer(); // Ensure local server is stopped
    super.onClose();
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
      apiKey.value = savedToken;
      _serverConfigController.updateWithToken(savedToken);
      isLoggedIn.value = true;
    }
  }

  Future<void> _saveToken(String token) async {
    if (_prefs == null) return;
    await _prefs!.setString(_tokenKey, token);
  }


  // --- OAuth State Persistence ---
  Future<void> _saveStateMap() async {
    if (_prefs == null) return;
    try {
      final jsonString = jsonEncode(_stateToProvider);
      await _prefs!.setString(_oauthStateKey, jsonString);
      print('Saved OAuth state map to SharedPreferences: $jsonString');
    } catch (e) {
      print('Error saving OAuth state map: $e');
    }
  }

  Future<void> _loadStateMap() async {
    if (_prefs == null) return;
    try {
      final jsonString = _prefs!.getString(_oauthStateKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        _stateToProvider.clear(); // Clear before loading to avoid duplicates
        _stateToProvider.addAll(Map<String, String>.from(jsonDecode(jsonString)));
        print('Loaded OAuth state map from SharedPreferences: $_stateToProvider');
      } else {
        print('No OAuth state map found in SharedPreferences.');
        _stateToProvider.clear(); // Ensure map is empty if nothing is loaded
      }
    } catch (e) {
      print('Error loading OAuth state map: $e');
      // If loading fails, clear potentially corrupted state
      await _prefs!.remove(_oauthStateKey);
      _stateToProvider.clear();
    }
  }

  Future<void> _clearStateEntry(String state) async {
    _stateToProvider.remove(state);
    await _saveStateMap(); // Persist the removal
  }
  // --- End OAuth State Persistence ---

  Future<void> _initAppLinks() async {
    try {
      final initialUri = await _appLinks.getInitialAppLink();
      _handleIncomingLink(initialUri);
      _uriLinkSubscription = _appLinks.uriLinkStream.listen(_handleIncomingLink, onError: (err) {
        print('app_links error: $err');
      });
    } on PlatformException {
      print('app_links failed to get initial uri (PlatformException).');
    } catch (e) {
      print('app_links failed to get initial uri: $e');
    }
  }

  // Handles deep links - might need adjustment based on state logic
  void _handleIncomingLink(Uri? uri) {
    if (uri != null && uri.scheme == 'evenrealities' && uri.host == 'oauth-callback') {
       print('Incoming deep link received: $uri');
       // Directly call handleOAuthCallback for unified processing
       handleOAuthCallback(uri);
    }
  }

  // --- OAuth Callback Handling ---
  Future<void> handleOAuthCallback(Uri callbackUri) async {
    print('Processing OAuth callback via direct handler: $callbackUri');
    print('--- State Map at start of handleOAuthCallback (after load) ---');
    print('Current state map: $_stateToProvider');
    print('-------------------------------------------------');
    isLoading.value = true;
    error.value = '';
    
    try {
      final String? code = callbackUri.queryParameters['code'];
      final String? state = callbackUri.queryParameters['state'];
      final String? errorParam = callbackUri.queryParameters['error'];
      
      print('--- Extracted state from callback URI: "$state" ---');
      
      if (errorParam != null) {
        error.value = 'OAuth Error: $errorParam';
        print('OAuth provider returned an error: $errorParam');
        isLoading.value = false;
        if (state != null) _stateToProvider.remove(state);
        _currentOAuthProvider.value = '';
        return;
      }

      if (code == null) {
        error.value = 'Authentication Error: Code parameter missing in callback.';
        print('Callback URI missing code: $callbackUri');
        isLoading.value = false;
        if (state != null) _stateToProvider.remove(state);
        _currentOAuthProvider.value = '';
        return;
      }

      print('--- OAuth Provider Check ---');
      print('Current OAuth Provider before restore: ${_currentOAuthProvider.value}');

      // Restore current OAuth provider if not set
      if (_currentOAuthProvider.value.isEmpty && _prefs != null) {
        // Try to get the original provider name first, fall back to normalized if not found
        final originalProvider = _prefs!.getString('current_oauth_provider_original');
        final normalizedProvider = _prefs!.getString('current_oauth_provider');
        
        // Use original provider name if available, otherwise use normalized
        _currentOAuthProvider.value = originalProvider ?? normalizedProvider ?? '';
        print('Restored OAuth provider from preferences (original: $originalProvider, normalized: $normalizedProvider)');
        print('Using provider: ${_currentOAuthProvider.value}');
      }

      // Get provider details
      final providerName = _currentOAuthProvider.value;
      final provider = oauthProviders.firstWhereOrNull((p) => p['name']?.toLowerCase() == providerName);
      final bool pkceRequired = provider?['pkce_required'] ?? false;

      print('Processing OAuth callback for provider: $providerName (PKCE Required: $pkceRequired)');

      if (pkceRequired && (state == null || !_stateToProvider.containsKey(state))) {
        error.value = 'Authentication Error: Invalid or missing state parameter for PKCE flow.';
        print('Error: State parameter missing or invalid in PKCE flow: $callbackUri');
        isLoading.value = false;
        return;
      }

      if (pkceRequired && state != pkceState.value) {
        error.value = 'Authentication Error: State mismatch.';
        print('Callback URI state does not match PKCE state: $state vs ${pkceState.value}');
        isLoading.value = false;
        _stateToProvider.remove(state);
        _currentOAuthProvider.value = '';
        return;
      }

      print('Exchanging code with backend');
      print('Provider: $providerName');
      print('Code: ${code.substring(0, 10)}... (truncated)');
      
      await _exchangeCodeWithBackend(
        provider: _currentOAuthProvider.value,
        code: code,
        state: pkceRequired ? (state ?? '') : '',
      );

      if (state != null) {
        _stateToProvider.remove(state);
      }

    } catch (e) {
      print('Error processing OAuth callback: $e');
      error.value = 'Error processing authentication callback: ${e.toString()}';
      isLoading.value = false;
      if (callbackUri.queryParameters['state'] != null) {
        _stateToProvider.remove(callbackUri.queryParameters['state']!);
      }
      _currentOAuthProvider.value = '';
    }
  }


  // --- Fetch PKCE Parameters from Backend ---
  Future<void> _fetchPkceParameters() async {
    if (sdk.value == null || _serverConfigController.baseUri.value.isEmpty) {
      error.value = 'Server configuration not set.';
      print('Cannot fetch PKCE parameters: Server config missing.');
      return;
    }
    try {
      final dio = Dio(BaseOptions(baseUrl: _serverConfigController.baseUri.value));
      final response = await dio.get('/v1/oauth2/pkce-simple');
      if (response.statusCode == 200 && response.data != null) {
        pkceCodeChallenge.value = response.data['code_challenge'];
        pkceState.value = response.data['state']; // State contains encrypted verifier
        print('Fetched PKCE Challenge: ${pkceCodeChallenge.value}');
        print('Fetched State (Encrypted Verifier): ${pkceState.value}');
      } else {
        error.value = 'Failed to fetch PKCE parameters: ${response.statusCode}';
        print('Error fetching PKCE parameters: ${response.statusCode} ${response.data}');
        // Clear potentially stale values
        pkceCodeChallenge.value = '';
        pkceState.value = '';
      }
    } catch (e) {
      print('Error fetching PKCE parameters: $e');
      error.value = 'Failed to fetch PKCE parameters from server.';
      // Clear potentially stale values
      pkceCodeChallenge.value = '';
      pkceState.value = '';
      if (e is DioException) {
         print('DioException details: ${e.message}, Response: ${e.response?.data}');
      }
    }
  }
  // --- End Fetch PKCE Parameters ---

 
  Future<void> fetchOAuthProviders() async {
    if (sdk.value == null || _serverConfigController.baseUri.value.isEmpty) {
      print('SDK not ready or server URI not set, cannot fetch OAuth providers.');
      return;
    }
    isLoading.value = true;
    error.value = '';
    try {
      final dio = Dio(BaseOptions(baseUrl: _serverConfigController.baseUri.value));
      final response = await dio.get('/v1/oauth');
      if (response.statusCode == 200 && response.data != null && response.data['providers'] is List) {
        final List<dynamic> providersData = response.data['providers'];
        oauthProviders.assignAll(providersData.map((p) => Map<String, dynamic>.from(p)).toList());
        print('Fetched OAuth providers: ${oauthProviders.length}');
      } else {
        error.value = 'Failed to fetch OAuth providers: ${response.statusCode}';
        print('Error fetching OAuth providers: ${response.statusCode} ${response.data}');
      }
    } catch (e) {
      print('Error fetching OAuth providers: $e');
      error.value = 'Failed to fetch OAuth providers. Check server connection.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> initiateOAuthFlow(String providerName) async {
    if (sdk.value == null || _serverConfigController.baseUri.value.isEmpty) {
      error.value = 'Server configuration not set.';
      print('Cannot initiate OAuth flow: Server config missing.');
      return;
    }
    if (oauthProviders.isEmpty) {
      await fetchOAuthProviders();
      if (oauthProviders.isEmpty) {
        error.value = 'OAuth providers not loaded. Cannot start flow.';
        print('Cannot initiate OAuth flow: Providers not loaded.');
        return;
      }
    }

    final provider = oauthProviders.firstWhereOrNull((p) => p['name']?.toLowerCase() == providerName.toLowerCase());
    if (provider == null) {
      error.value = 'OAuth provider "$providerName" not found or not configured on the server.';
      print('Provider $providerName not found in fetched list.');
      return;
    }
    final bool pkceRequired = provider['pkce_required'] ?? false;
    print('PKCE required for $providerName: $pkceRequired');
    final String normalizedProviderName = providerName.toLowerCase();
    
    // Always store provider name both in memory and persistent storage
    _currentOAuthProvider.value = normalizedProviderName;
    print('Setting current OAuth provider to: $normalizedProviderName');
    
    // Synchronous write to ensure it's available immediately
    if (_prefs != null) {
      // Store both normalized and original name to ensure exact match
      _prefs!.setString('current_oauth_provider', normalizedProviderName);
      _prefs!.setString('current_oauth_provider_original', providerName);
      
      // Verify storage
      final storedProvider = _prefs!.getString('current_oauth_provider');
      print('Verified stored OAuth provider: $storedProvider');
    } else {
      print('WARNING: SharedPreferences not initialized when storing provider name');
    }

    String? stateValue; // This will hold the state sent to the provider (nullable)

    isLoading.value = true;
    error.value = '';


    try {
      // Determine the state value to use
      if (pkceRequired) {
        await _fetchPkceParameters();
        if (pkceState.value.isEmpty || pkceCodeChallenge.value.isEmpty) {
          // Error is set within _fetchPkceParameters, stop the flow
          isLoading.value = false;
          _currentOAuthProvider.value = '';
          // No state was successfully generated or stored yet, so no cleanup needed here
          return;
        }
        stateValue = pkceState.value; // Use the state from the backend (contains encrypted verifier)
        print('--- PKCE State Value to be used: "$stateValue" ---'); // Log the exact value
        print('Using PKCE state from backend: $stateValue');
      } else {
        // Generate a random state if PKCE is not required
        stateValue = Uuid().v4();
        print('--- Generated UUID State Value to be used: "$stateValue" ---'); // Log the exact value
        pkceState.value = ''; // Ensure PKCE values are clear
        pkceCodeChallenge.value = '';
        print('Generated non-PKCE state: $stateValue');
      }

      // Store the state value that will actually be sent and expected back
      _stateToProvider[stateValue] = providerName.toLowerCase();
      print('Stored state mapping: $stateValue -> ${providerName.toLowerCase()}');
      print('Current state map: $_stateToProvider'); // Log map for debugging

      final String authUrl = provider['authorize']; // Use 'authorize' key as per JSON
      final String clientId = provider['client_id'];
      final String scopes = provider['scopes'];
      final String redirectUri = 'http://localhost:$_localServerPort/oauth-callback'; // Use local server URI

      final Map<String, String> queryParams = <String, String>{
        'client_id': clientId,
        'response_type': 'code',
        'scope': scopes,
        'redirect_uri': redirectUri,
      };
      
      // Only add state if PKCE is required
      if (pkceRequired) {
        queryParams['state'] = stateValue;
      }

      if (pkceRequired) {
        // PKCE state is already set in queryParams['state'] via stateValue
        // PKCE state is already in queryParams['state']
        queryParams['code_challenge'] = pkceCodeChallenge.value;
        queryParams['code_challenge_method'] = 'S256';
      }

      final authorizationUri = Uri.parse(authUrl).replace(queryParameters: queryParams);

      print('Constructed Auth URL: $authorizationUri');
      print('--- Full Authorization URI ---');
      print(authorizationUri.toString());
      print('--- State Parameter Check ---');
      print('State included in URL: ${authorizationUri.queryParameters['state']}');
      print('------------------------------');
      // Start local server BEFORE launching URL, wait for callback
      print('Starting local server for redirect URI: $redirectUri');
      final callbackUriFuture = startLocalServerAndAwaitCallback(); // Don't await yet

      if (await canLaunchUrl(authorizationUri)) {
        print('Launching OAuth URL...');
        await launchUrl(authorizationUri, mode: LaunchMode.externalApplication);

        // Now await the callback from the local server
        final callbackUri = await callbackUriFuture; // This now returns Future<Uri> or throws
        // Handle the callback URI received from the local server
        // Note: handleOAuthCallback will set isLoading = false eventually
        await handleOAuthCallback(callbackUri);

      } else {
        // If launch fails, stop the server and throw
        await stopLocalServer(); // Ensure server stops if launch fails
        throw Exception('Could not launch OAuth URL: $authorizationUri');
      }
    } catch (e) {
      print('Error initiating OAuth flow for $providerName: $e');
      error.value = 'Failed to start authentication with $providerName: ${e.toString()}'; // Include error details
      // Ensure loading stops and provider is cleared on any error
      isLoading.value = false;
      // Clean up the state map using the stateValue determined earlier, if it exists
      // Clean up the state map using the stateValue determined earlier, if it's not null and exists in the map
      if (stateValue != null && _stateToProvider.containsKey(stateValue)) {
         _stateToProvider.remove(stateValue);
         print('Cleaned up state map for state: $stateValue on error.');
         await _clearStateEntry(stateValue); // Clean up persisted state on error
      }
      _currentOAuthProvider.value = '';
      await stopLocalServer(); // Ensure server is stopped on error
    }
  }

  Future<void> _exchangeCodeWithBackend({
    required String provider,
    required String code,
    required String state,
  }) async {
    if (sdk.value == null || _serverConfigController.baseUri.value.isEmpty) {
      error.value = 'Server configuration not set.';
      print('Cannot exchange code: Server config missing.');
      isLoading.value = false;
      return;
    }

    print('Attempting to exchange code for provider: "$provider"');
    print('Available OAuth providers: ${oauthProviders.map((p) => p['name']).join(', ')}');
    
    // Fetch provider data and determine if PKCE is required *before* checking state
    final providerData = oauthProviders.firstWhereOrNull((p) => p['name']?.toLowerCase() == provider.toLowerCase());
    if (providerData == null) {
      error.value = 'Provider "$provider" not found in available providers.';
      print('Provider "$provider" not found during code exchange.');
      print('Provider comparison results:');
      oauthProviders.forEach((p) {
        print('  Provider: ${p['name']}, Lowercase match: ${p['name']?.toLowerCase() == provider.toLowerCase()}');
      });
      isLoading.value = false;
      return;
    }
    print('Found provider data: ${providerData['name']}');
    final bool pkceRequired = providerData['pkce_required'] ?? false;

    // Validate state only if PKCE is required
    if (pkceRequired && (state != pkceState.value)) {
      error.value = 'OAuth state mismatch. Potential security issue.';
      print('Error: OAuth state mismatch. Expected ${pkceState.value}, received $state');
      isLoading.value = false;
      _currentOAuthProvider.value = '';
      return;
    }
    // The original `if (state != pkceState.value)` block was removed as its logic
    // is now handled correctly by fetching pkceRequired first and then conditionally
    // checking the state based on its value.


    print('Exchanging code with backend for provider: $provider');
    try {
      final dio = Dio(BaseOptions(baseUrl: _serverConfigController.baseUri.value));
      final response = await dio.post('/v1/oauth2/$provider', data: {
        'code': code,
        'state': pkceRequired ? state : null, // Send state only if PKCE is required
      });

      if (response.statusCode == 200 && response.data != null) {
        final String? backendToken = response.data['token'];
        if (backendToken != null && backendToken.isNotEmpty) {
          print('Successfully exchanged code for AGiXT token via backend.');
          await loginWithToken(backendToken);
          Get.offNamed('/home');
        } else {
          error.value = response.data['detail'] ?? 'Backend did not return a valid token.';
          print('Backend response missing token: ${response.data}');
        }
      } else {
        error.value = 'Backend code exchange failed: ${response.statusCode} ${response.data?['detail'] ?? response.statusMessage}';
        print('Backend code exchange failed: ${response.statusCode} ${response.data}');
      }
    } catch (e) {
      print('Error exchanging code with backend: $e');
      error.value = 'Failed to complete authentication with backend.';
      if (e is DioException) {
        print('DioException: ${e.message}, Response: ${e.response?.data}');
      }
    } finally {
      isLoading.value = false;
      pkceState.value = '';
      pkceCodeChallenge.value = '';
      _currentOAuthProvider.value = '';
      if (_prefs != null) {
        await _prefs!.remove('current_oauth_provider');
        await _prefs!.remove('current_oauth_provider_original');
        print('Cleared OAuth provider preferences');
      }
    }
  }

  Future<bool> loginWithToken(String tokenValue) async {
    try {
      if (sdk.value == null) return false;
      isLoading.value = true;
      error.value = '';
      final fullToken = "Bearer $tokenValue";
      token.value = fullToken;
      apiKey.value = tokenValue;
      await _saveToken(tokenValue);
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

  // Added missing login method
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
        // Attempt to re-initialize SDK if null (e.g., after logout/restart)
        _serverConfigController.initializeSDK(
          _serverConfigController.baseUri.value,
          _serverConfigController.apiKey.value.isNotEmpty ? _serverConfigController.apiKey.value : null
        );
        if (sdk.value == null) {
           error.value = 'SDK not initialized. Check server settings.';
           return false;
        }
      }

      isLoading.value = true;
      error.value = '';

      final response = await sdk.value!.login(email, otp)
          .timeout(const Duration(seconds: 30));

      if (response == null) {
        error.value = 'Invalid login credentials';
        return false;
      }

      // Response should be like: "Log in at ?token=xyz"
      if (response.contains("?token=")) {
        final tokenValue = response.split("token=")[1];
        // Use the same token login flow as API key login
        return await loginWithToken(tokenValue);
      }

      error.value = 'Invalid login response format from server.';
      return false; // Indicate failure if token not found in response
    } catch (e) {
      print('Login error: $e');
      error.value = 'Login failed: ${e.toString()}';
       if (e is DioException) {
         print('DioException details: ${e.message}, Response: ${e.response?.data}');
         error.value = 'Login failed: Network or server error. Check connection and server status.';
       }
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  // Added missing registerUser method
  Future<bool> registerUser(String email, String firstName, String lastName) async {
    try {
       if (sdk.value == null) {
        // Attempt to re-initialize SDK if null
        _serverConfigController.initializeSDK(
          _serverConfigController.baseUri.value,
          _serverConfigController.apiKey.value.isNotEmpty ? _serverConfigController.apiKey.value : null
        );
        if (sdk.value == null) {
           error.value = 'SDK not initialized. Check server settings.';
           return false;
        }
      }

      isLoading.value = true;
      error.value = '';

      final response = await sdk.value!.registerUser(email, firstName, lastName)
          .timeout(const Duration(seconds: 30));

      if (response == null) {
        error.value = 'Registration failed. Please try again.';
        return false;
      }

      // Check for success message or specific response structure
      if (response.contains("OTP sent to")) {
        otpUri.value = response; // Store the response which might contain info
        print('Registration successful, OTP sent.');
        return true;
      } else if (response.contains("User already exists")) {
        error.value = 'User already exists. Please log in.';
        return false;
      }

      error.value = 'Registration failed: Unexpected server response.';
      print('Unexpected registration response: $response');
      return false;
    } catch (e) {
      print('Registration error: $e');
      error.value = 'Registration failed: ${e.toString()}';
      if (e is DioException) {
        print('DioException details: ${e.message}, Response: ${e.response?.data}');
        error.value = 'Registration failed: Network or server error.';
      }
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  // Added clearOtpUri method
  void clearOtpUri() {
    otpUri.value = '';
  }

  Future<void> logout() async {
    token.value = '';
    apiKey.value = '';
    isLoggedIn.value = false;
    _currentOAuthProvider.value = '';
    pkceState.value = '';
    pkceCodeChallenge.value = '';
    _stateToProvider.clear(); // Clear the state map on logout
    if (_prefs != null) {
      await _prefs!.remove(_tokenKey);
    }
    _serverConfigController.clearToken(); // Use the new method here
    Get.offAllNamed('/login'); // Navigate to login and remove all previous routes
  }

  // --- Local HTTP Server Methods ---
  // Changed return type to Future<Uri> and handle timeout by throwing exception
  Future<Uri> startLocalServerAndAwaitCallback() async {
    await stopLocalServer(); // Ensure any previous server is stopped
    
    if (_callbackCompleter != null && !_callbackCompleter!.isCompleted) {
      _callbackCompleter!.completeError(Exception('Previous callback completer was not completed'));
    }
    _callbackCompleter = Completer<Uri>();

    final router = Router();
    router.get('/oauth-callback', (Request request) {
      print('OAuth callback received by local server: ${request.requestedUri}');
      if (!_callbackCompleter!.isCompleted) {
        _callbackCompleter!.complete(request.requestedUri);
      }
      // Respond to the browser to close the tab/window
      return shelf.Response.ok(
        '''
        <html>
          <head><title>Authentication Successful</title></head>
          <body>
            <h1>Authentication Successful</h1>
            <p>You can close this window now.</p>
            <script>window.close();</script> 
          </body>
        </html>
        ''',
        headers: {'content-type': 'text/html'},
      );
    });

    try {
      _localServer = await io.serve(
        router,
        InternetAddress.loopbackIPv4, // Listen only on localhost
        _localServerPort,
      );
      print('Local server listening on http://localhost:$_localServerPort');

      // Timeout for the callback - throws TimeoutException on timeout
      return _callbackCompleter!.future.timeout(const Duration(minutes: 2), onTimeout: () {
        print('OAuth callback timed out.');
        error.value = 'Authentication timed out. Please try again.';
        isLoading.value = false;
        _currentOAuthProvider.value = '';
        stopLocalServer(); // Stop server on timeout
        // Throw an exception instead of returning null
        throw TimeoutException('OAuth callback timed out after 2 minutes.');
      });
    } catch (e) {
      print('Error starting local server: $e');
      error.value = 'Could not start local server for authentication.';
      isLoading.value = false;
      _currentOAuthProvider.value = '';
      if (_callbackCompleter != null && !_callbackCompleter!.isCompleted) {
         // Complete with error if not already completed
        _callbackCompleter!.completeError(e);
      }
      // Re-throw the exception to propagate the error
      throw Exception('Failed to start local server: $e');
    }
  }

  Future<void> stopLocalServer() async {
    if (_localServer != null) {
      print('Stopping local server...');
      await _localServer!.close(force: true);
      _localServer = null;
      print('Local server stopped.');
    }
    // If the completer is still waiting, complete it with an error
    if (_callbackCompleter != null && !_callbackCompleter!.isCompleted) {
      _callbackCompleter!.completeError(Exception('Local server stopped before callback received.'));
    }
    _callbackCompleter = null; // Reset completer
  }
  // --- End Local HTTP Server Methods ---
}
