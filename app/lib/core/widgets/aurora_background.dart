import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';

/// Arkada yumuşak, bulanık renk lekeleri; ekranlara canlılık verir ama
/// içeriğin önüne geçmez.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({
    super.key,
    required this.child,
    this.colors = const [AppColors.rose, AppColors.peach, AppColors.lilac],
    this.intensity = 1,
  });

  final Widget child;
  final List<Color> colors;

  /// 0–1 arası; form ekranlarında daha sakin bir arka plan için düşürülür.
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final blobs = [
      (Alignment(-1.2, -1.1), w * 0.9, colors[0]),
      (Alignment(1.3, -0.6), w * 0.75, colors[1 % colors.length]),
      (Alignment(-0.6, 1.25), w * 0.8, colors[2 % colors.length]),
    ];
    return ColoredBox(
      color: AppColors.background,
      child: Stack(
        children: [
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Stack(
                children: [
                  for (final (align, d, color) in blobs)
                    Align(
                      alignment: align,
                      child: Container(
                        width: d,
                        height: d,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.55 * intensity),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}
