import '../../auth/domain/app_user.dart';

/// Admin panelinde listelenen organizatör başvurusu (`profiles` satırı).
class OrganizerApplication {
  const OrganizerApplication({
    required this.id,
    required this.fullName,
    required this.status,
    required this.appliedAt,
    this.organization = const Organization(),
    this.updatedAt,
  });

  final String id;
  final String fullName;
  final OrganizerStatus status;
  final Organization organization;

  /// Hesabın oluşturulduğu an; organizatörler kayıtta başvurmuş olur.
  final DateTime appliedAt;
  final DateTime? updatedAt;

  String get displayName =>
      fullName.trim().isEmpty ? 'İsimsiz organizatör' : fullName.trim();

  String get organizationName => organization.name.trim().isEmpty
      ? 'Kurum adı girilmemiş'
      : organization.name.trim();

  OrganizerApplication copyWith({OrganizerStatus? status}) =>
      OrganizerApplication(
        id: id,
        fullName: fullName,
        status: status ?? this.status,
        organization: organization,
        appliedAt: appliedAt,
        updatedAt: DateTime.now(),
      );

  /// Listelemede yalnızca bu sütunlar istenir (KVKK: gereğinden fazla veri yok).
  static const columns =
      'id, full_name, organizer_status, organization, created_at, updated_at';

  factory OrganizerApplication.fromJson(Map<String, dynamic> json) {
    final org = json['organization'];
    return OrganizerApplication(
      id: json['id'] as String,
      fullName: json['full_name'] as String? ?? '',
      status:
          OrganizerStatus.parse(json['organizer_status'] as String?) ??
          OrganizerStatus.pending,
      organization: org is Map<String, dynamic>
          ? Organization.fromJson(org)
          : const Organization(),
      appliedAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String).toLocal(),
    );
  }
}
