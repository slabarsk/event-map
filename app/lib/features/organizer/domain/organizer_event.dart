/// Organizatörün gönderdiği etkinliğin yayın durumu.
enum EventStatus {
  pending,
  published,
  rejected;

  static EventStatus parse(String? v) => switch (v) {
    'published' => published,
    'rejected' => rejected,
    _ => pending,
  };

  String get label => switch (this) {
    pending => 'Onay bekliyor',
    published => 'Yayında',
    rejected => 'Reddedildi',
  };
}

/// Organizatör panelindeki "Etkinliklerim" satırı.
class OrganizerEvent {
  const OrganizerEvent({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.category,
    required this.status,
    this.venueName,
    this.reviewNote,
  });

  final String id;
  final String title;
  final DateTime startsAt;
  final String category;
  final EventStatus status;
  final String? venueName;

  /// Admin reddettiyse gerekçesi.
  final String? reviewNote;

  static const columns =
      'id, title, starts_at, category, status, review_note, venues(name)';

  factory OrganizerEvent.fromJson(Map<String, dynamic> j) => OrganizerEvent(
    id: j['id'] as String,
    title: j['title'] as String,
    startsAt: DateTime.parse(j['starts_at'] as String).toUtc(),
    category: (j['category'] as String?) ?? 'other',
    status: EventStatus.parse(j['status'] as String?),
    venueName: (j['venues'] as Map<String, dynamic>?)?['name'] as String?,
    reviewNote: j['review_note'] as String?,
  );
}

class OrganizerStats {
  const OrganizerStats({
    this.published = 0,
    this.pending = 0,
    this.rejected = 0,
    this.saves = 0,
  });
  final int published;
  final int pending;
  final int rejected;

  /// Organizatörün etkinliklerinin toplam kaydedilme sayısı.
  final int saves;
}

/// Kayıtlı mekân (etkinlik formunda seçilir).
class VenueOption {
  const VenueOption({required this.id, required this.name, this.address});
  final String id;
  final String name;
  final String? address;
}

/// Etkinlik gönderme formunun içeriği. Saatler UTC'dir; form İzmir saatiyle
/// girer ve çevirir.
class EventDraft {
  const EventDraft({
    required this.title,
    required this.category,
    required this.startsAt,
    this.endsAt,
    this.description,
    this.venueId,
    this.venueName,
    this.venueAddress,
    this.lat,
    this.lng,
    this.isFree = false,
    this.priceMin,
    this.priceMax,
    this.ticketUrl,
    this.requiresRegistration = false,
  });

  final String title;
  final String category;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String? description;

  /// Kayıtlı mekân seçildiyse; yoksa ad + konumla yeni mekân.
  final String? venueId;
  final String? venueName;
  final String? venueAddress;
  final double? lat;
  final double? lng;

  final bool isFree;
  final double? priceMin;
  final double? priceMax;
  final String? ticketUrl;
  final bool requiresRegistration;

  /// `submit_event` RPC parametreleri.
  Map<String, dynamic> toParams() => {
    'p_title': title,
    'p_starts_at': startsAt.toUtc().toIso8601String(),
    'p_category': category,
    'p_description': description,
    'p_ends_at': endsAt?.toUtc().toIso8601String(),
    'p_venue_id': venueId,
    'p_venue_name': venueId == null ? venueName : null,
    'p_venue_address': venueId == null ? venueAddress : null,
    'p_lat': venueId == null ? lat : null,
    'p_lng': venueId == null ? lng : null,
    'p_is_free': isFree,
    'p_price_min': isFree ? null : priceMin,
    'p_price_max': isFree ? null : priceMax,
    'p_ticket_url': ticketUrl,
    'p_requires_registration': requiresRegistration,
  };
}
