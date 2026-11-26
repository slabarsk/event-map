import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common.dart';
import '../../events/domain/event_format.dart';
import '../../events/presentation/event_visuals.dart';
import '../application/admin_providers.dart';
import '../data/admin_repository.dart';
import '../domain/review_event.dart';
import 'widgets/admin_widgets.dart';

/// Organizatörlerin gönderdiği etkinlikler: yayınla ya da gerekçeyle reddet.
class EventReviewsScreen extends ConsumerWidget {
  const EventReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(pendingEventsProvider);
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      children: [
        MaxWidth(
          width: 1000,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: DisplayTitle('Etkinlik', accent: 'onayları'),
                  ),
                  GlassIconButton(
                    tooltip: 'Yenile',
                    icon: Icons.refresh_rounded,
                    onPressed: () => ref.invalidate(pendingEventsProvider),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Yayınlanan etkinlik hemen haritada görünür. Reddedilen '
                'etkinliğin gerekçesi organizatörün panelinde gösterilir.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 22),
              events.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => AdminMessage(
                  icon: Icons.cloud_off_rounded,
                  title: 'Etkinlikler yüklenemedi',
                  body: '$e',
                  onRetry: () => ref.invalidate(pendingEventsProvider),
                ),
                data: (items) => items.isEmpty
                    ? const AdminMessage(
                        icon: Icons.inbox_rounded,
                        title: 'Onay bekleyen etkinlik yok',
                      )
                    : Column(
                        children: [
                          for (final e in items) ...[
                            _ReviewCard(event: e),
                            const SizedBox(height: 14),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewCard extends ConsumerStatefulWidget {
  const _ReviewCard({required this.event});
  final ReviewEvent event;

  @override
  ConsumerState<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends ConsumerState<_ReviewCard> {
  bool _busy = false;

  Future<void> _decide({required bool approve}) async {
    String? note;
    if (!approve) {
      note = await _askReason();
      if (note == null) return; // vazgeçildi
    }
    setState(() => _busy = true);
    try {
      await decideEvent(ref, widget.event.id, approve: approve, note: note);
      if (mounted) {
        showMessage(
          context,
          approve ? 'Etkinlik yayınlandı' : 'Etkinlik reddedildi',
        );
      }
    } on AdminFailure catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Boş gerekçe de geçerlidir; null dönerse işlem iptal edilir.
  Future<String?> _askReason() => showDialog<String>(
    context: context,
    builder: (_) => const _ReasonDialog(),
  );

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final text = Theme.of(context).textTheme;
    final cat = eventCategoryOf(e.category);
    final now = DateTime.now();
    final price = switch ((e.priceMin, e.priceMax)) {
      (0, 0) || (0, null) => 'Ücretsiz',
      (null, null) => 'Fiyat belirtilmemiş',
      (final lo?, final hi?) when lo != hi => '${lo.round()}–${hi.round()} ₺',
      (final lo, final hi) => '${(lo ?? hi)!.round()} ₺',
    };

    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    Text(e.title, style: text.titleMedium),
                    Text(
                      '${cat.label} · ${EventFormat.when(e.startsAt, now: now)}',
                      style: text.bodySmall?.copyWith(color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Line(
            Icons.place_outlined,
            [?e.venueName, ?e.venueAddress].join(' · '),
          ),
          _Line(
            Icons.storefront_outlined,
            [?e.organizationName, ?e.organizerName].join(' · '),
          ),
          _Line(
            Icons.payments_outlined,
            [price, if (e.requiresRegistration) 'Başvuru ile'].join(' · '),
          ),
          if (e.ticketUrl != null) _Line(Icons.link_rounded, e.ticketUrl!),
          _Line(
            Icons.schedule_send_outlined,
            'Gönderildi: ${formatAdminDate(e.submittedAt)}',
          ),
          if (e.description != null && e.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(e.description!, style: text.bodyMedium),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _decide(approve: false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                ),
                icon: const Icon(Icons.block_rounded),
                label: const Text('Reddet'),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : () => _decide(approve: true),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Yayınla'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.inkSoft),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// Red gerekçesi. Denetleyici diyaloğun kendi ömrüne bağlı; kapanış
/// animasyonu sürerken dispose edilmez.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Etkinliği reddet'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        maxLength: 300,
        decoration: const InputDecoration(
          hintText: 'Gerekçe (organizatöre gösterilir)',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Reddet'),
        ),
      ],
    );
  }
}
