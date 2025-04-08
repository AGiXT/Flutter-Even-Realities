import 'package:flutter/material.dart';
import 'package:get/get.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; // Import FontAwesome for icons
import '../controllers/auth_controller.dart';
import '../controllers/server_config_controller.dart';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final AuthController authController = Get.find();
  final ServerConfigController serverConfig = Get.find();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController otpController = TextEditingController();
  final TextEditingController tokenController = TextEditingController();
  final RxBool isTokenLogin = false.obs;
  late final Worker _oauthProviderWorker;

  @override
  void initState() {
    super.initState();
    // Fetch providers when the page initializes
    // Use addPostFrameCallback to ensure Get dependencies are ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (serverConfig.isConfigured.value) {
         print("[LoginPage] Fetching OAuth providers on init...");
         authController.fetchOAuthProviders();
      } else {
         print("[LoginPage] Server not configured, skipping OAuth provider fetch.");
      }
    });

    // Add a listener to log providers when they change
    _oauthProviderWorker = ever(authController.oauthProviders, (List<Map<String, dynamic>> providers) {
      print("[LoginPage] OAuth Providers Updated: ${providers.length} providers found.");
      if (providers.isNotEmpty) {
        print("[LoginPage] Provider Details:");
        providers.forEach((p) => print("  - Provider: $p")); // Log the full map
      }
    });
  }

  @override
  void dispose() {
    _oauthProviderWorker.dispose(); // Dispose the listener
    emailController.dispose();
    otpController.dispose();
    tokenController.dispose();
    super.dispose();
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

  // Helper to get FontAwesomeIcon based on provider name
  IconData _getIconForProvider(String providerName) {
    switch (providerName.toLowerCase()) {
      case 'google':
        return FontAwesomeIcons.google;
      case 'github':
        return FontAwesomeIcons.github;
      case 'microsoft':
        return FontAwesomeIcons.microsoft;
      case 'discord':
        return FontAwesomeIcons.discord;
      case 'x': // Twitter is now X
        return FontAwesomeIcons.xTwitter;
      // Add more cases as needed for other providers
      default:
        return FontAwesomeIcons.plug; // Default icon
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
            child: Column(
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
                  : SizedBox.shrink()),

                SizedBox(height: 20),

                // --- OAuth Login Buttons ---
                Obx(() {
                  if (authController.isProvidersLoading.value) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10.0),
                      child: CircularProgressIndicator(),
                    );
                  }
                  if (authController.oauthProviders.isEmpty) {
                    // Optionally show a message if no providers are available/loaded
                    return const SizedBox.shrink();
                  }
                  return Column(
                    children: [
                      const Divider(height: 30, thickness: 1),
                      const Text("Or continue with:", style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 15),
                      Wrap( // Use Wrap for better layout if many providers
                        spacing: 15.0, // Horizontal space between buttons
                        runSpacing: 10.0, // Vertical space between lines
                        alignment: WrapAlignment.center,
                        children: authController.oauthProviders.map((provider) {
                          final providerName = provider['name'] as String? ?? 'Unknown';
                          final buttonText = providerName.toLowerCase() == 'x'
                              ? 'Continue with X (Twitter)'
                              : 'Continue with ${providerName[0].toUpperCase()}${providerName.substring(1)}';

                          return ElevatedButton.icon(
                            icon: FaIcon(_getIconForProvider(providerName), size: 18), // Use FontAwesome icon
                            label: Text(buttonText),
                            onPressed: authController.isLoading.value ? null : () async { // Disable while any login is loading
                              final success = await authController.loginWithOAuth(provider);
                              if (success && authController.isLoggedIn.value) {
                                Get.offNamed('/home');
                              }
                              // Error is handled by the Obx below
                            },
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white, backgroundColor: Colors.blueGrey[700], // Text color
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                            ),
                          );
                        }).toList(),
                      ),
                      const Divider(height: 30, thickness: 1),
                    ],
                  );
                }),
                // --- End OAuth Login Buttons ---

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
            ),
          ),
        ),
      ),
    );
  }
}