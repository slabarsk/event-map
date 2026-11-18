import 'package:event_map/features/events/data/demo_events_repository.dart';
import 'package:event_map/features/events/domain/event.dart';
import 'package:event_map/features/events/domain/event_format.dart';
import 'package:event_map/features/events/presentation/event_visuals.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

MapEvent _event({
  double? min,
  double? max,
  PriceStatus status = PriceStatus.listed,
}) => MapEvent(
  id: 'e',
  title: 't',
  startsAt: DateTime.utc(2026, 11, 12, 17),
  category: 'concert',
  venueId: 'v',
  venueName: 'V',
  lat: 38.4,
  lng: 27.1,
  priceMin: min,
  priceMax: max,
  priceStatus: status,
);

void main() {
  setUpAll(() => initializeDateFormatting('tr'));

  group('MapEvent.fromRow', () {
    test('events_near satırını ayrıştırır', () {
      final e = MapEvent.fromRow({
        'id': 'a1',
        'title': 'Caz Gecesi',
        'description': null,
        'starts_at': '2026-11-12T17:00:00+00:00',
        'ends_at': '2026-11-12T19:00:00+00:00',
        'category': 'concert',
        'price_min': '250.00', // PostgREST numeric'i metin döndürebilir
        'price_max': 450,
        'price_status': 'looked_up',
        'price_source_url': 'https://example.org',
        'image_url': null,
        'ticket_url': null,
        'venue_id': 'v1',
        'venue_name': 'AASSM',
        'venue_address': 'Konak',
        'lat': 38.423,
        'lng': 27.1387,
        'distance_m': null,
        'source_count': 2,
      });
      expect(e.startsAt, DateTime.utc(2026, 11, 12, 17));
      expect(e.priceMin, 250);
      expect(e.priceMax, 450);
      expect(e.priceStatus, PriceStatus.lookedUp);
      expect(e.sourceCount, 2);
      expect(e.distanceM, isNull);
    });
  });

  group('EventFormat.price', () {
    test('ücretsiz, tek fiyat, aralık, bilinmiyor', () {
      expect(EventFormat.price(_event(min: 0, max: 0)), 'Ücretsiz');
      expect(EventFormat.price(_event(min: 150, max: 150)), '150 ₺');
      expect(EventFormat.price(_event(min: 1250, max: 2000)), '1.250–2.000 ₺');
      expect(EventFormat.price(_event()), 'Fiyat bilinmiyor');
    });

    test('başvuru ile katılım: etiket var, bilinmeyen fiyat metni yok', () {
      final unknown = MapEvent.fromRow({
        'id': 'a',
        'title': 'Atölye',
        'starts_at': '2026-11-20T10:00:00+00:00',
        'category': 'workshop',
        'price_status': 'unknown',
        'venue_id': 'v',
        'venue_name': 'AASSM',
        'lat': 38.4,
        'lng': 27.1,
        'requires_registration': true,
      });
      expect(unknown.requiresRegistration, isTrue);
      expect(EventFormat.registrationBadge(unknown), 'Başvuru ile');
      expect(EventFormat.showsPrice(unknown), isFalse);
      expect(EventFormat.priceBadge(unknown), isNull);

      // Ücretli başvuruda fiyat yine gösterilir.
      final paid = MapEvent(
        id: 'b',
        title: 't',
        startsAt: DateTime.utc(2026, 11, 20),
        category: 'workshop',
        venueId: 'v',
        venueName: 'V',
        lat: 38.4,
        lng: 27.1,
        priceMin: 100,
        priceMax: 100,
        priceStatus: PriceStatus.listed,
        requiresRegistration: true,
      );
      expect(EventFormat.showsPrice(paid), isTrue);
      expect(EventFormat.price(paid), '100 ₺');

      expect(EventFormat.registrationBadge(_event()), isNull);
      expect(EventFormat.showsPrice(_event()), isTrue);
    });

    test('unknown durumu "Fiyat bilinmiyor" gösterir, rozet yok', () {
      final e = _event(status: PriceStatus.unknown);
      expect(EventFormat.price(e), 'Fiyat bilinmiyor');
      expect(EventFormat.priceBadge(e), isNull);
      expect(PriceStatus.parse('unknown'), PriceStatus.unknown);
      expect(PriceStatus.parse(null), PriceStatus.unknown);
      expect(PriceStatus.parse('listed'), PriceStatus.listed);
      expect(PriceStatus.unknown.dbValue, 'unknown');
    });

    test('tahmini fiyat her zaman etiketlenir', () {
      expect(
        EventFormat.priceBadge(
          _event(min: 300, max: 500, status: PriceStatus.estimated),
        ),
        'Tahmini',
      );
      expect(EventFormat.priceBadge(_event(min: 300, max: 500)), isNull);
    });
  });

  group('EventFormat.when', () {
    // 12 Kasım 2026 Perşembe, İstanbul'da 10:00.
    final now = DateTime.utc(2026, 11, 12, 7);

    test('İstanbul saatine göre gün ve saat', () {
      expect(
        EventFormat.when(DateTime.utc(2026, 11, 12, 17), now: now),
        'Bugün 20:00',
      );
      expect(
        EventFormat.when(DateTime.utc(2026, 11, 13, 16, 30), now: now),
        'Yarın 19:30',
      );
      expect(
        EventFormat.when(DateTime.utc(2026, 11, 14, 11), now: now),
        'Cumartesi 14:00',
      );
      expect(
        EventFormat.when(DateTime.utc(2026, 12, 4, 17), now: now),
        '4 Aralık Cuma 20:00',
      );
    });

    test('UTC gece yarısı ile İstanbul gece yarısı karışmaz', () {
      // UTC 22:30 = İstanbul ertesi gün 01:30.
      expect(
        EventFormat.when(DateTime.utc(2026, 11, 12, 22, 30), now: now),
        'Yarın 01:30',
      );
    });
  });

  group('DemoEventsRepository', () {
    // İstanbul'da 12 Kasım 10:00.
    final now = DateTime.utc(2026, 11, 12, 7);
    final repo = DemoEventsRepository(clock: () => now);

    test('seed.sql ile aynı 12 etkinlik ve 8 mekân', () async {
      final events = await repo.upcoming(from: now);
      expect(events, hasLength(12));
      expect(events.map((e) => e.venueId).toSet(), hasLength(8));
      for (final e in events) {
        // İzmir il sınırları içinde.
        expect(e.lat, inInclusiveRange(38.0, 39.2));
        expect(e.lng, inInclusiveRange(26.2, 28.0));
      }
    });

    test('bitmiş etkinlikler gelmez (events_near ile aynı süzgeç)', () async {
      // İstanbul 22:30: 19:00–21:00 akustik akşam bitti, 21:00 rock sürüyor.
      final late = DateTime.utc(2026, 11, 12, 19, 30);
      final titles = (await repo.upcoming(from: late)).map((e) => e.title);
      expect(titles, isNot(contains('Sahilde Akustik Akşam')));
      expect(titles, contains('Ücretsiz Rock Konseri'));
    });

    test('etkinlik saatleri İstanbul saatiyle seed ile aynı', () async {
      final events = await repo.upcoming(from: now);
      final jazz = events.firstWhere((e) => e.title == 'Açık Hava Caz Gecesi');
      expect(EventFormat.toIstanbul(jazz.startsAt).hour, 20);
      expect(jazz.isFree, isTrue);
    });
  });

  test('aynı mekândaki etkinlikler tek pinde toplanır', () async {
    final now = DateTime.utc(2026, 11, 12, 7);
    final events = await DemoEventsRepository(clock: () => now)
        .upcoming(from: now);
    final groups = VenueGroup.fromEvents(events);
    expect(groups, hasLength(8));
    final pier = groups.firstWhere((g) => g.venueName == 'Konak Pier');
    expect(pier.events, hasLength(2));
    expect(
      pier.events.first.startsAt.isBefore(pier.events.last.startsAt),
      isTrue,
    );
  });

  test('bilinmeyen kategori "Diğer" olarak görünür', () {
    expect(eventCategoryOf('concert').label, 'Konser');
    expect(eventCategoryOf('party').label, 'Parti');
    expect(eventCategoryOf('xyz').label, 'Diğer');
  });
}
