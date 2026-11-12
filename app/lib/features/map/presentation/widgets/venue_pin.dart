import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../events/domain/event.dart';
import '../../../events/presentation/event_visuals.dart';

/// Mekân pini: en yakın etkinliğin kategori renginde daire, altında gölge
/// noktası. Mekânda birden çok etkinlik varsa köşede adet rozeti çıkar.
class VenuePin extends StatelessWidget {
  const VenuePin({super.key, required this.group, required this.onTap});
  final VenueGroup group;
  final VoidCallback onTap;

  static const width = 48.0;
  static const height = 52.0;

  @override
  Widget build(BuildContext context) {
    final cat = eventCategoryOf(group.first.category);
    final count = group.events.length;
    return Semantics(
      button: true,
      label: '${group.venueName}, $count etkinlik. İlki: ${group.first.title}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Column(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: cat.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: cat.color.withValues(alpha: 0.45),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Icon(cat.icon, size: 18, color: Colors.white),
                ),
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: cat.color.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            if (count > 1)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
