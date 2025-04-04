import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:agixtsdk/agixtsdk.dart';
import 'package:uuid/uuid.dart';
import '../controllers/auth_controller.dart';
import '../controllers/server_config_controller.dart';

class LoginPage extends StatelessWidget {
  final AuthController authController = Get.find();
  final ServerConfigController serverConfig = Get.find();
  // SDK instance - initialize in initState or similar if stateful, or here if stateless and config is ready
  late final AGiXTSDK sdk; // Will initialize later

  final TextEditingController emailController = TextEditingController();
  final TextEditingController otpController = TextEditingController();
  final TextEditingController tokenController = TextEditingController();
  final RxBool isTokenLogin = false.obs;

  // State for OAuth providers
  final RxList<Map<String, dynamic>> oauthProviders = <Map<String, dynamic>>[].obs;
  final RxBool isLoadingProviders = true.obs;
  final RxString providerError = ''.obs;

  LoginPage({super.key}) { // Added constructor for initialization
    // Initialize SDK using server config
    // Ensure serverConfig is initialized before accessing its values
    // This might be better handled in an initState if it were a StatefulWidget
    // or using GetX lifecycle methods if converting AuthController/ServerConfigController
    _initializeSdkAndFetchProviders();
  }

  void _initializeSdkAndFetchProviders() {
     // Use a listener or ensure config is ready before initializing
     // For simplicity here, assuming config is available via Get.find()
     sdk = AGiXTSDK(
        baseUri: serverConfig.baseUri.value,
        apiKey: authController.apiKey.value, // Assuming AuthController holds the key if logged in via token
        verbose: true // Enable verbose logging for debugging
     );
     _fetchOAuthProviders();
  }

  Future<void> _fetchOAuthProviders() async {
    isLoadingProviders.value = true;
    providerError.value = '';
    try {
      // Ensure the server is configured before fetching
      if (!serverConfig.isConfigured.value) {
        providerError.value = 'Server not configured.';
        isLoadingProviders.value = false;
        return;
      }
      final providers = await sdk.getOAuthProviders();
      // Filter providers that have a client_id, similar to the React example
      oauthProviders.assignAll(providers.where((p) => p['client_id'] != null && p['client_id'].isNotEmpty).toList());
    } catch (e) {
      print("Error fetching OAuth providers: $e");
      providerError.value = 'Failed to load OAuth providers.';
    } finally {
      isLoadingProviders.value = false;
    }
  }

  void _checkAndHandleTokenResponse(String response) {
    if (response.contains("?token=")) {
      final token = response.split("token=")[1];
      tokenController.text = token;
      isTokenLogin.value = true;
      _attemptTokenLogin(token);
    }
  }

  Future<void> _attemptTokenLogin(String token) async {
    if (token.isNotEmpty) {
      final success = await authController.loginWithToken(token);
      if (success) {
        Get.offNamed('/home');
      }
    }
  }

  // Helper to get FontAwesome icon
  IconData _getIconForProvider(String name) {
    switch (name.toLowerCase()) {
      case 'discord':
        return FontAwesomeIcons.discord;
      case 'github':
        return FontAwesomeIcons.github;
      case 'google':
        return FontAwesomeIcons.google;
      case 'microsoft':
        return FontAwesomeIcons.microsoft;
      case 'x':
        return FontAwesomeIcons.xTwitter; // Correct icon for X
      case 'tesla':
        return FontAwesomeIcons.car; // Placeholder, no direct Tesla icon
      case 'amazon':
        return FontAwesomeIcons.amazon;
      case 'walmart':
         return FontAwesomeIcons.store; // Placeholder
      default:
        return FontAwesomeIcons.signInAlt; // Generic login icon
    }
  }

