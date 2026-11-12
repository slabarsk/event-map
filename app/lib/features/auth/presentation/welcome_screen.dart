import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/catalog.dart';
import '../../../core/config/env.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../../core/widgets/common.dart';
import '../domain/app_user.dart';
import 'widgets/map_preview.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: MaxWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const BrandMark(),
                      const Spacer(),
                      if (!Env.hasSupabase)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.glass(0.8),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Demo',
                            style: text.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  MapPreview(
                    height: 300,
                    stats: [
                      ('5+', 'Kaynak'),
                      ('${Catalog.districts.length}', 'İlçe'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const _CategoryStrip(),
                  const SizedBox(height: 26),
                  const DisplayTitle(
                    'İzmir\'de bu akşam',
                    accent: 'ne var?',
                    size: 44,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Konserden sergiye şehrin etkinlikleri tek haritada; tarihi, mekânı ve fiyatıyla.',
                    style: text.bodyLarge?.copyWith(color: AppColors.inkSoft),
                  ),
                  const SizedBox(height: 26),
                  _RoleCard(
                    role: UserRole.user,
                    icon: Icons.explore_rounded,
                    title: 'Etkinlik keşfet',
                    body: 'Yakınındaki etkinlikleri bul, filtrele, kaydet.',
                    onTap: () => context.go(Routes.login(UserRole.user)),
                  ),
                  const SizedBox(height: 12),
                  _RoleCard(
                    role: UserRole.organizer,
                    icon: Icons.campaign_rounded,
                    title: 'Organizatörüm',
                    body: 'Etkinliklerini yayınla, haritada görünür ol.',
                    onTap: () => context.go(Routes.login(UserRole.organizer)),
                  ),
                  if (!Env.hasSupabase) ...[
                    const SizedBox(height: 18),
                    Center(
                      child: Text(
                        'Demo modu · veriler yalnızca bu cihazda',
                        style: text.bodySmall,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Haritanın altında story tarzı kategori satırı.
class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: Catalog.categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (_, i) {
          final c = Catalog.categories[i];
          return StoryCircle(icon: c.icon, label: c.label, color: c.color);
        },
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final UserRole role;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentFor(role);
    final text = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        radius: 26,
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppColors.accentSoftFor(role),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: accent, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(trUpper(title), style: AppTheme.display(19)),
                  const SizedBox(height: 2),
                  Text(body, style: text.bodyMedium),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: AppColors.gradientFor(role),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
