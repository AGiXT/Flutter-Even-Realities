// import 'package:agixt_even_realities/ble_manager.dart'; // Removed old import
import 'package:agixt_even_realities/services/text_service.dart';
import 'package:flutter/material.dart';
import 'package:agixt_even_realities/services/bluetooth_service.dart'; // Import BluetoothService
import 'package:get/get.dart'; // Import Get
class TextPage extends StatefulWidget {
  const TextPage({super.key});

  @override
  _TextPageState createState() => _TextPageState();
}

class _TextPageState extends State<TextPage> {
  final BluetoothService bluetoothService = Get.find<BluetoothService>(); // Get BluetoothService instance

  late TextEditingController tfController;

  String testContent = '''Welcome to G1.

    You're holding the first eyewear ever designed to blend stunning aesthetics, amazing wearability and useful functionality.

    At Even Realities we continuously explore the human relationship with technology. And our breakthrough is a pair of glasses that are unique, clever and capable but are still everyday glasses. The ones you'll reach for every morning and want to wear all day.

    No longer is being connected or focused on real life a choice. It's a seamless blend. A merging of worlds, with you in control.

    So you can see what matters. When it matters.''';

  @override
  void initState() {
    tfController = TextEditingController(text: testContent); 
    super.initState();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Text Transfer'),
    ),
    body: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            height: 300,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor, // Use theme card color
              borderRadius: BorderRadius.circular(5),
            ),
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: const InputDecoration.collapsed(hintText: ""),
              controller: tfController,
              onChanged: (newNotify) => setState(() {}),
              maxLines: null,
            ),
          ),
          GestureDetector(
            // TODO: Replace with BluetoothService connection check
            onTap: false /* !bluetoothService.isConnected.value */ && tfController.text.isNotEmpty // Placeholder
              ? null
              : () async {
                String content = tfController.text;
                TextService.get.startSendText(content);
              },
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor, // Use theme card color
                borderRadius: BorderRadius.circular(5),
              ),
              alignment: Alignment.center,
              child: Text(
                "Send to Glasses",
                style: TextStyle(
                  // TODO: Replace with BluetoothService connection check
                  color: false /* bluetoothService.isConnected.value */ && tfController.text.isNotEmpty // Placeholder
                      ? Theme.of(context).textTheme.bodyLarge?.color
                    : Colors.grey, // Keep grey for disabled state
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
