package com.example.demo_ai_even

import android.os.Bundle
import android.util.Log
import com.example.demo_ai_even.cpp.Cpp // Keep Cpp import if needed elsewhere
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
// Remove BlePermissionUtil import
import io.flutter.plugin.common.EventChannel

class MainActivity: FlutterActivity(), EventChannel.StreamHandler {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Cpp.init()
        // BleManager.instance.initBluetooth(this) // Remove BleManager init
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // BleChannelHelper.initChannel(this, flutterEngine) // Remove BleChannelHelper init
    }

    /// Interface - EventChannel.StreamHandler
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        Log.i(this::class.simpleName,"EventChannel.StreamHandler - OnListen: arguments = $arguments ,events = $events")
        // BleChannelHelper.addEventSink(arguments as String?, events) // Remove BleChannelHelper call
    }

    /// Interface - EventChannel.StreamHandler
    override fun onCancel(arguments: Any?) {
        Log.i(this::class.simpleName,"EventChannel.StreamHandler - OnCancel: arguments = $arguments")
        // BleChannelHelper.removeEventSink(arguments as String?) // Remove BleChannelHelper call
    }

}
