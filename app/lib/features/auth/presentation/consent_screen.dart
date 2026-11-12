import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../../core/widgets/common.dart';
import '../application/auth_controller.dart';
import '../data/auth_repository.dart';
import 'widgets/auth_widgets.dart';

/// Google ile ilk kez gelen kullanıcıdan KVKK açık rızası alır.
class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool _consent = false;
  bool _showError = false;
  bool _busy = false;

  Future<void> _continue() async {
    if (!_consent) {
      setState(() => _showError = true);
      return;
    }
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .save(user.copyWith(kvkkConsentAt: DateTime.now()));
    } on AuthFailure catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).value;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: AuroraBackground(
        intensity: 0.6,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: MaxWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: BrandMark(),
                  ),
                  const SizedBox(height: 36),
                  Text(
                    'Merhaba ${user?.firstName ?? ''} 👋',
                    style: text.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Başlamadan önce verilerini nasıl kullandığımızı onaylaman gerekiyor.',
                    style: text.bodyLarge?.copyWith(color: AppColors.inkSoft),
                  ),
                  const SizedBox(height: 24),
                  SurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _point(
                          context,
                          Icons.my_location_rounded,
                          'Konumun saklanmaz, yalnızca arama anında kullanılır.',
                        ),
                        _point(
                          context,
                          Icons.block_rounded,
                          'Verilerin reklam için paylaşılmaz.',
                        ),
                        _point(
                          context,
                          Icons.delete_outline_rounded,
                          'Hesabını istediğin an kalıcı olarak silebilirsin.',
                        ),
                        const Divider(height: 24),
                        KvkkConsentTile(
                          value: _consent,
                          showError: _showError,
                          onChanged: (v) => setState(() {
                            _consent = v;
                            if (v) _showError = false;
                          }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: 'Onayla ve devam et',
                    busy: _busy,
                    onPressed: _continue,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).signOut(),
                    child: const Text('Vazgeç ve çıkış yap'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _point(BuildContext context, IconData icon, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(body, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    ),
  );
}
