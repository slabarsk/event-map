import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/domain/app_user.dart';

class EventMapApp extends ConsumerWidget {
  const EventMapApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final role = ref.watch(authControllerProvider).value?.role ?? UserRole.user;
    return MaterialApp.router(
      title: 'Event Map',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(accent: AppColors.accentFor(role)),
      routerConfig: router,
    );
  }
}
