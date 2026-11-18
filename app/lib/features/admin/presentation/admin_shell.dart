import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/auth_controller.dart';
import 'widgets/admin_widgets.dart';

/// Admin panelinin iskeleti: geniş ekranda solda menü, dar ekranda üst çubuk.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value;
    final name = user?.fullName.trim().isNotEmpty == true
        ? user!.fullName
        : (user?.email ?? 'Admin');

    Future<void> signOut() =>
        ref.read(authControllerProvider.notifier).signOut();

    return Scaffold(
      body: AuroraBackground(
        intensity: 0.6,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= adminWideBreakpoint;
              if (!wide) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          const BrandMark(size: 36),
                          const Spacer(),
                          GlassIconButton(
                            tooltip: 'Çıkış yap',
                            icon: Icons.logout_rounded,
                            onPressed: signOut,
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: child),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 0, 20),
                    child: SizedBox(
                      width: 260,
                      child: _Sidebar(name: name, onSignOut: signOut),
                    ),
                  ),
                  Expanded(child: child),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.name, required this.onSignOut});
  final String name;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(fit: BoxFit.scaleDown, child: BrandMark(size: 40)),
          ),
          const SizedBox(height: 28),
          const SectionLabel('Yönetim'),
          Material(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.go(Routes.admin),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(Icons.how_to_reg_rounded, color: accent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Organizatör başvuruları',
                        style: text.labelLarge?.copyWith(color: accent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          const Divider(),
          const SizedBox(height: 14),
          Row(
            children: [
              InitialsAvatar(name, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelLarge,
                    ),
                    Text('Admin', style: text.bodySmall),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Çıkış yap',
                onPressed: onSignOut,
                icon: const Icon(
                  Icons.logout_rounded,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
