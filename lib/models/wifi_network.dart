class WifiNetwork {
  final String ssid;
  final String bssid;
  final String passwordEncrypted;
  final double latitude;
  final double longitude;

  WifiNetwork({
    required this.ssid,
    required this.bssid,
    required this.passwordEncrypted,
    required this.latitude,
    required this.longitude,
  });

  factory WifiNetwork.fromJson(Map<String, dynamic> json) {
  final location = json['location'] as Map<String, dynamic>;
  return WifiNetwork(
    ssid: json['ssid'] as String? ?? '',
    passwordEncrypted: json['password_encrypted'] as String? ?? '',
    bssid: (json['bssid'] as String? ?? '').trim(),
    latitude: (location['latitude'] as num).toDouble(),
    longitude: (location['longitude'] as num).toDouble(),
  );
}
}
