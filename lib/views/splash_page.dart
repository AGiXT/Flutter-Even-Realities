import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';
import '../controllers/server_config_controller.dart'; // Import ServerConfigController
import '../controllers/log_controller.dart'; // Import LogController

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to ensure controllers are ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLoginStatus();
    });
  }

  Future<void> _checkLoginStatus() async {
    // Ensure controllers are fully initialized (especially AuthController's async init)
    final authController = Get.find<AuthController>();
    final serverConfigController = Get.find<ServerConfigController>();
    final logController = Get.find<LogController>(); // Get LogController

    logController.addLog("[SplashPage] Checking login status..."); // Add test log

    // Wait a brief moment to allow async operations in onInit to complete
    await Future.delayed(const Duration(milliseconds: 100)); 

    if (!serverConfigController.isConfigured.value) {
      print("[SplashPage] Server not configured. Navigating to /config.");
      Get.offAllNamed('/config'); // Go to config first if not set up
    } else if (authController.isLoggedIn.value) {
       print("[SplashPage] User is logged in. Navigating to /home.");
      Get.offAllNamed('/home'); // Go home if logged in
    } else {
       print("[SplashPage] User is not logged in. Navigating to /login.");
      Get.offAllNamed('/login'); // Go to login if not logged in
    }
  }

  @override
  Widget build(BuildContext context) {
    // Simple loading indicator while checking status
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}