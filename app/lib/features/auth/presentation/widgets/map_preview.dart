import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/common.dart';

/// Karşılama ekranındaki stilize harita: körfez, yollar ve kategori renkli pinler.
class MapPreview extends StatelessWidget {
  const MapPreview({super.key, this.height = 210, this.stats = const []});
  final double height;

  /// Haritanın sağında yüzen istatistik kartları: (değer, etiket).
  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF4EEEA),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white, width: 5),
        boxShadow: [
          BoxShadow(
            color: AppColors.coral.withValues(alpha: 0.18),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          return Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _MapPainter())),
              _pin(
                w * 0.56,
                h * 0.30,
                AppColors.coral,
                Icons.music_note_rounded,
              ),
              _pin(
                w * 0.64,
                h * 0.60,
                AppColors.violet,
                Icons.theater_comedy_rounded,
              ),
              _pin(w * 0.40, h * 0.62, AppColors.amber, Icons.palette_rounded),
              _pin(
                w * 0.86,
                h * 0.84,
                AppColors.pink,
                Icons.celebration_rounded,
              ),
              _pin(
                w * 0.62,
                h * 0.80,
                AppColors.sky,
                Icons.mic_external_on_rounded,
              ),
              Positioned(
                left: w * 0.56 - 132,
                top: h * 0.30 - 38,
                child: const _Label(
                  title: 'Caz gecesi',
                  meta: '21:00 · Ücretsiz',
                ),
              ),
              if (stats.isNotEmpty)
                Positioned(
                  right: 12,
                  top: 12,
                  child: Column(
                    children: [
                      for (final (value, label) in stats) ...[
                        StatBubble(
                          value: value,
                          label: label,
                          color: AppColors.coral,
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              Positioned(
                left: 14,
                bottom: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.near_me_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Yakınımda bu akşam',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _pin(double x, double y, Color color, IconData icon) => Positioned(
    left: x - 17,
    top: y - 40,
    child: Column(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.45),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.35),
            shape: BoxShape.circle,
          ),
        ),
      ],
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label({required this.title, required this.meta});
  final String title;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.1),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: text.labelLarge?.copyWith(fontSize: 12)),
          Text(
            meta,
            style: text.labelSmall?.copyWith(
              color: AppColors.success,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Körfez
    final water = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.42, 0)
      ..cubicTo(w * 0.40, h * 0.20, w * 0.26, h * 0.28, w * 0.30, h * 0.46)
      ..cubicTo(w * 0.33, h * 0.60, w * 0.18, h * 0.70, w * 0.10, h * 1.0)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(water, Paint()..color = const Color(0xFFCFE3F7));

    // Parklar
    final park = Paint()..color = const Color(0xFFD9EED3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.46, h * 0.40, w * 0.16, h * 0.16),
        const Radius.circular(14),
      ),
      park,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.80, h * 0.66, w * 0.14, h * 0.22),
        const Radius.circular(14),
      ),
      park,
    );

    // Yollar
    final road = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final main = Path()
      ..moveTo(w * 0.40, -10)
      ..cubicTo(w * 0.36, h * 0.3, w * 0.42, h * 0.55, w * 0.30, h + 10);
    canvas.drawPath(main, road..strokeWidth = 7);
    for (final y in [0.18, 0.48, 0.74]) {
      canvas.drawLine(
        Offset(w * 0.34, h * y),
        Offset(w + 10, h * (y + 0.06)),
        road..strokeWidth = 5,
      );
    }
    for (final x in [0.52, 0.70, 0.88]) {
      canvas.drawLine(
        Offset(w * x, -10),
        Offset(w * (x - 0.06), h + 10),
        road..strokeWidth = 4,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
