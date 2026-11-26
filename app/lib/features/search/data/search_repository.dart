import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../events/data/events_repository.dart';
import '../../events/domain/event.dart';
import '../../events/domain/event_format.dart';
import '../domain/search_result.dart';

/// Doğal dil araması ("Bu akşam yakınımdaki ücretsiz konserler").
abstract class SearchRepository {
  Future<SearchResult> search(
    String query, {
    LatLng? location,
    int defaultRadiusM = 5000,
  });
}

/// `nl-search` Edge Function'ı. Konum yalnızca bu istekte gönderilir.
class SupabaseSearchRepository implements SearchRepository {
  SupabaseSearchRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<SearchResult> search(
    String query, {
    LatLng? location,
    int defaultRadiusM = 5000,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'nl-search',
        body: {
          'query': query,
          'lat': ?location?.latitude,
          'lng': ?location?.longitude,
          'default_radius_m': defaultRadiusM,
        },
      );
      return SearchResult.fromJson(
        query,
        res.data as Map<String, dynamic>,
        location: location,
      );
    } on FunctionException catch (e) {
      if (e.status == 404) {
        throw const SearchFailure('Arama servisi henüz yayında değil.');
      }
      if (e.status == 400) {
        throw const SearchFailure('Soruyu biraz kısaltıp tekrar dener misin?');
      }
      throw const SearchFailure('Arama yapılamadı, tekrar dene.');
    } on Exception {
      throw const SearchFailure('Bağlantı kurulamadı, tekrar dene.');
    }
  }
}

/// Supabase olmadan (demo modu ve testler): `nl-search`'teki kural tabanlı
/// ayrıştırıcının sade bir kopyası, demo etkinlikleri üzerinde çalışır.
class DemoSearchRepository implements SearchRepository {
  DemoSearchRepository(this._events, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final EventsRepository _events;
  final DateTime Function() _clock;

  static const _distance = Distance();

  @override
  Future<SearchResult> search(
    String query, {
    LatLng? location,
    int defaultRadiusM = 5000,
  }) async {
    final f = DemoQuery.parse(query);
    final now = _clock();
    final (from, to) = f.window(now);
    final radius = f.radiusM ?? defaultRadiusM;
    final useLocation = f.nearMe && location != null;

    final events = (await _events.upcoming(from: from, to: to)).where((e) {
      if (f.categories.isNotEmpty && !f.categories.contains(e.category)) {
        return false;
      }
      final price = e.priceMin ?? e.priceMax;
      if (f.freeOnly && price != 0) return false;
      if (f.maxPrice case final max? when price == null || price > max) {
        return false;
      }
      if (useLocation &&
          _distance.as(LengthUnit.Meter, location, LatLng(e.lat, e.lng)) >
              radius) {
        return false;
      }
      return true;
    }).toList();
    if (useLocation) {
      double d(MapEvent e) =>
          _distance.as(LengthUnit.Meter, location, LatLng(e.lat, e.lng));
      events.sort((a, b) => d(a).compareTo(d(b)));
    }

    return SearchResult(
      query: query,
      labels: [
        f.windowLabel,
        ...f.categoryLabels,
        if (f.freeOnly)
          'Ücretsiz'
        else if (f.maxPrice != null)
          '${f.maxPrice} ₺ altı',
        if (useLocation)
          '${(radius / 1000).toStringAsFixed(radius % 1000 == 0 ? 0 : 1).replaceAll('.', ',')} km içinde',
      ],
      events: events,
      needsLocation: f.nearMe && location == null,
      location: useLocation ? location : null,
      radiusM: f.nearMe ? radius : null,
    );
  }
}

/// `supabase/functions/nl-search/filter.ts` ruleBasedFilter + timeWindow'un
/// demo için sade Dart karşılığı.
class DemoQuery {
  const DemoQuery({
    this.categories = const [],
    this.freeOnly = false,
    this.maxPrice,
    this.timeWindow = 'upcoming',
    this.nearMe = false,
    this.radiusM,
  });

  final List<String> categories;
  final bool freeOnly;
  final int? maxPrice;
  final String timeWindow;
  final bool nearMe;
  final int? radiusM;

