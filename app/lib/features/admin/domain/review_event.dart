/// Admin onayı bekleyen, organizatörün gönderdiği etkinlik.
class ReviewEvent {
  const ReviewEvent({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.category,
    required this.submittedAt,
    this.description,
    this.endsAt,
    this.priceMin,
    this.priceMax,
    this.ticketUrl,
    this.requiresRegistration = false,
    this.venueName,
    this.venueAddress,
    this.organizerName,
    this.organizationName,
  });

  final String id;
  final String title;
  final String? description;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String category;
  final double? priceMin;
  final double? priceMax;
  final String? ticketUrl;
  final bool requiresRegistration;
  final String? venueName;
  final String? venueAddress;
  final String? organizerName;
  final String? organizationName;
  final DateTime submittedAt;

  static const columns =
      'id, title, description, starts_at, ends_at, category, price_min, '
      'price_max, ticket_url, requires_registration, created_at, '
      'venues(name, address), profiles(full_name, organization)';

  factory ReviewEvent.fromJson(Map<String, dynamic> j) {
    final venue = j['venues'] as Map<String, dynamic>?;
    final profile = j['profiles'] as Map<String, dynamic>?;
    final org = profile?['organization'] as Map<String, dynamic>?;
    double? num_(Object? v) => switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };
    return ReviewEvent(
      id: j['id'] as String,
      title: j['title'] as String,
      description: j['description'] as String?,
      startsAt: DateTime.parse(j['starts_at'] as String).toUtc(),
      endsAt: j['ends_at'] == null
          ? null
          : DateTime.parse(j['ends_at'] as String).toUtc(),
      category: (j['category'] as String?) ?? 'other',
      priceMin: num_(j['price_min']),
      priceMax: num_(j['price_max']),
      ticketUrl: j['ticket_url'] as String?,
      requiresRegistration: j['requires_registration'] == true,
      venueName: venue?['name'] as String?,
      venueAddress: venue?['address'] as String?,
      organizerName: profile?['full_name'] as String?,
      organizationName: org?['name'] as String?,
      submittedAt: DateTime.parse(j['created_at'] as String).toLocal(),
    );
  }
}
