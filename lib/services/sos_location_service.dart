import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class SosLocationService {
  static Future<Map<String, dynamic>> capture() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return {'locationStatus': 'services_disabled'};
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return {'locationStatus': 'permission_denied'};
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      String name = '';
      try {
        final places = await Geocoding()
            .placemarkFromCoordinates(position.latitude, position.longitude)
            .timeout(const Duration(seconds: 5));
        if (places.isNotEmpty) {
          final p = places.first;
          name = [p.name, p.street, p.subLocality, p.locality]
              .whereType<String>()
              .map((v) => v.trim())
              .where((v) => v.isNotEmpty)
              .toSet()
              .join(', ');
          if (name.length > 500) name = name.substring(0, 500);
        }
      } catch (_) {
        /* GPS remains usable if the address service is offline. */
      }
      return {
        'locationName': name,
        'locationStatus': 'available',
        'latitude': position.latitude,
        'longitude': position.longitude,
        'locationAccuracy': position.accuracy,
        'locationCapturedAt': position.timestamp.millisecondsSinceEpoch,
      };
    } catch (_) {
      return {'locationStatus': 'unavailable'};
    }
  }
}
