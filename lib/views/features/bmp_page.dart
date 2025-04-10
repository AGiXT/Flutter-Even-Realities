// ignore_for_file: library_private_types_in_public_api

// import 'package:agixt_even_realities/ble_manager.dart'; // Removed old import
import 'package:agixt_even_realities/services/features_services.dart';
import 'package:flutter/material.dart';
import 'package:agixt_even_realities/services/bluetooth_service.dart'; // Import BluetoothService
import 'package:get/get.dart'; // Import Get

class BmpPage extends StatefulWidget {
  const BmpPage({super.key});

  @override
  _BmpState createState() => _BmpState();
}

class _BmpState extends State<BmpPage> {
  final BluetoothService bluetoothService = Get.find<BluetoothService>(); // Get BluetoothService instance
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('BMP'),
        ),
        body: Padding(
          padding:
              const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 44),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () async {
                  // TODO: Replace with BluetoothService connection check
                  if (false /* !bluetoothService.isConnected.value */) return; // Placeholder
                  print("${DateTime.now()} to show bmp1-----------");
                  FeaturesServices().sendBmp("assets/images/image_1.bmp");
                },
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor, // Use theme card color
                    borderRadius: BorderRadius.circular(5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    "BMP 1",
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).textTheme.bodyLarge?.color // Use theme text color
                    )
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  // TODO: Replace with BluetoothService connection check
                  if (false /* !bluetoothService.isConnected.value */) return; // Placeholder
                  print("${DateTime.now()} to show bmp2-----------");
                  FeaturesServices().sendBmp("assets/images/image_2.bmp");
                },
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor, // Use theme card color
                    borderRadius: BorderRadius.circular(5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    "BMP 2",
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).textTheme.bodyLarge?.color // Use theme text color
                    )
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  // TODO: Replace with BluetoothService connection check
                  if (false /* !bluetoothService.isConnected.value */) return; // Placeholder
                  FeaturesServices().exitBmp(); // todo
                },
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor, // Use theme card color
                    borderRadius: BorderRadius.circular(5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    "Exit",
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).textTheme.bodyLarge?.color // Use theme text color
                    )
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
