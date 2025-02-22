import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';

class ExtensionsPage extends StatefulWidget {
  const ExtensionsPage({super.key});

  @override
  _ExtensionsPageState createState() => _ExtensionsPageState();
}

class _ExtensionsPageState extends State<ExtensionsPage> {
  List<String> extensions = [];
  List<bool> isEnabled = [];
  late final AuthController authController;

  @override
  void initState() {
    super.initState();
    authController = Get.find<AuthController>();
    _loadExtensions();
  }

  Future<void> _loadExtensions() async {
    try {
      if (authController.sdk.value == null) {
        print('SDK not initialized');
        return;
      }
      
      final extensionList = await authController.sdk.value!.getExtensions();
      setState(() {
        extensions = extensionList.map((e) => e['name'].toString()).toList().cast<String>();
        isEnabled = List.generate(extensions.length, (index) => false);
      });
    } catch (e) {
      print('Error loading extensions: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Extensions'),
      ),
      body: Obx(() => authController.sdk.value == null
        ? const Center(
            child: Text('SDK not initialized'),
          )
        : ListView.builder(
            itemCount: extensions.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(extensions[index]),
                trailing: Switch(
                  value: isEnabled[index],
                  onChanged: (value) {
                    setState(() {
                      isEnabled[index] = value;
                    });
                  },
                ),
              );
            },
          ),
      ),
    );
  }
}