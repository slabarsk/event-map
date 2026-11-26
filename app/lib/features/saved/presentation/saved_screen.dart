import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common.dart';
import '../../events/application/events_providers.dart';
import '../../events/domain/event.dart';
import '../../events/presentation/venue_events_sheet.dart';
import '../application/saved_providers.dart';

/// Kayıtlı etkinlikler: yaklaşanlar üstte, geçmişler altta.
class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedEventsProvider);
    // Kaydet/kaldır anında listeyi tazelemek için kimlikleri de izle.
    final ids = ref.watch(savedIdsProvider).value;
    final now = ref.read(clockProvider)();

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(savedIdsProvider);
          ref.invalidate(savedEventsProvider);
          await ref.read(savedEventsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            MaxWidth(
              width: 560,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const DisplayTitle('Kayıtlı', accent: 'etkinlikler'),
                  const SizedBox(height: 18),
                  ...switch (saved) {
                    AsyncData(:final value) => _list(
                      context,
                      ids == null
                          ? value
                          : value.where((e) => ids.contains(e.id)).toList(),
                      now,
                    ),
                    AsyncError(:final error) => [
                      _Empty(
                        icon: Icons.error_outline_rounded,
                        title: '$error',
                        action: 'Tekrar dene',
                        onAction: () => ref.invalidate(savedEventsProvider),
                      ),
                    ],
                    _ => const [
                      Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ],
                  },
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _list(
    BuildContext context,
    List<MapEvent> events,
    DateTime now,
  ) {
    if (events.isEmpty) {
      return [
        _Empty(
          icon: Icons.bookmark_border_rounded,
          title: 'Henüz kayıtlı etkinliğin yok',
          body: 'Haritada bir etkinliğin yanındaki yer imine dokunarak kaydedebilirsin.',
          action: 'Haritayı aç',
          onAction: () => context.go(Routes.map),
        ),
      ];
    }
    bool isPast(MapEvent e) =>
        (e.endsAt ?? e.startsAt.add(const Duration(hours: 3))).isBefore(now);
    final upcoming = events.where((e) => !isPast(e)).toList();
    final past = events.where(isPast).toList().reversed.toList();
    return [
      for (final e in upcoming) ...[
        EventCard(event: e, now: now, showVenue: true),
        const SizedBox(height: 12),
      ],
      if (past.isNotEmpty) ...[
        const SizedBox(height: 12),
        const SectionLabel('Geçmiş'),
        for (final e in past) ...[
          Opacity(
            opacity: 0.6,
            child: EventCard(event: e, now: now, showVenue: true),
          ),
          const SizedBox(height: 12),
        ],
      ],
    ];
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String? body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.inkFaint),
          const SizedBox(height: 12),
          Text(title, style: text.titleMedium, textAlign: TextAlign.center),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(body!, style: text.bodyMedium, textAlign: TextAlign.center),
          ],
          if (action != null) ...[
            const SizedBox(height: 14),
            TextButton(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    );
  }
}
