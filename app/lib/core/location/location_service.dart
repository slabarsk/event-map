import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Cihaz konumu. Yalnızca "yakınımda" araması sırasında istenir; konum hiçbir
/// yere yazılmaz, yalnızca o sorguda gönderilir.
abstract class LocationService {
  /// İzin verilmediyse ya da konum alınamadıysa null.
  Future<LatLng?> current();
}

class DeviceLocationService implements LocationService {
  @override
  Future<LatLng?> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return LatLng(p.latitude, p.longitude);
    } on Exception {
      return null;
    }
  }
}

/// Testlerde sabit bir konumla override edilir.
final locationServiceProvider = Provider<LocationService>(
  (ref) => DeviceLocationService(),
);
