import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/aurora_background.dart';
import '../../../core/widgets/common.dart';

/// Oturum bilgisi yüklenirken kısa süre görünür.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: AuroraBackground(
        // Logo, native açılış ekranındaki logoyla aynı boyutta ve tam
        // ortada; geçişte kıpırdamasın diye yükleme göstergesi ayrı konumlanır.
        child: Stack(
          alignment: Alignment.center,
          children: [
            BrandMark(size: 120, showName: false),
            Align(
              alignment: Alignment(0, 0.32),
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
