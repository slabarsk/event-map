import 'package:latlong2/latlong.dart';

import '../../events/domain/event.dart';

/// `nl-search` Edge Function'ının yanıtı.
class SearchResult {
  const SearchResult({
    required this.query,
    required this.labels,
    required this.events,
    this.needsLocation = false,
    this.location,
    this.radiusM,
    this.parser = 'rules',
  });

  final String query;

  /// Anlaşılan filtre: ["Bu akşam", "Konser", "Ücretsiz", "5 km içinde"].
  final List<String> labels;

  /// Yakından uzağa (konum varsa), sonra başlangıç saatine göre.
  final List<MapEvent> events;

  /// Soru "yakınımda" diyor ama konum gönderilmedi; sonuçlar şehir geneli.
  final bool needsLocation;

  /// Sorguda kullanılan konum (haritada gösterilir, saklanmaz).
  final LatLng? location;
  final int? radiusM;

  /// `claude` ya da `rules` (yedek ayrıştırıcı).
  final String parser;

  factory SearchResult.fromJson(
    String query,
    Map<String, dynamic> json, {
    LatLng? location,
  }) {
    final radius = json['radius_m'];
    final needsLocation = json['needs_location'] == true;
    return SearchResult(
      query: query,
      labels: [for (final l in json['labels'] as List? ?? const []) '$l'],
      events: [
        for (final row in json['events'] as List? ?? const [])
          MapEvent.fromRow(row as Map<String, dynamic>),
      ],
      needsLocation: needsLocation,
      // Soru konum istemediyse gönderilen konum kullanılmamıştır.
      location: radius is num && !needsLocation ? location : null,
      radiusM: radius is num ? radius.toInt() : null,
      parser: (json['parser'] as String?) ?? 'rules',
    );
  }
}

/// Ekranda gösterilebilen, Türkçe mesajlı arama hatası.
class SearchFailure implements Exception {
  const SearchFailure(this.message);
  final String message;

  @override
  String toString() => message;
}
