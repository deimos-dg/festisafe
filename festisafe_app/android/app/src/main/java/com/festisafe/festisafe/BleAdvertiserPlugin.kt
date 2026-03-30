package com.festisafe.festisafe

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.ParcelUuid
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * Plugin nativo para BLE Advertising en Android.
 * Permite que el dispositivo se anuncie como un nodo FestiSafe
 * para que otros miembros del grupo puedan detectarlo.
 *
 * Canal: com.festisafe/ble_advertiser
 * Métodos:
 *   - startAdvertising(payload: ByteArray) → void
 *   - stopAdvertising() → void
 *   - isSupported() → Boolean
 */
class BleAdvertiserPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private var advertiser: BluetoothLeAdvertiser? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var context: Context? = null

    companion object {
        private const val TAG = "BleAdvertiser"
        private const val CHANNEL = "com.festisafe/ble_advertiser"
        // UUID del servicio FestiSafe — debe coincidir con ble_service.dart
        private const val SERVICE_UUID = "f3e5a1b0-1234-5678-abcd-festisafe0001"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopAdvertising()
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startAdvertising" -> {
                val payload = call.argument<ByteArray>("payload")
                startAdvertising(payload, result)
            }
            "stopAdvertising" -> {
                stopAdvertising()
                result.success(null)
            }
            "isSupported" -> {
                result.success(isAdvertisingSupported())
            }
            else -> result.notImplemented()
        }
    }

    private fun isAdvertisingSupported(): Boolean {
        val ctx = context ?: return false
        val btManager = ctx.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val adapter = btManager?.adapter ?: return false
        return adapter.isEnabled && adapter.bluetoothLeAdvertiser != null
    }

    private fun startAdvertising(payload: ByteArray?, result: MethodChannel.Result) {
        if (!isAdvertisingSupported()) {
            result.error("NOT_SUPPORTED", "BLE advertising no soportado en este dispositivo", null)
            return
        }

        val ctx = context ?: run {
            result.error("NO_CONTEXT", "Contexto no disponible", null)
            return
        }

        val btManager = ctx.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        advertiser = btManager.adapter.bluetoothLeAdvertiser

        // Detener advertising anterior si existe
        stopAdvertising()

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_POWER)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_LOW)
            .setConnectable(false)
            .setTimeout(0) // 0 = sin timeout
            .build()

        val dataBuilder = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(UUID.fromString(SERVICE_UUID)))

        // Agregar payload como service data (máx ~20 bytes en BLE)
        if (payload != null && payload.isNotEmpty()) {
            val truncated = if (payload.size > 20) payload.copyOf(20) else payload
            dataBuilder.addServiceData(ParcelUuid(UUID.fromString(SERVICE_UUID)), truncated)
        }

        advertiseCallback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                Log.d(TAG, "BLE advertising iniciado correctamente")
            }

            override fun onStartFailure(errorCode: Int) {
                val msg = when (errorCode) {
                    ADVERTISE_FAILED_DATA_TOO_LARGE -> "Payload demasiado grande"
                    ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "Demasiados advertisers activos"
                    ADVERTISE_FAILED_ALREADY_STARTED -> "Ya está en advertising"
                    ADVERTISE_FAILED_INTERNAL_ERROR -> "Error interno de BLE"
                    ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "Feature no soportada"
                    else -> "Error desconocido: $errorCode"
                }
                Log.e(TAG, "BLE advertising falló: $msg")
            }
        }

        try {
            advertiser?.startAdvertising(settings, dataBuilder.build(), advertiseCallback)
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Excepción al iniciar advertising: ${e.message}")
            result.error("ADVERTISE_ERROR", e.message, null)
        }
    }

    private fun stopAdvertising() {
        try {
            advertiseCallback?.let { cb ->
                advertiser?.stopAdvertising(cb)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error al detener advertising: ${e.message}")
        } finally {
            advertiseCallback = null
        }
    }
}
