import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../controllers/auth_controller.dart';
import '../controllers/server_config_controller.dart';

class LoginPage extends StatelessWidget {
  final AuthController authController = Get.find();
  final ServerConfigController serverConfig = Get.find();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController otpController = TextEditingController();
  final TextEditingController tokenController = TextEditingController();
  final RxBool isTokenLogin = false.obs;

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
            ),
          ),
        ),
      ),
    );
  }
}