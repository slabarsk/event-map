import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/catalog.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/widgets/auth_widgets.dart';
import '../../home/presentation/home_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value;
    if (user == null) return const SizedBox.shrink();
    final prefs = user.preferences;
    final org = user.organization;

    final stats = user.isOrganizer
        ? [
            ('${org?.categories.length ?? 0}', 'Kategori'),
            ('0', 'Yayında'),
            ('0', 'Kaydeden'),
          ]
        : [
            ('${prefs.categories.length}', 'İlgi alanı'),
            ('${prefs.radiusKm} km', 'Mesafe'),
            ('0', 'Kayıtlı'),
          ];

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 120),
      child: Column(
        children: [
          _ProfileHeader(user: user, stats: stats),
          SafeArea(
            top: false,
            bottom: false,
            child: MaxWidth(
              width: 560,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (user.isOrganizer) ...[
                      OrganizerStatusCard(status: user.organizerStatus),
                      const SizedBox(height: 24),
                    ],
                    const SectionLabel('Tercihler'),
                    GlassCard(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          if (user.isOrganizer)
                            _Tile(
                              icon: Icons.storefront_outlined,
                              title: 'Organizasyon bilgileri',
                              value: org?.name ?? '',
                              onTap: () => context.push(Routes.settings),
                            )
                          else ...[
                            _Tile(
                              icon: Icons.favorite_outline_rounded,
                              title: 'İlgi alanları',
                              value: prefs.categories
                                  .map(Catalog.category)
                                  .nonNulls
                                  .map((c) => c.label)
                                  .take(3)
                                  .join(', '),
                              onTap: () => context.push(Routes.settings),
                            ),
                            const Divider(indent: 64),
                            _Tile(
                              icon: Icons.place_outlined,
                              title: 'Bölge ve mesafe',
                              value:
                                  '${prefs.district ?? 'Konumuma göre'} · ${prefs.radiusKm} km',
                              onTap: () => context.push(Routes.settings),
                            ),
                            const Divider(indent: 64),
                            _Tile(
                              icon: Icons.payments_outlined,
                              title: 'Bütçe',
                              value: prefs.freeOnly
                                  ? 'Yalnızca ücretsiz'
                                  : Catalog.priceCapLabel(prefs.maxPrice),
                              onTap: () => context.push(Routes.settings),
                            ),
                            const Divider(indent: 64),
                            _Tile(
                              icon: Icons.notifications_none_rounded,
                              title: 'Bildirimler',
                              value: [
                                if (prefs.notifyWeekend) 'Hafta sonu',
                                if (prefs.notifyNearby) 'Yakınımda',
                              ].join(', ').ifEmpty('Kapalı'),
                              onTap: () => context.push(Routes.settings),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const SectionLabel('Hesap'),
                    GlassCard(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          _Tile(
                            icon: Icons.privacy_tip_outlined,
                            title: 'KVKK aydınlatma metni',
                            onTap: () => showKvkkSheet(context),
                          ),
                          const Divider(indent: 64),
                          _Tile(
                            icon: Icons.logout_rounded,
                            title: 'Çıkış yap',
                            onTap: () => ref
                                .read(authControllerProvider.notifier)
                                .signOut(),
                          ),
                          const Divider(indent: 64),
                          _Tile(
                            icon: Icons.delete_outline_rounded,
                            title: 'Hesabımı sil',
                            color: AppColors.error,
                            onTap: () => _confirmDelete(context, ref),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hesabını silmek istiyor musun?'),
        content: const Text(
          'Profilin, tercihlerin ve kayıtlı etkinliklerin kalıcı olarak silinir. Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kalıcı olarak sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(authControllerProvider.notifier).deleteAccount();
    } on AuthFailure catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }
}

/// Degrade başlık: büyük beyaz "PROFİL", avatar, ad ve istatistikler.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user, required this.stats});
  final AppUser user;
  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = user.isOrganizer
        ? const [Color(0xFFB79AF5), AppColors.plum]
        : const [Color(0xFFF7A9C0), AppColors.coral];
    final subtitle = user.isOrganizer
        ? [
            user.organization?.type,
            user.organization?.district,
          ].nonNulls.join(' · ')
        : (user.preferences.district ?? 'İzmir');
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(40)),
      ),
      child: SafeArea(
        bottom: false,
        child: MaxWidth(
          width: 560,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'PROFİL',
                      style: AppTheme.display(
                        44,
                        color: Colors.white,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    GlassIconButton(
                      icon: Icons.tune_rounded,
                      tooltip: 'Profil ayarları',
                      onPressed: () => context.push(Routes.settings),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: UserAvatar(user: user, size: 76, square: true),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.fullName.isEmpty
                                ? user.firstName
                                : user.fullName,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            user.email,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                          const SizedBox(height: 8),
                          RoleBadge(role: user.role, dense: true),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    for (final (i, (value, label)) in stats.indexed) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                value,
                                style: AppTheme.display(
                                  22,
                                  color: Colors.white,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                trUpper(label),
                                style: text.labelSmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(
                        Icons.place_rounded,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        subtitle,
                        style: text.bodyMedium?.copyWith(color: Colors.white),
                      ),
                    ],
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

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.value,
    this.onTap,
    this.color,
  });
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accent = color ?? Theme.of(context).colorScheme.primary;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: accent, size: 20),
      ),
      title: Text(
        title,
        style: text.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
      subtitle: value == null || value!.isEmpty
          ? null
          : Text(
              value!,
              style: text.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: color == null
          ? const Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint)
          : null,
    );
  }
}

/// Baş harflerden oluşan, role göre degrade avatar.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    this.size = 48,
    this.square = false,
  });
  final AppUser user;
  final double size;
  final bool square;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: square ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: square ? BorderRadius.circular(size * 0.3) : null,
        gradient: AppColors.gradientFor(user.role),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Text(
        user.initials,
        style: AppTheme.display(
          size * 0.38,
          color: Colors.white,
          weight: FontWeight.w700,
        ),
      ),
    );
  }
}
