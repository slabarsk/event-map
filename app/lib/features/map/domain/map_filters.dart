import 'package:latlong2/latlong.dart';

import '../../events/domain/event.dart';
import '../../events/domain/event_format.dart';

enum MapDateFilter {
  upcoming('Yaklaşan'),
  today('Bugün'),
  tonight('Bu akşam'),
  tomorrow('Yarın'),
  weekend('Hafta sonu');

  const MapDateFilter(this.label);
  final String label;
}

/// Arama sonuçlarına da uygulanabilen, cihazda tutulan harita seçimleri.
class MapFilters {
  const MapFilters({
    this.date = MapDateFilter.upcoming,
    this.categories = const {},
    this.freeOnly = false,
    this.maxPrice,
    this.radiusKm,
    this.location,
  });

  final MapDateFilter date;
  final Set<String> categories;
  final bool freeOnly;
  final int? maxPrice;
  final int? radiusKm;
  final LatLng? location;

  int get activeCount =>
      (date == MapDateFilter.upcoming ? 0 : 1) +
      (categories.isEmpty ? 0 : 1) +
      (freeOnly || maxPrice != null ? 1 : 0) +
      (radiusKm == null ? 0 : 1);

  MapFilters copyWith({
    MapDateFilter? date,
    Set<String>? categories,
    bool? freeOnly,
    int? maxPrice,
    bool clearPrice = false,
    int? radiusKm,
    bool clearRadius = false,
    LatLng? location,
  }) => MapFilters(
    date: date ?? this.date,
    categories: Set.unmodifiable(categories ?? this.categories),
    freeOnly: freeOnly ?? this.freeOnly,
    maxPrice: clearPrice ? null : maxPrice ?? this.maxPrice,
    radiusKm: clearRadius ? null : radiusKm ?? this.radiusKm,
    location: clearRadius ? null : location ?? this.location,
  );

  /// Gün sınırları cihaz saat diliminden bağımsız, İstanbul saatindedir.
  (DateTime, DateTime?) window(DateTime now) {
    final day = EventFormat.istanbulDayStart(now);
    final local = EventFormat.toIstanbul(now);
    DateTime later(DateTime value) => value.isAfter(now) ? value : now;
    switch (date) {
      case MapDateFilter.upcoming:
        return (now, null);
      case MapDateFilter.today:
        return (now, day.add(const Duration(days: 1)));
      case MapDateFilter.tomorrow:
        return (
          day.add(const Duration(days: 1)),
          day.add(const Duration(days: 2)),
        );
      case MapDateFilter.tonight:
        final evening = local.hour < 3
            ? day.subtract(const Duration(days: 1))
            : day;
        return (
          later(evening.add(const Duration(hours: 17))),
          evening.add(const Duration(hours: 27)),
        );
      case MapDateFilter.weekend:
        // Cuma 17:00–pazartesi 00:00; hafta sonunda mevcut hafta sonu.
        final monday = day.add(Duration(days: 8 - local.weekday));
        return (
          later(monday.subtract(const Duration(days: 3, hours: -17))),
          monday,
        );
    }
  }

  List<MapEvent> apply(Iterable<MapEvent> events, DateTime now) {
    final (from, to) = window(now);
    const distance = Distance();
    return events.where((e) {
      final end = e.endsAt ?? e.startsAt.add(const Duration(hours: 3));
      if (!end.isAfter(from) || (to != null && !e.startsAt.isBefore(to))) {
        return false;
      }
      if (categories.isNotEmpty && !categories.contains(e.category)) {
        return false;
      }
      if (freeOnly && !e.isFree) return false;
      final price = e.priceMin ?? e.priceMax;
      if (!freeOnly &&
          maxPrice != null &&
          (price == null || price > maxPrice!)) {
        return false;
      }
      if (radiusKm != null) {
        final here = location;
        if (here == null ||
            distance.as(LengthUnit.Meter, here, LatLng(e.lat, e.lng)) >
                radiusKm! * 1000) {
          return false;
        }
      }
      return true;
    }).toList();
  }
}
