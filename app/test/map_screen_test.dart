import 'package:event_map/features/events/application/events_providers.dart';
import 'package:event_map/features/events/data/demo_events_repository.dart';
import 'package:event_map/features/events/data/events_repository.dart';
import 'package:event_map/features/events/domain/event.dart';
import 'package:event_map/features/map/presentation/map_screen.dart';
import 'package:event_map/features/map/presentation/widgets/venue_pin.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:latlong2/latlong.dart';

class _FailingRepository implements EventsRepository {
  @override
  Future<List<MapEvent>> upcoming({
    required DateTime from,
    DateTime? to,
    Set<String> categories = const {},
    int? maxPrice,
    LatLng? location,
    int? radiusM,
  }) => Future.error(const EventsFailure('Etkinlikler yüklenemedi.'));
}

Widget _app(EventsRepository repo, {DateTime? now}) => ProviderScope(
  overrides: [
    eventsRepositoryProvider.overrideWithValue(repo),
    if (now != null) clockProvider.overrideWithValue(() => now),
  ],
  child: const MaterialApp(home: Scaffold(body: MapScreen(showTiles: false))),
);

void main() {
  setUpAll(() => initializeDateFormatting('tr'));

  testWidgets('seed etkinlikleri mekân pini olarak görünür', (tester) async {
    // Saat sabit: tüm seed etkinlikleri yaklaşan durumda olsun.
    final now = DateTime.utc(2026, 11, 12, 7);
    final repo = DemoEventsRepository(clock: () => now);
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(repo, now: now));
    await tester.pumpAndSettle();

    // Görünür alandaki pinler; Urla şehir merkezinden uzakta olabilir.
    expect(find.byType(VenuePin), findsWidgets);
    expect(find.textContaining('mekân'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pin-venue-konak-pier')));
    await tester.pumpAndSettle();

    expect(find.text('Konak Pier'), findsOneWidget);
    expect(find.text('Stand-up: İzmir Gecesi'), findsOneWidget);
    expect(find.text('Elektronik Müzik Gecesi'), findsOneWidget);
    expect(find.text('Tahmini'), findsNWidgets(2));
  });

  testWidgets('veri hatası başlık kartında gösterilir', (tester) async {
    await tester.pumpWidget(_app(_FailingRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Etkinlikler yüklenemedi.'), findsOneWidget);
    expect(find.byTooltip('Tekrar dene'), findsOneWidget);
    expect(find.byType(VenuePin), findsNothing);
  });
}
