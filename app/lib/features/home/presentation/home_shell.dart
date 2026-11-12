import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/app_user.dart';

/// Ana sayfa ve profil; altta yüzen hap şeklinde gezinme çubuğu.
/// Organizatörlerde yanında siyah "etkinlik gönder" butonu durur.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value;
    final role = user?.role ?? UserRole.user;
    final onProfile = location.startsWith(Routes.profile);

    return Scaffold(
      extendBody: true,
      body: AuroraBackground(
        colors: AppColors.blobsFor(role),
        intensity: 0.6,
        child: child,
      ),
      // Kenar boşlukları güvenli alanın içinden verilir; yan çentikli ya da
      // yatay ekranlarda menü sistem şeridinin altına girmez.
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: MaxWidth(
            width: 440,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 66,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      gradient: AppColors.gradientFor(role),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accentFor(role)
                              .withValues(alpha: 0.4),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _NavItem(
                          icon: Icons.map_rounded,
                          label: 'Ana sayfa',
                          active: !onProfile,
                          role: role,
                          onTap: () => context.go(Routes.home),
                        ),
                        _NavItem(
                          icon: Icons.person_rounded,
                          label: 'Profil',
                          active: onProfile,
                          role: role,
                          onTap: () => context.go(Routes.profile),
                        ),
                      ],
                    ),
                  ),
                ),
                if (user?.isOrganizer ?? false) ...[
                  const SizedBox(width: 12),
                  _CreateButton(
                    approved: user!.organizerStatus == OrganizerStatus.approved,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.role,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final UserRole role;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      selected: active,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: active ? 18 : 14,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: active ? AppColors.accentFor(role) : Colors.white,
              ),
              if (active) ...[
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: AppColors.accentFor(role)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.approved});
  final bool approved;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Etkinlik gönder',
      child: Material(
        color: AppColors.ink,
        shape: const CircleBorder(),
        elevation: 6,
        shadowColor: AppColors.ink.withValues(alpha: 0.4),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => showMessage(
            context,
            approved
                ? 'Etkinlik gönderme yakında burada.'
                : 'Onaydan sonra etkinlik gönderebilirsin.',
          ),
          child: const SizedBox.square(
            dimension: 66,
            child: Icon(Icons.add_rounded, color: Colors.white, size: 30),
          ),
        ),
      ),
    );
  }
}
