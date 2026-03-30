package com.festisafe.festisafe

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Registrar plugin nativo de BLE Advertising
        flutterEngine.plugins.add(BleAdvertiserPlugin())
    }
}
