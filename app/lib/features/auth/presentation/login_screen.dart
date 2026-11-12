import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/common.dart';
import '../application/auth_controller.dart';
import '../data/auth_repository.dart';
import '../domain/app_user.dart';
import 'widgets/auth_widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, required this.role});
  final UserRole role;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _submitted = false;
  bool _googleBusy = false;

  bool get _organizer => widget.role == UserRole.organizer;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .signIn(_email.text, _password.text, widget.role);
      // Yönlendirmeyi router yapar (onboarding ya da ana sayfa).
    } on AuthFailure catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() => _googleBusy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .signInWithGoogle(widget.role);
    } on AuthFailure catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final controller = TextEditingController(text: _email.text);
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Şifreni sıfırla'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('E-postana bir sıfırlama bağlantısı gönderelim.'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-posta'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Gönder'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (email == null || !mounted) return;
    if (Validators.email(email) != null) {
      showMessage(context, 'Geçerli bir e-posta gir.', error: true);
      return;
    }
    try {
      await ref.read(authControllerProvider.notifier).sendPasswordReset(email);
      if (mounted) {
        showMessage(context, 'Bağlantı gönderildi, gelen kutunu kontrol et.');
      }
    } on AuthFailure catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      role: widget.role,
      tab: AuthTab.login,
      title: _organizer ? 'Sahne' : 'Tekrar',
      accentWord: _organizer ? 'senin' : 'hoş geldin',
      subtitle: _organizer
          ? 'Etkinliklerini yönet, yeni etkinlik gönder.'
          : 'Kaldığın yerden keşfetmeye devam et.',
      children: [
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            autovalidateMode: _submitted
                ? AutovalidateMode.onUserInteraction
                : AutovalidateMode.disabled,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    validator: Validators.email,
                    decoration: const InputDecoration(
                      labelText: 'E-posta',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  PasswordField(
                    controller: _password,
                    validator: (v) => Validators.required(v, 'Şifre'),
                    onSubmitted: (_) => _submit(),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _forgotPassword,
                      child: const Text('Şifremi unuttum'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  PrimaryButton(
                    label: 'Giriş yap',
                    busy: _busy,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
        const OrDivider(),
        GoogleButton(onPressed: _google, busy: _googleBusy),
        const SizedBox(height: 20),
        SwitchPrompt(
          text: _organizer
              ? 'Etkinlik mi arıyorsun?'
              : 'Etkinlik mi düzenliyorsun?',
          action: _organizer ? 'Kullanıcı girişi' : 'Organizatör girişi',
          onTap: () => context.go(
            Routes.login(_organizer ? UserRole.user : UserRole.organizer),
          ),
        ),
      ],
    );
  }
}
