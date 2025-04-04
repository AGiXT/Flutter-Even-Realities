import 'package:dio/dio.dart';
import 'dart:io'; // For HttpServer
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:agixtsdk/agixtsdk.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'server_config_controller.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'dart:math'; // For min() function in code truncation

class AuthController extends GetxController {
  final Rx<AGiXTSDK?> sdk = Rx<AGiXTSDK?>(null);
  final RxBool isLoggedIn = false.obs;
  final RxBool isLoading = false.obs;
  final RxString error = ''.obs;
  final RxString token = ''.obs;
  final RxString apiKey = ''.obs;
  final RxString otpUri = ''.obs;
  final RxList<Map<String, dynamic>> oauthProviders = RxList<Map<String, dynamic>>([]);
  final RxString pkceState = ''.obs;
  final RxString pkceCodeChallenge = ''.obs;
  final RxString _currentOAuthProvider = ''.obs;
  late final ServerConfigController _serverConfigController;
  SharedPreferences? _prefs;
  static const String _tokenKey = 'auth_token';
  final Map<String, String> _stateToProvider = {};
  static const String _oauthStateKey = 'oauth_state_map';
  static const String _currentOAuthProviderKey = 'current_oauth_provider';

  final _appLinks = AppLinks();
  StreamSubscription? _uriLinkSubscription;
  HttpServer? _localServer;
  final int _localServerPort = 8989;
  Completer<Uri>? _callbackCompleter;

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
    stopLocalServer();
    super.onClose();
  }

  Future<void> _initializeController() async {
    _prefs = await SharedPreferences.getInstance();
    await _restoreSavedToken();
    await _loadStateMap(); // Load state map during initialization
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

  String getPkceChallenge() => pkceCodeChallenge.value;
  String getPkceState() => pkceState.value;

  Future<void> fetchPkceParametersForProvider() async {
    await _fetchPkceParameters();
  }

  // Helper methods for provider detection
  String? _determineProvider(Uri callbackUri) {
    print('\nDetermining provider for callback URL:');
    print('URL: ${callbackUri.toString()}');
    
    final String? state = callbackUri.queryParameters['state'];
    final String scope = callbackUri.queryParameters['scope']?.toLowerCase() ?? '';
    
    // Try all available methods to determine the provider
    String? provider;
    
    // Check current provider in memory first
    if (_currentOAuthProvider.value.isNotEmpty) {
      provider = _currentOAuthProvider.value;
    }
    
    // Check state map if we have a state parameter
    if (provider == null && state != null && _stateToProvider.containsKey(state)) {
      provider = _stateToProvider[state];
    }
    
    // Check backup locations in state map
    if (provider == null) {
      provider = _stateToProvider['current'] ?? 
                _stateToProvider['last_provider'] ?? 
                _stateToProvider['active_provider'];
    }
    
    // Try to detect from URL patterns
    if (provider == null) {
      if (callbackUri.toString().contains('accounts.google.com') ||
          scope.contains('google') ||
          (scope.contains('openid') && scope.contains('profile') && scope.contains('email'))) {
        provider = 'google';
      }
      // Add detection for other providers here if needed
    }
    
    print('Provider determination results:');
    print('- From memory: ${_currentOAuthProvider.value}');
    print('- From state parameter: ${state != null ? _stateToProvider[state] : 'No state'}');
    print('- From URL pattern: ${_isGoogleOAuth(callbackUri) ? 'google' : 'not google'}');
    print('- Final determination: $provider');
    
    return provider?.toLowerCase();
  }
  
  // Improved helper method to detect Google OAuth
  bool _isGoogleOAuth(Uri callbackUri) {
    if (_currentOAuthProvider.value == 'google' || 
        _stateToProvider['current'] == 'google' ||
        _stateToProvider['provider_type'] == 'google') {
      return true;
    }
    
    final scope = callbackUri.queryParameters['scope']?.toLowerCase() ?? '';
    final uri = callbackUri.toString().toLowerCase();
    
    // Check multiple patterns that indicate Google OAuth
    return uri.contains('accounts.google.com') ||
           uri.contains('google') ||
           scope.contains('google') ||
           (scope.contains('openid') && scope.contains('profile') && scope.contains('email')) ||
           _currentOAuthProvider.value == 'google' ||
           _stateToProvider['current'] == 'google';
  }

  // --- Enhanced OAuth State Persistence ---
  Future<void> _saveStateMap() async {
    if (_prefs == null) return;
    try {
      // Make a safe copy of the map to avoid concurrent modification issues
      final Map<String, String> safeMap = Map<String, String>.from(_stateToProvider);
      final jsonString = jsonEncode(safeMap);
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
        _stateToProvider.clear();
        final Map<String, dynamic> decodedMap = jsonDecode(jsonString);
        decodedMap.forEach((key, value) {
          if (key is String && value is String) {
            _stateToProvider[key] = value;
          }
        });
        print('Loaded OAuth state map from SharedPreferences: $_stateToProvider');
      } else {
        print('No OAuth state map found in SharedPreferences.');
        _stateToProvider.clear();
      }
      
      // Also restore current provider if available
      final currentProvider = _prefs!.getString(_currentOAuthProviderKey);
      if (currentProvider != null && currentProvider.isNotEmpty) {
        _currentOAuthProvider.value = currentProvider;
        print('Restored current OAuth provider: $_currentOAuthProvider');
      }
    } catch (e) {
      print('Error loading OAuth state map: $e');
      await _prefs!.remove(_oauthStateKey);
      _stateToProvider.clear();
    }
  }
  
  Future<void> storeOAuthProvider(String providerName) async {
    final normalized = providerName.toLowerCase();
    print('\nStoring OAuth provider: $normalized');
    
    // Only perform cleanup if we're actually changing providers
    if (_currentOAuthProvider.value != normalized) {
      print('Switching to new provider:');
      print('- Previous: ${_currentOAuthProvider.value}');
      print('- New: $normalized');
      if (_currentOAuthProvider.value.isNotEmpty) {
        _stateToProvider.clear();
        await _clearCurrentProvider();
      }
    } else {
      print('Maintaining state for existing provider: $normalized');
    }
    
    // Update provider type for better detection
    _stateToProvider['provider_type'] = normalized;
    
    // Update in-memory value
    _currentOAuthProvider.value = normalized;
    
    // Store in SharedPreferences
    await _saveCurrentProvider(normalized);
    
    // Store in state map with multiple backups
    _stateToProvider['current'] = normalized;
    _stateToProvider['last_provider'] = normalized;
    _stateToProvider['active_provider'] = normalized;
    _stateToProvider['provider_backup'] = normalized;
    await _saveStateMap();
    
    print('Provider information stored:');
    print('- Memory: ${_currentOAuthProvider.value}');
    print('- State Map: $_stateToProvider');
    
    // Verify and ensure storage persistence
    final verifyProvider = await _prefs?.getString(_currentOAuthProviderKey);
    if (verifyProvider != normalized) {
      print('Warning: Provider storage verification failed, retrying...');
      await _saveCurrentProvider(normalized);
      // Wait for storage to sync
      await Future.delayed(const Duration(milliseconds: 100));
      final recheck = await _prefs?.getString(_currentOAuthProviderKey);
      if (recheck != normalized) {
        print('Error: Failed to persist provider information');
        error.value = 'Failed to initialize OAuth provider';
        return;
      }
    }
    
    print('Provider stored in all locations: $normalized');
    
    print('Stored provider in memory and persistent storage: $normalized');
    
    print('Stored and cleared previous state for OAuth provider: $normalized');
    
    // Pre-fetch PKCE parameters if needed
    final provider = oauthProviders.firstWhereOrNull((p) => 
        p['name']?.toLowerCase() == normalized);
    if (provider != null && (provider['pkce_required'] ?? false)) {
      await fetchPkceParametersForProvider();
    }
  }
  
  Future<void> addStateToProvider(String state, String providerName) async {
    final normalized = providerName.toLowerCase();
    
    // Store state mapping
    _stateToProvider[state] = normalized;
    _stateToProvider['last_state'] = state;
    _stateToProvider['current_state'] = state;
    _stateToProvider['provider_type'] = normalized; // Ensure provider type is set
    await _saveStateMap();
    
    // Ensure provider information is maintained
    if (_currentOAuthProvider.value != normalized) {
      await storeOAuthProvider(normalized);
    }
    
    print('Added state-to-provider mapping: $state -> $normalized');
    print('Current state map: $_stateToProvider');
  }

  Future<void> _clearStateEntry(String state) async {
    _stateToProvider.remove(state);
    await _saveStateMap();
  }
  
  Future<void> _saveCurrentProvider(String provider) async {
    if (_prefs == null) return;
    try {
      await _prefs!.setString(_currentOAuthProviderKey, provider);
      print('Saved current OAuth provider: $provider');
    } catch (e) {
      print('Error saving current OAuth provider: $e');
    }
  }
  
  Future<void> _cleanupOAuthState(String? state) async {
    if (state != null) {
      await _clearStateEntry(state);
    }
    // Only clear current provider if it's not Google OAuth
    if (_currentOAuthProvider.value != 'google') {
      await _clearCurrentProvider();
    }
  }
  
  Future<void> _processOAuthCallback(Uri callbackUri, {required bool isGoogleProvider}) async {
    isLoading.value = true;
    error.value = '';
    
    try {
      final String? code = callbackUri.queryParameters['code'];
      final String? state = callbackUri.queryParameters['state'];
      final String? errorParam = callbackUri.queryParameters['error'];
      final String? scope = callbackUri.queryParameters['scope'];
      
      print('Processing callback with full details:');
      print('- Code: $code');
      print('- State: $state');
      print('- Error: $errorParam');
      print('- Scope: $scope');
      print('- Is Google: $isGoogleProvider');
      print('- Current Provider: ${_currentOAuthProvider.value}');
      print('- State Map: $_stateToProvider');
      print('- SharedPrefs Provider: ${_prefs?.getString(_currentOAuthProviderKey)}');
      
      if (errorParam != null) {
        error.value = 'OAuth Error: $errorParam';
        print('OAuth provider returned an error: $errorParam');
        isLoading.value = false;
        await _cleanupOAuthState(state);
        return;
      }
      
      if (code == null) {
        error.value = 'Authentication Error: Code parameter missing in callback.';
        print('Callback URI missing code: $callbackUri');
        isLoading.value = false;
        await _cleanupOAuthState(state);
        return;
      }
      
      String? provider;
      if (isGoogleProvider) {
        provider = 'google';
      } else if (_currentOAuthProvider.value.isNotEmpty) {
        provider = _currentOAuthProvider.value;
      } else if (_stateToProvider['current'] != null) {
        provider = _stateToProvider['current'];
      } else if (_stateToProvider['last_provider'] != null) {
        provider = _stateToProvider['last_provider'];
      }
      
      if (provider == null || provider.isEmpty) {
        error.value = 'Authentication Error: Unable to determine OAuth provider.';
        isLoading.value = false;
        return;
      }
      
      print('Processing OAuth callback for provider: $provider');
      
      await _exchangeCodeWithBackend(
        provider: provider,
        code: code,
        state: state ?? '',
      );
      
    } catch (e) {
      print('Error in OAuth callback: $e');
      error.value = 'Error processing authentication callback: ${e.toString()}';
      isLoading.value = false;
    } finally {
      if (!isGoogleProvider) {
        await _cleanupOAuthState(null);
      }
    }
  }

  Future<void> _clearCurrentProvider() async {
    if (_prefs == null) return;
    try {
      await _prefs!.remove(_currentOAuthProviderKey);
      _currentOAuthProvider.value = '';
      print('Cleared current OAuth provider');
    } catch (e) {
      print('Error clearing current OAuth provider: $e');
    }
  }

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

  void _handleIncomingLink(Uri? uri) {
    if (uri != null && uri.scheme == 'evenrealities' && uri.host == 'oauth-callback') {
       print('Incoming deep link received: $uri');
       handleOAuthCallback(uri);
    }
  }

  // --- Improved OAuth Callback Handling ---
  Future<void> handleOAuthCallback(Uri callbackUri) async {
    print('\n=== Processing OAuth Callback ===');
    print('URL: ${callbackUri.toString()}');
    print('Current Provider: ${_currentOAuthProvider.value}');
    print('Provider Type: ${_stateToProvider['provider_type']}');
    print('State Map: $_stateToProvider');
    
    // Ensure we load the latest state
    await _loadStateMap();
    print('Current OAuth state before processing:');
    print('- Provider in memory: ${_currentOAuthProvider.value}');
    print('- Provider in state map: ${_stateToProvider['current']}');
    print('- Provider type: ${_stateToProvider['provider_type']}');
    
    // Load stored provider state
    String? provider = _currentOAuthProvider.value;
    if (provider.isEmpty) {
      // First check state parameter mapping
      final String? state = callbackUri.queryParameters['state'];
      if (state != null && _stateToProvider.containsKey(state)) {
        provider = _stateToProvider[state];
      } else {
        // Then check stored provider information
        provider = _stateToProvider['provider_type'] ?? 
                  _stateToProvider['current'] ?? 
                  _stateToProvider['last_provider'];
      }
    }
    
    // Detect Google OAuth if provider still unknown
    if ((provider?.isEmpty ?? true) && _isGoogleOAuth(callbackUri)) {
        print('Detected Google OAuth from callback URL');
        _currentOAuthProvider.value = 'google';
        await _saveCurrentProvider('google');
        _stateToProvider['current'] = 'google';
        _stateToProvider['provider_type'] = 'google';
        await _saveStateMap();
    }
    
    final String? state = callbackUri.queryParameters['state'];
    await _loadStateMap();
    
    print('Initial OAuth state:');
    print('Current provider (memory): ${_currentOAuthProvider.value}');
    print('State parameter from URL: $state');
    print('State map contents: $_stateToProvider');
    
    // Try all methods to identify the provider
    String? providerName = _determineProvider(callbackUri);
    
    if (providerName == 'google' || _isGoogleOAuth(callbackUri)) {
      providerName = 'google';
      _currentOAuthProvider.value = 'google';
      await _saveCurrentProvider('google');
    }
    
    if (providerName == null || providerName.isEmpty) {
      error.value = 'Authentication Error: Unable to determine OAuth provider';
      print('Failed to determine provider. URL: $callbackUri');
      isLoading.value = false;
      return;
    }

    print('Determined provider: $providerName');
    
    // Update state map with current provider
    _stateToProvider['current'] = providerName;
    if (state != null) {
      _stateToProvider[state] = providerName;
    }
    await _saveStateMap();
    
    // Process the callback
    await _processOAuthCallback(
      callbackUri,
      isGoogleProvider: providerName.toLowerCase() == 'google'
    );
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
        pkceCodeChallenge.value = '';
        pkceState.value = '';
      }
    } catch (e) {
      print('Error fetching PKCE parameters: $e');
      error.value = 'Failed to fetch PKCE parameters from server.';
      pkceCodeChallenge.value = '';
      pkceState.value = '';
      if (e is DioException) {
         print('DioException details: ${e.message}, Response: ${e.response?.data}');
      }
    }
  }

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
        print('Status Code: ${response.statusCode}');
        print('Response JSON:');
        print('${response.data}');
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

  // --- Improved OAuth Flow Initiation ---
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

    final provider = oauthProviders.firstWhereOrNull(
        (p) => p['name']?.toLowerCase() == providerName.toLowerCase());
    if (provider == null) {
      error.value = 'OAuth provider "$providerName" not found or not configured on the server.';
      print('Provider $providerName not found in fetched list.');
      return;
    }
    
    final bool pkceRequired = provider['pkce_required'] ?? false;
    print('PKCE required for $providerName: $pkceRequired');
    final String normalizedProviderName = providerName.toLowerCase();
    
    // Store provider name in memory and SharedPreferences
    _currentOAuthProvider.value = normalizedProviderName;
    print('Setting current OAuth provider to: $normalizedProviderName');
    await _saveCurrentProvider(normalizedProviderName);

    String? stateValue;
    isLoading.value = true;
    error.value = '';

    try {
      // Determine the state value to use
      if (pkceRequired) {
        await _fetchPkceParameters();
        if (pkceState.value.isEmpty || pkceCodeChallenge.value.isEmpty) {
          isLoading.value = false;
          await _clearCurrentProvider();
          return;
        }
        stateValue = pkceState.value;
        print('--- PKCE State Value to be used: "$stateValue" ---');
      } else {
        // For non-PKCE flows, generate a UUID
        stateValue = const Uuid().v4();
        print('--- Generated UUID State Value to be used: "$stateValue" ---');
        pkceState.value = '';
        pkceCodeChallenge.value = '';
      }

      // Store mapping of state to provider
      _stateToProvider[stateValue] = normalizedProviderName;
      print('Stored state mapping: $stateValue -> $normalizedProviderName');
      print('Current state map: $_stateToProvider');
      
      // Save state map immediately
      await _saveStateMap();

      final String authUrl = provider['authorize'];
      final String clientId = provider['client_id'];
      final String scopes = provider['scopes'];
      final String redirectUri = 'http://localhost:$_localServerPort/oauth-callback';

      // Create query parameters for the authorization URL
      final Map<String, String> queryParams = <String, String>{
        'client_id': clientId,
        'response_type': 'code',
        'scope': scopes,
        'redirect_uri': redirectUri,
        'state': stateValue, // Always include state parameter
      };

      // Add PKCE parameters if required
      if (pkceRequired) {
        queryParams['code_challenge'] = pkceCodeChallenge.value;
        queryParams['code_challenge_method'] = 'S256';
      }

      final authorizationUri = Uri.parse(authUrl).replace(queryParameters: queryParams);
      
      // Log the full URL for debugging
      print('Constructed Auth URL: $authorizationUri');
      print('--- Full Authorization URI ---');
      print(authorizationUri.toString());
      print('--- State Parameter Check ---');
      print('State included in URL: ${authorizationUri.queryParameters['state']}');
      print('------------------------------');
      
      // Start local server before launching URL
      print('Starting local server for redirect URI: $redirectUri');
      final callbackUriFuture = startLocalServerAndAwaitCallback();

      if (await canLaunchUrl(authorizationUri)) {
        print('Launching OAuth URL...');
        await launchUrl(authorizationUri, mode: LaunchMode.externalApplication);
        
        // Wait for the callback from the local server
        final callbackUri = await callbackUriFuture;
        await handleOAuthCallback(callbackUri);
      } else {
        await stopLocalServer();
        throw Exception('Could not launch OAuth URL: $authorizationUri');
      }
    } catch (e) {
      print('Error initiating OAuth flow for $providerName: $e');
      error.value = 'Failed to start authentication with $providerName: ${e.toString()}';
      isLoading.value = false;
      
      if (stateValue != null && _stateToProvider.containsKey(stateValue)) {
         await _clearStateEntry(stateValue);
      }
      await _clearCurrentProvider();
      await stopLocalServer();
    }
  }

  Future<void> _exchangeCodeWithBackend({
    required String provider,
    required String code,
    required String state,
  }) async {
    print('\nStarting code exchange with backend:');
    print('Provider: $provider');
    print('Code available: ${code.isNotEmpty}');
    print('State: $state');
    print('Current provider in memory: ${_currentOAuthProvider.value}');
    print('State map: $_stateToProvider\n');
    if (sdk.value == null || _serverConfigController.baseUri.value.isEmpty) {
      error.value = 'Server configuration not set.';
      print('Cannot exchange code: Server config missing.');
      isLoading.value = false;
      return;
    }

    print('Attempting to exchange code for provider: "$provider"');
    print('Available OAuth providers: ${oauthProviders.map((p) => p['name']).join(', ')}');
    
    // Find provider data
    final providerData = oauthProviders.firstWhereOrNull(
        (p) => p['name']?.toLowerCase() == provider.toLowerCase());
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

    // For Google, we'll proceed even if state is missing
    final bool isGoogleProvider = provider.toLowerCase() == 'google';
    final bool isStateValid = isGoogleProvider || // Google OAuth sometimes drops state
                             !pkceRequired || // Non-PKCE flows don't require state validation
                             state == pkceState.value || // PKCE state matches
                             (state != null && _stateToProvider.containsKey(state)); // State in map

    if (!isStateValid) {
      print('OAuth state validation failed:');
      print('- Provider: $provider');
      print('- Is Google: $isGoogleProvider');
      print('- PKCE Required: $pkceRequired');
      print('- State Parameter: $state');
      print('- PKCE State: ${pkceState.value}');
      print('- State in Map: ${state != null && _stateToProvider.containsKey(state)}');
      
      error.value = 'Invalid OAuth state parameter';
      isLoading.value = false;
      await _cleanupOAuthState(state);
      return;
    }

    print('Exchanging code with backend for provider: $provider');
    try {
      final dio = Dio(BaseOptions(baseUrl: _serverConfigController.baseUri.value));
      final Map<String, dynamic> requestData = {'code': code};
      
      if (pkceRequired && state.isNotEmpty) {
        requestData['state'] = state;
      } else if (pkceRequired && pkceState.value.isNotEmpty) {
        // Fall back to stored PKCE state if the callback state is empty
        print('Using stored PKCE state as fallback');
        requestData['state'] = pkceState.value;
      }
      
      print('Sending code exchange request to backend for provider: $provider');
      print('Request data: $requestData');
      
      final response = await dio.post('/v1/oauth2/$provider', data: requestData);
      print('Received response from backend: ${response.data}');

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
      await _clearCurrentProvider();
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

      final response = await sdk.value!.login(email, otp)
          .timeout(const Duration(seconds: 30));

      if (response == null) {
        error.value = 'Invalid login credentials';
        return false;
      }

      // Response should be like: "Log in at ?token=xyz"
      if (response.contains("?token=")) {
        final tokenValue = response.split("token=")[1];
        return await loginWithToken(tokenValue);
      }

      error.value = 'Invalid login response format from server.';
      return false;
    } catch (e) {
      print('Login error: $e');
      error.value = 'Login failed: ${e.toString()}';
       if (e is DioException) {
         print('DioException details: ${e.message}, Response: ${e.response?.data}');
         error.value = 'Login failed: Network or server error.';
       }
      return false;
    } finally {
      isLoading.value = false;
    }
  }

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

      if (response.contains("OTP sent to")) {
        otpUri.value = response;
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

  void clearOtpUri() {
    otpUri.value = '';
  }

  Future<void> logout() async {
    token.value = '';
    apiKey.value = '';
    isLoggedIn.value = false;
    await _clearCurrentProvider();
    pkceState.value = '';
    pkceCodeChallenge.value = '';
    _stateToProvider.clear();
    await _saveStateMap(); // Ensure cleared state map is persisted
    if (_prefs != null) {
      await _prefs!.remove(_tokenKey);
      await _prefs!.remove(_oauthStateKey);
      await _prefs!.remove(_currentOAuthProviderKey);
    }
    _serverConfigController.clearToken();
    Get.offAllNamed('/login');
  }

  // --- Local HTTP Server Methods ---
  Future<Uri> startLocalServerAndAwaitCallback() async {
    await stopLocalServer(); // Ensure any previous server is stopped
    
    // Load and verify state before starting server
    await _loadStateMap();
    final currentProvider = _currentOAuthProvider.value;
    final providerType = _stateToProvider['provider_type'];
    
    print('\n=== Starting OAuth Server ===');
    print('Starting server with provider: $currentProvider');
    print('Provider type: $providerType');
    
    if (currentProvider.isEmpty && providerType != null) {
      _currentOAuthProvider.value = providerType;
      await _saveCurrentProvider(providerType);
    }
    
    if (_callbackCompleter != null && !_callbackCompleter!.isCompleted) {
      _callbackCompleter!.completeError(Exception('Previous callback completer was not completed'));
    }
    _callbackCompleter = Completer<Uri>();
    print('Current provider: ${_currentOAuthProvider.value}');
    print('State map: $_stateToProvider');
    print('Provider type: ${_stateToProvider['provider_type']}');
    print('===========================\n');

    final router = Router();
    router.get('/oauth-callback', (Request request) async {
      print('OAuth callback received by local server: ${request.requestedUri}');
      
      // Load saved state and ensure provider info is preserved
      await _loadStateMap();
      final String? state = request.requestedUri.queryParameters['state'];
      final String scope = request.requestedUri.queryParameters['scope'] ?? '';
      
      print('\nServer callback received with provider info:');
      print('Current provider type: ${_stateToProvider['provider_type']}');
      print('Current provider: ${_currentOAuthProvider.value}');
      
      // If we have a provider type stored, ensure it's set in memory
      if (_stateToProvider['provider_type'] != null) {
        _currentOAuthProvider.value = _stateToProvider['provider_type']!;
      }
      
      print('Local server callback state:');
      print('- Current provider: ${_currentOAuthProvider.value}');
      print('- State map: $_stateToProvider');
      print('- State param: $state');
      print('- Scope: $scope');
      
      // First check if we already have provider information
    if (_currentOAuthProvider.value.isNotEmpty) {
      print('Using existing provider: ${_currentOAuthProvider.value}');
    }
    // Then try to restore from state if needed
    else if (state != null && _stateToProvider.containsKey(state)) {
        final provider = _stateToProvider[state];
        _currentOAuthProvider.value = provider!;
        _stateToProvider['current'] = provider;
        print('Restored provider from state mapping: $provider');
      } else if (_currentOAuthProvider.value.isEmpty) {
        // Try to detect provider from various sources
        if (scope.toLowerCase().contains('google') || 
            request.requestedUri.toString().contains('accounts.google.com')) {
          _currentOAuthProvider.value = 'google';
          _stateToProvider['current'] = 'google';
          _stateToProvider['provider_type'] = 'google';
          print('Setting Google as provider in local server');
        } else if (state != null && _stateToProvider.containsKey(state)) {
          final provider = _stateToProvider[state];
          _currentOAuthProvider.value = provider!;
          _stateToProvider['current'] = provider;
          print('Restored provider from state map: $provider');
        }
        await _saveStateMap();
        await _saveCurrentProvider(_currentOAuthProvider.value);
        print('Updated provider state in local server: ${_currentOAuthProvider.value}');
      }
      
      if (!_callbackCompleter!.isCompleted) {
        _callbackCompleter!.complete(request.requestedUri);
        handleOAuthCallback(request.requestedUri);
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
        _clearCurrentProvider();
        stopLocalServer();
        throw TimeoutException('OAuth callback timed out after 2 minutes.');
      });
    } catch (e) {
      print('Error starting local server: $e');
      error.value = 'Could not start local server for authentication.';
      isLoading.value = false;
      _clearCurrentProvider();
      if (_callbackCompleter != null && !_callbackCompleter!.isCompleted) {
        _callbackCompleter!.completeError(e);
      }
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
}