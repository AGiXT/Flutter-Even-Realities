import 'package:dio/dio.dart';
import 'dart:io'; // For HttpServer
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart'; // Keep this as is
import 'package:shelf/shelf.dart' as shelf; // Add prefix for shelf Response
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:agixtsdk/agixtsdk.dart';
import 'dart:math'; // For random number generation
import 'dart:convert'; // For base64UrlEncode and utf8
import 'package:crypto/crypto.dart'; // For SHA256 hashing
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
  final RxString _pkceCodeVerifier = ''.obs; // Store the code verifier locally
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
      final String? state = callbackUri.queryParameters['state']; // Need state for PKCE
      final String? errorParam = callbackUri.queryParameters['error'];

      if (errorParam != null) {
        error.value = 'OAuth Error: $errorParam';
        print('OAuth provider returned an error: $errorParam');
        isLoading.value = false;
        _currentOAuthProvider.value = ''; // Clear provider state
        return;
      }

      if (code != null && state != null) {
        print('Received authorization code and state via direct handler: $code');
        // Call the backend exchange method if provider context is available
        // This assumes the flow was initiated and _currentOAuthProvider was set.
        if (_currentOAuthProvider.value.isNotEmpty) {
           _exchangeCodeWithBackend(
             provider: _currentOAuthProvider.value,
             code: code,
             state: state,
           );
        } else {
           // This case might happen if the callback is triggered without prior context,
           // e.g., manually opening the callback URL.
           print('Error: OAuth callback received but no provider context was stored.');
           error.value = 'Authentication session error. Please try initiating the flow again.';
           isLoading.value = false;
        }
      } else {
        error.value = 'Callback received, but no code or state found.';
        print('Callback URI did not contain code or state: $callbackUri');
        isLoading.value = false;
        _currentOAuthProvider.value = ''; // Clear provider state
      }
    } catch (e) {
      print('Error processing OAuth callback: $e');
      error.value = 'Error processing authentication callback: ${e.toString()}';
      isLoading.value = false; // Ensure loading stops on error
      _currentOAuthProvider.value = ''; // Clear provider state
    }
    // isLoading state is managed within _exchangeCodeWithBackend or the error paths above.
  }
  // --- End OAuth Callback Handling ---

  // --- PKCE Helper Functions ---
  String _generateRandomString(int length) {
    final random = Random.secure();
    final values = List<int>.generate(length, (i) => random.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', ''); // Use base64Url encoding without padding
  }

  void _generatePkceParameters() {
    _pkceCodeVerifier.value = _generateRandomString(32); // Generate a 32-byte random verifier
    pkceCodeChallenge.value = _generateCodeChallenge(_pkceCodeVerifier.value);
    pkceState.value = _generateRandomString(16); // Generate a 16-byte random state
    print('Generated PKCE Verifier: ${_pkceCodeVerifier.value}');
    print('Generated PKCE Challenge: ${pkceCodeChallenge.value}');
    print('Generated State: ${pkceState.value}');
  }

  String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    // Base64Url encode the SHA256 hash, removing padding
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  // Note: _generateState is effectively the same as _generateRandomString(16)
  // --- End PKCE Helper Functions ---


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

    // Generate PKCE parameters locally
    _generatePkceParameters();

    _currentOAuthProvider.value = providerName.toLowerCase();
    isLoading.value = true;
    error.value = '';

    try {
      final String authUrl = provider['auth_url'];
      final String clientId = provider['client_id'];
      final String scopes = provider['scopes'];
      final String redirectUri = 'evenrealities://oauth-callback';

      final authorizationUri = Uri.parse(authUrl).replace(queryParameters: {
        'client_id': clientId,
        'response_type': 'code',
        'scope': scopes,
        'redirect_uri': redirectUri,
        'state': pkceState.value,
        'code_challenge': pkceCodeChallenge.value,
        'code_challenge_method': 'S256',
      });

      print('Constructed Auth URL: $authorizationUri');

      if (await canLaunchUrl(authorizationUri)) {
        print('Launching OAuth URL...');
        await launchUrl(authorizationUri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not launch OAuth URL: $authorizationUri');
      }
    } catch (e) {
      print('Error initiating OAuth flow for $providerName: $e');
      error.value = 'Failed to start authentication with $providerName.';
      if (e is DioException) {
        print('DioException: ${e.message}, Response: ${e.response?.data}');
      }
      _currentOAuthProvider.value = '';
    }
    // Note: isLoading remains true until callback is handled
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

    if (state != pkceState.value) {
      error.value = 'OAuth state mismatch. Potential security issue.';
      print('Error: OAuth state mismatch. Expected ${pkceState.value}, received $state');
      isLoading.value = false;
      _currentOAuthProvider.value = '';
      return;
    }

    print('Exchanging code with backend for provider: $provider');
    try {
      final dio = Dio(BaseOptions(baseUrl: _serverConfigController.baseUri.value));
      // Include the code_verifier in the token exchange request
      final response = await dio.post('/v1/oauth2/$provider', data: { // Assuming backend expects 'code_verifier'
        'code': code,
        'state': state,
        'code_verifier': _pkceCodeVerifier.value,
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
      _pkceCodeVerifier.value = ''; // Clear the verifier after use
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
