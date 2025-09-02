import 'dart:async';
import 'package:geolocator/geolocator.dart';

class LocationHelper {
  static Future<Position> getCurrentLocation({Duration timeout = const Duration(seconds: 15)}) async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: timeout,
      );
    } on TimeoutException {
      final lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null) {
        return lastPosition;
      }
      throw Exception('Could not determine current location');
    }
  }
}
