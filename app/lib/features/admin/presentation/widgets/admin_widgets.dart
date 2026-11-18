import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/common.dart';
import '../../../auth/domain/app_user.dart';

/// Panelin geniş (masaüstü) düzene geçtiği genişlik.
const adminWideBreakpoint = 900.0;

String formatAdminDate(DateTime d) =>
    DateFormat('d MMM y, HH:mm', 'tr').format(d);

extension OrganizerStatusLabels on OrganizerStatus {
  String get label => switch (this) {
    OrganizerStatus.pending => 'Bekliyor',
    OrganizerStatus.approved => 'Onaylandı',
    OrganizerStatus.rejected => 'Reddedildi',
  };

  /// Filtre hapı etiketi.
  String get filterLabel => switch (this) {
    OrganizerStatus.pending => 'Bekleyen',
    OrganizerStatus.approved => 'Onaylanan',
    OrganizerStatus.rejected => 'Reddedilen',
  };

  Color get color => switch (this) {
    OrganizerStatus.pending => AppColors.amber,
    OrganizerStatus.approved => AppColors.success,
    OrganizerStatus.rejected => AppColors.error,
  };

  IconData get icon => switch (this) {
    OrganizerStatus.pending => Icons.hourglass_top_rounded,
    OrganizerStatus.approved => Icons.verified_rounded,
    OrganizerStatus.rejected => Icons.block_rounded,
  };
}

/// Başvuru durumunu gösteren küçük renkli hap.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final OrganizerStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              status.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// Baş harflerden oluşan yuvarlak avatar.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key, this.size = 40});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final initials = parts.isEmpty
        ? '?'
        : parts.take(2).map((p) => p[0].toUpperCase()).join();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF9466F0), AppColors.plumDeep],
        ),
      ),
      child: Text(
        initials,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: Colors.white, fontSize: size * 0.36),
      ),
    );
  }
}

/// Boş liste, hata ve "bulunamadı" durumları için ortalanmış mesaj kartı.
class AdminMessage extends StatelessWidget {
  const AdminMessage({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String? body;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.inkFaint),
          const SizedBox(height: 12),
          Text(title, style: text.titleMedium, textAlign: TextAlign.center),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(body!, style: text.bodyMedium, textAlign: TextAlign.center),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tekrar dene'),
            ),
          ],
        ],
      ),
    );
  }
}
