import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/widgets/auth_widgets.dart';
import '../../onboarding/presentation/organizer_steps.dart';
import '../../onboarding/presentation/user_steps.dart';

/// Profil ayarları. Onboarding'den gelindiyse kaydedince ana sayfaya geçer.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.fromOnboarding = false});
  final bool fromOnboarding;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  AppUser? _draft;
  bool _saving = false;

  Future<void> _save() async {
    final draft = _draft!;
    if (draft.fullName.trim().isEmpty) {
      showMessage(context, 'Ad soyad boş olamaz', error: true);
      return;
    }
    if (draft.isOrganizer &&
        (draft.organization?.name.trim().isEmpty ?? true)) {
      showMessage(context, 'Organizasyon adı boş olamaz', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(authControllerProvider.notifier).save(draft);
      if (!mounted) return;
      if (widget.fromOnboarding) {
        context.go(Routes.home);
      } else {
        showMessage(context, 'Ayarların kaydedildi');
        context.canPop() ? context.pop() : context.go(Routes.profile);
      }
    } on AuthFailure catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).value;
    if (user == null) return const Scaffold();
    final draft = _draft ??= user;
    final accent = AppColors.accentFor(draft.role);
    final prefs = draft.preferences;
    void set(AppUser u) => setState(() => _draft = u);
    void setPrefs(UserPreferences p) => set(draft.copyWith(preferences: p));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Geri',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => widget.fromOnboarding
              ? context.go(Routes.home)
              : (context.canPop() ? context.pop() : context.go(Routes.profile)),
        ),
        title: Text(trUpper('Profil ayarları')),
      ),
      body: AuroraBackground(
        colors: AppColors.blobsFor(draft.role),
        intensity: 0.6,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: MaxWidth(
                    width: 560,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.fromOnboarding) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.accentSoftFor(draft.role),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.tips_and_updates_outlined,
                                  color: accent,
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Seçimlerini gözden geçir; kaydettiğinde ana sayfaya geçeceksin.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        const SectionLabel('Kişisel bilgiler'),
                        TextFormField(
                          initialValue: draft.fullName,
                          textCapitalization: TextCapitalization.words,
                          onChanged: (v) => set(draft.copyWith(fullName: v)),
                          decoration: const InputDecoration(
                            labelText: 'Ad soyad',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: draft.email,
                          enabled: false,
                          decoration: const InputDecoration(
                            labelText: 'E-posta',
                            prefixIcon: Icon(Icons.mail_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 32),
                        if (draft.isOrganizer) ...[
                          const SectionLabel('Organizasyon'),
                          OrganizationFields(
                            org: draft.organization ?? const Organization(),
                            onChanged: (o) =>
                                set(draft.copyWith(organization: o)),
                          ),
                          const SizedBox(height: 32),
                          const SectionLabel('Kategoriler'),
                          CategoryPicker(
                            selected:
                                draft.organization?.categories ?? const {},
                            onChanged: (s) => set(
                              draft.copyWith(
                                organization:
                                    (draft.organization ?? const Organization())
                                        .copyWith(categories: s),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          const SectionLabel('Bağlantılar'),
                          OrganizationLinks(
                            org: draft.organization ?? const Organization(),
                            onChanged: (o) =>
                                set(draft.copyWith(organization: o)),
                          ),
                        ] else ...[
                          const SectionLabel('İlgi alanları'),
                          CategoryPicker(
                            selected: prefs.categories,
                            onChanged: (s) =>
                                setPrefs(prefs.copyWith(categories: s)),
                          ),
                          const SizedBox(height: 32),
                          const SectionLabel('Bölge'),
                          DistrictPicker(
                            value: prefs.district,
                            accent: accent,
                            onChanged: (d) => setPrefs(
                              d == null
                                  ? prefs.copyWith(clearDistrict: true)
                                  : prefs.copyWith(district: d),
                            ),
                          ),
                          const SizedBox(height: 32),
                          const SectionLabel('Yakınımda mesafesi'),
                          RadiusPicker(
                            value: prefs.radiusKm,
                            accent: accent,
                            onChanged: (km) =>
                                setPrefs(prefs.copyWith(radiusKm: km)),
                          ),
                          const SizedBox(height: 32),
                          const SectionLabel('Bütçe'),
                          SurfaceCard(
                            child: BudgetPicker(
                              prefs: prefs,
                              accent: accent,
                              onChanged: setPrefs,
                            ),
                          ),
                          const SizedBox(height: 32),
                          const SectionLabel('Bildirimler'),
                          SurfaceCard(
                            child: NotificationToggles(
                              prefs: prefs,
                              onChanged: setPrefs,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: MaxWidth(
                  width: 560,
                  child: PrimaryButton(
                    label: widget.fromOnboarding
                        ? 'Kaydet ve ana sayfaya geç'
                        : 'Kaydet',
                    busy: _saving,
                    onPressed: _save,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
