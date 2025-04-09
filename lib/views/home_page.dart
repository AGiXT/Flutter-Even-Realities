// ignore_for_file: library_private_types_in_public_api

import 'dart:async';

import 'package:agixt_even_realities/ble_manager.dart';
import 'package:agixt_even_realities/services/evenai.dart';
import 'package:agixt_even_realities/views/even_list_page.dart';
import 'package:agixt_even_realities/views/features_page.dart';
import 'package:agixt_even_realities/views/extensions_page.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/server_config_controller.dart'; // Import ServerConfigController

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? scanTimer;
  bool isScanning = false;
  final ServerConfigController serverConfigController = Get.find<ServerConfigController>(); // Get controller instance

  @override
  void initState() {
    super.initState();
    BleManager.get().setMethodCallHandler();
    BleManager.get().startListening();
    BleManager.get().onStatusChanged = _refreshPage;
  }

  void _refreshPage() => setState(() {});

  Future<void> _startScan() async {
    setState(() => isScanning = true);
    await BleManager.get().startScan();
    scanTimer?.cancel();
    scanTimer = Timer(15.seconds, () {
      // todo
      _stopScan();
    });
  }

  Future<void> _stopScan() async {
    if (isScanning) {
      await BleManager.get().stopScan();
      setState(() => isScanning = false);
    }
  }

  Widget blePairedList() => Expanded(
        child: ListView.separated(
          separatorBuilder: (context, index) => const SizedBox(height: 5),
          itemCount: BleManager.get().getPairedGlasses().length,
          itemBuilder: (context, index) {
            final glasses = BleManager.get().getPairedGlasses()[index];
            return GestureDetector(
              onTap: () async {
                String channelNumber = glasses['channelNumber']!;
                await BleManager.get().connectToGlasses("Pair_$channelNumber");
                _refreshPage();
              },
              child: Container(
                height: 72,
                padding: const EdgeInsets.only(left: 16, right: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor, // Use theme card color
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pair: ${glasses['channelNumber']}',
                          style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color), // Use theme text color
                        ),
                        Text(
                          'Left: ${glasses['leftDeviceName']} \nRight: ${glasses['rightDeviceName']}',
                          style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color), // Use theme text color
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
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
  @override
  Widget build(BuildContext context) => Scaffold(
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
                  if (BleManager.get().getConnectionStatus() ==
                      'Not connected') {
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
                  child: Text(BleManager.get().getConnectionStatus(),
                      style: TextStyle(fontSize: 16, color: Theme.of(context).textTheme.bodyLarge?.color)), // Use theme text color
                ),
              ),
              const SizedBox(height: 16),
              if (BleManager.get().getConnectionStatus() == 'Not connected')
                blePairedList(),
              if (BleManager.get().isConnected)
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
                                        color: BleManager.get().isConnected
                                            ? Theme.of(context).textTheme.bodyLarge?.color // Use theme text color
                                            : Colors.grey.withOpacity(0.5)), // Keep grey for disconnected state
                                    textAlign: TextAlign.center,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

  @override
  void dispose() {
    scanTimer?.cancel();
    isScanning = false;
    BleManager.get().onStatusChanged = null;
    super.dispose();
  }
}
