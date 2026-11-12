import 'package:material_ui/material_ui.dart';

import '../../../core/catalog.dart';
import '../../../core/theme/app_colors.dart';

/// Veritabanındaki kategori kimliğinin ikon, renk ve etiketi.
///
/// Onboarding kataloğunda olmayan kategoriler (crawler'ın ürettiği `party`,
/// `other` gibi) burada tamamlanır; bilinmeyen değer "Diğer" olarak görünür.
EventCategory eventCategoryOf(String id) =>
    Catalog.category(id) ?? _extra[id] ?? _other;

const _other = EventCategory(
  'other',
  'Diğer',
  Icons.place_rounded,
  AppColors.inkSoft,
);

const _extra = <String, EventCategory>{
  'party': EventCategory(
    'party',
    'Parti',
    Icons.nightlife_rounded,
    AppColors.pink,
  ),
  'other': _other,
};
