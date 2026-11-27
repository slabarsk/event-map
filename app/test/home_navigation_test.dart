import 'package:event_map/features/auth/application/auth_controller.dart';
import 'package:event_map/features/auth/data/auth_repository.dart';
import 'package:event_map/features/auth/domain/app_user.dart';
import 'package:event_map/features/events/application/events_providers.dart';
import 'package:event_map/features/events/data/demo_events_repository.dart';
import 'package:event_map/features/home/presentation/home_screen.dart';
import 'package:event_map/features/map/application/map_filter_provider.dart';
import 'package:event_map/features/map/domain/map_filters.dart';
import 'package:event_map/features/search/application/search_providers.dart';
import 'package:event_map/features/search/domain/search_result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

class _Auth implements AuthRepository {
  @override
  Stream<AppUser?> authStateChanges() => const Stream.empty();
  @override
  Future<AppUser?> currentUser() async => AppUser(
    id: 'user',
    fullName: 'Deniz Test',
    email: 'deniz@test.local',
    role: UserRole.user,
    onboardingCompleted: true,
    kvkkConsentAt: DateTime(2026, 11, 1),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

  Future<(ProviderContainer, GoRouter)> pumpHome(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.utc(2026, 11, 27, 7);
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_Auth()),
        eventsRepositoryProvider.overrideWithValue(
          DemoEventsRepository(clock: () => now),
        ),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    // Önceki bir arama ve elle seçilen filtre yeni keşfi daraltmamalı.
    container
        .read(mapSearchProvider.notifier)
        .show(
          const SearchResult(query: 'önceki arama', labels: [], events: []),
        );
    container
        .read(mapFiltersProvider.notifier)
        .apply(const MapFilters(freeOnly: true));
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) =>
              const Scaffold(body: HomeScreen(showMapTiles: false)),
        ),
        GoRoute(
          path: '/map',
          builder: (_, _) => const Scaffold(body: Text('Harita açıldı')),
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
    return (container, router);
  }

  testWidgets(
    'kategoriye dokununca yalnızca o kategori seçilerek harita açılır',
    (tester) async {
      final (container, router) = await pumpHome(tester);
      await tester.tap(find.text('Konser').first);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/map');
      expect(container.read(mapFiltersProvider).categories, {'concert'});
      expect(container.read(mapFiltersProvider).freeOnly, isFalse);
      expect(container.read(mapSearchProvider), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('gerçek harita önizlemesi tüm etkinlikleri keşfe açar', (
    tester,
  ) async {
    final (container, router) = await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('home-map-preview')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/map');
    expect(container.read(mapFiltersProvider).activeCount, 0);
    expect(container.read(mapSearchProvider), isNull);
  });
}
