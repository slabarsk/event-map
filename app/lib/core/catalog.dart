import 'package:material_ui/material_ui.dart';

import 'theme/app_colors.dart';

/// Etkinlik kategorileri. `id` veritabanında saklanan değerdir.
class EventCategory {
  const EventCategory(this.id, this.label, this.icon, this.color);
  final String id;
  final String label;
  final IconData icon;
  final Color color;
}

abstract final class Catalog {
  static const categories = <EventCategory>[
    EventCategory(
      'concert',
      'Konser',
      Icons.music_note_rounded,
      AppColors.violet,
    ),
    EventCategory(
      'theatre',
      'Tiyatro',
      Icons.theater_comedy_rounded,
      AppColors.coral,
    ),
    EventCategory(
      'exhibition',
      'Sergi',
      Icons.palette_rounded,
      AppColors.amber,
    ),
    EventCategory(
      'festival',
      'Festival',
      Icons.celebration_rounded,
      AppColors.pink,
    ),
    EventCategory(
      'standup',
      'Stand-up',
      Icons.mic_external_on_rounded,
      AppColors.sky,
    ),
    EventCategory('workshop', 'Atölye', Icons.brush_rounded, AppColors.lime),
    EventCategory('cinema', 'Sinema', Icons.movie_rounded, AppColors.teal),
    EventCategory('talk', 'Söyleşi', Icons.forum_rounded, AppColors.coral),
    EventCategory('sports', 'Spor', Icons.sports_soccer_rounded, AppColors.sky),
    EventCategory(
      'family',
      'Çocuk & Aile',
      Icons.family_restroom_rounded,
      AppColors.amber,
    ),
  ];

  static EventCategory? category(String id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  static const districts = <String>[
    'Konak',
    'Karşıyaka',
    'Bornova',
    'Buca',
    'Bayraklı',
    'Çiğli',
    'Karabağlar',
    'Balçova',
    'Narlıdere',
    'Gaziemir',
    'Güzelbahçe',
    'Urla',
    'Çeşme',
    'Seferihisar',
  ];

  static const radiusOptionsKm = <int>[2, 5, 10, 25];

  static const priceCaps = <int?>[null, 100, 250, 500, 1000];

  static String priceCapLabel(int? cap) =>
      cap == null ? 'Fark etmez' : '$cap ₺ altı';

  static const organizerTypes = <String>[
    'Mekân',
    'Festival / organizasyon şirketi',
    'Kültür kurumu / belediye',
    'Topluluk / kulüp',
    'Bağımsız sanatçı',
  ];
}
