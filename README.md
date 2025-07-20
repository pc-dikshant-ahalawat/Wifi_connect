📶 WiFi Connect App
A simple Flutter app to scan and connect to available Wi-Fi networks programmatically.

🛠️ IDE, Packages & Plugins Used
IDE: Visual Studio Code

Flutter SDK: 3.7.2

Main Plugins:

wifi_iot: To scan and connect to Wi-Fi networks

permission_handler: To manage runtime permissions

location: To request location access (required for Wi-Fi scanning)

📱 Platform Support
✅ Android
Works on Android 6.0+

For Android 10+ (API 29+), due to platform limitations:

Internet access may not be routed through the programmatically connected Wi-Fi (you may need platform channels to bind network)

Fine and coarse location permissions are mandatory

🚫 iOS
Not supported

iOS does not allow programmatic connection to Wi-Fi networks due to App Store policy and platform restrictions.

🔐 Permissions Handling
On first launch, the app requests the following permissions:

ACCESS_FINE_LOCATION and/or ACCESS_COARSE_LOCATION

CHANGE_WIFI_STATE, ACCESS_WIFI_STATE, and INTERNET

We used:

dart
Copy
Edit
await Permission.location.request();
Additionally, if location services (GPS) are off, the app prompts the user to enable them using the location plugin.

💾 Database/Backend Logic
This version does not use a database.
Instead, it compares scanned Wi-Fi SSIDs with a hardcoded local JSON list of valid Wi-Fi credentials, including:

SSID

Encrypted password (base64)

Associated latitude & longitude

When a network is nearby and matches the list, the app attempts to connect using WiFiForIoTPlugin.connect.

🌟 Bonus Features & Notes
✅ Automatically filters Wi-Fi networks based on proximity to pre-defined coordinates.

✅ Base64-encrypted passwords used for basic obfuscation.

✅ UI updates dynamically on connection success (Connected button state).