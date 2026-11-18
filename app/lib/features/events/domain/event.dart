/// Fiyatın nereden geldiği. Ücretsiz etkinlik `price = 0` ve [listed] olur.
enum PriceStatus {
  /// Fiyat bilinmiyor (kaynakta yok, fiyat ajanı da bulamadı/tahmin etmedi).
  unknown,

  /// Kaynak sayfada yazıyor.
  listed,

  /// Fiyat ajanı bilet/detay sayfasında buldu.
  lookedUp,

  /// Bulunamadı; benzer etkinliklerden tahmin edildi. UI'da her zaman
  /// "Tahmini" olarak etiketlenir.
  estimated;

  static PriceStatus parse(String? value) => switch (value) {
    'listed' => listed,
    'looked_up' => lookedUp,
    'estimated' => estimated,
    _ => unknown,
  };

  String get dbValue => switch (this) {
    unknown => 'unknown',
    listed => 'listed',
    lookedUp => 'looked_up',
    estimated => 'estimated',
  };
}

/// Haritada gösterilen yayınlanmış etkinlik. Alanlar `events_near` RPC'sinin
/// döndürdüğü satırla birebir eşleşir (bkz. supabase/migrations).
class MapEvent {
  const MapEvent({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.category,
    required this.venueId,
    required this.venueName,
    required this.lat,
    required this.lng,
    this.description,
    this.endsAt,
    this.priceMin,
    this.priceMax,
    this.priceStatus = PriceStatus.unknown,
    this.priceSourceUrl,
    this.imageUrl,
    this.ticketUrl,
    this.venueAddress,
    this.distanceM,
    this.sourceCount = 0,
  });

  final String id;
  final String title;
  final String? description;

  /// UTC.
  final DateTime startsAt;
  final DateTime? endsAt;

  /// Veritabanındaki kategori kimliği (`concert`, `theatre`, …).
  final String category;

  final double? priceMin;
  final double? priceMax;
  final PriceStatus priceStatus;
  final String? priceSourceUrl;
  final String? imageUrl;
  final String? ticketUrl;

  final String venueId;
  final String venueName;
  final String? venueAddress;
  final double lat;
  final double lng;

  /// Sorguda konum verildiyse metre cinsinden uzaklık; yoksa null.
  final double? distanceM;

  /// Etkinliğin bulunduğu kaynak sayısı (duplicate merge sonrası).
  final int sourceCount;

  bool get isFree => priceMin == 0 && (priceMax ?? 0) == 0;

  factory MapEvent.fromRow(Map<String, dynamic> row) => MapEvent(
    id: row['id'] as String,
    title: row['title'] as String,
    description: row['description'] as String?,
    startsAt: DateTime.parse(row['starts_at'] as String).toUtc(),
    endsAt: _date(row['ends_at']),
    category: (row['category'] as String?) ?? 'other',
    priceMin: _num(row['price_min']),
    priceMax: _num(row['price_max']),
    priceStatus: PriceStatus.parse(row['price_status'] as String?),
    priceSourceUrl: row['price_source_url'] as String?,
    imageUrl: row['image_url'] as String?,
    ticketUrl: row['ticket_url'] as String?,
    venueId: row['venue_id'] as String,
    venueName: row['venue_name'] as String,
    venueAddress: row['venue_address'] as String?,
    lat: (row['lat'] as num).toDouble(),
    lng: (row['lng'] as num).toDouble(),
    distanceM: _num(row['distance_m']),
    sourceCount: (row['source_count'] as num?)?.toInt() ?? 0,
  );

  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.parse(v as String).toUtc();

  // PostgREST numeric sütunları sayı ya da metin olarak gelebilir.
  static double? _num(Object? v) => switch (v) {
    null => null,
    num n => n.toDouble(),
    String s => double.tryParse(s),
    _ => null,
  };
}

/// Aynı mekândaki etkinlikler tek pin olarak gösterilir; aksi halde aynı
/// koordinattaki pinler üst üste biner.
class VenueGroup {
  const VenueGroup(this.events);

  /// Başlangıç saatine göre sıralı, en az bir etkinlik.
  final List<MapEvent> events;

  MapEvent get first => events.first;
  String get venueId => first.venueId;
  String get venueName => first.venueName;
  double get lat => first.lat;
  double get lng => first.lng;

  static List<VenueGroup> fromEvents(Iterable<MapEvent> events) {
    final byVenue = <String, List<MapEvent>>{};
    for (final e in events) {
      byVenue.putIfAbsent(e.venueId, () => []).add(e);
    }
    return [
      for (final list in byVenue.values)
        VenueGroup(list..sort((a, b) => a.startsAt.compareTo(b.startsAt))),
    ]..sort((a, b) => a.first.startsAt.compareTo(b.first.startsAt));
  }
}
