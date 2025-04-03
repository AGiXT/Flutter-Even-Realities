import 'package:dio/dio.dart'; // For making HTTP requests
import 'dart:io'; // For HttpServer
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart'; // Keep this as is
import 'package:shelf/shelf.dart' as shelf; // Add prefix for shelf Response
import 'dart:async'; // Added for StreamSubscription
import 'package:get/get.dart';
import 'package:agixtsdk/agixtsdk.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'server_config_controller.dart';
import 'package:app_links/app_links.dart'; // Replaced uni_links
import 'package:flutter/services.dart'; // Added for PlatformException
  // --- Google OAuth Credentials (Replace with your actual values!) ---
  // IMPORTANT: Store these securely, not hardcoded in production.
  // Removed Google Client ID - Backend will handle this.
  // Removed Google Client Secret - Backend will handle this.


class AuthController extends GetxController {
  final Rx<AGiXTSDK?> sdk = Rx<AGiXTSDK?>(null);
  final RxBool isLoggedIn = false.obs;
  final RxBool isLoading = false.obs;
  final RxString error = ''.obs;
  final RxString otpUri = ''.obs;
  final RxString token = ''.obs;
  final RxString apiKey = ''.obs; // Added to store API key separately if needed

  late final ServerConfigController _serverConfigController;
  SharedPreferences? _prefs;
  static const String _tokenKey = 'auth_token';
  StreamSubscription? _uriLinkSubscription; // Added for uni_links
  final _appLinks = AppLinks(); // Instance of AppLinks
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
    // Initialize empty SDK - will configure later if valid credentials exist
    sdk.value = AGiXTSDK(baseUri: '', apiKey: '', verbose: false); // Empty credentials will be populated after login
    _initializeController();
    _initAppLinks(); // Initialize app_links listener
  }

  @override
  void onClose() {
    _uriLinkSubscription?.cancel(); // Cancel listener on close
    stopLocalServer(); // Ensure local server is stopped
    super.onClose();
  }

  // --- OAuth Callback Handling ---
  Future<void> handleOAuthCallback(Uri callbackUri) async {
    print('Processing OAuth callback: $callbackUri');
    isLoading.value = true;
    error.value = '';

    try {
      // Extract the authorization code (common flow)
      final String? code = callbackUri.queryParameters['code'];
      // Or extract token directly if using Implicit Grant (less common, less secure)
      final String? receivedToken = callbackUri.queryParameters['token'];
      final String? errorParam = callbackUri.queryParameters['error'];

      if (errorParam != null) {
        error.value = 'OAuth Error: $errorParam';
        print('OAuth provider returned an error: $errorParam');
        isLoading.value = false;
        return;
      }

      if (code != null) {
        print('Received authorization code: $code');
        // --- Google Token Exchange ---
        final tokenEndpoint = 'https://oauth2.googleapis.com/token';
        final redirectUri = 'http://localhost:$_localServerPort/oauth-callback';

        // Prepare request data (mask secret for logging)
        final requestData = {
          'code': code,
          'client_id': _googleClientId,
          'client_secret': _googleClientSecret, // Will be sent, just masked for logging
          'redirect_uri': redirectUri,
          'grant_type': 'authorization_code',
        };
        final logData = Map.from(requestData); // Create copy for logging
        logData['client_secret'] = '********'; // Mask secret in log data
        print('Attempting token exchange with data: $logData');

        try {
          final dio = Dio();
          final response = await dio.post(
            tokenEndpoint,
            data: requestData, // Use the original data with the real secret
            options: Options(
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            ),
          );

          if (response.statusCode == 200 && response.data != null) {
            final accessToken = response.data['access_token'];
            if (accessToken != null) {
              print('Successfully exchanged code for access token.');
              // TODO: Decide if you need to use the AGiXT loginWithToken
              // or if you need a different way to associate the Google token
              // with the AGiXT user session.
              // For now, let's assume loginWithToken works with the Google access token
              // This might require backend changes in AGiXT if it doesn't support
              // arbitrary external tokens directly.
              await loginWithToken(accessToken);
              Get.offNamed('/home'); // Navigate on success
            } else {
              error.value = 'Failed to get access token from response.';
              print('Token exchange response missing access_token: ${response.data}');
            }
          } else {
            error.value = 'Token exchange failed: ${response.statusCode} ${response.statusMessage}';
            print('Token exchange failed: ${response.statusCode} ${response.data}');
          }
        } catch (e) {
          error.value = 'Error during token exchange. Check credentials and redirect URI.'; // More specific hint
          print('Error during token exchange: $e'); // Log the full exception
          if (e is DioException && e.response != null) {
            // Log more details from DioException if available
            print('DioException Response Status: ${e.response?.statusCode}');
            print('DioException Response Data: ${e.response?.data}');
            print('DioException Request Options: ${e.requestOptions.uri}'); // Log the request URI
            // Avoid logging full request options data directly if it might contain sensitive info repeatedly
          }
        }
        // --- End Google Token Exchange ---

      } else if (receivedToken != null) {
        print('Received token directly: $receivedToken');
        // Handle direct token (Implicit Grant - less recommended)
        await loginWithToken(receivedToken);
        Get.offNamed('/home'); // Navigate on success
      } else {
        error.value = 'Callback received, but no code or token found.';
        print('Callback URI did not contain code or token: $callbackUri');
      }
    } catch (e) {
      print('Error processing OAuth callback: $e');
      error.value = 'Error processing authentication callback: ${e.toString()}';
    } finally {
      isLoading.value = false;
      // Server should be stopped automatically by the handler or timeout
    }
  }
  // --- End OAuth Callback Handling ---

  Future<void> _initializeController() async {
    _prefs = await SharedPreferences.getInstance();
    await _restoreSavedToken();
  }


  Future<void> _restoreSavedToken() async {
    if (_prefs == null) return;
    
    final savedToken = _prefs!.getString(_tokenKey);
    if (savedToken != null) {
      final fullToken = "Bearer $savedToken";
      token.value = fullToken; // Keep original token format if needed elsewhere
      apiKey.value = savedToken; // Store just the key part
      _serverConfigController.updateWithToken(savedToken); // Update server config with key
      isLoggedIn.value = true;
    }
  }

  Future<void> _saveToken(String token) async {
    if (_prefs == null) return;
    await _prefs!.setString(_tokenKey, token);
  }

  // --- UniLinks Initialization and Handling ---
  // Renamed from _initUniLinks
  Future<void> _initAppLinks() async {
    try {
      // Get the initial link the app was opened with
      final initialUri = await _appLinks.getInitialAppLink();
      _handleIncomingLink(initialUri);

      // Listen for subsequent links
      // Note: app_links stream provides non-nullable Uri
      _uriLinkSubscription = _appLinks.uriLinkStream.listen((Uri uri) {
        _handleIncomingLink(uri);
      }, onError: (err) {
        print('app_links error: $err');
        // Handle error appropriately
      });
    } on PlatformException {
      print('app_links failed to get initial uri (PlatformException).');
      // Handle error appropriately
    } catch (e) {
      print('app_links failed to get initial uri: $e');
      // Handle other potential errors
    }
  }

  void _handleIncomingLink(Uri? uri) {
    if (uri != null) {
      print('Received incoming link: $uri');
      // Check if it's our expected OAuth callback
      // Example: evenrealities://oauth-callback?token=YOUR_API_TOKEN
      if (uri.scheme == 'evenrealities' && uri.host == 'oauth-callback') {
        final receivedToken = uri.queryParameters['token'];
        if (receivedToken != null && receivedToken.isNotEmpty) {
          print('Extracted token from OAuth callback: $receivedToken');
          loginWithToken(receivedToken); // Use existing token login flow
          Get.offNamed('/home'); // Navigate to home after successful login
        }
      }
    }
  }
  // --- End UniLinks ---

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
      token.value = fullToken; // Keep original token format if needed elsewhere
      apiKey.value = tokenValue; // Store just the key part
      await _saveToken(tokenValue); // Save just the key part
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
    apiKey.value = '';
    if (_prefs != null) {
      await _prefs!.remove(_tokenKey);
    }
    // Re-initialize SDK without the token
    _serverConfigController.initializeSDK(_serverConfigController.baseUri.value, null);
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