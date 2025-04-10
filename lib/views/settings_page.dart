import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/settings_controller.dart'; // Import SettingsController

class SettingsPage extends StatelessWidget {
  // Remove const constructor
  SettingsPage({super.key});

  // Remove field initialization

  @override
  Widget build(BuildContext context) {
    // Get instance of SettingsController inside build method
    final SettingsController settingsController = Get.find<SettingsController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: <Widget>[
          Obx(() => SwitchListTile( // Use Obx to react to state changes
                title: const Text('Enable Debug Logging'),
                subtitle: const Text('Show detailed logs in the console'),
                value: settingsController.isDebugLoggingEnabled.value, // Bind to controller state
                onChanged: (bool value) {
                  settingsController.setDebugLogging(value); // Call controller method
                },
              )),
          // Add other settings here if needed
        ],
      ),
    );
  }
}