import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/aurora_background.dart';
import '../../../../core/widgets/common.dart';
import '../../domain/app_user.dart';

enum AuthTab { login, register }

/// Giriş/kayıt ekranlarının ortak iskeleti: rol rengine göre tema, arka plan,
/// geri butonu, rol rozeti, giriş/kayıt sekmeleri ve büyük başlık.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.role,
    required this.title,
    required this.subtitle,
    required this.children,
    this.accentWord,
    this.tab,
  });

  final UserRole role;
  final String title;
  final String? accentWord;
  final String subtitle;
  final AuthTab? tab;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentFor(role);
    return Theme(
      data: AppTheme.light(accent: accent),
      child: Builder(
        builder: (context) => Scaffold(
          body: AuroraBackground(
            colors: AppColors.blobsFor(role),
            intensity: 0.85,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: MaxWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          GlassIconButton(
                            tooltip: 'Geri',
                            icon: Icons.arrow_back_rounded,
                            onPressed: () => context.canPop()
                                ? context.pop()
                                : context.go(Routes.welcome),
                          ),
                          const Spacer(),
                          RoleBadge(role: role),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (tab != null) ...[
                        _AuthTabs(role: role, current: tab!),
                        const SizedBox(height: 22),
                      ],
                      DisplayTitle(title, accent: accentWord, size: 38),
                      const SizedBox(height: 10),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(color: AppColors.inkSoft),
                      ),
                      const SizedBox(height: 24),
                      ...children,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthTabs extends StatelessWidget {
  const _AuthTabs({required this.role, required this.current});
  final UserRole role;
  final AuthTab current;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentFor(role);
    Widget tab(AuthTab t, String label, String route) {
      final active = t == current;
      return GestureDetector(
        onTap: active ? null : () => context.go(route),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              trUpper(label),
              style: AppTheme.display(
                18,
                color: active ? accent : AppColors.inkFaint,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: active ? 26 : 0,
              height: 4,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        tab(AuthTab.login, 'Giriş yap', Routes.login(role)),
        const SizedBox(width: 28),
        tab(AuthTab.register, 'Kayıt ol', Routes.register(role)),
      ],
    );
  }
}

class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role, this.dense = false});
  final UserRole role;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final organizer = role == UserRole.organizer;
    final accent = AppColors.accentFor(role);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 10 : 14,
        vertical: dense ? 6 : 9,
      ),
      decoration: BoxDecoration(
        color: AppColors.glass(0.8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            organizer ? Icons.campaign_rounded : Icons.explore_rounded,
            size: dense ? 14 : 16,
            color: accent,
          ),
          const SizedBox(width: 6),
          Text(
            organizer ? 'Organizatör' : 'Kullanıcı',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: accent, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Şifre',
    this.validator,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.autofillHints = const [AutofillHints.password],
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String> autofillHints;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      validator: widget.validator,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onSubmitted,
      autofillHints: widget.autofillHints,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Şifreyi göster' : 'Şifreyi gizle',
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }
}

class GoogleButton extends StatelessWidget {
  const GoogleButton({super.key, required this.onPressed, this.busy = false});
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'G',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF4285F4),
                  ),
                ),
                const SizedBox(width: 12),
                const Text('Google ile devam et'),
              ],
            ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final enabled = onPressed != null && !busy;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          colors: [
            Color.lerp(primary, Colors.white, 0.18)!,
            Color.lerp(primary, Colors.black, 0.08)!,
          ],
        ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: primary.withValues(alpha: 0.38),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            height: 58,
            child: Center(
              child: busy
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        if (icon != null) ...[
                          const SizedBox(width: 10),
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, size: 18, color: Colors.white),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('ya da', style: Theme.of(context).textTheme.bodySmall),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

/// Alt kısımdaki "Hesabın yok mu? Kayıt ol" tarzı satır.
class SwitchPrompt extends StatelessWidget {
  const SwitchPrompt({
    super.key,
    required this.text,
    required this.action,
    required this.onTap,
  });
  final String text;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(text, style: Theme.of(context).textTheme.bodyMedium),
        TextButton(onPressed: onTap, child: Text(action)),
      ],
    );
  }
}

abstract final class Validators {
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'E-posta gerekli';
    if (!_email.hasMatch(v.trim())) return 'Geçerli bir e-posta gir';
    return null;
  }

  static String? required(String? v, String field) =>
      (v == null || v.trim().isEmpty) ? '$field gerekli' : null;

  static String? newPassword(String? v) {
    if (v == null || v.length < 8) return 'En az 8 karakter';
    if (!RegExp(r'[0-9]').hasMatch(v) ||
        !RegExp(r'[A-Za-zçğıöşüÇĞİÖŞÜ]').hasMatch(v)) {
      return 'Harf ve rakam içermeli';
    }
    return null;
  }
}

/// KVKK aydınlatma metni.
// TODO(hukuk): Yayın öncesi metin bir hukukçu tarafından gözden geçirilmeli.
Future<void> showKvkkSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (context) {
      final text = Theme.of(context).textTheme;
      Widget item(IconData icon, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(body, style: text.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      );
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          children: [
            Text('KVKK Aydınlatma Metni', style: text.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '6698 sayılı Kişisel Verilerin Korunması Kanunu kapsamında verilerinin nasıl '
              'işlendiğini özetliyoruz.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 24),
            item(
              Icons.badge_outlined,
              'Hangi verileri işliyoruz?',
              'Ad soyad, e-posta, hesap türü, ilgi alanların ve bildirim tercihlerin. '
                  'Organizatörler için kurum adı ve iletişim bilgileri.',
            ),
            item(
              Icons.my_location_rounded,
              'Konum',
              '"Yakınımda" araması için konumun yalnızca sorgu anında kullanılır, '
                  'sunucularda saklanmaz.',
            ),
            item(
              Icons.flag_outlined,
              'Amaç',
              'Hesabını oluşturmak, sana uygun etkinlikleri göstermek ve organizatör '
                  'başvurularını değerlendirmek.',
            ),
            item(
              Icons.lock_outline_rounded,
              'Saklama ve aktarım',
              'Veriler hizmet sağlayıcımızın sunucularında şifreli bağlantıyla saklanır, '
                  'reklam amacıyla üçüncü kişilerle paylaşılmaz.',
            ),
            item(
              Icons.delete_outline_rounded,
              'Hakların',
              'Verilerine erişebilir, düzeltilmesini isteyebilir ve hesabını Profil > '
                  'Hesabımı sil adımıyla dilediğin an kalıcı olarak silebilirsin.',
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Anladım'),
            ),
          ],
        ),
      );
    },
  );
}

/// KVKK açık rıza onay kutusu; metin bağlantısı aydınlatma metnini açar.
class KvkkConsentTile extends StatelessWidget {
  const KvkkConsentTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.showError = false,
  });
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showError;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text.rich(
                      TextSpan(
                        style: text.bodyMedium,
                        children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: GestureDetector(
                              onTap: () => showKvkkSheet(context),
                              child: Text(
                                'Aydınlatma Metni',
                                style: text.bodyMedium?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.underline,
                                  decorationColor: accent,
                                ),
                              ),
                            ),
                          ),
                          const TextSpan(
                            text:
                                '\'ni okudum; kişisel verilerimin bu kapsamda '
                                'işlenmesine açık rıza veriyorum.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showError && !value)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2),
            child: Text(
              'Devam etmek için onay gerekli',
              style: text.bodySmall?.copyWith(color: AppColors.error),
            ),
          ),
      ],
    );
  }
}
