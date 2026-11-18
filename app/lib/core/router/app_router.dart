import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/admin/presentation/admin_login_screen.dart';
import '../../features/admin/presentation/admin_shell.dart';
import '../../features/admin/presentation/application_detail_screen.dart';
import '../../features/admin/presentation/applications_screen.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/consent_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/home/presentation/home_shell.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/map/presentation/map_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/settings_screen.dart';

abstract final class Routes {
  static const splash = '/';
  static const welcome = '/welcome';
  static String login(UserRole role) => '/auth/${role.name}/login';
  static String register(UserRole role) => '/auth/${role.name}/register';
  static const consent = '/consent';
  static const onboarding = '/onboarding';
  static const home = '/home';
  static const map = '/map';
  static const profile = '/profile';
  static const settings = '/profile/settings';

  // Web yönetim paneli; yalnızca role = 'admin'.
  static const admin = '/admin';
  static const adminLogin = '/admin/login';
  static String adminList(OrganizerStatus status) =>
      status == OrganizerStatus.pending ? admin : '$admin?durum=${status.name}';
  static String adminApplication(String id) => '$admin/applications/$id';
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) =>
        _redirect(ref.read(authControllerProvider), state),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(
        path: '/auth/:role/login',
        builder: (_, s) => LoginScreen(role: _authRole(s)),
      ),
      GoRoute(
        path: '/auth/:role/register',
        builder: (_, s) => RegisterScreen(role: _authRole(s)),
      ),
      GoRoute(path: Routes.consent, builder: (_, _) => const ConsentScreen()),
      GoRoute(
        path: Routes.onboarding,
        builder: (_, _) => const OnboardingScreen(),
      ),
      ShellRoute(
        builder: (_, state, child) =>
            HomeShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: Routes.home,
            pageBuilder: (_, _) => const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: Routes.map,
            pageBuilder: (_, _) => const NoTransitionPage(child: MapScreen()),
          ),
          GoRoute(
            path: Routes.profile,
            pageBuilder: (_, _) =>
                const NoTransitionPage(child: ProfileScreen()),
          ),
        ],
      ),
      GoRoute(
        path: Routes.settings,
        builder: (_, s) => SettingsScreen(
          fromOnboarding: s.uri.queryParameters['from'] == 'onboarding',
        ),
      ),
      GoRoute(
        path: Routes.adminLogin,
        builder: (_, _) => const AdminLoginScreen(),
      ),
      ShellRoute(
        builder: (_, _, child) => AdminShell(child: child),
        routes: [
          GoRoute(
            path: Routes.admin,
            pageBuilder: (_, s) => NoTransitionPage(
              child: ApplicationsScreen(
                status:
                    OrganizerStatus.parse(s.uri.queryParameters['durum']) ??
                    OrganizerStatus.pending,
              ),
            ),
          ),
          GoRoute(
            path: '/admin/applications/:id',
            pageBuilder: (_, s) => NoTransitionPage(
              child: ApplicationDetailScreen(id: s.pathParameters['id']!),
            ),
          ),
        ],
      ),
    ],
  );
});

/// Giriş/kayıt ekranları yalnızca kullanıcı ve organizatör içindir; admin
/// girişi [Routes.adminLogin].
UserRole _authRole(GoRouterState s) => s.pathParameters['role'] == 'organizer'
    ? UserRole.organizer
    : UserRole.user;

/// Akış: giriş yok → karşılama; KVKK onayı yok → onay; onboarding bitmedi →
/// onboarding; hepsi tamam → ana sayfa.
///
/// `/admin` altı ayrı kurallıdır: giriş yoksa admin girişi, admin değilse ana
/// akış, admin ise panel. Admin'in açılış ekranı paneldir.
String? _redirect(AsyncValue<AppUser?> auth, GoRouterState state) {
  final path = state.uri.path;
  final atAuthFlow = path == Routes.welcome || path.startsWith('/auth/');
  final atAdmin = path == Routes.admin || path.startsWith('${Routes.admin}/');

  if (auth.isLoading && !auth.hasValue) {
    if (path == Routes.splash) return null;
    // Web'de doğrudan açılan /admin adresi oturum yüklenince geri gelsin.
    return atAdmin
        ? Uri(
            path: Routes.splash,
            queryParameters: {'next': state.uri.toString()},
          ).toString()
        : Routes.splash;
  }

  final user = auth.value;
  final next = state.uri.queryParameters['next'];
  if (path == Routes.splash && next != null && next.startsWith(Routes.admin)) {
    return next;
  }

  if (atAdmin) {
    if (user == null) {
      return path == Routes.adminLogin ? null : Routes.adminLogin;
    }
    if (!user.isAdmin) return Routes.home;
    return path == Routes.adminLogin ? Routes.admin : null;
  }

  if (user == null) return atAuthFlow ? null : Routes.welcome;
  if (user.isAdmin && (atAuthFlow || path == Routes.splash)) {
    return Routes.admin;
  }

  if (user.kvkkConsentAt == null) {
    return path == Routes.consent ? null : Routes.consent;
  }
  if (!user.onboardingCompleted) {
    return path == Routes.onboarding ? null : Routes.onboarding;
  }
  if (atAuthFlow ||
      path == Routes.splash ||
      path == Routes.consent ||
      path == Routes.onboarding) {
    return Routes.home;
  }
  return null;
}