  static String normalize(String s) {
    const from = 'İIıŞşĞğÜüÖöÇç';
    const to = 'iiissgguuoocc';
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString().toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static final _categories = <String, RegExp>{
    'concert': RegExp(r'\b(konser|muzik|caz|jazz|rock|resital|senfoni)'),
    'theatre': RegExp(r'\b(tiyatro|opera|bale|muzikal)'),
    'exhibition': RegExp(r'\b(sergi|muze|resim|galeri)'),
    'festival': RegExp(r'\bfestival'),
    'standup': RegExp(r'\b(stand[ -]?up|komedi)'),
    'workshop': RegExp(r'\b(atolye|workshop|kurs)'),
    'cinema': RegExp(r'\b(sinema|film)'),
    'talk': RegExp(r'\b(soylesi|konferans|panel|seminer)'),
    'sports': RegExp(r'\b(spor|mac|kosu|yoga)'),
    'family': RegExp(r'\b(cocuk|aile)'),
    'party': RegExp(r'\b(parti|dj)'),
  };

  static const _categoryLabels = {
    'concert': 'Konser',
    'theatre': 'Tiyatro',
    'exhibition': 'Sergi',
    'festival': 'Festival',
    'standup': 'Stand-up',
    'workshop': 'Atölye',
    'cinema': 'Sinema',
    'talk': 'Söyleşi',
    'sports': 'Spor',
    'family': 'Çocuk & Aile',
    'party': 'Parti',
  };

  factory DemoQuery.parse(String query) {
    final q = normalize(query);
    bool has(String pattern) => RegExp(pattern).hasMatch(q);
    final window = has(r'\b(yarin|tomorrow)\b')
        ? 'tomorrow'
        : has(r'\b(hafta ?sonu|cumartesi|pazar|weekend)\b')
        ? 'this_weekend'
        : has(r'\b(bu ?aksam|bu ?gece|aksam|gece|tonight)\b')
        ? 'tonight'
        : has(r'\b(bugun|today)\b')
        ? 'today'
        : has(r'\bbu hafta\b')
        ? 'this_week'
        : 'upcoming';
    final price = RegExp(r'(\d+)\s*(?:(?:tl|lira)\b|₺)').firstMatch(q);
    final km = RegExp(r'(\d+(?:[.,]\d+)?)\s*(km|kilometre)\b').firstMatch(q);
    final walking = has(r'\byurume mesafesi');
    final free = has(r'\b(ucretsiz|bedava|free|parasiz)\b');
    return DemoQuery(
      categories: [
        for (final MapEntry(:key, :value) in _categories.entries)
          if (value.hasMatch(q)) key,
      ],
      freeOnly: free,
      maxPrice: free || price == null ? null : int.parse(price.group(1)!),
      timeWindow: window,
      nearMe:
          walking ||
          km != null ||
          has(r'\b(yakin|civar|etrafimda|cevremde|near)'),
      radiusM: km != null
          ? (double.parse(km.group(1)!.replaceAll(',', '.')) * 1000).round()
          : walking
          ? 1500
          : null,
    );
  }

  String get windowLabel => switch (timeWindow) {
    'tonight' => 'Bu akşam',
    'today' => 'Bugün',
    'tomorrow' => 'Yarın',
    'this_weekend' => 'Hafta sonu',
    'this_week' => 'Bu hafta',
    _ => 'Yaklaşan',
  };

  List<String> get categoryLabels => [
    for (final c in categories) _categoryLabels[c] ?? c,
  ];

  /// (from, to): events_near parametreleri. "Bu akşam" 17:00–03:00.
  (DateTime, DateTime?) window(DateTime now) {
    final day = EventFormat.istanbulDayStart(now);
    final hour = EventFormat.toIstanbul(now).hour;
    DateTime later(DateTime t) => t.isAfter(now) ? t : now;
    final weekday = EventFormat.toIstanbul(now).weekday; // 1 = Pazartesi
    final monday = day.add(Duration(days: 8 - weekday));
    return switch (timeWindow) {
      'tonight' => () {
        final evening = hour < 3 ? day.subtract(const Duration(days: 1)) : day;
        return (
          later(evening.add(const Duration(hours: 17))),
          evening.add(const Duration(hours: 27)),
        );
      }(),
      'today' => (now, day.add(const Duration(days: 1))),
      'tomorrow' => (
        day.add(const Duration(days: 1)),
        day.add(const Duration(days: 2)),
      ),
      'this_weekend' => (
        later(monday.subtract(const Duration(days: 3, hours: -17))),
        monday,
      ),
      'this_week' => (now, monday),
      _ => (now, null),
    };
  }
}
