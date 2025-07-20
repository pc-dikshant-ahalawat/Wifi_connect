import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';

void main() {
  runApp(const MaterialApp(home: HomeScreen()));
}

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
  bool showNetworks = false;
  bool scanning = false;

  @override
  void initState() {
    super.initState();
    _updateConnectionStatus();
  }

  Future<void> _updateConnectionStatus() async {
    final ssid = await WiFiForIoTPlugin.getSSID();
    setState(() {
      connectedSSID = ssid?.replaceAll('"', '');
    });
  }

  Future<Position> _getCurrentLocation() async {
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<void> _scanAndLoadNetworks() async {
    setState(() {
      scanning = true;
      showNetworks = false;
      matchedNetworks.clear();
    });

    await [
      Permission.location,
      Permission.locationWhenInUse,
    ].request();

    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
      return;
    }

    try {
      final Position position = await _getCurrentLocation();
      final String jsonString =
          await rootBundle.loadString('assets/wifi_db.json');
      final List<dynamic> jsonData = json.decode(jsonString);

      final List<WifiNetwork> dbNetworks = jsonData
          .map((e) => WifiNetwork.fromJson(e as Map<String, dynamic>))
          .toList();

      final scanned = await WiFiForIoTPlugin.loadWifiList();
      final List<WifiNetwork> resultList = [];

      for (final s in scanned) {
        if (s.ssid == null) continue;

        for (final db in dbNetworks) {
          if (s.ssid == db.ssid) {
            final double distance = Geolocator.distanceBetween(
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        scanning = false;
      });
    }
  }

  void _promptPassword(WifiNetwork network) {
    final TextEditingController controller = TextEditingController();
    final decodedPassword =
        utf8.decode(base64Decode(network.passwordEncrypted));

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Enter Password for ${network.ssid}'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(hintText: "Password"),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              if (controller.text == decodedPassword) {
                final success = await WiFiForIoTPlugin.connect(
                  network.ssid,
                  password: decodedPassword,
                  security: NetworkSecurity.WPA,
                  joinOnce: true,
                );
                await _updateConnectionStatus();
                setState(() {
                  isConnected = success;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Connected to ${network.ssid}'
                          : 'Connection failed',
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Incorrect password')),
                );
              }
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
      appBar: AppBar(title: const Text('Nearby WiFi Networks')),
      body: scanning
          ? const Center(child: CircularProgressIndicator())
          : !showNetworks
              ? Center(
                  child: ElevatedButton(
                    onPressed: _scanAndLoadNetworks,
                    child: const Text('Scan & Connect to WiFi'),
                  ),
                )
              : matchedNetworks.isEmpty
                  ? const Center(child: Text("No nearby Wi-Fi found."))
                  : ListView.builder(
                      itemCount: matchedNetworks.length,
                      itemBuilder: (context, index) {
                        final network = matchedNetworks[index];
                        final alreadyConnected =
                            connectedSSID == network.ssid && isConnected;

                        return ListTile(
                          title: Text(network.ssid),
                          subtitle: Text(
                              'Lat: ${network.latitude}, Lng: ${network.longitude}'),
                          trailing: ElevatedButton(
                            onPressed: alreadyConnected
                                ? null
                                : () => _promptPassword(network),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  alreadyConnected ? Colors.grey : null,
                            ),
                            child: Text(alreadyConnected
                                ? 'Connected'
                                : 'Connect'),
                          ),
                        );
                      },
                    ),
    );
  }
}
