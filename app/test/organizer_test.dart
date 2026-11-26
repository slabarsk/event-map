import 'package:event_map/features/admin/application/admin_providers.dart';
import 'package:event_map/features/admin/data/admin_repository.dart';
import 'package:event_map/features/admin/presentation/event_reviews_screen.dart';
import 'package:event_map/features/organizer/application/organizer_providers.dart';
import 'package:event_map/features/organizer/data/organizer_repository.dart';
import 'package:event_map/features/organizer/domain/organizer_event.dart';
import 'package:event_map/features/organizer/presentation/submit_event_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

/// 12 Kasım 2026, İzmir saatiyle 10:00. Form varsayılanı: yarın 20:00.
final _now = DateTime.utc(2026, 11, 12, 7);

void main() {
  setUpAll(() => initializeDateFormatting('tr'));

  test('EventDraft.toParams: kayıtlı mekânda yeni mekân alanları gitmez', () {
    final p = EventDraft(
      title: 'Caz',
      category: 'concert',
      startsAt: DateTime.utc(2026, 11, 13, 17),
      venueId: 'v1',
      venueName: 'yok sayılır',
      lat: 38,
      lng: 27,
      isFree: true,
      priceMin: 100,
    ).toParams();
    expect(p['p_venue_id'], 'v1');
    expect(p['p_venue_name'], isNull);
    expect(p['p_lat'], isNull);
    expect(p['p_is_free'], isTrue);
    expect(p['p_price_min'], isNull);
    expect(p['p_starts_at'], '2026-11-13T17:00:00.000Z');
  });

  group('SubmitEventScreen', () {
    late DemoOrganizerRepository repo;

    Future<void> pump(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      repo = DemoOrganizerRepository();
      final router = GoRouter(
        initialLocation: '/new',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: Text('PANEL')),
          ),
          GoRoute(
            path: '/new',
            builder: (_, _) => SubmitEventScreen(showTiles: false, now: _now),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [organizerRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> submit(WidgetTester tester) async {
      await tester.tap(find.text('Onaya gönder'));
      await tester.pumpAndSettle();
    }

    testWidgets('kategori seçilmeden gönderilemez', (tester) async {
      await pump(tester);
      await submit(tester);
      expect(find.text('Etkinlik adı gerekli'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('event-title')), 'Caz');
      await submit(tester);
      expect(find.text('Bir kategori seç.'), findsOneWidget);
      expect(await repo.myEvents(), isEmpty);
    });

    testWidgets('kayıtlı mekânla gönderir ve panele döner', (tester) async {
      await pump(tester);
      await tester.enterText(
        find.byKey(const ValueKey('event-title')),
        'Kordon Caz Gecesi',
      );
      await tester.tap(find.text('Konser'));
      await tester.enterText(
        find.byKey(const ValueKey('venue-search')),
        'saygun',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ahmet Adnan Saygun Sanat Merkezi'));
      await tester.pumpAndSettle();
      await submit(tester);

      expect(find.text('PANEL'), findsOneWidget);
      final events = await repo.myEvents();
      expect(events.single.title, 'Kordon Caz Gecesi');
      expect(events.single.status, EventStatus.pending);
      expect(events.single.venueName, 'Ahmet Adnan Saygun Sanat Merkezi');
      // Yarın 20:00 İzmir = 17:00 UTC.
      expect(events.single.startsAt, DateTime.utc(2026, 11, 13, 17));
    });

    testWidgets('yeni mekân için haritada konum ister', (tester) async {
      await pump(tester);
      await tester.enterText(
        find.byKey(const ValueKey('event-title')),
        'Atölye',
      );
      await tester.tap(find.text('Atölye').last);
      await tester.tap(find.text('Yeni mekân'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('venue-name')),
        'Bostanlı Sahne',
      );
      await submit(tester);
      expect(find.text('Mekânın yerini haritada işaretle.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('venue-map')));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.textContaining('Konum işaretlendi'), findsOneWidget);
      await submit(tester);

      expect(find.text('PANEL'), findsOneWidget);
      expect((await repo.myEvents()).single.venueName, 'Bostanlı Sahne');
    });
  });

  group('EventReviewsScreen', () {
    Future<DemoAdminRepository> pump(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = DemoAdminRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: Scaffold(body: EventReviewsScreen())),
        ),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('yayınlanınca listeden düşer', (tester) async {
      final repo = await pump(tester);
      expect(find.text('Alsancak Akustik Gece'), findsOneWidget);

      await tester.tap(find.text('Yayınla'));
      await tester.pumpAndSettle();

      expect(find.text('Onay bekleyen etkinlik yok'), findsOneWidget);
      expect(await repo.pendingEvents(), isEmpty);
    });

    testWidgets('red diyaloğunda vazgeçince değişmez, gerekçeyle reddedilir', (
      tester,
    ) async {
      final repo = await pump(tester);

      await tester.tap(find.text('Reddet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(await repo.pendingEvents(), hasLength(1));

      await tester.tap(find.text('Reddet'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Tarih geçmiş');
      await tester.tap(find.text('Reddet').last);
      await tester.pumpAndSettle();

      expect(find.text('Onay bekleyen etkinlik yok'), findsOneWidget);
    });
  });
}
