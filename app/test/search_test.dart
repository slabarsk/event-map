import 'package:event_map/core/location/location_service.dart';
import 'package:event_map/features/events/application/events_providers.dart';
import 'package:event_map/features/events/data/demo_events_repository.dart';
import 'package:event_map/features/events/domain/event_format.dart';
import 'package:event_map/features/search/application/search_providers.dart';
import 'package:event_map/features/search/data/search_repository.dart';
import 'package:event_map/features/search/domain/search_result.dart';
import 'package:event_map/features/search/presentation/search_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

/// 12 Kasım 2026 Perşembe, İzmir saatiyle 10:00.
final _now = DateTime.utc(2026, 11, 12, 7);

/// Kültürpark (demo verisinde iki ücretsiz konser burada).
const _kulturpark = LatLng(38.4343, 27.1463);

class _FakeLocation implements LocationService {
  _FakeLocation(this.value);
  final LatLng? value;
  int calls = 0;

  @override
  Future<LatLng?> current() async {
    calls++;
    return value;
  }
}

DateTime _ist(int y, int m, int d, [int h = 0]) =>
    DateTime.utc(y, m, d, h).subtract(EventFormat.istanbulOffset);

void main() {
  setUpAll(() => initializeDateFormatting('tr'));

  group('DemoQuery', () {
    test('demo sorusu: bu akşam yakınımdaki ücretsiz konserler', () {
      final q = DemoQuery.parse('Bu akşam yakınımdaki ücretsiz konserler');
      expect(q.timeWindow, 'tonight');
      expect(q.categories, ['concert']);
      expect(q.freeOnly, isTrue);
      expect(q.nearMe, isTrue);
      expect(q.radiusM, isNull);
    });

    test('yarın akşam yarın sayılır; fiyat ve mesafe okunur', () {
      final q = DemoQuery.parse('Yarın akşam 3 km içinde 200 TL altı tiyatro');
      expect(q.timeWindow, 'tomorrow');
      expect(q.categories, ['theatre']);
      expect(q.maxPrice, 200);
      expect(q.radiusM, 3000);
      expect(q.nearMe, isTrue);
    });

    test('bu akşam penceresi 17:00–03:00 (İzmir)', () {
      final (from, to) = const DemoQuery(timeWindow: 'tonight').window(_now);
      expect(from, _ist(2026, 11, 12, 17));
      expect(to, _ist(2026, 11, 13, 3));
    });

    test('hafta sonu perşembe günü cuma 17:00–pazartesi', () {
      final (from, to) = const DemoQuery(timeWindow: 'this_weekend')
          .window(_now);
      expect(from, _ist(2026, 11, 13, 17));
      expect(to, _ist(2026, 11, 16));
    });
  });

  group('DemoSearchRepository', () {
    late DemoSearchRepository repo;
    setUp(
      () => repo = DemoSearchRepository(
        DemoEventsRepository(clock: () => _now),
        clock: () => _now,
      ),
    );

    test('konum yoksa needs_location ve şehir geneli sonuç', () async {
      final r = await repo.search('Bu akşam yakınımdaki ücretsiz konserler');
      expect(r.needsLocation, isTrue);
      expect(r.location, isNull);
      expect(r.events.map((e) => e.title), [
        'Sahilde Akustik Akşam',
        'Açık Hava Caz Gecesi',
        'Ücretsiz Rock Konseri',
      ]);
      expect(r.labels, ['Bu akşam', 'Konser', 'Ücretsiz']);
    });

    test('konumla yarıçap dışındakiler elenir', () async {
      final r = await repo.search(
        'Bu akşam 2 km içinde ücretsiz konser',
        location: _kulturpark,
      );
      expect(r.needsLocation, isFalse);
      expect(r.location, _kulturpark);
      expect(r.events.map((e) => e.title), [
        'Açık Hava Caz Gecesi',
        'Ücretsiz Rock Konseri',
      ]);
      expect(r.labels.last, '2 km içinde');
    });
  });

  test('SearchResult.fromJson', () {
    final r = SearchResult.fromJson('q', {
      'labels': ['Bu akşam', 'Konser'],
      'needs_location': false,
      'radius_m': 5000,
      'parser': 'claude',
      'events': [
        {
          'id': 'a',
          'title': 'Caz',
          'starts_at': '2026-11-12T17:00:00+00:00',
          'category': 'concert',
          'venue_id': 'v',
          'venue_name': 'V',
          'lat': 38.4,
          'lng': 27.1,
          'distance_m': 850.4,
        },
      ],
    }, location: _kulturpark);
    expect(r.labels, ['Bu akşam', 'Konser']);
    expect(r.events.single.distanceM, 850.4);
    expect(r.location, _kulturpark);
    expect(r.parser, 'claude');
    expect(EventFormat.distance(850.4), '850 m');
    expect(EventFormat.distance(2400), '2,4 km');
  });

  group('SearchScreen', () {
    Future<ProviderContainer> pump(
      WidgetTester tester,
      LocationService location,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = ProviderContainer(
        overrides: [
          eventsRepositoryProvider.overrideWithValue(
            DemoEventsRepository(clock: () => _now),
          ),
          clockProvider.overrideWithValue(() => _now),
          locationServiceProvider.overrideWithValue(location),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SearchScreen()),
          GoRoute(
            path: '/map',
            builder: (_, _) => const Scaffold(body: Text('HARİTA')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('örnek soru konum ister, sonuçları gösterir ve haritaya '
        'gönderir', (tester) async {
      final location = _FakeLocation(_kulturpark);
      final container = await pump(tester, location);

      await tester.tap(find.text(SearchScreen.suggestions.first));
      await tester.pumpAndSettle();

      expect(location.calls, 1);
      expect(find.text('5 km içinde'), findsOneWidget);
      expect(find.text('Açık Hava Caz Gecesi'), findsOneWidget);
      expect(find.text('Sahilde Akustik Akşam'), findsOneWidget);
      expect(find.textContaining('Konum izni'), findsNothing);

      await tester.tap(find.textContaining('Haritada göster'));
      await tester.pumpAndSettle();
      expect(find.text('HARİTA'), findsOneWidget);
      final shown = container.read(mapSearchProvider);
      expect(shown?.events, hasLength(3));
      expect(shown?.location, _kulturpark);
    });

    testWidgets('konum izni yoksa şehir geneli ve uyarı', (tester) async {
      await pump(tester, _FakeLocation(null));

      await tester.enterText(
        find.byKey(const ValueKey('search-field')),
        'yakınımda ücretsiz konser bu akşam',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.textContaining('Konum izni'), findsOneWidget);
      expect(find.text('Ücretsiz Rock Konseri'), findsOneWidget);
    });

    testWidgets('konum gerektirmeyen soru izin istemez', (tester) async {
      final location = _FakeLocation(_kulturpark);
      await pump(tester, location);

      await tester.tap(find.text('Yarın akşam tiyatro'));
      await tester.pumpAndSettle();

      expect(location.calls, 0);
      expect(
        find.text(
          'Bu aramaya uyan etkinlik bulunamadı. '
          'Zamanı ya da mesafeyi genişletmeyi dene.',
        ),
        findsOneWidget,
      );
    });
  });
}
