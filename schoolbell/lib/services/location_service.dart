import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationService {
  static const double defaultLat = 40.7074;
  static const double defaultLng = -73.8184;
  static const double defaultRadius = 150.0;

  static Future<double> _getLat() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('school_lat') ?? defaultLat;
  }

  static Future<double> _getLng() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('school_lng') ?? defaultLng;
  }

  static Future<double> _getRadius() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('school_radius') ?? defaultRadius;
  }

  static Future<bool> isAtSchool() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 15));

      final lat = await _getLat();
      final lng = await _getLng();
      final radius = await _getRadius();

      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        lat,
        lng,
      );

      return distance <= radius;
    } catch (_) {
      return false;
    }
  }
}
