import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:get/get.dart';
import '../controllers/log_controller.dart';

// Basic structure for a discovered device representation
class DiscoveredDevice {
  final BluetoothDevice device;
  final ScanResult scanResult;
  // Add other relevant info like parsed name, channel number if needed

  DiscoveredDevice({required this.device, required this.scanResult});

  String get name => device.platformName.isNotEmpty ? device.platformName : "Unknown Device";
  String get id => device.remoteId.str;
}

class BluetoothService extends GetxService {
  final LogController _log = Get.find<LogController>();
  final RxList<DiscoveredDevice> discoveredDevices = <DiscoveredDevice>[].obs;
  final RxBool isScanning = false.obs;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;

  // --- Connection State ---
  final Rx<BluetoothDevice?> leftDevice = Rx<BluetoothDevice?>(null);
  final Rx<BluetoothDevice?> rightDevice = Rx<BluetoothDevice?>(null);
  final RxBool isLeftConnected = false.obs;
  final RxBool isRightConnected = false.obs;
  final RxString leftConnectionStatus = 'Left: Not Connected'.obs;
  final RxString rightConnectionStatus = 'Right: Not Connected'.obs;
  // --- End Connection State ---

  // TODO: Add methods for connecting, disconnecting, reading/writing characteristics

  @override
  void onInit() {
    super.onInit();
    _log.addLog("[BluetoothService] Initializing...");
    fetchSystemDevices(); // Fetch already connected devices
    _listenToAdapterState();
  }

  @override
  void onClose() {
    _log.addLog("[BluetoothService] Closing...");
    stopScan();
    _connectionStateSubscription?.cancel(); // Cancel connection listener
    _scanResultsSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    super.onClose();
  }

  void _listenToAdapterState() {
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      _log.addLog("[BluetoothService] Adapter State: ${state.toString()}");
      if (state == BluetoothAdapterState.off) {
        // Handle Bluetooth being turned off (e.g., clear devices, show message)
        discoveredDevices.clear();
        stopScan();
      } else if (state == BluetoothAdapterState.on) {
        // Fetch system devices when adapter turns on
        fetchSystemDevices();
      }
    });
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 15)}) async {
    if (isScanning.value) {
      _log.addLog("[BluetoothService] Scan already in progress.");
      return;
    }

    // Check adapter state
     if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
       _log.addLog("[BluetoothService] Bluetooth Adapter is off. Cannot start scan.");
       // Optionally request user to turn on Bluetooth
       return;
     }

    _log.addLog("[BluetoothService] Starting scan...");
    discoveredDevices.clear(); // Clear previous results
    isScanning.value = true;

    try {
      // Subscribe to scan results
      _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          // Filter devices - adjust this logic based on your device naming convention (e.g., G1_...)
          if (r.device.platformName.isNotEmpty /* && r.device.platformName.contains("G1_") */) {
             // Avoid duplicates
             if (!discoveredDevices.any((d) => d.id == r.device.remoteId.str)) {
                _log.addLog("[BluetoothService] Found: ${r.device.platformName} (${r.device.remoteId}) RSSI: ${r.rssi}");
                discoveredDevices.add(DiscoveredDevice(device: r.device, scanResult: r));
             }
          }
        }
      }, onError: (e) {
         _log.addLog("[BluetoothService] Scan Error: $e");
         stopScan(); // Stop scan on error
      });

      // Start scanning
      await FlutterBluePlus.startScan(timeout: timeout);

      // Wait for scan to complete (or timeout)
      await Future.delayed(timeout);
      stopScan();

    } catch (e) {
      _log.addLog("[BluetoothService] Error starting scan: $e");
      isScanning.value = false; // Ensure scanning state is reset
    }
  }

