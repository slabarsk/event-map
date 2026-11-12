import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/consent_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/home/presentation/home_shell.dart';
import '../../features/home/presentation/home_screen.dart';
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
  static const profile = '/profile';
  static const settings = '/profile/settings';
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
        builder: (_, s) =>
            LoginScreen(role: UserRole.parse(s.pathParameters['role'])),
      ),
      GoRoute(
        path: '/auth/:role/register',
        builder: (_, s) =>
            RegisterScreen(role: UserRole.parse(s.pathParameters['role'])),
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
    ],
  );
});

/// Akış: giriş yok → karşılama; KVKK onayı yok → onay; onboarding bitmedi →
/// onboarding; hepsi tamam → ana sayfa.
String? _redirect(AsyncValue<AppUser?> auth, GoRouterState state) {
  final path = state.uri.path;
  final atAuthFlow = path == Routes.welcome || path.startsWith('/auth/');

  if (auth.isLoading && !auth.hasValue) {
    return path == Routes.splash ? null : Routes.splash;
  }

  final user = auth.value;
  if (user == null) return atAuthFlow ? null : Routes.welcome;

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
