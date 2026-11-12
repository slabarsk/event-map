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
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandMark(size: 64, showName: false),
              SizedBox(height: 28),
              SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
