/// A GPS point, independent of address searches or nearby place listings.
/// Stores GPS coordinates and provides links to map applications.
class LocationCoordinates {
  /// Creates a location using latitude and longitude.
  const LocationCoordinates._(this.latitude, this.longitude);

  /// Stores the latitude and longitude values.
  final double latitude, longitude;

  /// Checks whether the coordinates are valid before creating a location.
  static LocationCoordinates? fromValues(Object? latitude, Object? longitude) {
    if (latitude is! num ||
        longitude is! num ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      return null;
    }

    /// Converts valid coordinates into double values.
    return LocationCoordinates._(latitude.toDouble(), longitude.toDouble());
  }

  /// Converts a coordinate string into latitude and longitude values.
  static LocationCoordinates? fromQuery(String? query) {
    final parts = query?.split(',');

    /// Returns null if the coordinate format is incorrect.
    if (parts == null || parts.length != 2) return null;
    return fromValues(
      double.tryParse(parts[0].trim()),
      double.tryParse(parts[1].trim()),
    );
  }

  /// Formats the coordinates for map searches and display.
  String get pair => '$latitude,$longitude';
  String get display => '$latitude, $longitude';

  /// Creates a Google Maps link using the coordinates.
  Uri get webUri =>
      Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': pair});

  /// Gets the place name to display as a map label.
  String _label(String? name) {
    ///Uses the first part of the address to avoid a long map label.
    final label = name
        ?.split(',')
        .map((part) => part.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((part) => part.isNotEmpty)
        .firstOrNull;

    /// Uses the coordinates if no place name is available.
    return label == null || label.isEmpty ? display : label;
  }

  /// Creates a location link for Android map applications.
  Uri androidUri({String? label}) => Uri(
    scheme: 'geo',
    path: '0,0',
    queryParameters: {'q': '$pair(${_label(label)})', 'z': '18'},
  );

  /// Creates a location link for Apple Maps.
  Uri appleUri({String? label}) => Uri.https('maps.apple.com', '/', {
    'll': pair,
    'q': _label(label),
    'z': '18',
  });
}
