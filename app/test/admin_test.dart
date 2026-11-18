import 'package:event_map/core/router/app_router.dart';
import 'package:event_map/core/theme/app_theme.dart';
import 'package:event_map/features/admin/application/admin_providers.dart';
import 'package:event_map/features/admin/data/admin_repository.dart';
import 'package:event_map/features/admin/presentation/admin_login_screen.dart';
import 'package:event_map/features/admin/presentation/applications_screen.dart';
import 'package:event_map/features/admin/presentation/application_detail_screen.dart';
import 'package:event_map/features/auth/application/auth_controller.dart';
import 'package:event_map/features/auth/data/auth_repository.dart';
import 'package:event_map/features/auth/domain/app_user.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

/// Sabit bir kullanıcıyla oturum açmış gibi davranan auth.
class _FakeAuth implements AuthRepository {
  _FakeAuth(this.user);
  final AppUser? user;

  @override
  Stream<AppUser?> authStateChanges() => const Stream.empty();
  @override
  Future<AppUser?> currentUser() async => user;
  int signOuts = 0;

  @override
  Future<void> signOut() async => signOuts++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AppUser _user(UserRole role) => AppUser(
  id: 'u-${role.name}',
  email: '${role.name}@test.local',
  fullName: 'Test ${role.name}',
  role: role,
  onboardingCompleted: true,
  kvkkConsentAt: DateTime(2026, 11, 1),
);

class _Harness {
  _Harness(
    this.tester, {
    AppUser? user,
    bool loggedIn = true,
    this.adminOnly = false,
  }) : repo = DemoAdminRepository(),
       auth = _FakeAuth(loggedIn ? user ?? _user(UserRole.admin) : null);

  final WidgetTester tester;
  final DemoAdminRepository repo;
  final _FakeAuth auth;
  final bool adminOnly;
  late final ProviderContainer container;

  GoRouter get router => container.read(routerProvider);

  Future<void> pump(String location) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        adminRepositoryProvider.overrideWithValue(repo),
        adminOnlyProvider.overrideWithValue(adminOnly),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: ref.watch(routerProvider),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    router.go(location);
    await tester.pumpAndSettle();
  }

