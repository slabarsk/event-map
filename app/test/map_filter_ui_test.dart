import 'package:event_map/core/location/location_service.dart';
import 'package:event_map/features/events/application/events_providers.dart';
import 'package:event_map/features/events/data/demo_events_repository.dart';
import 'package:event_map/features/events/domain/event.dart';
import 'package:event_map/features/home/presentation/event_map_preview.dart';
import 'package:event_map/features/map/application/map_filter_provider.dart';
import 'package:event_map/features/map/domain/map_filters.dart';
import 'package:event_map/features/map/presentation/map_screen.dart';
import 'package:event_map/features/map/presentation/widgets/event_map_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

class _Location implements LocationService {
  _Location(this.result);
  final LatLng? result;
  int requests = 0;
  @override
  Future<LatLng?> current() async {
    requests++;
    return result;
  }
}

final _now = DateTime.utc(2026, 11, 27, 7);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  LocationService? location,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(
    overrides: [
      eventsRepositoryProvider.overrideWithValue(
        DemoEventsRepository(clock: () => _now),
      ),
      clockProvider.overrideWithValue(() => _now),
      if (location != null) locationServiceProvider.overrideWithValue(location),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: MapScreen(showTiles: false)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _openFilters(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-map-filters')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('tr');
  });
  setUp(() {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if ('${details.exception}'.contains('GoogleFonts')) return;
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
  });

  testWidgets('filtreler uygulanır, tekrar açılınca korunur ve temizlenir', (
    tester,
  ) async {
    final container = await _pump(tester);
    await _openFilters(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Yarın'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilterChip, 'Konser'));
    await tester.tap(find.widgetWithText(FilterChip, 'Konser'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-map-filters')));
    await tester.pumpAndSettle();
    expect(container.read(mapFiltersProvider).date, MapDateFilter.tomorrow);
    expect(container.read(mapFiltersProvider).categories, {'concert'});
    expect(find.text('Filtreler · 2'), findsOneWidget);
    await _openFilters(tester);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Yarın'))
          .selected,
      isTrue,
    );
    await tester.tap(find.byTooltip('Kapat'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Sıfırla'));
    await tester.pumpAndSettle();
    expect(container.read(mapFiltersProvider).activeCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panel kapatılırsa taslak seçimler uygulanmaz', (tester) async {
    final container = await _pump(tester);
    await _openFilters(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Bugün'));
    await tester.tap(find.byTooltip('Kapat'));
    await tester.pumpAndSettle();
    expect(container.read(mapFiltersProvider).activeCount, 0);
  });

  testWidgets('mesafe için izin reddedilirse filtre sessizce uygulanmaz', (
    tester,
  ) async {
    final location = _Location(null);
    final container = await _pump(tester, location: location);
    expect(location.requests, 0);
    await _openFilters(tester);
    final distance = find.widgetWithText(ChoiceChip, '5 km');
    await tester.ensureVisible(distance);
    await tester.tap(distance);
    await tester.pumpAndSettle();
    expect(location.requests, 1);
    expect(find.textContaining('Konum alınamadı.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('apply-map-filters')));
    await tester.pumpAndSettle();
    expect(container.read(mapFiltersProvider).radiusKm, isNull);
  });

  testWidgets('mesafe seçilince cihaz konumu ile filtrelenir', (tester) async {
    final location = _Location(const LatLng(38.43, 27.14));
    final container = await _pump(tester, location: location);
    await _openFilters(tester);
    final distance = find.widgetWithText(ChoiceChip, '2 km');
    await tester.ensureVisible(distance);
    await tester.tap(distance);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-map-filters')));
    await tester.pumpAndSettle();
    expect(container.read(mapFiltersProvider).radiusKm, 2);
    expect(find.byKey(const ValueKey('my-location')), findsOneWidget);
    final events = container
        .read(venueGroupsProvider)
        .requireValue
        .expand((g) => g.events);
    expect(events, isNotEmpty);
    expect(
      events.every(
        (e) =>
            const Distance().as(
              LengthUnit.Meter,
              location.result!,
              LatLng(e.lat, e.lng),
            ) <=
            2000,
      ),
      isTrue,
    );
  });

  testWidgets(
    'önizleme gerçek etkinlik/mekân sayısını gösterir ve haritayı açar',
    (tester) async {
      var opened = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eventsRepositoryProvider.overrideWithValue(
              DemoEventsRepository(clock: () => _now),
            ),
            clockProvider.overrideWithValue(() => _now),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: EventMapPreview(
                showTiles: false,
                onOpen: () => opened = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('12 etkinlik · 8 mekân'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-map-preview')));
      expect(opened, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('boş filtre sonucu temizlenince etkinlikler geri gelir', (
    tester,
  ) async {
    final container = await _pump(tester);
    container
        .read(mapFiltersProvider.notifier)
        .apply(const MapFilters(categories: {'nonexistent'}));
    await tester.pumpAndSettle();
    expect(
      find.text('Bu filtrelere uygun etkinlik bulunamadı.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Filtreleri temizle'));
    await tester.pumpAndSettle();
    expect(container.read(venueGroupsProvider).requireValue, isNotEmpty);
    expect(find.text('Bu filtrelere uygun etkinlik bulunamadı.'), findsNothing);
  });

  testWidgets('aynı koordinattaki mekânlar en yüksek zoomda da açılır', (
    tester,
  ) async {
    MapEvent event(String id) => MapEvent(
      id: id,
      title: 'Etkinlik $id',
      startsAt: _now.add(const Duration(hours: 10)),
      category: 'concert',
      venueId: id,
      venueName: 'Mekân $id',
      lat: 38.43,
      lng: 27.14,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: EventMapView(
              groups: [
                VenueGroup([event('a')]),
                VenueGroup([event('b')]),
              ],
              showTiles: false,
              initialZoom: 18,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('2 mekânı göster'));
    await tester.pumpAndSettle();
    expect(find.text('Mekân a'), findsOneWidget);
    expect(find.text('Mekân b'), findsOneWidget);
    await tester.tap(find.text('Mekân b'));
    await tester.pumpAndSettle();
    expect(find.text('Etkinlik b'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
