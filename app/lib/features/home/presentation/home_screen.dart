import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/catalog.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/widgets/auth_widgets.dart';
import '../../auth/presentation/widgets/map_preview.dart';
import '../../profile/presentation/profile_screen.dart';

/// Role göre kullanıcı ana sayfası ya da organizatör paneli.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value;
    if (user == null) return const SizedBox.shrink();
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
        child: MaxWidth(
          width: 560,
          child: user.isOrganizer
              ? _OrganizerHome(user: user)
              : _UserHome(user: user),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.user,
    required this.title,
    this.accent,
    this.trailing,
  });
  final AppUser user;
  final String title;
  final String? accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => context.go(Routes.profile),
          child: UserAvatar(user: user, size: 50),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Merhaba ${user.firstName} 👋',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              DisplayTitle(title, accent: accent, size: 22),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _UserHome extends StatelessWidget {
  const _UserHome({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final prefs = user.preferences;
    final mine = prefs.categories.map(Catalog.category).nonNulls.toList();
    final others = Catalog.categories.where(
      (c) => !prefs.categories.contains(c.id),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          user: user,
          title: prefs.district ?? 'İzmir',
          accent: 'bu akşam',
          trailing: GlassIconButton(
            icon: Icons.notifications_none_rounded,
            tooltip: 'Bildirimler',
            onPressed: () => context.push(Routes.settings),
          ),
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () =>
              showMessage(context, 'Doğal dil araması yakında burada.'),
          child: GlassCard(
            radius: 999,
            padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Bu akşam yakınımdaki ücretsiz konserler…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium,
                  ),
                ),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientFor(user.role),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.search_rounded, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 86,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final c in mine)
                StoryCircle(icon: c.icon, label: c.label, color: c.color),
              for (final c in others)
                StoryCircle(
                  icon: c.icon,
                  label: c.label,
                  color: c.color,
                  active: false,
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        MapPreview(
          height: 300,
          stats: [('${prefs.radiusKm}', 'km'), ('${mine.length}', 'İlgi')],
        ),
        const SizedBox(height: 28),
        SectionHeader(
          'Bu akşam',
          accent: 'sana özel',
          action: 'Tümü',
          onAction: () {},
        ),
        const SizedBox(height: 14),
        GlassCard(
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.coralSoft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.event_available_rounded,
                  color: AppColors.coral,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Etkinlikler toplanmaya başladığında ilgi alanlarına göre burada listelenecek.',
                  style: text.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrganizerHome extends StatelessWidget {
  const _OrganizerHome({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final org = user.organization ?? const Organization();
    final approved = user.organizerStatus == OrganizerStatus.approved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          user: user,
          title: org.name.isEmpty ? 'Organizatör' : org.name,
          accent: 'paneli',
        ),
        const SizedBox(height: 20),
        OrganizerStatusCard(status: user.organizerStatus),
        const SizedBox(height: 16),
        Opacity(
          opacity: approved ? 1 : 0.5,
          child: PrimaryButton(
            label: 'Etkinlik gönder',
            icon: Icons.add_rounded,
            onPressed: () => showMessage(
              context,
              approved
                  ? 'Etkinlik gönderme yakında burada.'
                  : 'Onaydan sonra etkinlik gönderebilirsin.',
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Yayında',
                value: '0',
                color: AppColors.plum,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                label: 'Bekleyen',
                value: '0',
                color: AppColors.amber,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                label: 'Kaydeden',
                value: '0',
                color: AppColors.coral,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        SectionHeader(
          'Organizasyonun',
          action: 'Düzenle',
          onAction: () => context.push(Routes.settings),
        ),
        const SizedBox(height: 14),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                trUpper(org.name.isEmpty ? 'İsimsiz organizasyon' : org.name),
                style: AppTheme.display(22),
              ),
              const SizedBox(height: 4),
              Text(
                [org.type, org.district].nonNulls.join(' · '),
                style: text.bodyMedium,
              ),
              if (org.categories.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c
                        in org.categories.map(Catalog.category).nonNulls)
                      CategoryChip(category: c, selected: true, onTap: () {}),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 24,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(
        children: [
          Text(
            value,
            style: AppTheme.display(32, color: color, weight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            trUpper(label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.inkSoft,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class OrganizerStatusCard extends StatelessWidget {
  const OrganizerStatusCard({super.key, required this.status});
  final OrganizerStatus? status;

  @override
  Widget build(BuildContext context) {
    final (color, icon, title, body) = switch (status) {
      OrganizerStatus.approved => (
        AppColors.success,
        Icons.verified_rounded,
        'Hesabın onaylı',
        'Etkinliklerin onaydan sonra haritada yayınlanır.',
      ),
      OrganizerStatus.rejected => (
        AppColors.error,
        Icons.error_outline_rounded,
        'Başvurun onaylanmadı',
        'Ayrıntılar için e-postanı kontrol et.',
      ),
      _ => (
        AppColors.amber,
        Icons.hourglass_top_rounded,
        'Onay bekliyor',
        'Bilgilerini inceliyoruz, genellikle 1–2 iş günü sürer.',
      ),
    };
    final text = Theme.of(context).textTheme;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trUpper(title), style: AppTheme.display(17)),
                Text(
                  body,
                  style: text.bodySmall?.copyWith(color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
