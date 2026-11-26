import 'package:event_map/features/events/application/events_providers.dart';
import 'package:event_map/features/events/data/demo_events_repository.dart';
import 'package:event_map/features/events/domain/event.dart';
import 'package:event_map/features/events/presentation/venue_events_sheet.dart';
import 'package:event_map/features/map/presentation/map_screen.dart';
import 'package:event_map/features/saved/application/saved_providers.dart';
import 'package:event_map/features/saved/data/saved_events_repository.dart';
import 'package:event_map/features/saved/presentation/saved_screen.dart';
import 'package:event_map/features/search/application/search_providers.dart';
import 'package:event_map/features/search/domain/search_result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

final _now = DateTime.utc(2026, 11, 12, 7);

MapEvent _event(String id, {DateTime? startsAt}) => MapEvent(
  id: id,
  title: 'Etkinlik $id',
  startsAt: startsAt ?? _now.add(const Duration(hours: 10)),
  category: 'concert',
  venueId: 'v',
  venueName: 'Mekân',
  lat: 38.43,
  lng: 27.14,
);

class _FailingSaves extends DemoSavedEventsRepository {
  @override
  Future<void> save(MapEvent event) => Future.error(
    const SavedEventsFailure('Kayıtlı etkinlikler güncellenemedi.'),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('tr'));

  group('SavedIds', () {
    test('kaydet ve kaldır', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sub = container.listen(savedIdsProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(savedIdsProvider.future);

      final notifier = container.read(savedIdsProvider.notifier);
      expect(await notifier.toggle(_event('a')), isTrue);
      expect(container.read(savedIdsProvider).value, {'a'});
      expect(await notifier.toggle(_event('a')), isFalse);
      expect(container.read(savedIdsProvider).value, isEmpty);
    });

    test('sunucu hatasında geri alınır', () async {
      final container = ProviderContainer(
        overrides: [
          savedEventsRepositoryProvider.overrideWithValue(_FailingSaves()),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(savedIdsProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(savedIdsProvider.future);

      await expectLater(
        container.read(savedIdsProvider.notifier).toggle(_event('a')),
        throwsA(isA<SavedEventsFailure>()),
      );
      expect(container.read(savedIdsProvider).value, isEmpty);
    });
  });

  testWidgets('kartın yer imi butonu kaydeder, Kayıtlı ekranında görünür', (
    tester,
  ) async {
    final repo = DemoSavedEventsRepository();
    final event = _event('a');
    final past = _event('b', startsAt: _now.subtract(const Duration(days: 2)));
    await repo.save(past);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          savedEventsRepositoryProvider.overrideWithValue(repo),
          clockProvider.overrideWithValue(() => _now),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                EventCard(event: event, now: _now),
                const Expanded(child: SavedScreen()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('GEÇMİŞ'), findsOneWidget);
    expect(find.text('Etkinlik a'), findsOneWidget); // yalnızca kartta

    await tester.tap(find.byTooltip('Kaydet').first);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Kayıttan çıkar'), findsWidgets);
    expect(find.text('Etkinlik a'), findsNWidgets(2)); // kart + liste
    expect((await repo.ids()), {'a', 'b'});
  });

  testWidgets('arama sonucu haritada yalnızca kendi pinlerini gösterir', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [
        eventsRepositoryProvider.overrideWithValue(
          DemoEventsRepository(clock: () => _now),
        ),
        clockProvider.overrideWithValue(() => _now),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(mapSearchProvider.notifier)
        .show(
          SearchResult(
            query: 'Bu akşam ücretsiz konser',
            labels: const ['Bu akşam', 'Konser', 'Ücretsiz'],
            events: [_event('a')],
            location: const LatLng(38.42, 27.13),
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: MapScreen(showTiles: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bu akşam ücretsiz konser'), findsOneWidget);
    expect(find.byKey(const ValueKey('pin-v')), findsOneWidget);
    expect(find.byKey(const ValueKey('my-location')), findsOneWidget);

    await tester.tap(find.byTooltip('Aramayı temizle'));
    await tester.pumpAndSettle();
    expect(container.read(mapSearchProvider), isNull);
    expect(find.text('İzmir etkinlikleri'), findsOneWidget);
    expect(find.byKey(const ValueKey('my-location')), findsNothing);
  });
}
