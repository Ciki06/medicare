/// A GPS point, independent of address searches or nearby place listings.
class LocationCoordinates {
  const LocationCoordinates._(this.latitude, this.longitude);
  final double latitude, longitude;

  static LocationCoordinates? fromValues(Object? latitude, Object? longitude) {
    if (latitude is! num ||
        longitude is! num ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      return null;
    }
    return LocationCoordinates._(latitude.toDouble(), longitude.toDouble());
  }

  static LocationCoordinates? fromQuery(String? query) {
    final parts = query?.split(',');
    if (parts == null || parts.length != 2) return null;
    return fromValues(
      double.tryParse(parts[0].trim()),
      double.tryParse(parts[1].trim()),
    );
  }

  String get pair => '$latitude,$longitude';
  String get display => '$latitude, $longitude';

  Uri get webUri =>
      Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': pair});

  String _label(String? name) {
    // Reverse geocoding joins the place name and full address. Use the first
    // named component for the pin so a repeated street/address stays out of it.
    final label = name
        ?.split(',')
        .map((part) => part.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((part) => part.isNotEmpty)
        .firstOrNull;
    return label == null || label.isEmpty ? display : label;
  }

  Uri androidUri({String? label}) => Uri(
    scheme: 'geo',
    path: '0,0',
    queryParameters: {'q': '$pair(${_label(label)})', 'z': '18'},
  );

  Uri appleUri({String? label}) => Uri.https('maps.apple.com', '/', {
    'll': pair,
    'q': _label(label),
    'z': '18',
  });
}