  String get location =>
      router.routerDelegate.currentConfiguration.uri.toString();
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('tr');
  });

  // Google Fonts testte ağdan font indiremez; bu hatalar ekranı etkilemez.
  setUp(() {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if ('${details.exception}'.contains('GoogleFonts')) return;
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
  });

  group('erişim', () {
    testWidgets('giriş yapmamış kullanıcı admin girişine yönlenir', (
      tester,
    ) async {
      final h = _Harness(tester, loggedIn: false);
      await h.pump(Routes.admin);
      expect(find.byType(AdminLoginScreen), findsOneWidget);
      expect(h.location, Routes.adminLogin);
    });

    testWidgets('normal kullanıcı paneli açamaz, ana sayfaya yönlenir', (
      tester,
    ) async {
      final h = _Harness(tester, user: _user(UserRole.user));
      await h.pump('/admin');
      expect(find.byType(ApplicationsScreen), findsNothing);
      expect(h.location, Routes.home);
    });

    testWidgets('organizatör paneli açamaz', (tester) async {
      final h = _Harness(tester, user: _user(UserRole.organizer));
      await h.pump('/admin/applications/demo-1');
      expect(find.byType(ApplicationDetailScreen), findsNothing);
      expect(h.location, Routes.home);
    });

    testWidgets('admin açılışta panele gider', (tester) async {
      final h = _Harness(tester);
      await h.pump(Routes.splash);
      expect(find.byType(ApplicationsScreen), findsOneWidget);
      expect(h.location, Routes.admin);
    });
  });

  group('admin-only derleme', () {
    testWidgets('uygulama rotaları admin girişine gider', (tester) async {
      final h = _Harness(tester, loggedIn: false, adminOnly: true);
      await h.pump(Routes.welcome);
      expect(find.byType(AdminLoginScreen), findsOneWidget);
      expect(h.location, Routes.adminLogin);
    });

    testWidgets('admin olmayan oturum kapatılır ve uyarı gösterilir', (
      tester,
    ) async {
      final h = _Harness(tester, user: _user(UserRole.user), adminOnly: true);
      await h.pump(Routes.home);

      expect(find.byType(AdminLoginScreen), findsOneWidget);
      expect(h.auth.signOuts, 1);
      expect(
        find.text('Bu hesabın yönetim paneline erişim yetkisi yok.'),
        findsOneWidget,
      );
    });

    testWidgets('admin uygulama rotasından panele yönlenir', (tester) async {
      final h = _Harness(tester, adminOnly: true);
      await h.pump(Routes.map);
      expect(find.byType(ApplicationsScreen), findsOneWidget);
      expect(h.location, Routes.admin);
    });
  });

  group('başvuru listesi', () {
    testWidgets('varsayılan olarak bekleyen başvurular listelenir', (
      tester,
    ) async {
      final h = _Harness(tester);
      await h.pump(Routes.admin);

      expect(find.text('Deniz Kaya'), findsOneWidget);
      expect(find.text('Alsancak Sahne'), findsOneWidget);
      expect(find.text('Ece Arslan'), findsOneWidget);
      expect(find.text('Mert Demir'), findsNothing);
      expect(find.text('17 Kas 2026, 14:20'), findsOneWidget);
    });

    testWidgets('durum filtresi onaylananları ve boş durumu gösterir', (
      tester,
    ) async {
      final h = _Harness(tester);
      await h.pump(Routes.admin);

      await tester.tap(find.text('Onaylanan'));
      await tester.pumpAndSettle();
      expect(h.location, '/admin?durum=approved');
      expect(find.text('Mert Demir'), findsOneWidget);
      expect(find.text('Deniz Kaya'), findsNothing);

      await tester.tap(find.text('Reddedilen'));
      await tester.pumpAndSettle();
      expect(find.text('Reddedilen başvuru yok'), findsOneWidget);
    });

    testWidgets('satıra tıklayınca detay açılır', (tester) async {
      final h = _Harness(tester);
      await h.pump(Routes.admin);

      await tester.tap(find.byKey(const ValueKey('application-demo-1')));
      await tester.pumpAndSettle();

      expect(find.byType(ApplicationDetailScreen), findsOneWidget);
      expect(find.text('Mekân'), findsOneWidget);
      expect(find.text('@alsancaksahne'), findsOneWidget);
      expect(find.text('organizator-demo-1@ornek.test'), findsOneWidget);
      expect(find.text('Konser'), findsOneWidget);
    });
  });

  group('başvuru detayı', () {
    testWidgets('onay diyaloğu onaylanınca başvuru onaylanır', (tester) async {
      final h = _Harness(tester);
      await h.pump(Routes.adminApplication('demo-1'));

      await tester.tap(find.byKey(const ValueKey('decide-approved')));
      await tester.pumpAndSettle();
      expect(find.text('Başvuru onaylansın mı?'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('confirm-decision')));
      await tester.pumpAndSettle();

      expect(
        (await h.repo.application('demo-1'))!.status,
        OrganizerStatus.approved,
      );
      expect(find.text('Başvuru onaylandı.'), findsOneWidget);
      expect(find.text('Onaylandı'), findsOneWidget);
      // Onaylı başvuruda yalnızca geri alma (Reddet) kalır.
      expect(find.byKey(const ValueKey('decide-approved')), findsNothing);
      expect(find.byKey(const ValueKey('decide-rejected')), findsOneWidget);
    });

    testWidgets('red diyaloğunda vazgeçince durum değişmez', (tester) async {
      final h = _Harness(tester);
      await h.pump(Routes.adminApplication('demo-2'));

      await tester.tap(find.byKey(const ValueKey('decide-rejected')));
      await tester.pumpAndSettle();
      expect(find.text('Başvuru reddedilsin mi?'), findsOneWidget);

      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();

      expect(
        (await h.repo.application('demo-2'))!.status,
        OrganizerStatus.pending,
      );
    });

    testWidgets('red onaylanınca başvuru reddedilir', (tester) async {
      final h = _Harness(tester);
      await h.pump(Routes.adminApplication('demo-2'));

      await tester.tap(find.byKey(const ValueKey('decide-rejected')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-decision')));
      await tester.pumpAndSettle();

      expect(
        (await h.repo.application('demo-2'))!.status,
        OrganizerStatus.rejected,
      );
      expect(find.text('Başvuru reddedildi.'), findsOneWidget);
    });

    testWidgets('bilinmeyen başvuru için bulunamadı mesajı', (tester) async {
      final h = _Harness(tester);
      await h.pump(Routes.adminApplication('yok'));
      expect(find.text('Başvuru bulunamadı'), findsOneWidget);
    });
  });
}
