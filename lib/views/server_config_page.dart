import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../controllers/server_config_controller.dart';

class ServerConfigPage extends StatefulWidget {
  @override
  State<ServerConfigPage> createState() => _ServerConfigPageState();
}

class _ServerConfigPageState extends State<ServerConfigPage> {
  final ServerConfigController controller = Get.find<ServerConfigController>();
  late final TextEditingController uriController;
  final TextEditingController apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    uriController = TextEditingController(text: controller.baseUri.value);
  }

  @override
  void dispose() {
    uriController.dispose();
    apiKeyController.dispose();
    super.dispose();
  }

  Widget _buildConnectionStatus() {
    return Obx(() => Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: controller.isConfigured.value
          ? Colors.green.withOpacity(0.1)
          : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: controller.isConfigured.value
            ? Colors.green.withOpacity(0.3)
            : Colors.red.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            controller.isConfigured.value
              ? Icons.check_circle_outline
              : Icons.error_outline,
            color: controller.isConfigured.value
              ? Colors.green
              : Colors.red,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              controller.isConfigured.value
                ? 'Connected to server'
                : 'Not connected to server. Please configure server details.',
              style: TextStyle(
                color: controller.isConfigured.value
                  ? Colors.green
                  : Colors.red,
              ),
            ),
          ),
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
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

                  Text(
                    'Server Configuration',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[100],
                    ),
                  ),

                  _buildConnectionStatus(),

                  // Base URI field
                  TextField(
                    controller: uriController,
                    decoration: InputDecoration(
                      labelText: 'Base URI',
                      prefixIcon: Icon(
                        Icons.link,
                        color: Colors.grey[600],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    style: TextStyle(color: Colors.grey[100]),
                  ),
                  SizedBox(height: 20),

                  // API Key field
                  TextField(
                    controller: apiKeyController,
                    decoration: InputDecoration(
                      labelText: 'API Key (optional)',
                      prefixIcon: Icon(
                        Icons.vpn_key,
                        color: Colors.grey[600],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    style: TextStyle(color: Colors.grey[100]),
                    obscureText: true,
                  ),
                  SizedBox(height: 30),

                  // Configure button
                  ElevatedButton(
                    onPressed: () {
                      final success = controller.configureServer(
                        uriController.text,
                        apiKeyController.text.isEmpty ? null : apiKeyController.text,
                      );
                      if (success) {
                        Get.offNamed('/login');
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      height: 50,
                      child: Center(
                        child: Text(
                          'Configure Server',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: 20),

                  // Error message
                  Obx(() => controller.error.value.isNotEmpty
                      ? Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.red.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            controller.error.value,
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                      : SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}