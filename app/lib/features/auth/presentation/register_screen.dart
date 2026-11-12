import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common.dart';
import '../application/auth_controller.dart';
import '../data/auth_repository.dart';
import '../domain/app_user.dart';
import 'widgets/auth_widgets.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, required this.role});
  final UserRole role;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _org = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _consent = false;
  bool _showConsentError = false;
  bool _busy = false;
  bool _submitted = false;
  bool _googleBusy = false;

  bool get _organizer => widget.role == UserRole.organizer;

  @override
  void dispose() {
    _name.dispose();
    _org.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState!.validate();
    setState(() {
      _submitted = true;
      _showConsentError = !_consent;
    });
    if (!valid || !_consent) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .signUp(
            fullName: _name.text,
            email: _email.text,
            password: _password.text,
            role: widget.role,
            organizationName: _organizer ? _org.text : null,
          );
    } on AuthFailure catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() => _googleBusy = true);
    try {
      // KVKK onayı Google sonrası ayrı ekranda alınır.
      await ref
          .read(authControllerProvider.notifier)
          .signInWithGoogle(widget.role);
    } on AuthFailure catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      role: widget.role,
      tab: AuthTab.register,
      title: _organizer ? 'Etkinliğini' : 'Şehri',
      accentWord: _organizer ? 'haritaya taşı' : 'keşfetmeye başla',
      subtitle: _organizer
          ? 'Etkinliklerin onaydan sonra haritada yayınlanır.'
          : 'İlgi alanlarını seç, sana uygun etkinlikleri gösterelim.',
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
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    validator: (v) => Validators.required(v, 'Ad soyad'),
                    decoration: const InputDecoration(
                      labelText: 'Ad soyad',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  if (_organizer) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _org,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.organizationName],
                      validator: (v) =>
                          Validators.required(v, 'Organizasyon adı'),
                      decoration: const InputDecoration(
                        labelText: 'Organizasyon / mekân adı',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
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
                    validator: Validators.newPassword,
                    autofillHints: const [AutofillHints.newPassword],
                    onSubmitted: (_) => _submit(),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 6),
                    child: Text(
                      'En az 8 karakter, harf ve rakam içersin.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  KvkkConsentTile(
                    value: _consent,
                    showError: _showConsentError,
                    onChanged: (v) => setState(() {
                      _consent = v;
                      if (v) _showConsentError = false;
                    }),
                  ),
                  if (_organizer) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.plumSoft,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.verified_user_outlined,
                            color: AppColors.plum,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Organizatör hesapları ekibimiz tarafından onaylanır. '
                              'Onay beklerken profilini tamamlayabilirsin.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.inkSoft),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: 'Hesap oluştur',
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
          action: _organizer ? 'Kullanıcı kaydı' : 'Organizatör kaydı',
          onTap: () => context.go(
            Routes.register(_organizer ? UserRole.user : UserRole.organizer),
          ),
        ),
      ],
    );
  }
}
