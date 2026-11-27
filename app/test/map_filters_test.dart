import 'package:event_map/features/events/application/events_providers.dart';
import 'package:event_map/features/events/domain/event.dart';
import 'package:event_map/features/map/application/map_filter_provider.dart';
import 'package:event_map/features/map/domain/map_filters.dart';
import 'package:event_map/features/map/domain/venue_cluster.dart';
import 'package:event_map/features/search/application/search_providers.dart';
import 'package:event_map/features/search/domain/search_result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

final _now = DateTime.utc(2026, 11, 27, 7); // Cuma 10:00, İstanbul.

MapEvent _event(
  String id, {
  String category = 'concert',
  double? min,
  double? max,
  DateTime? start,
  DateTime? end,
  double lat = 38.43,
  double lng = 27.14,
}) => MapEvent(
  id: id,
  title: id,
  startsAt: start ?? DateTime.utc(2026, 11, 27, 18),
  endsAt: end,
  category: category,
  priceMin: min,
  priceMax: max,
  venueId: id,
  venueName: id,
  lat: lat,
  lng: lng,
);

void main() {
  group('Harita filtreleri', () {
    test('kategori ve ücretsiz filtresi birlikte çalışır; fiyat aralığı ücretsiz sayılmaz', () {
      final events = [
        _event('free-concert', min: 0, max: 0),
        _event('range', min: 0, max: 500),
        _event('unknown'),
        _event('free-theatre', category: 'theatre', min: 0),
      ];
      const filters = MapFilters(categories: {'concert'}, freeOnly: true);
      expect(filters.apply(events, _now).map((e) => e.id), ['free-concert']);
    });

    test(
      'fiyat sınırı başlangıç fiyatını kullanır, bilinmeyen fiyatı dışlar',
      () {
        final events = [
          _event('at-cap', min: 250, max: 500),
          _event('expensive', min: 251),
          _event('max-only', max: 100),
          _event('unknown'),
        ];
        expect(
          const MapFilters(maxPrice: 250).apply(events, _now).map((e) => e.id),
          ['at-cap', 'max-only'],
        );
      },
    );

    test('bugün ve yarın İstanbul gece yarısında ayrılır', () {
      final events = [
        _event(
          'today',
          start: DateTime.utc(2026, 11, 27, 20, 59),
          end: DateTime.utc(2026, 11, 27, 21),
        ),
        _event('tomorrow', start: DateTime.utc(2026, 11, 27, 21)),
      ];
      expect(
        const MapFilters(date: MapDateFilter.today)
            .apply(events, _now)
            .map((e) => e.id),
        ['today'],
      );
      expect(
        const MapFilters(date: MapDateFilter.tomorrow)
            .apply(events, _now)
            .map((e) => e.id),
        ['tomorrow'],
      );
    });

    test('bu akşam devam eden etkinliği tutar, 03:00 sınırındakini dışlar', () {
      final events = [
        _event(
          'afternoon',
          start: DateTime.utc(2026, 11, 27, 10),
          end: DateTime.utc(2026, 11, 27, 12),
        ),
        _event(
          'ongoing',
          start: DateTime.utc(2026, 11, 27, 13),
          end: DateTime.utc(2026, 11, 27, 15),
        ),
        _event('evening'),
        _event('at-three', start: DateTime.utc(2026, 11, 28)),
      ];
      expect(
        const MapFilters(date: MapDateFilter.tonight)
            .apply(events, _now)
            .map((e) => e.id),
        ['ongoing', 'evening'],
      );
    });

    test('gece 01:00 için bu akşam önceki günün gecesidir', () {
      final now = DateTime.utc(2026, 11, 27, 22);
      final (from, to) = const MapFilters(date: MapDateFilter.tonight)
          .window(now);
      expect(from, now);
      expect(to, DateTime.utc(2026, 11, 28));
    });

    test('hafta sonu cuma 17:00–pazartesi 00:00 aralığıdır', () {
      final filters = const MapFilters(date: MapDateFilter.weekend);
      final (from, to) = filters.window(_now);
      expect(from, DateTime.utc(2026, 11, 27, 14));
      expect(to, DateTime.utc(2026, 11, 29, 21));
      final sunday = DateTime.utc(2026, 11, 29, 12);
      expect(filters.window(sunday), (sunday, to));
    });

    test('mesafe gerçek koordinatlardan hesaplanır, konumsuz uygulanmaz', () {
      final events = [_event('near'), _event('far', lat: 38.50)];
      const filters = MapFilters(radiusKm: 2, location: LatLng(38.43, 27.14));
      expect(filters.apply(events, _now).map((e) => e.id), ['near']);
      expect(const MapFilters(radiusKm: 2).apply(events, _now), isEmpty);
    });

    test('elle seçilen filtre arama sonucu ile kesişir', () {
      final container = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(() => _now)],
      );
      addTearDown(container.dispose);
      container
          .read(mapSearchProvider.notifier)
          .show(
            SearchResult(
              query: 'konser',
              labels: const ['Konser'],
              events: [_event('free', min: 0), _event('paid', min: 200)],
            ),
          );
      container
          .read(mapFiltersProvider.notifier)
          .apply(const MapFilters(freeOnly: true));
      expect(
        container.read(venueGroupsProvider).requireValue.single.first.id,
        'free',
      );
      container.read(mapFiltersProvider.notifier).clear();
      expect(container.read(venueGroupsProvider).requireValue, hasLength(2));
      expect(container.read(mapSearchProvider), isNotNull);
    });
  });

  group('Pin kümeleme', () {
    final groups = [
      VenueGroup([_event('a')]),
      VenueGroup([_event('b')]),
      VenueGroup([_event('c')]),
    ];

    test(
      'komşu hücrelerdeki yakın pinleri birleştirir, uzak pini ayrı tutar',
      () {
        final points = {
          'a': const Offset(55, 0),
          'b': const Offset(57, 0),
          'c': const Offset(300, 0),
        };
        final clusters = VenueCluster.build(groups, (g) => points[g.venueId]!);
        expect(clusters.map((c) => c.groups.length), [2, 1]);
      },
    );

    test('zoom arttıkça uzaklaşan pinler ayrılır', () {
      Offset project(VenueGroup g) => Offset(g.venueId == 'a' ? 0 : 40, 0);
      expect(
        VenueCluster.build(groups.take(2).toList(), project),
        hasLength(1),
      );
      expect(
        VenueCluster.build(groups.take(2).toList(), (g) => project(g) * 4),
        hasLength(2),
      );
    });

    test('kaynak sırası küme üyelerini değiştirmez', () {
      Offset project(VenueGroup g) => Offset(g.venueId.codeUnitAt(0) * 10, 0);
      final forward = VenueCluster.build(groups, project);
      final reverse = VenueCluster.build(groups.reversed.toList(), project);
      expect(
        forward.map((c) => c.groups.map((g) => g.venueId).join(',')),
        reverse.map((c) => c.groups.map((g) => g.venueId).join(',')),
      );
    });
  });
}
