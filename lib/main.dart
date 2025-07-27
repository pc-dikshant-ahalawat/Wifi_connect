import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

void main() {
  runApp(const MaterialApp(home: HomeScreen()));
}
//Wifi NetwOrk model
class WifiNetwork {
  final String ssid;
  final String passwordEncrypted;
  final double latitude;
  final double longitude;

  WifiNetwork({
    required this.ssid,
    required this.passwordEncrypted,
    required this.latitude,
    required this.longitude,
  });

  factory WifiNetwork.fromJson(Map<String, dynamic> json) {
    final location = json['location'];
    return WifiNetwork(
      ssid: json['ssid'] ?? '',
      passwordEncrypted: json['password_encrypted'] ?? '',
      latitude: (location['latitude'] as num).toDouble(),
      longitude: (location['longitude'] as num).toDouble(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<WifiNetwork> matchedNetworks = [];
  String? connectedSSID;
  bool isConnected = false;
  bool hasInternet = false;
  bool showNetworks = false;
  bool scanning = false;
  Position? currentPosition;
  String? errorMessage;
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _updateConnectionStatus();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
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
      final ssid = await WiFiForIoTPlugin.getSSID();
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
      // Try multiple endpoints to confirm internet access
      final results = await Future.wait([
        InternetAddress.lookup('google.com'),
        InternetAddress.lookup('microsoft.com'),
        InternetAddress.lookup('example.com'),
      ]);
      return results.any((list) => list.isNotEmpty && list[0].rawAddress.isNotEmpty);
    } on SocketException catch (_) {
      return false;
    }
  }

  Future<Position> _getCurrentLocation() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 15),
      );
    } on TimeoutException {
      final lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null) {
        return lastPosition;
      }
      throw Exception('Could not determine current location');
    }
  }

  Future<void> _scanAndLoadNetworks() async {
    setState(() {
      scanning = true;
      showNetworks = false;
      matchedNetworks.clear();
      errorMessage = null;
    });

    try {
      final status = await Permission.location.request();
      if (!status.isGranted) {
        throw Exception('Location permission denied');
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
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

      final position = await _getCurrentLocation();
      setState(() => currentPosition = position);

      final jsonString = await rootBundle.loadString('assets/wifi_db.json');
      final jsonData = json.decode(jsonString) as List;

      final dbNetworks = jsonData
          .map((e) => WifiNetwork.fromJson(e as Map<String, dynamic>))
          .toList();

      final scanned = await WiFiForIoTPlugin.loadWifiList();
      final resultList = <WifiNetwork>[];

      for (final s in scanned) {
        if (s.ssid == null) continue;

        for (final db in dbNetworks) {
          if (s.ssid == db.ssid) {
            final distance = Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              db.latitude,
              db.longitude,
            );

            if (distance <= 100) {
              resultList.add(db);
            }
          }
        }
      }

      setState(() {
        matchedNetworks = resultList;
        showNetworks = true;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => scanning = false);
      }
    }
  }

  Future<void> _connectToNetwork(WifiNetwork network) async {
    try {
      final decodedPassword = utf8.decode(base64Decode(network.passwordEncrypted));
      
      // First disconnect from current network if connected
      if (await WiFiForIoTPlugin.isConnected()) {
        await WiFiForIoTPlugin.disconnect();
        await Future.delayed(const Duration(seconds: 1));
      }

      final success = await WiFiForIoTPlugin.connect(
        network.ssid,
        password: decodedPassword,
        security: NetworkSecurity.WPA,
        joinOnce: false,
      ).timeout(const Duration(seconds: 15));

      // Wait for network to stabilize
      await Future.delayed(const Duration(seconds: 2));
      await _updateConnectionStatus();

      // Verify internet access with multiple checks
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
              ? internetVerified
                  ? 'Connected to ${network.ssid} with internet'
                  : 'Connected to ${network.ssid} but no internet'
              : 'Failed to connect to ${network.ssid}'),
          backgroundColor: success 
              ? (internetVerified ? Colors.green : Colors.orange) 
              : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );

      if (success && !internetVerified) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('No Internet Access'),
            content: const Text('The WiFi network has no internet connection. '
                'Make sure your hotspot has mobile data enabled.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
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

  void _promptPassword(WifiNetwork network) {
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
              color: Colors.red[100],
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
                              final isCurrent = connectedSSID == network.ssid && isConnected;
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
                                          ? (hasInternet ? Colors.green : Colors.orange)
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