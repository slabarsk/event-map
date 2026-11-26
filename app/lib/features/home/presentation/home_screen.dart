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
import '../../events/application/events_providers.dart';
import '../../events/domain/event.dart';
import '../../events/domain/event_format.dart';
import '../../events/presentation/event_visuals.dart';
import '../../events/presentation/venue_events_sheet.dart';
import '../../organizer/application/organizer_providers.dart';
import '../../organizer/data/organizer_repository.dart';
import '../../organizer/domain/organizer_event.dart';
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
          key: const ValueKey('home-search'),
          onTap: () => context.push(Routes.search()),
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
        Semantics(
          button: true,
          label: 'Haritayı aç',
          child: GestureDetector(
            onTap: () => context.go(Routes.map),
            child: MapPreview(
              height: 300,
              stats: [('${prefs.radiusKm}', 'km'), ('${mine.length}', 'İlgi')],
            ),
          ),
        ),
        const SizedBox(height: 28),
        SectionHeader(
          'Bu akşam',
          accent: 'sana özel',
          action: 'Tümü',
          onAction: () => context.push(Routes.search('Bu akşam')),
        ),
        const SizedBox(height: 14),
        _TonightList(interests: prefs.categories),
      ],
    );
  }
}

/// Bu akşamki (17:00–03:00) etkinlikler; önce ilgi alanlarına uyanlar.
class _TonightList extends ConsumerWidget {
  const _TonightList({required this.interests});
  final Set<String> interests;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.read(clockProvider)();
    final async = ref.watch(upcomingEventsProvider);
    if (async.isLoading && !async.hasValue) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // Veri yüklenemediyse boş durum gösterilir; harita sekmesi hatayı ayrıca
    // ve "Tekrar dene" ile gösterir.
    final events = async.value ?? const <MapEvent>[];
    final dayStart = EventFormat.istanbulDayStart(now);
    final eveningEnd = dayStart.add(const Duration(hours: 27));
    final tonight =
        events.where((e) => e.startsAt.isBefore(eveningEnd)).toList()
          ..sort((a, b) {
            final ai = interests.contains(a.category) ? 0 : 1;
            final bi = interests.contains(b.category) ? 0 : 1;
            return ai != bi ? ai - bi : a.startsAt.compareTo(b.startsAt);
          });
    if (tonight.isEmpty) {
      return GlassCard(
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
                'Bu akşam için etkinlik görünmüyor. Hafta sonuna göz atmak ister misin?',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final MapEvent e in tonight.take(3)) ...[
          EventCard(event: e, now: now, showVenue: true),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _OrganizerHome extends ConsumerWidget {
  const _OrganizerHome({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final org = user.organization ?? const Organization();
    final approved = user.organizerStatus == OrganizerStatus.approved;
    final stats = ref.watch(organizerStatsProvider).value;
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
            onPressed: () => approved
                ? context.push(Routes.submitEvent)
                : showMessage(
                    context,
                    'Onaydan sonra etkinlik gönderebilirsin.',
                  ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Yayında',
                value: '${stats?.published ?? 0}',
                color: AppColors.plum,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                label: 'Bekleyen',
                value: '${stats?.pending ?? 0}',
                color: AppColors.amber,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                label: 'Kaydeden',
                value: '${stats?.saves ?? 0}',
                color: AppColors.coral,
              ),
            ),
          ],
        ),
        if (approved) ...[
          const SizedBox(height: 28),
          const SectionHeader('Etkinliklerin'),
          const SizedBox(height: 14),
          const _MyEvents(),
        ],
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

/// Organizatörün gönderdiği etkinlikler ve durumları.
class _MyEvents extends ConsumerWidget {
  const _MyEvents();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final now = ref.read(clockProvider)();
    return switch (ref.watch(myEventsProvider)) {
      AsyncData(:final value) when value.isEmpty => GlassCard(
        child: Text(
          'Henüz etkinlik göndermedin. Gönderdiğin etkinlikler onay durumuyla burada görünür.',
          style: text.bodyMedium,
        ),
      ),
      AsyncData(:final value) => Column(
        children: [
          for (final e in value) ...[
            _MyEventTile(event: e, now: now),
            const SizedBox(height: 10),
          ],
        ],
      ),
      AsyncError(:final error) => GlassCard(
        child: Text('$error', style: text.bodyMedium),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _MyEventTile extends ConsumerWidget {
  const _MyEventTile({required this.event, required this.now});
  final OrganizerEvent event;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final cat = eventCategoryOf(event.category);
    final color = switch (event.status) {
      EventStatus.published => AppColors.success,
      EventStatus.pending => AppColors.amber,
      EventStatus.rejected => AppColors.error,
    };
    return GlassCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(cat.icon, color: cat.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.title, style: text.titleSmall),
                    Text(
                      [
                        EventFormat.when(event.startsAt, now: now),
                        ?event.venueName,
                      ].join(' · '),
                      style: text.bodySmall?.copyWith(color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  event.status.label,
                  style: text.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (event.status == EventStatus.pending)
                IconButton(
                  tooltip: 'Geri çek',
                  icon: const Icon(Icons.undo_rounded, size: 20),
                  onPressed: () => _withdraw(context, ref),
                ),
            ],
          ),
          if (event.status == EventStatus.rejected &&
              (event.reviewNote?.isNotEmpty ?? false)) ...[
            const SizedBox(height: 8),
            Text(
              'Gerekçe: ${event.reviewNote}',
              style: text.bodySmall?.copyWith(color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Etkinliği geri çek?'),
        content: Text('"${event.title}" onay listesinden kaldırılır.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Geri çek'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(organizerRepositoryProvider).withdraw(event.id);
      refreshOrganizer(ref);
    } on OrganizerFailure catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
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
