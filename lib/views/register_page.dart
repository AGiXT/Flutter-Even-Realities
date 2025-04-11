import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../controllers/auth_controller.dart';

class RegisterPage extends StatelessWidget {
  final AuthController authController = Get.find();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
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

                Text(
                  'Register',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.headlineSmall?.color, // Use theme color
                  ),
                ),
                SizedBox(height: 20),

                // Registration Form
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    labelStyle: TextStyle(color: Colors.grey[400]),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color), // Use theme text color
                ),
                SizedBox(height: 20),

                TextField(
                  controller: firstNameController,
                  decoration: InputDecoration(
                    labelText: 'First Name',
                    border: OutlineInputBorder(),
                    labelStyle: TextStyle(color: Colors.grey[400]),
                  ),
                  style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color), // Use theme text color
                ),
                SizedBox(height: 20),

                TextField(
                  controller: lastNameController,
                  decoration: InputDecoration(
                    labelText: 'Last Name',
                    border: OutlineInputBorder(),
                    labelStyle: TextStyle(color: Colors.grey[400]),
                  ),
                  style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color), // Use theme text color
                ),
                SizedBox(height: 30),

                // Register button
                Obx(() => authController.isLoading.value
                  ? CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    )
                  : ElevatedButton(
                      onPressed: () async {
                        if (emailController.text.isNotEmpty &&
                            firstNameController.text.isNotEmpty &&
                            lastNameController.text.isNotEmpty) {
                          final success = await authController.registerUser(
                            emailController.text,
                            firstNameController.text,
                            lastNameController.text,
                          );
                          if (success) {
                            _showOtpQrDialog(context);
                          }
                        }
                      },
                      child: Text('Register'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
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
                  : SizedBox.shrink(),
                ),

                // Back to login button
                TextButton(
                  onPressed: () => Get.back(),
                  child: Text('Back to Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showOtpQrDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Setup Authentication',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.titleLarge?.color, // Use theme color
                ),
              ),
              SizedBox(height: 20),

              // QR Code
              Obx(() => authController.otpUri.value.isNotEmpty
                ? Column(
                    children: [
                      QrImageView(
                        data: authController.otpUri.value,
                        version: QrVersions.auto,
                        size: 200.0,
                        backgroundColor: Colors.white,
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Scan this QR code with your authenticator app',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color), // Use theme text color
                      ),
                      SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(
                            text: authController.otpUri.value,
                          ));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('OTP URI copied to clipboard')),
                          );
                        },
                        child: Text('Copy OTP URI'),
                      ),
                    ],
                  )
                : CircularProgressIndicator(),
              ),

              SizedBox(height: 20),

              ElevatedButton(
                onPressed: () {
                  authController.clearOtpUri();
                  Get.back();
                  Get.offNamed('/login');
                },
                child: Text('Proceed to Login'),
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}