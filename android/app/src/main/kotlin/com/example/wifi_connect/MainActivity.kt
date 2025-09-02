package com.example.wifi_connect

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.wifi/connect"
    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        Log.d("WifiConnect", "Configuring FlutterEngine and setting MethodChannel")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "connectToWifi") {
                val ssid = call.argument<String>("ssid")
                val password = call.argument<String>("password")

                Log.d("WifiConnect", "Received connectToWifi request - SSID: $ssid, Password: ${if (password != null) "******" else "null"}")

                if (ssid == null || password == null) {
                    Log.e("WifiConnect", "SSID or password is null")
                    result.error("INVALID_ARGS", "SSID or password missing", null)
                    return@setMethodCallHandler
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    connectToWifiOnAndroidQ(ssid, password)
                    Log.d("WifiConnect", "WiFi connection requested via WifiNetworkSpecifier")

                    // Return true immediately - connection is async
                    result.success(true)
                } else {
                    Log.e("WifiConnect", "Android version not supported for WifiNetworkSpecifier")
                    result.error("UNSUPPORTED_VERSION", "Android version does not support WifiNetworkSpecifier API", null)
                }
            } else {
                Log.w("WifiConnect", "Method not implemented: ${call.method}")
                result.notImplemented()
            }
        }
    }

    private fun connectToWifiOnAndroidQ(ssid: String, password: String) {
        Log.d("WifiConnect", "Starting WiFi connection for SSID: $ssid")

        // Unregister any previous callback to avoid leaks
        networkCallback?.let {
            try {
                connectivityManager?.unregisterNetworkCallback(it)
                Log.d("WifiConnect", "Unregistered previous network callback")
            } catch (e: Exception) {
                Log.e("WifiConnect", "Error unregistering previous callback: ${e.message}")
            }
        }

        val wifiNetworkSpecifier = WifiNetworkSpecifier.Builder()
            .setSsid(ssid)
            .setWpa2Passphrase(password)
            .build()

        val networkRequest = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .setNetworkSpecifier(wifiNetworkSpecifier)
            .build()

        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                Log.d("WifiConnect", "Network is available: $network")
                connectivityManager?.bindProcessToNetwork(network)
                Log.d("WifiConnect", "Bound process to network $network")
            }

            override fun onUnavailable() {
                Log.d("WifiConnect", "Network request is unavailable")
            }

            override fun onLost(network: Network) {
                Log.d("WifiConnect", "Network lost: $network")
                connectivityManager?.bindProcessToNetwork(null)
                Log.d("WifiConnect", "Unbound process from network")
            }

            override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
                Log.d("WifiConnect", "Network capabilities changed: $networkCapabilities")
            }

            override fun onBlockedStatusChanged(network: Network, blocked: Boolean) {
                Log.d("WifiConnect", "Network blocked status changed: $blocked")
            }
        }

        connectivityManager?.requestNetwork(networkRequest, networkCallback!!)
        Log.d("WifiConnect", "Network request submitted to ConnectivityManager")
    }
}
