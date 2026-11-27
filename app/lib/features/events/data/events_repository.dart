import 'package:latlong2/latlong.dart';

import '../domain/event.dart';

/// Ekranlarda doğrudan gösterilebilen, Türkçe mesajlı veri hatası.
class EventsFailure implements Exception {
  const EventsFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// `events_near` RPC'sinin istemci tarafı. Konum verilmezse şehir geneli
/// sonuç döner; kullanıcı konumu hiçbir yerde saklanmaz.
abstract class EventsRepository {
  /// [from] sonrasında biten (ya da devam eden) yayınlanmış etkinlikler.
  /// [to] verilirse o andan önce başlayanlarla sınırlanır.
  Future<List<MapEvent>> upcoming({
    required DateTime from,
    DateTime? to,
    Set<String> categories = const {},
    int? maxPrice,
    LatLng? location,
    int? radiusM,
  });
}