  // Function to launch OAuth URL
  Future<void> _handleOAuthLogin(Map<String, dynamic> provider) async {
    try {
      final String authorizeUrl = provider['authorize'];
      final String clientId = provider['client_id'];
      final String scopes = provider['scopes'];
      final String providerName = provider['name'].toLowerCase();
      
      print('\nInitializing OAuth flow for: $providerName');
      print('Authorization URL: $authorizeUrl');
    
      // Store provider information
      await authController.storeOAuthProvider(providerName);
      print('Initialized OAuth flow with provider: $providerName');
    
      // IMPORTANT: Redirect URI needs careful handling for mobile apps.
      // --- Start Local Server and Prepare Redirect URI ---
      final localServerPort = authController.getLocalServerPort(); // Use getter from AuthController
      final String redirectUri = 'http://localhost:$localServerPort/oauth-callback';
      print('Starting local server for redirect URI: $redirectUri');
      // Start server and get the future that completes when callback is received
      final Future<Uri?> callbackFuture = authController.startLocalServerAndAwaitCallback();
      // --- End Local Server Setup ---

      // Check if this provider requires PKCE
      final bool pkceRequired = provider['pkce_required'] ?? false;

      // Get PKCE challenge and state if required
      if (pkceRequired) {
        await authController.fetchPkceParametersForProvider();
      }

      // Generate state parameter and link it to the provider
      final String state = const Uuid().v4();
      print('Generated state for OAuth flow: $state');
      
      // Store state mapping with provider linkage
      await authController.addStateToProvider(state, providerName);
      
      // Verify provider state is maintained
      print('Verifying provider state:');
      print('State mapping: $state -> $providerName');
      print('State parameter mapped to provider: $state -> $providerName');
      
      // Construct the full URL with provider-specific parameters
      final Map<String, String> queryParams = {
        'client_id': clientId,
        'scope': scopes,
        'response_type': 'code',
        'redirect_uri': redirectUri,
        'state': state, // Always include state parameter
      };

      // Add provider-specific parameters
      switch (providerName) {
        case 'google':
          queryParams['access_type'] = 'offline';
          queryParams['prompt'] = 'consent';
          break;
        case 'github':
          // Add GitHub-specific parameters if needed
          break;
        // Add cases for other providers as needed
      }

      // Add PKCE parameters if required
      if (pkceRequired) {
        await authController.fetchPkceParametersForProvider();
        if (authController.getPkceChallenge().isNotEmpty) {
          queryParams['code_challenge'] = authController.getPkceChallenge();
          queryParams['code_challenge_method'] = 'S256';
        }
      }

      final Uri url = Uri.parse(authorizeUrl).replace(queryParameters: queryParams);

      print('Launching OAuth URL with state parameter: ${url.queryParameters['state']}');
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication); // Opens in external browser

        // --- Await Callback ---
        print('Waiting for OAuth callback...');
        // Wait for the local server to receive the callback
        final Uri? callbackUri = await callbackFuture;

        if (callbackUri != null) {
          print('OAuth callback received:');
          print('URL: $callbackUri');
          // Pass the full callback URI to the controller for processing (code exchange, etc.)
          await authController.handleOAuthCallback(callbackUri);
        } else {
          // This means the server timed out or failed to start
          print('OAuth flow failed, timed out, or server error.');
          Get.snackbar('Error', 'Authentication failed or timed out.');
        }
        // --- End Await Callback ---

      } else {
        print('Could not launch $url');
        Get.snackbar('Error', 'Could not open authentication page.');
        // Ensure server stops if we couldn't even launch the URL
        await authController.stopLocalServer();
      }
    } catch (e) {
      print('Error during OAuth flow: $e');
      Get.snackbar('Error', 'Failed to complete authentication: ${e.toString()}');
      await authController.stopLocalServer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            // Corrected Structure: Padding -> SingleChildScrollView -> Column
            child: SingleChildScrollView(
              child: Column( // This Column now correctly inside SingleChildScrollView
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // AGiXT Logo
                Padding(
                  padding: const EdgeInsets.only(bottom: 40.0),
                  child: SvgPicture.asset(
                    'assets/PoweredBy_AGiXT_New.svg',
                    height: 100,
                  ),
                ),

                // Server Info
                Padding(
                  padding: const EdgeInsets.only(bottom: 20.0),
                  child: Obx(() => Text(
                    'Server: ${serverConfig.baseUri.value} ${serverConfig.isConfigured.value ? '(Connected)' : '(Not Connected)'}',
                    style: TextStyle(
                      color: serverConfig.isConfigured.value ? Colors.green : Colors.red,
                      fontSize: 14,
                    ),
                  )),
                ),

                // Login Method Toggle
                // Consider if OAuth should bypass this toggle or be presented alongside
                Padding(
                  padding: const EdgeInsets.only(bottom: 20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => isTokenLogin.value = false,
                        child: Obx(() => Text(
                          'Email/OTP',
                          style: TextStyle(
                            color: !isTokenLogin.value ? Colors.blue : Colors.grey,
                          ),
                        )),
                      ),
                      TextButton(
                        onPressed: () => isTokenLogin.value = true,
                        child: Obx(() => Text(
                          'API Key',
                          style: TextStyle(
                            color: isTokenLogin.value ? Colors.blue : Colors.grey,
                          ),
                        )),
                      ),
                    ],
                  ),
                ),

                Obx(() => isTokenLogin.value
                  ? // API Key login
                    TextField(
                      controller: tokenController,
                      decoration: InputDecoration(
                        labelText: 'API Key',
                        border: OutlineInputBorder(),
                        labelStyle: TextStyle(color: Colors.grey[400]),
                      ),
                      style: TextStyle(color: Colors.white),
                    )
                  : // Email/OTP login
                    Column(
                      children: [
                        TextField(
                          controller: emailController,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                            labelStyle: TextStyle(color: Colors.grey[400]),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          style: TextStyle(color: Colors.white),
                        ),
                        SizedBox(height: 20),
                        TextField(
                          controller: otpController,
                          decoration: InputDecoration(
                            labelText: 'OTP',
                            border: OutlineInputBorder(),
                            labelStyle: TextStyle(color: Colors.grey[400]),
                          ),
                          keyboardType: TextInputType.number,
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    )
                ),
                
                SizedBox(height: 30),

                // --- OAuth Login Buttons ---
                Obx(() {
                  if (isLoadingProviders.value) {
                    return const CircularProgressIndicator();
                  }
                  if (providerError.value.isNotEmpty) {
                    return Text(providerError.value, style: const TextStyle(color: Colors.orange));
                  }
                  if (oauthProviders.isEmpty) {
                    return const SizedBox.shrink(); // Or Text('No OAuth providers available.')
                  }

                  // Sort providers alphabetically by name
                  final sortedProviders = List<Map<String, dynamic>>.from(oauthProviders);
                  sortedProviders.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

                  return Column(
                    children: [
                       const Text("Or continue with:", style: TextStyle(color: Colors.grey)),
                       const SizedBox(height: 15),
                       Wrap( // Use Wrap for better layout if many providers
                         spacing: 10.0, // Horizontal space between buttons
                         runSpacing: 10.0, // Vertical space between rows
                         alignment: WrapAlignment.center,
                         children: sortedProviders.map((provider) {
                           final name = provider['name'] as String;
                           final capitalizedName = name[0].toUpperCase() + name.substring(1);
                           return ElevatedButton.icon(
                             icon: FaIcon(_getIconForProvider(name), size: 18),
                             label: Text(name.toLowerCase() == 'x' ? 'Continue with X (Twitter)' : 'Continue with $capitalizedName'),
                             onPressed: () => _handleOAuthLogin(provider),
                             style: ElevatedButton.styleFrom(
                               foregroundColor: Colors.white, backgroundColor: Colors.grey[800], // Text color
                               shape: RoundedRectangleBorder(
                                 borderRadius: BorderRadius.circular(8),
                               ),
                               padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                             ),
                           );
                         }).toList(),
                       ),
                       const SizedBox(height: 30), // Space after OAuth buttons
                    ],
                  );
                }),
                // --- End OAuth Login Buttons ---

                // Login button
                Obx(() => authController.isLoading.value
                  ? const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    )
                  : ElevatedButton(
                      onPressed: () async {
                        if (isTokenLogin.value) {
                          if (tokenController.text.isNotEmpty) {
                            await _attemptTokenLogin(tokenController.text);
                          }
                        } else {
                          if (emailController.text.isNotEmpty && otpController.text.isNotEmpty) {
                            final success = await authController.login(
                              emailController.text,
                              otpController.text,
                            );
                            if (success) {
                              final response = authController.error.value;
                              // Extract and use token from response regardless of format
                              _checkAndHandleTokenResponse(response);
                              Get.offNamed('/home');
                            }
                          }
                        }
                      },
                      child: Text(isTokenLogin.value ? 'Login with API Key' : 'Login'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                ),

                SizedBox(height: 20),
                
                // Register button (only show for email/OTP login)
                Obx(() => !isTokenLogin.value
                  ? TextButton(
                      onPressed: () => Get.toNamed('/register'),
                      child: const Text('Register'),
                    )
                  : SizedBox.shrink()
                ),

                SizedBox(height: 20),

                // Error message
                Obx(() => authController.error.value.isNotEmpty
                  ? Text(
                      authController.error.value,
                      style: TextStyle(
                        color: Colors.red[400],
                        fontSize: 14,
                      ),
                    )
                  : const SizedBox.shrink(),
                ),

                // Change Server button
                TextButton(
                  onPressed: () {
                    serverConfig.isConfigured.value = false;
                    Get.offNamed('/config');
                  },
                  child: const Text('Change Server'),
                ),
              ],
            ), // End Column
          ), // End SingleChildScrollView
          ),
        ),
      ),
    );
  }
}