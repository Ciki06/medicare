import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class SosLocationProvider {
  Future<bool> servicesEnabled() => Geolocator.isLocationServiceEnabled();
  Future<LocationPermission> permission() => Geolocator.checkPermission();
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();
  Future<Position> current({bool deviceGps = false}) =>
      Geolocator.getCurrentPosition(
        locationSettings: deviceGps
            ? AndroidSettings(
                forceLocationManager: true,
                accuracy: LocationAccuracy.high,
                timeLimit: const Duration(seconds: 25),
              )
            : const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 20),
              ),
      );
  Future<Position?> lastKnown() => Geolocator.getLastKnownPosition();
  Future<List<Placemark>> address(Position position) => Geocoding()
      .placemarkFromCoordinates(position.latitude, position.longitude)
      .timeout(const Duration(seconds: 5));
}

class SosLocationService {
  static String message(Map<String, dynamic> location) {
    if (location['locationStatus'] == 'available') {
      return 'Your current SOS location has been captured and will be shared in chat.';
    }
    return switch (location['locationFailure']) {
      'services_disabled' =>
        'Location services are off. Turn on Location/GPS in Settings. Your SOS was still submitted.',
      'permission_denied_forever' =>
        'Location access is blocked. Allow location for MediCare in app Settings. Your SOS was still submitted.',
      'permission_denied' =>
        'Location permission was denied. Allow location access to share your position. Your SOS was still submitted.',
      'timeout' =>
        'A current GPS fix could not be obtained. Move near a window or outdoors and try again. Your SOS was still submitted.',
      _ =>
        'Your location could not be obtained. Check Location/GPS and try again. Your SOS was still submitted.',
    };
  }

  static Future<Map<String, dynamic>> capture({
    SosLocationProvider? provider,
    bool? useAndroidFallback,
    DateTime Function()? now,
  }) async {
    final source = provider ?? SosLocationProvider();
    Map<String, dynamic> failure(String status, String reason) => {
      'locationStatus': status,
      'locationFailure': reason,
    };
    try {
      if (!await source.servicesEnabled()) {
        return failure('services_disabled', 'services_disabled');
      }
      var permission = await source.permission();
      if (permission == LocationPermission.denied) {
        permission = await source.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return failure('permission_denied', 'permission_denied_forever');
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        return failure('permission_denied', 'permission_denied');
      }
      Position? position;
      Object? error;
      try {
        position = await source.current();
      } catch (e) {
        error = e;
      }
      // Fall back to device GPS when Google Play's fused provider is unavailable.
      if (position == null &&
          (useAndroidFallback ??
              (!kIsWeb && defaultTargetPlatform == TargetPlatform.android))) {
        try {
          position = await source.current(deviceGps: true);
        } catch (e) {
          error = e;
        }
      }
      if (position == null) {
        try {
          final cached = await source.lastKnown();
          final age = (now?.call() ?? DateTime.now()).difference(
            cached?.timestamp ?? DateTime(1970),
          );
          if (cached != null &&
              !age.isNegative &&
              age <= const Duration(minutes: 2) &&
              cached.accuracy <= 200) {
            position = cached;
          }
        } catch (_) {}
      }
      if (position == null) {
        if (!await source.servicesEnabled()) {
          return failure('services_disabled', 'services_disabled');
        }
        final currentPermission = await source.permission();
        if (currentPermission == LocationPermission.deniedForever) {
          return failure('permission_denied', 'permission_denied_forever');
        }
        if (error is PermissionDeniedException ||
            currentPermission == LocationPermission.denied) {
          return failure('permission_denied', 'permission_denied');
        }
        return failure(
          'unavailable',
          error is TimeoutException ? 'timeout' : 'unavailable',
        );
      }
      if (!position.latitude.isFinite ||
          position.latitude.abs() > 90 ||
          !position.longitude.isFinite ||
          position.longitude.abs() > 180 ||
          !position.accuracy.isFinite ||
          position.accuracy < 0) {
        return failure('unavailable', 'unavailable');
      }
      String name = '';
      try {
        final places = await source.address(position);
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
        'locationFailure': '',
        'latitude': position.latitude,
        'longitude': position.longitude,
        'locationAccuracy': position.accuracy,
        'locationCapturedAt': position.timestamp.millisecondsSinceEpoch,
      };
    } catch (error) {
      if (error is LocationServiceDisabledException) {
        return failure('services_disabled', 'services_disabled');
      }
      if (error is PermissionDeniedException) {
        return failure('permission_denied', 'permission_denied');
      }
      return failure('unavailable', 'unavailable');
    }
  }
}
