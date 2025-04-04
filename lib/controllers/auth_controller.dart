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
  final RxString _currentOAuthProvider = ''.obs;
  late final ServerConfigController _serverConfigController;
  SharedPreferences? _prefs;
  static const String _tokenKey = 'auth_token';
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
      final code = uri.queryParameters['code'];
      final state = uri.queryParameters['state'];
      final errorParam = uri.queryParameters['error'];
      if (errorParam != null) {
        print('OAuth provider returned an error in callback: $errorParam');
        error.value = 'Authentication failed: $errorParam';
        isLoading.value = false;
        _currentOAuthProvider.value = '';
      } else if (code != null && state != null) {
        print('Extracted code and state from OAuth callback.');
        if (_currentOAuthProvider.value.isNotEmpty) {
          _exchangeCodeWithBackend(provider: _currentOAuthProvider.value, code: code, state: state);
        }
      }
    }
  }

  // --- OAuth Callback Handling ---
  // Note: This might be redundant if app_links handles everything via _handleIncomingLink,
  // but keeping it based on original structure and potential direct callback needs (e.g., from local server).
  Future<void> handleOAuthCallback(Uri callbackUri) async {
    print('Processing OAuth callback via direct handler: $callbackUri');
    isLoading.value = true;
    error.value = '';

    try {
      final String? code = callbackUri.queryParameters['code'];
      final String? state = callbackUri.queryParameters['state'];
      final String? errorParam = callbackUri.queryParameters['error'];

      if (errorParam != null) {
        error.value = 'OAuth Error: $errorParam';
        print('OAuth provider returned an error: $errorParam');
        isLoading.value = false;
        _currentOAuthProvider.value = ''; // Clear provider state
        return;
      }

      if (code == null) {
        error.value = 'Authentication Error: Code parameter missing in callback.';
        print('Callback URI missing code: $callbackUri');
        isLoading.value = false;
        _currentOAuthProvider.value = ''; // Clear provider state
        return;
      }

      if (_currentOAuthProvider.value.isEmpty) {
        error.value = 'Authentication session error. Please try initiating the flow again.';
        print('Error: OAuth callback received but no provider context was stored.');
        isLoading.value = false;
        return;
      }

      final provider = oauthProviders.firstWhereOrNull((p) => p['name']?.toLowerCase() == _currentOAuthProvider.value);
      final bool pkceRequired = provider?['pkce_required'] ?? false;

      if (pkceRequired && state == null) {
        error.value = 'Authentication Error: State parameter missing in callback.';
        print('Callback URI received code but is missing the required state parameter: $callbackUri');
        isLoading.value = false;
        _currentOAuthProvider.value = ''; // Clear provider state
        return;
      }

      await _exchangeCodeWithBackend(
        provider: _currentOAuthProvider.value,
        code: code,
        state: state ?? '', // Use empty string if state is null and not required
      );

    } catch (e) {
      print('Error processing OAuth callback: $e');
      error.value = 'Error processing authentication callback: ${e.toString()}';
      isLoading.value = false; // Ensure loading stops on error
      _currentOAuthProvider.value = ''; // Clear provider state
    }
    // isLoading state is managed within _exchangeCodeWithBackend or the error paths above.
  }
  // --- End OAuth Callback Handling ---


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

    _currentOAuthProvider.value = providerName.toLowerCase();
    final bool pkceRequired = provider['pkce_required'] ?? false;
    isLoading.value = true;
    error.value = '';

    try {
      // Fetch PKCE parameters only if required
      if (pkceRequired) {
        await _fetchPkceParameters();
        if (pkceState.value.isEmpty || pkceCodeChallenge.value.isEmpty) {
          // Error is set within _fetchPkceParameters
          isLoading.value = false;
          _currentOAuthProvider.value = '';
          return;
        }
      } else {
        // Clear PKCE values if not required
        pkceState.value = '';
        pkceCodeChallenge.value = '';
      }

      final String authUrl = provider['authorize']; // Use 'authorize' key as per JSON
      final String clientId = provider['client_id'];
      final String scopes = provider['scopes'];
      final String redirectUri = 'http://localhost:$_localServerPort/oauth-callback'; // Use local server URI

      final Map<String, String> queryParams = {
        'client_id': clientId,
        'response_type': 'code',
        'scope': scopes,
        'redirect_uri': redirectUri,
      };
      if (pkceRequired) {
        queryParams['state'] = pkceState.value;
        queryParams['code_challenge'] = pkceCodeChallenge.value;
        queryParams['code_challenge_method'] = 'S256';
      }

      final authorizationUri = Uri.parse(authUrl).replace(queryParameters: queryParams);

      print('Constructed Auth URL: $authorizationUri');
      print('--- Full Authorization URI ---');
      print(authorizationUri.toString());
      print('------------------------------');


      // Start local server BEFORE launching URL, wait for callback
      print('Starting local server for redirect URI: $redirectUri');
      final callbackUriFuture = startLocalServerAndAwaitCallback(); // Don't await yet

      if (await canLaunchUrl(authorizationUri)) {
        print('Launching OAuth URL...');
        await launchUrl(authorizationUri, mode: LaunchMode.externalApplication);

        // Now await the callback from the local server
        final callbackUri = await callbackUriFuture;
        if (callbackUri == null) {
          // Error handled within startLocalServerAndAwaitCallback or timeout
          throw Exception('Failed to receive callback from local server.');
        }
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
      error.value = 'Failed to start authentication with $providerName.';
      // Ensure loading stops and provider is cleared on any error
      isLoading.value = false;
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

    // Fetch provider data and determine if PKCE is required *before* checking state
    final providerData = oauthProviders.firstWhereOrNull((p) => p['name']?.toLowerCase() == provider.toLowerCase());
    if (providerData == null) {
      error.value = 'Provider not found.';
      print('Provider $provider not found during code exchange.');
      isLoading.value = false;
      return;
    }
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
      otpUri.value = ''; // Ensure otpUri is cleared before registration attempt

      final result = await sdk.value!.registerUser(email, firstName, lastName);

      if (result != null) {
        if (result.toString().startsWith('otpauth://')) {
          otpUri.value = result; // Store the OTP URI for display
          print('Registration successful, OTP URI received.');
          return true; // Indicate success, UI should show OTP QR code
        } else {
          // Handle cases where the backend returns an error message instead of OTP URI
          error.value = result.toString();
          print('Registration failed: Server returned message: $result');
        }
      } else {
        // Handle null response from SDK call
        error.value = 'Registration failed: No response from server.';
        print('Registration failed: Null response from SDK.');
      }
      return false; // Indicate failure
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

  // Added missing clearOtpUri method
  void clearOtpUri() {
    otpUri.value = '';
  }

  Future<void> logout() async {
    isLoggedIn.value = false;
    token.value = '';
    apiKey.value = '';
    otpUri.value = ''; // Also clear otpUri on logout
    if (_prefs != null) await _prefs!.remove(_tokenKey);
    _serverConfigController.initializeSDK(_serverConfigController.baseUri.value, null);
    await fetchOAuthProviders();
  }

  // --- Local HTTP Server Methods ---

  Future<Uri?> startLocalServerAndAwaitCallback() async {
    await stopLocalServer(); // Ensure any previous server is stopped

    _callbackCompleter = Completer<Uri>();
    final router = Router();

    router.get('/oauth-callback', (Request request) {
      final callbackUri = request.requestedUri;
      print('Received callback: $callbackUri');

      // Complete the completer only if it hasn't been completed yet
      if (_callbackCompleter != null && !_callbackCompleter!.isCompleted) {
        _callbackCompleter!.complete(callbackUri);
      } else {
         print('Warning: Callback received but completer was already completed or null.');
      }      // Schedule server stop after response is sent
      Future.delayed(Duration(seconds: 1), () => stopLocalServer());      return shelf.Response.ok( // Use prefix here
        '<html><body><h1>Authentication successful!</h1><p>You can close this window now.</p></body></html>',
        headers: {'content-type': 'text/html'},
      );
    });

    try {
      _localServer = await io.serve(
        router,
        InternetAddress.loopbackIPv4, // Listen only on localhost
        _localServerPort,
      );
      print('Local server started on port $_localServerPort');

      // Wait for the callback or a timeout (e.g., 5 minutes)
      return await _callbackCompleter!.future.timeout(Duration(minutes: 5), onTimeout: () {
        final errorMsg = 'OAuth callback timed out after 5 minutes.';
        print(errorMsg);
        stopLocalServer(); // Ensure server stops on timeout
        // Complete the future with an error instead of returning null
        throw TimeoutException(errorMsg);
      });

    } catch (e) {
      print('Error starting local server: $e');
      error.value = 'Could not start local server for authentication. Port $_localServerPort might be in use.';
      await stopLocalServer(); // Ensure cleanup
       if (_callbackCompleter != null && !_callbackCompleter!.isCompleted) {
         _callbackCompleter!.completeError(e); // Complete with error if waiting
       }
      return null;
    }
  }

  Future<void> stopLocalServer() async {
    if (_localServer != null) {
      print('Stopping local server...');
      await _localServer!.close(force: true);
      _localServer = null;
      print('Local server stopped.');
    }
     // Cancel the completer if it's still waiting and the server is stopped externally
     if (_callbackCompleter != null && !_callbackCompleter!.isCompleted) {
       print('Cancelling pending callback completer due to server stop.');
       _callbackCompleter!.completeError(Exception("Local server stopped before callback received."));
     }
    _callbackCompleter = null; // Reset completer
  }

}
