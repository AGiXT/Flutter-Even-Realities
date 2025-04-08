import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:http/http.dart' as http;

class OAuthResult {
  final String code;
  final String providerName;
  final String state;

  OAuthResult({
    required this.code,
    required this.providerName,
    required this.state,
  });
}

class OAuthService {
  HttpServer? _server;
  final int _port = 8080; // Or choose a different available port
  final String _redirectPath = '/oauth/callback';
  Completer<OAuthResult>? _completer;
  String _baseUri; // Add baseUri field

  // Constructor to accept baseUri
  OAuthService({required String baseUri}) : _baseUri = baseUri;

  // Method to update baseUri if server config changes
  void updateBaseUri(String newUri) {
    _baseUri = newUri;
  }

  // Generate a random string for code_verifier and state
  String _generateRandomString(int length) {
    const chars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
    final rnd = Random.secure();
    return List.generate(length, (index) => chars[rnd.nextInt(chars.length)]).join();
  }

  // Generate PKCE code challenge from verifier
  String _generateCodeChallenge(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    // Base64Url encoding without padding
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  // Pass the generated state and potential code verifier to the server handler
  Future<void> _startServer(String providerName, String expectedState, String? codeVerifierForPkce) async {
    if (_server != null) {
      await _stopServer(); // Ensure previous server is stopped
    }

    final router = Router();

    router.get(_redirectPath, (Request request) async {
      final code = request.url.queryParameters['code'];
      final stateReceived = request.url.queryParameters['state'];

      // With JWT state from backend, we don't need to validate it here - backend will do that
      if (!stateReceived!.startsWith('eyJ')) {
        _completer?.completeError(Exception('OAuth failed: Invalid state format received.'));
        await _stopServer();
        return Response.forbidden(
          '<html><body><h1>Authentication Failed</h1><p>Invalid state format.</p></body></html>',
          headers: {'content-type': 'text/html'},
        );
      }


      if (code != null) {
        // Successfully received code
        if (stateReceived == null) {
          throw Exception('No state parameter received from OAuth provider');
        }
        
        // Validate authorization code format
        if (!code.startsWith('4/0') || code.length < 50) {
          throw Exception('Invalid authorization code format received from Google');
        }
        
        print("[OAuthService] Received valid authorization code"); // Log success
        print("[OAuthService] Code length: ${code.length}"); // Log code length
        print("[OAuthService] State length: ${stateReceived.length}"); // Log state length
        
        _completer?.complete(OAuthResult(
          code: code,
          providerName: providerName,
          state: stateReceived,
        ));
        await _stopServer(); // Stop server after handling redirect
        
        // Return a simple success page or message
        return Response.ok(
          '<html><body><h1>Authentication Successful!</h1><p>You can close this window.</p></body></html>',
          headers: {'content-type': 'text/html'},
        );
      } else {
        // Handle error case
        final error = request.url.queryParameters['error'];
        final errorDescription = request.url.queryParameters['error_description'];
        _completer?.completeError(
            Exception('OAuth failed: ${error ?? 'Unknown error'} - ${errorDescription ?? 'No description'}'));
        await _stopServer();
        return Response.internalServerError(
          body: '<html><body><h1>Authentication Failed</h1><p>${errorDescription ?? error ?? 'Unknown error'}</p></body></html>',
          headers: {'content-type': 'text/html'},
        );
      }
    });

    try {
      // Use IPv4 loopback address explicitly for better compatibility
      _server = await shelf_io.serve(router, InternetAddress.loopbackIPv4, _port);
      print('OAuth redirect server listening on http://${_server!.address.host}:${_server!.port}');
    } catch (e) {
      print("Error starting shelf server: $e");
      _completer?.completeError(Exception("Failed to start local server for OAuth redirect. Port $_port might be in use."));
      throw Exception("Failed to start local server for OAuth redirect.");
    }
  }

  Future<void> _stopServer() async {
    await _server?.close(force: true);
    _server = null;
    print('OAuth redirect server stopped.');
  }

  Future<OAuthResult> authenticate(
      {required String authorizationUrl,
      required String clientId,
      required String scopes,
      required String providerName,
      bool pkceRequired = false,
      Map<String, String> additionalParams = const {}}) async {

    _completer = Completer<OAuthResult>();

    // Use localhost for mobile/desktop, detect origin for web
    final String redirectHost = kIsWeb ? Uri.base.host : InternetAddress.loopbackIPv4.address;
    final int redirectPort = kIsWeb ? Uri.base.port : _port;
    final String redirectScheme = kIsWeb ? Uri.base.scheme : 'http';

    // Construct redirect URI based on platform
    final String redirectUri = kIsWeb
        ? '$redirectScheme://$redirectHost${redirectPort == 80 || redirectPort == 443 ? '' : ':$redirectPort'}$_redirectPath'
        // For mobile/desktop, use the explicit loopback address and port
        : 'http://${InternetAddress.loopbackIPv4.address}:$_port$_redirectPath';

// Initialize variables
String state = _generateRandomString(32); // Default state
String? codeChallenge;
bool usePkce = pkceRequired || providerName.toLowerCase() == 'google';

print("[OAuthService] Authenticate called for $providerName. PKCE Required: $usePkce");

// Get PKCE challenge from backend if needed
if (usePkce) {
  try {
    final redirectEndpoint = 'http://${InternetAddress.loopbackIPv4.address}:$_port$_redirectPath';
    final pkceUrl = Uri.parse('$_baseUri/v1/oauth2/pkce-simple').replace(
      queryParameters: {
        'redirect_uri': redirectEndpoint
      }
    );
    print("[OAuthService] Getting PKCE with redirect: $redirectEndpoint");
    final pkceResponse = await http.get(pkceUrl);
    
    if (pkceResponse.statusCode == 200) {
      final pkceData = jsonDecode(pkceResponse.body);
      print("[OAuthService] PKCE data from backend: $pkceData");
      codeChallenge = pkceData['code_challenge'];
      state = pkceData['state']; // Contains encrypted verifier from backend
      print("[OAuthService] Got PKCE challenge from backend");
    } else {
      throw Exception('Failed to get PKCE challenge from backend');
    }
  } catch (e) {
    print("[OAuthService] Error getting PKCE challenge: $e");
    throw Exception('Failed to setup PKCE: $e');
  }
}

    if (!kIsWeb) {
      // Start server only for non-web platforms
       try {
         // Pass the JWT state through without validation
         await _startServer(providerName, state, null);
       } catch (e) {
         return Future.error(e); // Propagate server start error
       }
    }



// Build and launch the authorization URL
final String authUrl = Uri.parse(authorizationUrl).replace(
  queryParameters: {
    'client_id': clientId,
    'response_type': 'code',
    'scope': scopes,
    'redirect_uri': redirectUri,
    'state': state,
    if (usePkce && codeChallenge != null) 'code_challenge': codeChallenge,
    if (usePkce) 'code_challenge_method': 'S256',
    ...additionalParams,
  },
).toString();

print("[OAuthService] Using state from backend");
print("[OAuthService] State JWT length: ${state.length}");
print("Launching OAuth URL: $authUrl");

if (await canLaunchUrl(Uri.parse(authUrl))) {
  // For web, launch in the same window/tab to handle redirect easily
  // For mobile/desktop, launch externally
  final launchMode = kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication;
  await launchUrl(Uri.parse(authUrl), mode: launchMode);
} else {
  _completer?.completeError(Exception('Could not launch $authUrl'));
      if (!kIsWeb) await _stopServer();
    }

    // Add a timeout for the completer
    return _completer!.future.timeout(Duration(minutes: 5), onTimeout: () {
      if (!kIsWeb) _stopServer();
      throw TimeoutException('OAuth flow timed out after 5 minutes.');
    }).catchError((e) {
       if (!kIsWeb && _server != null) _stopServer(); // Ensure server stops on error
       throw e; // Re-throw the error
    });
  }

  // Call this method when the app is closing or auth flow is cancelled
  Future<void> dispose() async {
    await _stopServer();
  }
}