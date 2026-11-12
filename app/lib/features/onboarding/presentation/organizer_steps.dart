import 'package:material_ui/material_ui.dart';

import '../../../core/catalog.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common.dart';
import '../../auth/domain/app_user.dart';
import 'user_steps.dart';

/// Organizasyon bilgisinin form alanları; onboarding ve profil ayarlarında ortak.
class OrganizationFields extends StatelessWidget {
  const OrganizationFields({
    super.key,
    required this.org,
    required this.onChanged,
  });
  final Organization org;
  final ValueChanged<Organization> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.plum;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          initialValue: org.name,
          textCapitalization: TextCapitalization.words,
          onChanged: (v) => onChanged(org.copyWith(name: v)),
          decoration: const InputDecoration(
            labelText: 'Organizasyon / mekân adı',
            prefixIcon: Icon(Icons.storefront_outlined),
          ),
        ),
        const SizedBox(height: 24),
        const SectionLabel('Organizasyon türü'),
        PillSelector<String?>(
          options: Catalog.organizerTypes,
          value: org.type,
          accent: accent,
          labelOf: (t) => t ?? '',
          onChanged: (t) => onChanged(org.copyWith(type: t)),
        ),
        const SizedBox(height: 24),
        const SectionLabel('Bölge'),
        DistrictPicker(
          value: org.district,
          accent: accent,
          allowAuto: false,
          onChanged: (d) => onChanged(org.copyWith(district: d)),
        ),
      ],
    );
  }
}

class OrganizationLinks extends StatelessWidget {
  const OrganizationLinks({
    super.key,
    required this.org,
    required this.onChanged,
  });
  final Organization org;
  final ValueChanged<Organization> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          initialValue: org.website,
          keyboardType: TextInputType.url,
          onChanged: (v) => onChanged(org.copyWith(website: v.trim())),
          decoration: const InputDecoration(
            labelText: 'Web sitesi (isteğe bağlı)',
            hintText: 'ornek.com',
            prefixIcon: Icon(Icons.language_rounded),
          ),
        ),
        const SizedBox(height: 14),
        TextFormField(
          initialValue: org.instagram,
          onChanged: (v) => onChanged(
            org.copyWith(instagram: v.trim().replaceFirst('@', '')),
          ),
          decoration: const InputDecoration(
            labelText: 'Instagram (isteğe bağlı)',
            prefixText: '@',
            prefixIcon: Icon(Icons.camera_alt_outlined),
          ),
        ),
      ],
    );
  }
}

class OrganizerIdentityStep extends StatelessWidget {
  const OrganizerIdentityStep({
    super.key,
    required this.draft,
    required this.onChanged,
  });
  final AppUser draft;
  final ValueChanged<AppUser> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeader(
          icon: Icons.storefront_rounded,
          color: AppColors.plum,
          title: 'Organizasyonunu tanıt',
          subtitle: 'Kullanıcılar etkinliklerinde bu bilgileri görecek.',
        ),
        OrganizationFields(
          org: draft.organization!,
          onChanged: (o) => onChanged(draft.copyWith(organization: o)),
        ),
      ],
    );
  }
}

class OrganizerFocusStep extends StatelessWidget {
  const OrganizerFocusStep({
    super.key,
    required this.draft,
    required this.onChanged,
  });
  final AppUser draft;
  final ValueChanged<AppUser> onChanged;

  @override
  Widget build(BuildContext context) {
    final org = draft.organization!;
    void set(Organization o) => onChanged(draft.copyWith(organization: o));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeader(
          icon: Icons.local_activity_rounded,
          color: AppColors.coral,
          title: 'Neler düzenliyorsun?',
          subtitle: 'Etkinlik gönderirken bu kategoriler öne çıkar.',
        ),
        CategoryPicker(
          selected: org.categories,
          onChanged: (s) => set(org.copyWith(categories: s)),
        ),
        const SizedBox(height: 28),
        const SectionLabel('Bağlantılar'),
        OrganizationLinks(org: org, onChanged: set),
      ],
    );
  }
}

class OrganizerContactStep extends StatelessWidget {
  const OrganizerContactStep({
    super.key,
    required this.draft,
    required this.onChanged,
  });
  final AppUser draft;
  final ValueChanged<AppUser> onChanged;

  @override
  Widget build(BuildContext context) {
    final org = draft.organization!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeader(
          icon: Icons.verified_rounded,
          color: AppColors.coral,
          title: 'Onay süreci',
          subtitle:
              'Hesabını doğrulayabilmemiz için bir iletişim numarası bırak.',
        ),
        TextFormField(
          initialValue: org.contactPhone,
          keyboardType: TextInputType.phone,
          onChanged: (v) => onChanged(
            draft.copyWith(organization: org.copyWith(contactPhone: v.trim())),
          ),
          decoration: const InputDecoration(
            labelText: 'Telefon (isteğe bağlı)',
            hintText: '0 5xx xxx xx xx',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: 28),
        const SectionLabel('Sonraki adımlar'),
        const SurfaceCard(
          child: Column(
            children: [
              _TimelineItem(
                icon: Icons.check_rounded,
                color: AppColors.success,
                title: 'Başvuru alındı',
                body: 'Hesabın oluşturuldu.',
                done: true,
              ),
              _TimelineItem(
                icon: Icons.hourglass_top_rounded,
                color: AppColors.amber,
                title: 'İnceleme',
                body: 'Ekibimiz bilgilerini kontrol eder, genellikle 1–2 iş günü.',
              ),
              _TimelineItem(
                icon: Icons.campaign_rounded,
                color: AppColors.plum,
                title: 'Yayına hazır',
                body: 'Onaydan sonra gönderdiğin etkinlikler haritada görünür.',
                last: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.done = false,
    this.last = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final bool done;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: done ? color : color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: done ? Colors.white : color),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: AppColors.line,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 4, bottom: last ? 0 : 18),
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
                  Text(
                    body,
                    style: text.bodySmall?.copyWith(color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
