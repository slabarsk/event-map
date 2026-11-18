import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/domain/app_user.dart';
import '../domain/organizer_application.dart';

/// Ekranda gösterilebilen, Türkçe mesajlı admin işlemi hatası.
class AdminFailure implements Exception {
  const AdminFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract class AdminRepository {
  /// En yeni başvuru önce.
  Future<List<OrganizerApplication>> applications(OrganizerStatus status);

  /// Bulunamazsa ya da erişim yoksa null.
  Future<OrganizerApplication?> application(String id);

  /// Organizatörün iletişim e-postası; yalnızca detay ekranında istenir.
  Future<String?> organizerEmail(String id);

  Future<void> setStatus(String id, OrganizerStatus status);
}

/// `profiles` (admin RLS politikası) + `set_organizer_status` /
/// `admin_organizer_email` RPC'leri. Bkz. supabase/migrations/*_admin_profiles.sql.
class SupabaseAdminRepository implements AdminRepository {
  SupabaseAdminRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<OrganizerApplication>> applications(
    OrganizerStatus status,
  ) async {
    final rows = await _guard(
      () => _client
          .from('profiles')
          .select(OrganizerApplication.columns)
          .eq('role', 'organizer')
          .eq('organizer_status', status.name)
          .order('created_at', ascending: false),
    );
    return rows.map(OrganizerApplication.fromJson).toList();
  }

  @override
  Future<OrganizerApplication?> application(String id) async {
    final row = await _guard(
      () => _client
          .from('profiles')
          .select(OrganizerApplication.columns)
          .eq('role', 'organizer')
          .eq('id', id)
          .maybeSingle(),
    );
    return row == null ? null : OrganizerApplication.fromJson(row);
  }

  @override
  Future<String?> organizerEmail(String id) => _guard(
    () async => await _client.rpc<String?>(
      'admin_organizer_email',
      params: {'p_user_id': id},
    ),
  );

  @override
  Future<void> setStatus(String id, OrganizerStatus status) => _guard(
    () => _client.rpc<void>(
      'set_organizer_status',
      params: {'p_user_id': id, 'p_status': status.name},
    ),
  );

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const AdminFailure('Bu işlem için admin yetkisi gerekiyor.');
      }
      throw AdminFailure('Sunucu hatası: ${e.message}');
    } on AuthException catch (_) {
      throw const AdminFailure('Oturumun sona ermiş, yeniden giriş yap.');
    }
  }
}

/// Supabase anahtarı olmadan (demo modu) ve testlerde kullanılan bellek içi
/// başvurular. Gerçek kişisel veri içermez.
class DemoAdminRepository implements AdminRepository {
  DemoAdminRepository({List<OrganizerApplication>? seed})
    : _items = {for (final a in seed ?? _demoSeed()) a.id: a};

  final Map<String, OrganizerApplication> _items;

  @override
  Future<List<OrganizerApplication>> applications(
    OrganizerStatus status,
  ) async {
    final list = _items.values.where((a) => a.status == status).toList()
      ..sort((a, b) => b.appliedAt.compareTo(a.appliedAt));
    return list;
  }

  @override
  Future<OrganizerApplication?> application(String id) async => _items[id];

  @override
  Future<String?> organizerEmail(String id) async =>
      _items.containsKey(id) ? 'organizator-$id@ornek.test' : null;

  @override
  Future<void> setStatus(String id, OrganizerStatus status) async {
    final item = _items[id];
    if (item == null) throw const AdminFailure('Başvuru bulunamadı.');
    _items[id] = item.copyWith(status: status);
  }

  static List<OrganizerApplication> _demoSeed() => [
    OrganizerApplication(
      id: 'demo-1',
      fullName: 'Deniz Kaya',
      status: OrganizerStatus.pending,
      appliedAt: DateTime(2026, 11, 17, 14, 20),
      organization: const Organization(
        name: 'Alsancak Sahne',
        type: 'Mekân',
        district: 'Konak',
        website: 'https://alsancaksahne.example',
        instagram: 'alsancaksahne',
        categories: {'concert', 'standup'},
        contactPhone: '0232 000 00 00',
      ),
    ),
    OrganizerApplication(
      id: 'demo-2',
      fullName: 'Ece Arslan',
      status: OrganizerStatus.pending,
      appliedAt: DateTime(2026, 11, 16, 9, 5),
      organization: const Organization(
        name: 'Bornova Film Kulübü',
        type: 'Topluluk / kulüp',
        district: 'Bornova',
        categories: {'cinema', 'talk'},
      ),
    ),
    OrganizerApplication(
      id: 'demo-3',
      fullName: 'Mert Demir',
      status: OrganizerStatus.approved,
      appliedAt: DateTime(2026, 11, 10, 18, 40),
      organization: const Organization(
        name: 'Kordon Festivali',
        type: 'Festival / organizasyon şirketi',
        district: 'Karşıyaka',
        categories: {'festival'},
      ),
    ),
  ];
}
