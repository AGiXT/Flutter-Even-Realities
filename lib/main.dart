import 'package:agixt_even_realities/ble_manager.dart';
import 'package:agixt_even_realities/controllers/evenai_model_controller.dart';
import 'package:agixt_even_realities/views/home_page.dart';
import 'package:agixt_even_realities/views/login_page.dart';
import 'package:agixt_even_realities/views/register_page.dart';
import 'package:agixt_even_realities/views/server_config_page.dart';
import 'package:agixt_even_realities/views/extensions_page.dart';
import 'package:agixt_even_realities/controllers/auth_controller.dart';
import 'package:agixt_even_realities/controllers/server_config_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

void main() {
  // Initialize controllers
  BleManager.get();
  Get.put(EvenaiModelController());
  Get.put(ServerConfigController());
  Get.put(AuthController()); // Add AuthController initialization back
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final darkTheme = ThemeData.dark().copyWith(
    primaryColor: Colors.blue,
    scaffoldBackgroundColor: const Color(0xFF1A1A1A),
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xFF2D2D2D),
      elevation: 0,
    ),
    cardTheme: CardTheme(
      color: const Color(0xFF2D2D2D),
      elevation: 4,
    ),
    inputDecorationTheme: InputDecorationTheme(
      fillColor: const Color(0xFF2D2D2D),
      filled: true,
      border: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.grey[800]!),
        borderRadius: BorderRadius.circular(8),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.grey[800]!),
        borderRadius: BorderRadius.circular(8),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.blue),
        borderRadius: BorderRadius.circular(8),
      ),
      labelStyle: TextStyle(color: Colors.grey[400]),
      hintStyle: TextStyle(color: Colors.grey[600]),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 4,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colors.blue,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'AGiXT Even Realities',
      theme: darkTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.dark,
      initialRoute: '/config',
      getPages: [
        GetPage(name: '/config', page: () => ServerConfigPage()),
        GetPage(name: '/login', page: () => LoginPage()),
        GetPage(name: '/register', page: () => RegisterPage()),
        GetPage(name: '/home', page: () => HomePage()),
        GetPage(name: '/extensions', page: () => ExtensionsPage()),
      ],
    );
  }
}
