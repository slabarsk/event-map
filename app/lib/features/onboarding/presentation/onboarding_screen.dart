import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/widgets/auth_widgets.dart';
import 'organizer_steps.dart';
import 'user_steps.dart';

/// 3 adımlı onboarding. Kullanıcı ve organizatör için farklı adımlar gösterilir;
/// son adımdan sonra özet ekranı gelir ve profil ancak orada kaydedilir.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _stepCount = 3;

  late AppUser _draft;
  int _step = 0;
  bool _done = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).value!;
    _draft = user.isOrganizer && user.organization == null
        ? user.copyWith(organization: const Organization())
        : user;
  }

  bool get _organizer => _draft.isOrganizer;

  /// Adımın ileri gitmeye izin verip vermediği.
  String? get _blocker {
    if (_organizer) {
      final org = _draft.organization!;
      return switch (_step) {
        0 when org.name.trim().isEmpty => 'Organizasyon adını yaz',
        0 when org.type == null => 'Organizasyon türünü seç',
        1 when org.categories.isEmpty => 'En az bir kategori seç',
        _ => null,
      };
    }
    return switch (_step) {
      0 when _draft.preferences.categories.isEmpty => 'En az bir kategori seç',
      _ => null,
    };
  }

  void _next() {
    final blocker = _blocker;
    setState(() => _error = blocker);
    if (blocker != null) return;
    setState(() {
      if (_step < _stepCount - 1) {
        _step++;
      } else {
        _done = true;
      }
    });
  }

  void _back() => setState(() {
    _error = null;
    _done ? _done = false : _step--;
  });

  Future<void> _finish({required bool toSettings}) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .save(_draft.copyWith(onboardingCompleted: true));
      if (!mounted) return;
      context.go(
        toSettings ? '${Routes.settings}?from=onboarding' : Routes.home,
      );
    } on AuthFailure catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentFor(_draft.role);
    final blobs = AppColors.blobsFor(_draft.role);

    final steps = _organizer
        ? [
            OrganizerIdentityStep(draft: _draft, onChanged: _update),
            OrganizerFocusStep(draft: _draft, onChanged: _update),
            OrganizerContactStep(draft: _draft, onChanged: _update),
          ]
        : [
            UserInterestsStep(draft: _draft, onChanged: _update),
            UserAreaStep(draft: _draft, onChanged: _update),
            UserPreferencesStep(draft: _draft, onChanged: _update),
          ];

    return Scaffold(
      body: AuroraBackground(
        colors: blobs,
        intensity: 0.85,
        child: SafeArea(
          child: MaxWidth(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Row(
                    children: [
                      if (_step > 0 || _done)
                        GlassIconButton(
                          tooltip: 'Geri',
                          onPressed: _saving ? null : _back,
                          icon: Icons.arrow_back_rounded,
                        )
                      else
                        const SizedBox(width: 46),
                      const Spacer(),
                      RoleBadge(role: _draft.role, dense: true),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: _StepProgress(
                    count: _stepCount,
                    current: _done ? _stepCount : _step,
                    color: accent,
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    layoutBuilder: (current, previous) => Stack(
                      fit: StackFit.expand,
                      children: [...previous, ?current],
                    ),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0.06, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: SingleChildScrollView(
                      key: ValueKey(_done ? 'done' : _step),
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      child: _done ? _Summary(user: _draft) : steps[_step],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: _done
                      ? Column(
                          children: [
                            PrimaryButton(
                              label: 'Ana sayfaya geç',
                              icon: Icons.arrow_forward_rounded,
                              busy: _saving,
                              onPressed: () => _finish(toSettings: false),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _saving
                                  ? null
                                  : () => _finish(toSettings: true),
                              icon: const Icon(Icons.tune_rounded),
                              label: const Text('Profil ayarlarımı düzenle'),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            AnimatedSize(
                              duration: const Duration(milliseconds: 180),
                              child: _error == null
                                  ? const SizedBox(width: double.infinity)
                                  : Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 10,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.info_outline_rounded,
                                            size: 18,
                                            color: AppColors.error,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _error!,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  color: AppColors.error,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                            PrimaryButton(
                              label: _step == _stepCount - 1
                                  ? 'Bitir'
                                  : 'Devam',
                              icon: Icons.arrow_forward_rounded,
                              onPressed: _next,
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _update(AppUser user) => setState(() {
    _draft = user;
    _error = null;
  });
}

class _StepProgress extends StatelessWidget {
  const _StepProgress({
    required this.count,
    required this.current,
    required this.color,
  });
  final int count;
  final int current;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final label = current >= count ? 'Hazır' : 'Adım ${current + 1} / $count';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < count; i++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 8,
                  decoration: BoxDecoration(
                    color: i <= current ? null : AppColors.glass(0.8),
                    gradient: i <= current
                        ? LinearGradient(
                            colors: [
                              Color.lerp(color, Colors.white, 0.25)!,
                              color,
                            ],
                          )
                        : null,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              if (i < count - 1) const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(trUpper(label), style: AppTheme.display(14, color: color)),
      ],
    );
  }
}

/// Onboarding sonunda seçimlerin özeti.
class _Summary extends StatelessWidget {
  const _Summary({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accent = AppColors.accentFor(user.role);
    final org = user.organization;
    final rows = user.isOrganizer
        ? [
            (Icons.storefront_outlined, 'Organizasyon', org?.name ?? ''),
            (Icons.category_outlined, 'Tür', org?.type ?? '-'),
            (Icons.place_outlined, 'Bölge', org?.district ?? 'Belirtilmedi'),
            (
              Icons.local_activity_outlined,
              'Kategoriler',
              '${org?.categories.length ?? 0} kategori',
            ),
          ]
        : [
            (
              Icons.favorite_outline_rounded,
              'İlgi alanları',
              '${user.preferences.categories.length} kategori',
            ),
            (
              Icons.place_outlined,
              'Bölge',
              user.preferences.district ?? 'Konumuma göre',
            ),
            (Icons.radar_rounded, 'Mesafe', '${user.preferences.radiusKm} km'),
            (
              Icons.payments_outlined,
              'Bütçe',
              user.preferences.freeOnly
                  ? 'Yalnızca ücretsiz'
                  : user.preferences.maxPrice == null
                  ? 'Fark etmez'
                  : '${user.preferences.maxPrice} ₺ altı',
            ),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: AppColors.gradientFor(user.role),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 38),
        ),
        const SizedBox(height: 24),
        DisplayTitle('Her şey hazır,', accent: '${user.firstName}!', size: 40),
        const SizedBox(height: 8),
        Text(
          user.isOrganizer
              ? 'Başvurun incelemeye alındı. Bu sürede panelini gezebilir, profilini düzenleyebilirsin.'
              : 'Seçimlerine göre etkinlikleri sıralayacağız. Bunları profilinden istediğin zaman değiştirebilirsin.',
          style: text.bodyLarge?.copyWith(color: AppColors.inkSoft),
        ),
        const SizedBox(height: 24),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            children: [
              for (final (i, (icon, label, value)) in rows.indexed) ...[
                if (i > 0) const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Icon(icon, size: 20, color: accent),
                      const SizedBox(width: 12),
                      Text(label, style: text.bodyMedium),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          value,
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
