import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/catalog.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common.dart';
import '../../auth/domain/app_user.dart';
import '../application/admin_providers.dart';
import '../domain/organizer_application.dart';
import 'widgets/admin_widgets.dart';

/// Organizatör başvuruları: durum filtresi + tablo (dar ekranda kart listesi).
class ApplicationsScreen extends ConsumerWidget {
  const ApplicationsScreen({super.key, required this.status});
  final OrganizerStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final applications = ref.watch(organizerApplicationsProvider(status));
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      children: [
        MaxWidth(
          width: 1000,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DisplayTitle('Organizatör', accent: 'başvuruları'),
              const SizedBox(height: 8),
              Text(
                'Onaylanan organizatörler etkinlik gönderebilir. '
                'Reddedilen başvurular daha sonra yeniden onaylanabilir.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: PillSelector<OrganizerStatus>(
                      options: OrganizerStatus.values,
                      value: status,
                      labelOf: (s) => s.filterLabel,
                      accent: Theme.of(context).colorScheme.primary,
                      onChanged: (s) => context.go(Routes.adminList(s)),
                    ),
                  ),
                  GlassIconButton(
                    tooltip: 'Yenile',
                    icon: Icons.refresh_rounded,
                    onPressed: () =>
                        ref.invalidate(organizerApplicationsProvider(status)),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              applications.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => AdminMessage(
                  icon: Icons.cloud_off_rounded,
                  title: 'Başvurular yüklenemedi',
                  body: '$e',
                  onRetry: () =>
                      ref.invalidate(organizerApplicationsProvider(status)),
                ),
                data: (items) => items.isEmpty
                    ? AdminMessage(
                        icon: Icons.inbox_rounded,
                        title: switch (status) {
                          OrganizerStatus.pending => 'Bekleyen başvuru yok',
                          OrganizerStatus.approved =>
                            'Henüz onaylanan organizatör yok',
                          OrganizerStatus.rejected => 'Reddedilen başvuru yok',
                        },
                      )
                    : _ApplicationsTable(items: items),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ApplicationsTable extends StatelessWidget {
  const _ApplicationsTable({required this.items});
  final List<OrganizerApplication> items;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        return GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              if (wide)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                  child: DefaultTextStyle(
                    style: text.labelSmall!.copyWith(
                      color: AppColors.inkSoft,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                    child: const Row(
                      children: [
                        Expanded(flex: 4, child: Text('AD SOYAD')),
                        Expanded(flex: 5, child: Text('ORGANİZASYON')),
                        Expanded(flex: 3, child: Text('BAŞVURU TARİHİ')),
                        SizedBox(width: 140, child: Text('DURUM')),
                        SizedBox(width: 24),
                      ],
                    ),
                  ),
                ),
              for (final (i, item) in items.indexed) ...[
                if (i > 0 || wide) const Divider(indent: 20, endIndent: 20),
                _ApplicationRow(item: item, wide: wide),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ApplicationRow extends StatelessWidget {
  const _ApplicationRow({required this.item, required this.wide});
  final OrganizerApplication item;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final org = item.organization;
    final orgDetails = [
      org.type,
      org.district,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    final categories = org.categories
        .map((id) => Catalog.category(id)?.label ?? id)
        .join(', ');

    final name = Row(
      children: [
        InitialsAvatar(item.displayName, size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            item.displayName,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    final organization = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.organizationName,
          style: text.bodyLarge?.copyWith(
            color: AppColors.ink,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (orgDetails.isNotEmpty || categories.isNotEmpty)
          Text(
            [orgDetails, categories].where((s) => s.isNotEmpty).join(' — '),
            style: text.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
    final date = Text(formatAdminDate(item.appliedAt), style: text.bodyMedium);

    return InkWell(
      key: ValueKey('application-${item.id}'),
      onTap: () => context.go(Routes.adminApplication(item.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: wide
            ? Row(
                children: [
                  Expanded(flex: 4, child: name),
                  Expanded(flex: 5, child: organization),
                  Expanded(flex: 3, child: date),
                  SizedBox(
                    width: 140,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: StatusChip(item.status),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.inkFaint,
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: name),
                      StatusChip(item.status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  organization,
                  const SizedBox(height: 4),
                  date,
                ],
              ),
      ),
    );
  }
}
