import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/organizer_event.dart';

/// Ekranda gösterilebilen, Türkçe mesajlı organizatör işlemi hatası.
class OrganizerFailure implements Exception {
  const OrganizerFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract class OrganizerRepository {
  /// Etkinliği admin onayına gönderir; yeni etkinliğin kimliğini döner.
  Future<String> submit(EventDraft draft);

  /// Organizatörün tüm etkinlikleri (her durumda), yaklaşan önce.
  Future<List<OrganizerEvent>> myEvents();

  Future<OrganizerStats> stats();

  /// Ada göre kayıtlı mekânlar (en fazla 8).
  Future<List<VenueOption>> searchVenues(String query);

  /// Onay bekleyen etkinliği geri çeker (siler).
  Future<void> withdraw(String eventId);
}

/// `submit_event` / `organizer_stats` RPC'leri ve `events` RLS'i
/// (organizatör kendi etkinliklerini görür, yalnızca pending olanı siler).
class SupabaseOrganizerRepository implements OrganizerRepository {
  SupabaseOrganizerRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<String> submit(EventDraft draft) => _guard(
    () async =>
        await _client.rpc<String>('submit_event', params: draft.toParams()),
  );

  @override
  Future<List<OrganizerEvent>> myEvents() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _guard(
      () => _client
          .from('events')
          .select(OrganizerEvent.columns)
          .eq('created_by', uid)
          .order('starts_at', ascending: false)
          .limit(100),
    );
    return rows.map(OrganizerEvent.fromJson).toList();
  }

  @override
  Future<OrganizerStats> stats() async {
    final rows = await _guard(
      () => _client.rpc<List<dynamic>>('organizer_stats'),
    );
    if (rows.isEmpty) return const OrganizerStats();
    final r = rows.first as Map<String, dynamic>;
    int n(String k) => (r[k] as num?)?.toInt() ?? 0;
    return OrganizerStats(
      published: n('published'),
      pending: n('pending'),
      rejected: n('rejected'),
      saves: n('saves'),
    );
  }

  @override
  Future<List<VenueOption>> searchVenues(String query) async {
    final q = query.trim().replaceAll(RegExp(r'[%_,()]'), ' ');
    if (q.length < 2) return const [];
    final rows = await _guard(
      () => _client
          .from('venues')
          .select('id, name, address')
          .ilike('name', '%$q%')
          .order('name')
          .limit(8),
    );
    return [
      for (final r in rows)
        VenueOption(
          id: r['id'] as String,
          name: r['name'] as String,
          address: r['address'] as String?,
        ),
    ];
  }

  @override
  Future<void> withdraw(String eventId) => _guard(
    () => _client
        .from('events')
        .delete()
        .eq('id', eventId)
        .eq('status', 'pending'),
  );

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw OrganizerFailure(switch (e.code) {
        '42501' =>
          'Etkinlik göndermek için hesabının onaylanmış olması gerekiyor.',
        '22023' => _validationMessage(e.message),
        '23514' => 'Bilgilerden biri geçersiz (fiyat aralığı ya da saatler).',
        _ => 'Sunucu hatası, tekrar dene.',
      });
    } on AuthException {
      throw const OrganizerFailure('Oturumun sona ermiş, yeniden giriş yap.');
    }
  }

  static String _validationMessage(String m) {
    if (m.contains('future')) return 'Başlangıç saati gelecekte olmalı.';
    if (m.contains('outside')) {
      return 'Mekân konumu İzmir/Türkiye dışında görünüyor.';
    }
    if (m.contains('venue')) return 'Mekân seç ya da haritadan konum işaretle.';
    return 'Eksik ya da geçersiz bilgi var.';
  }
}

/// Supabase olmadan (demo modu ve testler) bellek içi organizatör verisi.
class DemoOrganizerRepository implements OrganizerRepository {
  final List<OrganizerEvent> _events = [];
  int _next = 1;

  static const _venues = [
    VenueOption(
      id: 'venue-aassm',
      name: 'Ahmet Adnan Saygun Sanat Merkezi',
      address: 'Konak/İzmir',
    ),
    VenueOption(
      id: 'venue-kulturpark',
      name: 'Kültürpark Açık Hava Tiyatrosu',
      address: 'Konak/İzmir',
    ),
    VenueOption(
      id: 'venue-bornova',
      name: 'Bornova Kültür Merkezi',
      address: 'Bornova/İzmir',
    ),
  ];

  @override
  Future<String> submit(EventDraft draft) async {
    final venue = draft.venueId == null
        ? draft.venueName
        : _venues.where((v) => v.id == draft.venueId).firstOrNull?.name;
    final id = 'draft-${_next++}';
    _events.insert(
      0,
      OrganizerEvent(
        id: id,
        title: draft.title,
        startsAt: draft.startsAt,
        category: draft.category,
        status: EventStatus.pending,
        venueName: venue,
      ),
    );
    return id;
  }

  @override
  Future<List<OrganizerEvent>> myEvents() async => List.of(_events);

  @override
  Future<OrganizerStats> stats() async => OrganizerStats(
    published: _events.where((e) => e.status == EventStatus.published).length,
    pending: _events.where((e) => e.status == EventStatus.pending).length,
    rejected: _events.where((e) => e.status == EventStatus.rejected).length,
  );

  @override
  Future<List<VenueOption>> searchVenues(String query) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    return _venues.where((v) => v.name.toLowerCase().contains(q)).toList();
  }

  @override
  Future<void> withdraw(String eventId) async =>
      _events.removeWhere((e) => e.id == eventId);
}
