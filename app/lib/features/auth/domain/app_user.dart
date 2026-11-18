enum UserRole {
  user,
  organizer,

  /// Yalnızca SQL ile atanır (bkz. README); kayıt ekranlarında seçilemez.
  admin;

  static UserRole parse(String? value) => switch (value) {
    'organizer' => UserRole.organizer,
    'admin' => UserRole.admin,
    _ => UserRole.user,
  };
}

enum OrganizerStatus {
  pending,
  approved,
  rejected;

  static OrganizerStatus? parse(String? value) => switch (value) {
    'pending' => OrganizerStatus.pending,
    'approved' => OrganizerStatus.approved,
    'rejected' => OrganizerStatus.rejected,
    _ => null,
  };
}

/// Normal kullanıcının keşif tercihleri. Organizatörler de bildirim alanlarını kullanır.
class UserPreferences {
  const UserPreferences({
    this.categories = const {},
    this.district,
    this.radiusKm = 5,
    this.freeOnly = false,
    this.maxPrice,
    this.notifyWeekend = true,
    this.notifyNearby = false,
  });

  final Set<String> categories;
  final String? district;
  final int radiusKm;
  final bool freeOnly;

  /// TL cinsinden üst sınır; null = sınır yok.
  final int? maxPrice;
  final bool notifyWeekend;
  final bool notifyNearby;

  UserPreferences copyWith({
    Set<String>? categories,
    String? district,
    bool clearDistrict = false,
    int? radiusKm,
    bool? freeOnly,
    int? maxPrice,
    bool clearMaxPrice = false,
    bool? notifyWeekend,
    bool? notifyNearby,
  }) => UserPreferences(
    categories: categories ?? this.categories,
    district: clearDistrict ? null : (district ?? this.district),
    radiusKm: radiusKm ?? this.radiusKm,
    freeOnly: freeOnly ?? this.freeOnly,
    maxPrice: clearMaxPrice ? null : (maxPrice ?? this.maxPrice),
    notifyWeekend: notifyWeekend ?? this.notifyWeekend,
    notifyNearby: notifyNearby ?? this.notifyNearby,
  );

  Map<String, dynamic> toJson() => {
    'categories': categories.toList(),
    'district': district,
    'radius_km': radiusKm,
    'free_only': freeOnly,
    'max_price': maxPrice,
    'notify_weekend': notifyWeekend,
    'notify_nearby': notifyNearby,
  };

  factory UserPreferences.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const UserPreferences();
    return UserPreferences(
      categories: {...(json['categories'] as List? ?? const []).cast<String>()},
      district: json['district'] as String?,
      radiusKm: (json['radius_km'] as num?)?.toInt() ?? 5,
      freeOnly: json['free_only'] as bool? ?? false,
      maxPrice: (json['max_price'] as num?)?.toInt(),
      notifyWeekend: json['notify_weekend'] as bool? ?? true,
      notifyNearby: json['notify_nearby'] as bool? ?? false,
    );
  }
}

/// Organizatörün kurum bilgisi.
class Organization {
  const Organization({
    this.name = '',
    this.type,
    this.district,
    this.website,
    this.instagram,
    this.categories = const {},
    this.contactPhone,
  });

  final String name;
  final String? type;
  final String? district;
  final String? website;
  final String? instagram;
  final Set<String> categories;
  final String? contactPhone;

  Organization copyWith({
    String? name,
    String? type,
    String? district,
    String? website,
    String? instagram,
    Set<String>? categories,
    String? contactPhone,
  }) => Organization(
    name: name ?? this.name,
    type: type ?? this.type,
    district: district ?? this.district,
    website: website ?? this.website,
    instagram: instagram ?? this.instagram,
    categories: categories ?? this.categories,
    contactPhone: contactPhone ?? this.contactPhone,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'district': district,
    'website': website,
    'instagram': instagram,
    'categories': categories.toList(),
    'contact_phone': contactPhone,
  };

  factory Organization.fromJson(Map<String, dynamic> json) => Organization(
    name: json['name'] as String? ?? '',
    type: json['type'] as String?,
    district: json['district'] as String?,
    website: json['website'] as String?,
    instagram: json['instagram'] as String?,
    categories: {...(json['categories'] as List? ?? const []).cast<String>()},
    contactPhone: json['contact_phone'] as String?,
  );
}

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.organizerStatus,
    this.onboardingCompleted = false,
    this.preferences = const UserPreferences(),
    this.organization,
    this.kvkkConsentAt,
  });

  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final OrganizerStatus? organizerStatus;
  final bool onboardingCompleted;
  final UserPreferences preferences;
  final Organization? organization;
  final DateTime? kvkkConsentAt;

  bool get isOrganizer => role == UserRole.organizer;
  bool get isAdmin => role == UserRole.admin;

  String get firstName {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return email.split('@').first;
    return trimmed.split(RegExp(r'\s+')).first;
  }

  String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty);
    if (parts.isEmpty) return email.isEmpty ? '?' : email[0].toUpperCase();
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  AppUser copyWith({
    String? fullName,
    bool? onboardingCompleted,
    UserPreferences? preferences,
    Organization? organization,
    DateTime? kvkkConsentAt,
  }) => AppUser(
    id: id,
    email: email,
    fullName: fullName ?? this.fullName,
    role: role,
    organizerStatus: organizerStatus,
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    preferences: preferences ?? this.preferences,
    organization: organization ?? this.organization,
    kvkkConsentAt: kvkkConsentAt ?? this.kvkkConsentAt,
  );

  /// `profiles` tablosundaki satırın biçimi.
  Map<String, dynamic> toProfileJson() => {
    'id': id,
    'full_name': fullName,
    'role': role.name,
    'organizer_status': organizerStatus?.name,
    'onboarding_completed': onboardingCompleted,
    'preferences': preferences.toJson(),
    'organization': organization?.toJson(),
    'kvkk_consent_at': kvkkConsentAt?.toIso8601String(),
  };

  factory AppUser.fromProfileJson(
    Map<String, dynamic> json, {
    required String email,
  }) {
    final org = json['organization'];
    final consent = json['kvkk_consent_at'] as String?;
    return AppUser(
      id: json['id'] as String,
      email: email,
      fullName: json['full_name'] as String? ?? '',
      role: UserRole.parse(json['role'] as String?),
      organizerStatus: OrganizerStatus.parse(
        json['organizer_status'] as String?,
      ),
      onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
      preferences: UserPreferences.fromJson(
        json['preferences'] as Map<String, dynamic>?,
      ),
      organization: org is Map<String, dynamic>
          ? Organization.fromJson(org)
          : null,
      kvkkConsentAt: consent == null ? null : DateTime.tryParse(consent),
    );
  }
}
