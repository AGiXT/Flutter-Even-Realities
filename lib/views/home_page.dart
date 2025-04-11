// ignore_for_file: library_private_types_in_public_api

import 'dart:async';

// Remove old BleManager import
import 'package:agixt_even_realities/services/evenai.dart';
import 'package:agixt_even_realities/views/even_list_page.dart';
import 'package:agixt_even_realities/views/features_page.dart';
import 'package:agixt_even_realities/views/extensions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart'; // Import for ScrollController jump
import 'package:flutter/services.dart'; // Import for Clipboard
import 'package:get/get.dart';
import '../controllers/server_config_controller.dart'; // Import ServerConfigController
import '../controllers/settings_controller.dart'; // Import SettingsController
import '../controllers/log_controller.dart'; // Import LogController
import '../services/bluetooth_service.dart'; // Import BluetoothService
import 'package:google_fonts/google_fonts.dart'; // For monospace font
import 'package:permission_handler/permission_handler.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? scanTimer;
  bool isScanning = false;
  final ServerConfigController serverConfigController = Get.find<ServerConfigController>();
  final SettingsController settingsController = Get.find<SettingsController>(); // Get SettingsController
  final LogController logController = Get.find<LogController>(); // Get LogController
  final BluetoothService bluetoothService = Get.find<BluetoothService>(); // Get BluetoothService
  final ScrollController _logScrollController = ScrollController(); // For auto-scrolling logs

  @override
  void initState() {
    super.initState();
    // Remove old BleManager setup
    // BleManager.get().setMethodCallHandler();
    // BleManager.get().startListening();
    // BleManager.get().onStatusChanged = _refreshPage; // Remove old status listener

    // Listener to auto-scroll log console
    logController.logMessages.listen((_) {
      // Ensure controller is attached before trying to jump
      if (_logScrollController.hasClients) {
         // Use SchedulerBinding to scroll after the frame is built
         SchedulerBinding.instance.addPostFrameCallback((_) {
            _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
         });
      }
    });
  }

  void _refreshPage() => setState(() {});

  // Updated _startScan to use BluetoothService
  Future<void> _startScan() async {
    // Permissions should be handled by flutter_blue_plus or requested separately if needed
    // Consider adding permission checks here using permission_handler if flutter_blue_plus doesn't handle it adequately
    logController.addLog("[HomePage] User triggered scan.");
    await bluetoothService.startScan();
    // No need for manual timer/stopScan call here, service handles timeout
  }

  // _stopScan is likely not needed anymore as the service handles it
  // Future<void> _stopScan() async { ... }

  Widget bleDevicePicker() {
    return Expanded(
      child: Column(
        children: [
          Text(
            'Select Connected Devices',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color),
          ),
          const SizedBox(height: 10),
          // TODO: Update this section based on BluetoothService connection state
          Obx(() => (bluetoothService.isLeftConnected.value || bluetoothService.isRightConnected.value) // Use Obx for reactivity
              ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                            if (bluetoothService.isLeftConnected.value) {
                                // TODO: Logic to interact with connected device
                                logController.addLog('[HomePage] Left Device interaction TBD');
                            } else {
                                // Trigger scan or show device list for selection
                                logController.addLog('[HomePage] Loading devices for Left connection');
                                _startScan();
                            }
                        },
                        child: Text('Left Device', style: TextStyle(color: bluetoothService.isLeftConnected.value ? Theme.of(context).textTheme.bodyLarge?.color : Colors.grey)),
                      ),
                      ElevatedButton(
                        onPressed: () {
                            if (bluetoothService.isRightConnected.value) {
                                // TODO: Logic to interact with connected device
                                logController.addLog('[HomePage] Right Device interaction TBD');
                            } else {
                                // Trigger scan or show device list for selection
                                logController.addLog('[HomePage] Loading devices for Right connection');
                                _startScan();
                            }
                        },
                        child: Text('Right Device', style: TextStyle(color: bluetoothService.isRightConnected.value ? Theme.of(context).textTheme.bodyLarge?.color : Colors.grey)),
                      ),
                    ],
                  )
              : const Text( // Show when not connected
                    'No device connected.',
                  )),
            // This Row and Text are now inside the Obx above
          const SizedBox(height: 20),
          blePairedList(),
        ],
      ),
    );
  }

  // Updated blePairedList to use BluetoothService
  Widget blePairedList() => Expanded(
        child: RefreshIndicator(
          onRefresh: _startScan, // Call updated _startScan
          child: Obx(() => ListView.separated( // Wrap with Obx to react to discoveredDevices changes
                physics: const AlwaysScrollableScrollPhysics(),
                separatorBuilder: (context, index) => const SizedBox(height: 5),
                itemCount: bluetoothService.discoveredDevices.length,
                itemBuilder: (context, index) {
                  final discovered = bluetoothService.discoveredDevices[index];
                  return ListTile( // Use ListTile for simplicity
                     tileColor: Theme.of(context).cardColor,
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                     title: Text(
                       discovered.name,
                       style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                     ),
                     subtitle: Text(
                       discovered.id, // Show device ID
                       style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color),
                     ),
                     trailing: Row(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         ElevatedButton(
                           child: Text(bluetoothService.isLeftConnected.value && bluetoothService.leftDevice.value?.remoteId == discovered.device.remoteId
                               ? 'Connected (Left)'
                               : 'Left'),
                           onPressed: () {
                             if (!(bluetoothService.isLeftConnected.value && bluetoothService.leftDevice.value?.remoteId == discovered.device.remoteId)) {
                               bluetoothService.connectToDevice(discovered, isLeft: true);
                             }
                           },
                           style: ElevatedButton.styleFrom(
                             backgroundColor: bluetoothService.isLeftConnected.value && bluetoothService.leftDevice.value?.remoteId == discovered.device.remoteId
                                 ? Colors.green
                                 : null,
                           ),
                         ),
                         const SizedBox(width: 8),
                         ElevatedButton(
                           child: Text(bluetoothService.isRightConnected.value && bluetoothService.rightDevice.value?.remoteId == discovered.device.remoteId
                               ? 'Connected (Right)'
                               : 'Right'),
                           onPressed: () {
                             if (!(bluetoothService.isRightConnected.value && bluetoothService.rightDevice.value?.remoteId == discovered.device.remoteId)) {
                               bluetoothService.connectToDevice(discovered, isLeft: false);
                             }
                           },
                           style: ElevatedButton.styleFrom(
                             backgroundColor: bluetoothService.isRightConnected.value && bluetoothService.rightDevice.value?.remoteId == discovered.device.remoteId
                                 ? Colors.green
                                 : null,
                           ),
                         ),
                       ],
                     ),
                     onTap: () { // Keep onTap for potential future use or remove
                       // Prompt user to choose side
                       showDialog(
                         context: context,
                         builder: (context) => AlertDialog(
                           title: Text('Connect ${discovered.name}'),
                           content: const Text('Which side should this device be connected to?'),
                           actions: [
                             TextButton(
                               onPressed: () {
                                 if (!(bluetoothService.isLeftConnected.value && bluetoothService.leftDevice.value?.remoteId == discovered.device.remoteId)) {
                                   bluetoothService.connectToDevice(discovered, isLeft: true);
                                   Navigator.pop(context);
                                 }
                               },
                               child: Text(bluetoothService.isLeftConnected.value && bluetoothService.leftDevice.value?.remoteId == discovered.device.remoteId
                                   ? 'Connected (Left)'
                                   : 'Left'),
                             ),
                             TextButton(
                               onPressed: () {
                                 if (!(bluetoothService.isRightConnected.value && bluetoothService.rightDevice.value?.remoteId == discovered.device.remoteId)) {
                                   bluetoothService.connectToDevice(discovered, isLeft: false);
                                   Navigator.pop(context);
                                 }
                               },
                               child: Text(bluetoothService.isRightConnected.value && bluetoothService.rightDevice.value?.remoteId == discovered.device.remoteId
                                   ? 'Connected (Right)'
                                   : 'Right'),
                             ),
                           ],
                         ),
                       );
                     },
                  );
                },
              )),
        ),
      );

  // Widget to build the agent selection dropdown for AppBar
  Widget _buildAgentSelector() {
    return Obx(() {
      final bool isEnabled = serverConfigController.isConfigured.value && serverConfigController.availableAgents.isNotEmpty;
      final List<Map<String, dynamic>> agents = serverConfigController.availableAgents;
      final String? currentSelection = serverConfigController.selectedAgent.value;

      // Ensure the current selection is valid among available agents
      final String? validSelection = agents.any((agent) => agent['name'] == currentSelection)
          ? currentSelection
          : (agents.isNotEmpty ? agents.first['name'] : null);

      // Update controller if selection was invalid and agents are available
      if (validSelection != currentSelection && validSelection != null) {
         WidgetsBinding.instance.addPostFrameCallback((_) {
            serverConfigController.selectAgent(validSelection);
         });
      }

      // Use PopupMenuButton for AppBar placement
      return PopupMenuButton<String>(
        icon: Icon(Icons.person_pin_circle_outlined, color: isEnabled ? Theme.of(context).appBarTheme.foregroundColor : Colors.grey),
        tooltip: isEnabled ? "Select Agent" : (serverConfigController.isConfigured.value ? "No agents found" : "Server not configured"),
        enabled: isEnabled,
        initialValue: validSelection,
        onSelected: (String newValue) {
          serverConfigController.selectAgent(newValue);
        },
        itemBuilder: (BuildContext context) {
          if (!isEnabled) {
            return <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: null, // Non-selectable
                child: Text('No agents available'),
              ),
            ];
          }
          return agents.map((agent) {
            return PopupMenuItem<String>(
              value: agent['name'],
              child: Text(agent['name'] ?? 'Unnamed Agent'),
            );
          }).toList();
        },
      );
    });
  }
  // --- Log Console Widget ---
  Widget _buildLogConsole() {
    return Obx(() {
      if (!settingsController.isDebugLoggingEnabled.value) {
        return const SizedBox.shrink(); // Don't show if disabled
      }

      // Use a Column to hold the console and the copy button
      return Container(
        color: Colors.black87, // Background for the whole console area
        padding: const EdgeInsets.only(top: 4.0, left: 8.0, right: 8.0, bottom: 4.0),
        child: Column(
          mainAxisSize: MainAxisSize.min, // Take minimum space needed
          children: [
            // Log List View Area
            SizedBox(
              height: 130, // Adjusted height for the list view
              child: logController.logMessages.isEmpty
                  ? Center(
                      child: Text(
                        'Debug console enabled. Logs will appear here.',
                        style: GoogleFonts.robotoMono(color: Colors.greenAccent, fontSize: 12),
                      ),
                    )
                  : ListView.builder(
                      controller: _logScrollController,
                      itemCount: logController.logMessages.length,
                      itemBuilder: (context, index) {
                        final logEntry = logController.logMessages[index];
                        return Text(
                          logEntry.toString(),
                          style: GoogleFonts.robotoMono(color: Colors.greenAccent, fontSize: 12),
                        );
                      },
                    ),
            ),
            // Separator and Copy Button
            const Divider(height: 1, color: Colors.grey),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.copy, size: 16, color: Colors.grey),
                label: const Text('Copy Logs', style: TextStyle(color: Colors.grey, fontSize: 12)),
                onPressed: () {
                  final allLogs = logController.logMessages.map((entry) => entry.toString()).join('\n');
                  Clipboard.setData(ClipboardData(text: allLogs));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Logs copied to clipboard!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    });
  }
  // --- End Log Console Widget ---

  @override
  Widget build(BuildContext context) {
    // Log state during build
    logController.addLog("[HomePage Build] Left Connected: ${bluetoothService.isLeftConnected.value}, Right Connected: ${bluetoothService.isRightConnected.value}, Left Status: ${bluetoothService.leftConnectionStatus.value}, Right Status: ${bluetoothService.rightConnectionStatus.value}, Devices: ${bluetoothService.discoveredDevices.length}");
    
    return Scaffold( // Ensure Scaffold is returned directly
        appBar: AppBar(
          title: const Text('Even AI Demo'),
          actions: [
            InkWell(
              onTap: () {
                print("To Features Page...");
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const FeaturesPage()),
                );
              },
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: const Padding(
                padding:
                    EdgeInsets.only(left: 16, top: 12, bottom: 14, right: 16),
                child: Icon(Icons.menu),
              ),
            ),
            _buildAgentSelector(), // Add agent selector to AppBar actions
            // Add Settings Icon Button
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Settings',
              onPressed: () {
                Get.toNamed('/settings'); // Navigate to settings page
              },
            ),
          ],
        ),
        body: Padding(
          padding:
              const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 44),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () async {
                  // Trigger scan only if not fully connected
                  if (!bluetoothService.isLeftConnected.value || !bluetoothService.isRightConnected.value) {
                    _startScan();
                  }
                },
                child: Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor, // Use theme card color
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        spreadRadius: 2,
                        blurRadius: 5,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  // Display reactive connection status for both sides
                  child: Obx(() => Text(
                    '${bluetoothService.leftConnectionStatus.value}\n${bluetoothService.rightConnectionStatus.value}',
                      style: TextStyle(fontSize: 16, /* color: Theme.of(context).textTheme.bodyLarge?.color */))), // Added missing ')' for Text widget
                ),
              ),
              const SizedBox(height: 16),
              // Show device list if not fully connected
              Obx(() => (bluetoothService.isLeftConnected.value && bluetoothService.isRightConnected.value)
                  ? const SizedBox.shrink() // Hide list when both connected
                  : bleDevicePicker()),
              // Show AI history section only when at least one side is connected
              Obx(() => (bluetoothService.isLeftConnected.value || bluetoothService.isRightConnected.value)
                  ? Column( // This section shows when connected
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          // todo
                          print("To AI History List...");
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const EvenAIListPage(),
                            ),
                          );
                        },
                        child: Container(
                          color: Theme.of(context).cardColor, // Use theme card color
                          padding: const EdgeInsets.all(16),
                          alignment: Alignment.topCenter,
                          child: SingleChildScrollView(
                            child: StreamBuilder<String>(
                              stream: EvenAI.textStream,
                              initialData:
                                  "Press and hold left TouchBar to engage Even AI.",
                              builder: (context, snapshot) => Obx(
                                () => EvenAI.isEvenAISyncing.value
                                    ? const SizedBox(
                                        width: 50,
                                        height: 50,
                                        child: CircularProgressIndicator(),
                                      )
                                    : Text(
                                        snapshot.data ?? "Loading...",
                                        style: TextStyle(
                                            fontSize: 14,
                                            color: (bluetoothService.isLeftConnected.value || bluetoothService.isRightConnected.value) // Use reactive state
                                               ? Theme.of(context).textTheme.bodyLarge?.color
                                               : Colors.grey.withOpacity(0.5)),
                                        textAlign: TextAlign.center,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ], // End children of Column shown when connected
                )
              : const SizedBox.shrink()), // Hide Column when not connected
                // Removed extra closing parenthesis
        _buildLogConsole(),
            ], // End children of main Column inside Padding
          ), // End main Column inside Padding
        ), // End Padding
        // (Log console will be inserted inside the Column below)
      );
  }

  @override
  void dispose() {
    scanTimer?.cancel();
    isScanning = false;
    // BleManager.get().onStatusChanged = null; // Remove old status listener cleanup
    _logScrollController.dispose(); // Dispose scroll controller
    super.dispose();
  }
}
