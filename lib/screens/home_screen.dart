import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:wifi_iot/wifi_iot.dart' as wifi_iot;

import '../models/wifi_network.dart' as my_models;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const platform = MethodChannel('com.example.wifi/connect');

  List<my_models.WifiNetwork> availableNetworks = [];
  String? connectedSSID;
  bool isConnected = false;
  bool hasInternet = false;
  bool showNetworks = false;
  bool loading = false;
  String? errorMessage;
  final Connectivity _connectivity = Connectivity();
  late final StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _updateConnectionStatus();
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  Future<void> _initConnectivity() async {
    try {
      final List<ConnectivityResult> result = await _connectivity.checkConnectivity();
      await _updateConnectionStatus(result);
    } on PlatformException catch (e) {
      debugPrint('Could not check connectivity status: $e');
    }
  }

  Future<void> _updateConnectionStatus([List<ConnectivityResult>? results]) async {
    results ??= await _connectivity.checkConnectivity();

    try {
      final ssid = await wifi_iot.WiFiForIoTPlugin.getSSID();
      setState(() {
        connectedSSID = ssid?.replaceAll('"', '');
        isConnected = connectedSSID != null;
        hasInternet = results!.contains(ConnectivityResult.wifi) ||
            results.contains(ConnectivityResult.mobile);
      });
    } on PlatformException catch (e) {
      setState(() {
        errorMessage = 'Failed to check connection: ${e.message}';
      });
    }
  }

  Future<bool> _verifyInternetAccess() async {
    try {
      final results = await Future.wait([
        InternetAddress.lookup('google.com'),
        InternetAddress.lookup('microsoft.com'),
        InternetAddress.lookup('example.com'),
      ]);
      return results.any((list) => list.isNotEmpty && list[0].rawAddress.isNotEmpty);
    } on SocketException {
      return false;
    }
  }

  Future<void> _loadNetworks() async {
    setState(() {
      loading = true;
      showNetworks = false;
      availableNetworks.clear();
      errorMessage = null;
    });

    try {
      // Load all networks from JSON file
      final jsonString = await rootBundle.loadString('assets/wifi_db.json');
      final jsonData = json.decode(jsonString) as List;
      final networks = jsonData
          .map((e) => my_models.WifiNetwork.fromJson(e as Map<String, dynamic>))
          .toList();

      setState(() {
        availableNetworks = networks;
        showNetworks = true;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading networks: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }


  Future<bool> _connectToWifiAndroid(String ssid, String password) async {
    try {
      final bool result = await platform.invokeMethod('connectToWifi', {
        'ssid': ssid,
        'password': password,
      });
      return result;
    } on PlatformException {
      return false;
    }
  }

  Future<void> _connectToNetwork(my_models.WifiNetwork network) async {
    final decodedPassword = utf8.decode(base64Decode(network.passwordEncrypted));
    if (Platform.isAndroid) {
      final success = await _connectToWifiAndroid(network.ssid, decodedPassword);

      await Future.delayed(const Duration(seconds: 2));
      await _updateConnectionStatus();

      bool internetVerified = false;
      for (int i = 0; i < 3; i++) {
        if (await _verifyInternetAccess()) {
          internetVerified = true;
          break;
        }
        await Future.delayed(const Duration(seconds: 1));
      }

      if (!mounted) return;
      setState(() => hasInternet = internetVerified);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? (internetVerified
                  ? 'Connected to ${network.ssid} with internet'
                  : 'Connected to ${network.ssid} but no internet')
              : 'Failed to connect to ${network.ssid}'),
          backgroundColor: success
              ? (internetVerified ? Colors.green : Colors.orange)
              : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      try {
        if (await wifi_iot.WiFiForIoTPlugin.isConnected()) {
          await wifi_iot.WiFiForIoTPlugin.disconnect();
          await Future.delayed(const Duration(seconds: 1));
        }

        final success = await wifi_iot.WiFiForIoTPlugin.connect(
          network.ssid,
          password: decodedPassword,
          security: wifi_iot.NetworkSecurity.WPA,
          joinOnce: false,
        ).timeout(const Duration(seconds: 15));

        await Future.delayed(const Duration(seconds: 2));
        await _updateConnectionStatus();

        bool internetVerified = false;
        for (int i = 0; i < 3; i++) {
          if (await _verifyInternetAccess()) {
            internetVerified = true;
            break;
          }
          await Future.delayed(const Duration(seconds: 1));
        }

        if (!mounted) return;
        setState(() => hasInternet = internetVerified);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? (internetVerified
                    ? 'Connected to ${network.ssid} with internet'
                    : 'Connected to ${network.ssid} but no internet')
                : 'Failed to connect to ${network.ssid}'),
            backgroundColor: success
                ? (internetVerified ? Colors.green : Colors.orange)
                : Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      } on TimeoutException {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection timed out'),
            backgroundColor: Colors.red,
          ),
        );
      } on PlatformException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _promptPassword(my_models.WifiNetwork network) {
    final decodedPassword = utf8.decode(base64Decode(network.passwordEncrypted));
    final controller = TextEditingController(text: decodedPassword);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Connect to ${network.ssid}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: decodedPassword));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password copied to clipboard')),
                );
              },
              child: const Text('Copy Password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _connectToNetwork(network);
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Available WiFi Networks'),
        actions: [
          if (connectedSSID != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Chip(
                label: Text(
                  connectedSSID!.length > 12
                      ? '${connectedSSID!.substring(0, 12)}...'
                      : connectedSSID!,
                ),
                backgroundColor: isConnected
                    ? (hasInternet ? Colors.green : Colors.orange)
                    : Colors.grey,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (errorMessage != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.red.shade100,
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(child: Text(errorMessage!, style: const TextStyle(color: Colors.red))),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => setState(() => errorMessage = null),
                  ),
                ],
              ),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : !showNetworks
                    ? Center(
                        child: ElevatedButton(
                          onPressed: _loadNetworks,
                          child: const Text('Load Available WiFi Networks'),
                        ),
                      )
                    : availableNetworks.isEmpty
                        ? const Center(child: Text("No networks available"))
                        : ListView.builder(
                            itemCount: availableNetworks.length,
                            itemBuilder: (context, index) {
                              final network = availableNetworks[index];
                              final isCurrent =
                                  connectedSSID == network.ssid && isConnected;
                              final decodedPassword = utf8.decode(base64Decode(network.passwordEncrypted));

                              return Card(
                                margin: const EdgeInsets.all(8),
                                child: ListTile(
                                  title: Text(
                                    network.ssid,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Password: $decodedPassword'),
                                      if (network.bssid != null)
                                        Text('BSSID: ${network.bssid}',
                                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.copy, color: Colors.blue),
                                        onPressed: () async {
                                          await Clipboard.setData(ClipboardData(text: decodedPassword));
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Password copied to clipboard')),
                                          );
                                        },
                                        tooltip: 'Copy Password',
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          isCurrent ? Icons.wifi : Icons.wifi_find,
                                          color: isCurrent
                                              ? (hasInternet
                                                  ? Colors.green
                                                  : Colors.orange)
                                              : null,
                                        ),
                                        onPressed: isCurrent
                                            ? null
                                            : () => _promptPassword(network),
                                        tooltip: isCurrent ? 'Connected' : 'Connect',
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadNetworks,
        tooltip: 'Refresh',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
