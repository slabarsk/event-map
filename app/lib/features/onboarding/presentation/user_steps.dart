import 'package:material_ui/material_ui.dart';

import '../../../core/catalog.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common.dart';
import '../../auth/domain/app_user.dart';

/// Onboarding adımlarının başlığı.
class StepHeader extends StatelessWidget {
  const StepHeader({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final words = title.split(' ');
    final head = words.length > 1
        ? words.sublist(0, words.length - 1).join(' ')
        : title;
    final accent = words.length > 1 ? words.last : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: 0.8), color],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 20),
          DisplayTitle(head, accent: accent, size: 36),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: text.bodyLarge?.copyWith(color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tekrar kullanılabilir tercih seçicileri (onboarding + profil ayarları)
// ---------------------------------------------------------------------------

class CategoryPicker extends StatelessWidget {
  const CategoryPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in Catalog.categories)
          CategoryChip(
            category: c,
            selected: selected.contains(c.id),
            onTap: () => onChanged(
              selected.contains(c.id)
                  ? ({...selected}..remove(c.id))
                  : {...selected, c.id},
            ),
          ),
      ],
    );
  }
}

class DistrictPicker extends StatelessWidget {
  const DistrictPicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.accent,
    this.allowAuto = true,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final Color accent;

  /// "Konumuma göre" seçeneği (null değer).
  final bool allowAuto;

  @override
  Widget build(BuildContext context) {
    return PillSelector<String?>(
      options: [if (allowAuto) null, ...Catalog.districts],
      value: value,
      accent: accent,
      labelOf: (d) => d ?? 'Konumuma göre',
      onChanged: onChanged,
    );
  }
}

class RadiusPicker extends StatelessWidget {
  const RadiusPicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.accent,
  });
  final int value;
  final ValueChanged<int> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return PillSelector<int>(
      options: Catalog.radiusOptionsKm,
      value: value,
      accent: accent,
      labelOf: (km) => '$km km',
      onChanged: onChanged,
    );
  }
}

class BudgetPicker extends StatelessWidget {
  const BudgetPicker({
    super.key,
    required this.prefs,
    required this.onChanged,
    required this.accent,
  });
  final UserPreferences prefs;
  final ValueChanged<UserPreferences> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ToggleRow(
          icon: Icons.money_off_rounded,
          title: 'Yalnızca ücretsiz etkinlikler',
          subtitle: 'Ücretli etkinlikleri varsayılan olarak gizle',
          value: prefs.freeOnly,
          onChanged: (v) => onChanged(prefs.copyWith(freeOnly: v)),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: prefs.freeOnly
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: PillSelector<int?>(
              options: Catalog.priceCaps,
              value: prefs.maxPrice,
              accent: accent,
              labelOf: Catalog.priceCapLabel,
              onChanged: (cap) => onChanged(
                cap == null
                    ? prefs.copyWith(clearMaxPrice: true)
                    : prefs.copyWith(maxPrice: cap),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ToggleRow extends StatelessWidget {
  const ToggleRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 22,
              ),
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
                    Text(subtitle, style: text.bodySmall),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class NotificationToggles extends StatelessWidget {
  const NotificationToggles({
    super.key,
    required this.prefs,
    required this.onChanged,
  });
  final UserPreferences prefs;
  final ValueChanged<UserPreferences> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ToggleRow(
          icon: Icons.weekend_outlined,
          title: 'Hafta sonu önerileri',
          subtitle: 'Cuma günleri ilgi alanlarına göre kısa liste',
          value: prefs.notifyWeekend,
          onChanged: (v) => onChanged(prefs.copyWith(notifyWeekend: v)),
        ),
        const Divider(height: 20),
        ToggleRow(
          icon: Icons.near_me_outlined,
          title: 'Yakınımda yeni etkinlik',
          subtitle: 'Seçtiğin mesafede yeni etkinlik eklenince',
          value: prefs.notifyNearby,
          onChanged: (v) => onChanged(prefs.copyWith(notifyNearby: v)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Kullanıcı onboarding adımları
// ---------------------------------------------------------------------------

class UserInterestsStep extends StatelessWidget {
  const UserInterestsStep({
    super.key,
    required this.draft,
    required this.onChanged,
  });
  final AppUser draft;
  final ValueChanged<AppUser> onChanged;

  @override
  Widget build(BuildContext context) {
    final count = draft.preferences.categories.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepHeader(
          icon: Icons.favorite_rounded,
          color: AppColors.pink,
          title: 'Neleri seversin?',
          subtitle: 'İlgini çeken kategorileri seç. Harita ve öneriler buna göre şekillenir.',
        ),
        CategoryPicker(
          selected: draft.preferences.categories,
          onChanged: (s) => onChanged(
            draft.copyWith(
              preferences: draft.preferences.copyWith(categories: s),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          count == 0 ? 'En az bir kategori seç' : '$count kategori seçildi',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class UserAreaStep extends StatelessWidget {
  const UserAreaStep({super.key, required this.draft, required this.onChanged});
  final AppUser draft;
  final ValueChanged<AppUser> onChanged;

  @override
  Widget build(BuildContext context) {
    final prefs = draft.preferences;
    final accent = AppColors.accentFor(draft.role);
    void set(UserPreferences p) => onChanged(draft.copyWith(preferences: p));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeader(
          icon: Icons.place_rounded,
          color: AppColors.sky,
          title: 'Nerede takılıyorsun?',
          subtitle: 'Sık gittiğin semti ve "yakınımda" aramasında ne kadar uzağa bakacağımızı seç.',
        ),
        const SectionLabel('Bölge'),
        DistrictPicker(
          value: prefs.district,
          accent: accent,
          onChanged: (d) => set(
            d == null
                ? prefs.copyWith(clearDistrict: true)
                : prefs.copyWith(district: d),
          ),
        ),
        const SizedBox(height: 24),
        const SectionLabel('Yakınımda mesafesi'),
        RadiusPicker(
          value: prefs.radiusKm,
          accent: accent,
          onChanged: (km) => set(prefs.copyWith(radiusKm: km)),
        ),
        const SizedBox(height: 24),
        const _PrivacyNote(),
      ],
    );
  }
}

class UserPreferencesStep extends StatelessWidget {
  const UserPreferencesStep({
    super.key,
    required this.draft,
    required this.onChanged,
  });
  final AppUser draft;
  final ValueChanged<AppUser> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentFor(draft.role);
    void set(UserPreferences p) => onChanged(draft.copyWith(preferences: p));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeader(
          icon: Icons.auto_awesome_rounded,
          color: AppColors.amber,
          title: 'Son dokunuşlar',
          subtitle: 'Bütçeni ve sana ne zaman haber vereceğimizi seç.',
        ),
        const SectionLabel('Bütçe'),
        SurfaceCard(
          child: BudgetPicker(
            prefs: draft.preferences,
            accent: accent,
            onChanged: set,
          ),
        ),
        const SizedBox(height: 24),
        const SectionLabel('Bildirimler'),
        SurfaceCard(
          child: NotificationToggles(prefs: draft.preferences, onChanged: set),
        ),
      ],
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.glass(0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, size: 20, color: AppColors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Konumun yalnızca arama anında kullanılır, kaydedilmez.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}
