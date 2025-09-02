import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:wifi_iot/wifi_iot.dart' as wifi_iot;

import '../models/wifi_network.dart' as my_models;
import '../services/location_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const platform = MethodChannel('com.example.wifi/connect');

  List<my_models.WifiNetwork> matchedNetworks = [];
  String? connectedSSID;
  bool isConnected = false;
  bool hasInternet = false;
  bool showNetworks = false;
  bool scanning = false;
  Position? currentPosition;
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

  Future<void> _scanAndLoadNetworks() async {
  setState(() {
    scanning = true;
    showNetworks = false;
    matchedNetworks.clear();
    errorMessage = null;
  });

  print('DEBUG: Starting scan...');

  try {
    final status = await Permission.location.request();
    print('DEBUG: Location permission status: ${status.isGranted}');
    if (!status.isGranted) {
      throw Exception('Location permission denied');
    }

    final locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    print('DEBUG: Location services enabled: $locationServiceEnabled');
    if (!locationServiceEnabled) {
      final shouldOpenSettings = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Location Services Disabled'),
          content: const Text('Please enable location services to scan networks'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enable'),
            ),
          ],
        ),
      );
      print('DEBUG: User chose to open location settings: $shouldOpenSettings');
      if (shouldOpenSettings == true) {
        await Geolocator.openLocationSettings();
        await Future.delayed(const Duration(seconds: 2));
        if (!await Geolocator.isLocationServiceEnabled()) {
          throw Exception('Location services still disabled');
        }
      } else {
        throw Exception('Location services disabled');
      }
    }

    final position = await LocationHelper.getCurrentLocation();
    print('DEBUG: Current position: ${position.latitude}, ${position.longitude}');
    setState(() => currentPosition = position);

    final jsonString = await rootBundle.loadString('assets/wifi_db.json');
    final jsonData = json.decode(jsonString) as List;
    final dbNetworks = jsonData
        .map((e) => my_models.WifiNetwork.fromJson(e as Map<String, dynamic>))
        .toList();
    print('DEBUG: Loaded ${dbNetworks.length} networks from DB');

    final scanned = await wifi_iot.WiFiForIoTPlugin.loadWifiList();
    print('DEBUG: Scanned WiFi networks count: ${scanned.length}');
    for (var s in scanned) {
      print('DEBUG: Scanned SSID: ${s.ssid}, BSSID: ${s.bssid}');
    }

    final resultList = <my_models.WifiNetwork>[];
    for (final s in scanned) {
      if (s.ssid == null) continue;
      for (final db in dbNetworks) {
        print('DEBUG: Matching scanned SSID: ${s.ssid} with DB SSID: ${db.ssid}');
        print('DEBUG: Comparing BSSID: scanned=${s.bssid}, db=${db.bssid}');
        final scannedBssid = s.bssid?.toLowerCase().trim() ?? '';
final dbBssid = db.bssid?.toLowerCase().trim() ?? '';
final scannedSsid = s.ssid?.trim() ?? '';
final dbSsid = db.ssid?.trim() ?? '';
dbNetworks.forEach((db) {
  print('DB Network SSID: "${db.ssid}", BSSID: "${db.bssid}"');
});

        if (scannedSsid == dbSsid && scannedBssid == dbBssid) {
          final distance = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            db.latitude,
            db.longitude,
          );
          print('DEBUG: Distance to network: ${distance.toStringAsFixed(2)}m');
          if (distance <= 500) {
            print('DEBUG: Network within distance, adding to matched list');
            resultList.add(db);
          } else {
            print('DEBUG: Network too far, skipping');
          }
        }
      }
    }

    print('DEBUG: Total matched networks: ${resultList.length}');
    setState(() {
      matchedNetworks = resultList;
      showNetworks = true;
    });
  } catch (e) {
    setState(() {
      errorMessage = e.toString();
    });
    print('DEBUG: Exception during scan: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  } finally {
    if (mounted) {
      setState(() => scanning = false);
    }
    print('DEBUG: Scan complete.');
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
        title: const Text('Nearby WiFi Networks'),
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
              color: Colors.red,
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(child: Text(errorMessage!)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => errorMessage = null),
                  ),
                ],
              ),
            ),
          if (currentPosition != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Current location: ${currentPosition!.latitude.toStringAsFixed(4)}, '
                '${currentPosition!.longitude.toStringAsFixed(4)}',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          Expanded(
            child: scanning
                ? const Center(child: CircularProgressIndicator())
                : !showNetworks
                    ? Center(
                        child: ElevatedButton(
                          onPressed: _scanAndLoadNetworks,
                          child: const Text('Scan Nearby WiFi Networks'),
                        ),
                      )
                    : matchedNetworks.isEmpty
                        ? const Center(child: Text("No nearby Wi-Fi found"))
                        : ListView.builder(
                            itemCount: matchedNetworks.length,
                            itemBuilder: (context, index) {
                              final network = matchedNetworks[index];
                              final isCurrent =
                                  connectedSSID == network.ssid && isConnected;
                              final distance = currentPosition != null
                                  ? '${Geolocator.distanceBetween(
                                              currentPosition!.latitude,
                                              currentPosition!.longitude,
                                              network.latitude,
                                              network.longitude,
                                            ).toStringAsFixed(0)}m'
                                  : '?';

                              return Card(
                                margin: const EdgeInsets.all(8),
                                child: ListTile(
                                  title: Text(network.ssid),
                                  subtitle: Text(distance),
                                  trailing: IconButton(
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
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _scanAndLoadNetworks,
        tooltip: 'Rescan',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
