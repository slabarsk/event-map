import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/catalog.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common.dart';
import '../../auth/domain/app_user.dart';
import '../application/admin_providers.dart';
import '../data/admin_repository.dart';
import '../domain/organizer_application.dart';
import 'widgets/admin_widgets.dart';

/// Başvuru detayı: onboarding'de girilen bilgiler ve Onayla / Reddet.
class ApplicationDetailScreen extends ConsumerWidget {
  const ApplicationDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final application = ref.watch(organizerApplicationProvider(id));
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      children: [
        MaxWidth(
          width: 1000,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go(Routes.admin),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Başvurular'),
                ),
              ),
              const SizedBox(height: 8),
              application.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => AdminMessage(
                  icon: Icons.cloud_off_rounded,
                  title: 'Başvuru yüklenemedi',
                  body: '$e',
                  onRetry: () =>
                      ref.invalidate(organizerApplicationProvider(id)),
                ),
                data: (a) => a == null
                    ? const AdminMessage(
                        icon: Icons.search_off_rounded,
                        title: 'Başvuru bulunamadı',
                        body: 'Hesap silinmiş ya da organizatör değil.',
                      )
                    : _Detail(application: a),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.application});
  final OrganizerApplication application;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = application;
    final org = a.organization;
    final text = Theme.of(context).textTheme;
    final email = ref.watch(organizerEmailProvider(a.id));

    final header = Row(
      children: [
        InitialsAvatar(a.displayName, size: 56),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DisplayTitle(a.displayName, size: 30),
              const SizedBox(height: 4),
              Text(
                a.organizationName,
                style: text.titleMedium?.copyWith(color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
        StatusChip(a.status),
      ],
    );

    final orgCard = _InfoCard(
      title: 'Organizasyon',
      rows: [
        _InfoRow('Kurum adı', org.name),
        _InfoRow('Tür', org.type),
        _InfoRow('İlçe', org.district),
        _InfoRow('Web sitesi', org.website),
        _InfoRow(
          'Instagram',
          org.instagram == null || org.instagram!.isEmpty
              ? null
              : '@${org.instagram}',
        ),
      ],
      footer: org.categories.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Text('Kategoriler', style: text.bodySmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final id in org.categories) _CategoryTag(id)],
                ),
              ],
            ),
    );

    final contactCard = _InfoCard(
      title: 'Başvuran',
      rows: [
        _InfoRow('Ad soyad', a.fullName),
        _InfoRow(
          'E-posta',
          email.when(
            data: (v) => v,
            loading: () => '…',
            error: (_, _) => 'Okunamadı',
          ),
        ),
        _InfoRow('Telefon', org.contactPhone),
        _InfoRow('Başvuru tarihi', formatAdminDate(a.appliedAt)),
        if (a.updatedAt != null)
          _InfoRow('Son güncelleme', formatAdminDate(a.updatedAt!)),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 720
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: orgCard),
                    const SizedBox(width: 18),
                    Expanded(child: contactCard),
                  ],
                )
              : Column(
                  children: [orgCard, const SizedBox(height: 18), contactCard],
                ),
        ),
        const SizedBox(height: 18),
        _DecisionCard(application: a),
      ],
    );
  }
}

class _DecisionCard extends ConsumerStatefulWidget {
  const _DecisionCard({required this.application});
  final OrganizerApplication application;

  @override
  ConsumerState<_DecisionCard> createState() => _DecisionCardState();
}

class _DecisionCardState extends ConsumerState<_DecisionCard> {
  OrganizerStatus? _busy;

  Future<void> _decide(OrganizerStatus status) async {
    final a = widget.application;
    final approve = status == OrganizerStatus.approved;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          approve ? 'Başvuru onaylansın mı?' : 'Başvuru reddedilsin mi?',
        ),
        content: Text(
          approve
              ? '${a.displayName} (${a.organizationName}) etkinlik gönderebilecek. '
                    'Gönderdiği etkinlikler yine admin onayından geçer.'
              : '${a.displayName} (${a.organizationName}) etkinlik gönderemeyecek. '
                    'Kararı daha sonra değiştirebilirsin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            key: const ValueKey('confirm-decision'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              backgroundColor: approve ? AppColors.success : AppColors.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(approve ? 'Onayla' : 'Reddet'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = status);
    try {
      await decideApplication(ref, a.id, status);
      if (mounted) {
        showMessage(
          context,
          approve ? 'Başvuru onaylandı.' : 'Başvuru reddedildi.',
        );
      }
    } on AdminFailure catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (_) {
      if (mounted) {
        showMessage(context, 'İşlem tamamlanamadı, tekrar dene.', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.application.status;
    final text = Theme.of(context).textTheme;
    final canApprove = status != OrganizerStatus.approved;
    final canReject = status != OrganizerStatus.rejected;

    Widget button({
      required String label,
      required IconData icon,
      required Color color,
      required OrganizerStatus target,
      bool filled = false,
    }) {
      final busy = _busy == target;
      final child = busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(label),
              ],
            );
      final onPressed = _busy == null ? () => _decide(target) : null;
      return SizedBox(
        width: 180,
        child: filled
            ? FilledButton(
                key: ValueKey('decide-${target.name}'),
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: onPressed,
                child: child,
              )
            : OutlinedButton(
                key: ValueKey('decide-${target.name}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withValues(alpha: 0.5)),
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: onPressed,
                child: child,
              ),
      );
    }

    return GlassCard(
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Karar', style: text.titleMedium),
                const SizedBox(height: 4),
                Text(switch (status) {
                  OrganizerStatus.pending =>
                    'Bilgileri kontrol edip başvuruyu onayla ya da reddet.',
                  OrganizerStatus.approved =>
                    'Bu organizatör onaylı. Gerekirse onayı geri alabilirsin.',
                  OrganizerStatus.rejected =>
                    'Bu başvuru reddedildi. Gerekirse onaylayabilirsin.',
                }, style: text.bodyMedium),
              ],
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (canReject)
                button(
                  label: 'Reddet',
                  icon: Icons.close_rounded,
                  color: AppColors.error,
                  target: OrganizerStatus.rejected,
                ),
              if (canApprove)
                button(
                  label: 'Onayla',
                  icon: Icons.check_rounded,
                  color: AppColors.success,
                  target: OrganizerStatus.approved,
                  filled: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow {
  const _InfoRow(this.label, this.value);
  final String label;
  final String? value;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.rows, this.footer});
  final String title;
  final List<_InfoRow> rows;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(title),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(r.label, style: text.bodySmall),
                  ),
                  Expanded(
                    child: SelectableText(
                      r.value == null || r.value!.trim().isEmpty
                          ? '—'
                          : r.value!,
                      style: text.bodyMedium?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ?footer,
        ],
      ),
    );
  }
}

class _CategoryTag extends StatelessWidget {
  const _CategoryTag(this.id);
  final String id;

  @override
  Widget build(BuildContext context) {
    final c = Catalog.category(id);
    final color = c?.color ?? AppColors.inkSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(c?.icon ?? Icons.label_rounded, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            c?.label ?? id,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
