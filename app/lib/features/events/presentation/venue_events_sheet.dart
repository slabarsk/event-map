import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../domain/event.dart';
import '../domain/event_format.dart';
import 'event_visuals.dart';

/// Pine dokununca açılan alt sayfa: mekân ve oradaki yaklaşan etkinlikler.
class VenueEventsSheet extends StatelessWidget {
  const VenueEventsSheet({super.key, required this.group, required this.now});
  final VenueGroup group;
  final DateTime now;

  static Future<void> show(BuildContext context, VenueGroup group) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VenueEventsSheet(group: group, now: DateTime.now()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final address = group.first.venueAddress;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: group.events.length > 1 ? 0.6 : 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: MaxWidth(
          width: 560,
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(group.venueName, style: AppTheme.display(22)),
              if (address != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      size: 16,
                      color: AppColors.inkSoft,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        address,
                        style: text.bodySmall?.copyWith(
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              for (final e in group.events) ...[
                EventCard(event: e, now: now),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, required this.now});
  final MapEvent event;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cat = eventCategoryOf(event.category);
    final badge = EventFormat.priceBadge(event);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      radius: 24,
      opacity: 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cat.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(cat.icon, color: cat.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.title, style: text.titleMedium),
                    Text(
                      '${cat.label} · ${EventFormat.when(event.startsAt, now: now)}',
                      style: text.bodySmall?.copyWith(color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (event.description case final d? when d.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(d, style: text.bodyMedium),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                EventFormat.price(event),
                style: text.titleSmall?.copyWith(
                  color: event.isFree ? AppColors.success : AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (badge != null)
                PriceBadge(label: badge, status: event.priceStatus),
              if (event.sourceCount > 1)
                Text(
                  '${event.sourceCount} kaynak',
                  style: text.labelSmall?.copyWith(color: AppColors.inkSoft),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Tahmini" ya da "Bilet sayfasından" rozeti.
class PriceBadge extends StatelessWidget {
  const PriceBadge({super.key, required this.label, required this.status});
  final String label;
  final PriceStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status == PriceStatus.estimated
        ? AppColors.amber
        : AppColors.sky;
    return Tooltip(
      message: status == PriceStatus.estimated
          ? 'Kaynakta fiyat yoktu; benzer etkinliklerden tahmin edildi.'
          : 'Fiyat bilet sayfasında bulundu.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