// --- Fetch System Connected Devices ---
Future<void> fetchSystemDevices() async {
  try {
    _log.addLog("[BluetoothService] Fetching system devices...");
    // Trying function call based on strange error message - this might be incorrect API usage
    List<BluetoothDevice> systemDevices = await FlutterBluePlus.systemDevices([]);
    _log.addLog("[BluetoothService] systemDevices call returned ${systemDevices.length} devices.");
    for (BluetoothDevice device in systemDevices) {
       // Check if it's already in our discovered list (maybe from a previous scan)
       if (!discoveredDevices.any((d) => d.id == device.remoteId.str)) {
          // Create a placeholder ScanResult as we don't have one from a scan
          // You might want to adjust DiscoveredDevice or handle this differently
          final placeholderScanResult = ScanResult(
            device: device,
            advertisementData: AdvertisementData(
              advName: device.platformName, // Use platformName if available
              txPowerLevel: null,
              connectable: true, // Assume connectable
              manufacturerData: {},
              serviceData: {},
              serviceUuids: [],
              appearance: null, // Add required appearance parameter (can be null)
            ),
            rssi: -100, // Placeholder RSSI
            timeStamp: DateTime.now(),
          );
           _log.addLog("[BluetoothService] Adding system device to discovered list: ${device.platformName} (${device.remoteId})");
           // Add with a way to potentially identify it as a system-found device if needed
           discoveredDevices.add(DiscoveredDevice(device: device, scanResult: placeholderScanResult));
       }
    }
  } catch (e) {
     _log.addLog("[BluetoothService] Error fetching system devices: $e");
  }
}

  Future<void> stopScan() async {
    if (!isScanning.value && !FlutterBluePlus.isScanningNow) return; // Avoid stopping if not scanning

    _log.addLog("[BluetoothService] Stopping scan...");
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
       _log.addLog("[BluetoothService] Error stopping scan: $e");
    } finally {
       isScanning.value = false;
       _scanResultsSubscription?.cancel(); // Cancel subscription
       _scanResultsSubscription = null;
    }
  }

  // --- Connection Logic ---
  Future<void> connectToDevice(DiscoveredDevice discovered, {required bool isLeft}) async {
    _log.addLog("[BluetoothService] Attempting to connect to ${discovered.name} (${discovered.id}) as ${isLeft ? 'Left' : 'Right'}...");
    if (isLeft && isLeftConnected.value && leftDevice.value?.remoteId == discovered.device.remoteId) {
      _log.addLog("[BluetoothService] Already connected to this device as Left.");
      return;
    } else if (!isLeft && isRightConnected.value && rightDevice.value?.remoteId == discovered.device.remoteId) {
      _log.addLog("[BluetoothService] Already connected to this device as Right.");
      return;
    }

    // Disconnect from any previous device on the same side
    if (isLeft) {
      await disconnectDevice(isLeft: true);
    } else {
      await disconnectDevice(isLeft: false);
    }

    if (isLeft) {
      leftConnectionStatus.value = 'Connecting to ${discovered.name}...';
    } else {
      rightConnectionStatus.value = 'Connecting to ${discovered.name}...';
    }
    _connectionStateSubscription = discovered.device.connectionState.listen((state) {
      _log.addLog("[BluetoothService] Connection state for ${discovered.name} (${isLeft ? 'Left' : 'Right'}): $state");
      switch (state) {
        case BluetoothConnectionState.connecting:
          if (isLeft) {
            leftConnectionStatus.value = 'Connecting to ${discovered.name}...';
            isLeftConnected.value = false;
          } else {
            rightConnectionStatus.value = 'Connecting to ${discovered.name}...';
            isRightConnected.value = false;
          }
          break;
        case BluetoothConnectionState.connected:
          if (isLeft) {
            leftConnectionStatus.value = 'Connected to ${discovered.name}';
            isLeftConnected.value = true;
            leftDevice.value = discovered.device;
          } else {
            rightConnectionStatus.value = 'Connected to ${discovered.name}';
            isRightConnected.value = true;
            rightDevice.value = discovered.device;
          }
          // TODO: Discover services after connection
          // _discoverServices(discovered.device);
          break;
        case BluetoothConnectionState.disconnecting:
          if (isLeft) {
            leftConnectionStatus.value = 'Disconnecting from ${discovered.name}...';
            isLeftConnected.value = false;
          } else {
            rightConnectionStatus.value = 'Disconnecting from ${discovered.name}...';
            isRightConnected.value = false;
          }
          break;
        case BluetoothConnectionState.disconnected:
          if (isLeft) {
            leftConnectionStatus.value = 'Left: Not Connected';
            isLeftConnected.value = false;
            leftDevice.value = null;
          } else {
            rightConnectionStatus.value = 'Right: Not Connected';
            isRightConnected.value = false;
            rightDevice.value = null;
          }
          _connectionStateSubscription?.cancel(); // Clean up listener
          _connectionStateSubscription = null;
          break;
      }
    });

    try {
      await discovered.device.connect(autoConnect: false); // Connect
    } catch (e) {
      _log.addLog("[BluetoothService] Error connecting to ${discovered.name}: $e");
      if (isLeft) {
        leftConnectionStatus.value = 'Left: Connection Failed';
      } else {
        rightConnectionStatus.value = 'Right: Connection Failed';
      }
      _connectionStateSubscription?.cancel();
      _connectionStateSubscription = null;
    }
  }

  Future<void> disconnectDevice({required bool isLeft}) async {
    if (isLeft && leftDevice.value != null) {
       _log.addLog("[BluetoothService] Disconnecting from Left: ${leftDevice.value!.platformName}...");
       try {
          await leftDevice.value!.disconnect();
          // State update handled by the connectionState listener
       } catch (e) {
          _log.addLog("[BluetoothService] Error disconnecting Left: $e");
          // Force state update if disconnect fails unexpectedly
          leftConnectionStatus.value = 'Left: Disconnection Failed';
          isLeftConnected.value = false; // Assume disconnected on error
          leftDevice.value = null;
          _connectionStateSubscription?.cancel();
          _connectionStateSubscription = null;
       }
    } else if (!isLeft && rightDevice.value != null) {
       _log.addLog("[BluetoothService] Disconnecting from Right: ${rightDevice.value!.platformName}...");
       try {
          await rightDevice.value!.disconnect();
          // State update handled by the connectionState listener
       } catch (e) {
          _log.addLog("[BluetoothService] Error disconnecting Right: $e");
          // Force state update if disconnect fails unexpectedly
          rightConnectionStatus.value = 'Right: Disconnection Failed';
          isRightConnected.value = false; // Assume disconnected on error
          rightDevice.value = null;
          _connectionStateSubscription?.cancel();
          _connectionStateSubscription = null;
       }
    } else {
       // Ensure state is clean if called when not connected
       if (isLeft) {
         leftConnectionStatus.value = 'Left: Not Connected';
         isLeftConnected.value = false;
       } else {
         rightConnectionStatus.value = 'Right: Not Connected';
         isRightConnected.value = false;
       }
       _connectionStateSubscription?.cancel();
       _connectionStateSubscription = null;
    }
  }

}