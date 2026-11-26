import 'package:supabase_flutter/supabase_flutter.dart';

import '../../events/domain/event.dart';

/// Ekranda gösterilebilen, Türkçe mesajlı kayıt hatası.
class SavedEventsFailure implements Exception {
  const SavedEventsFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Kullanıcının kaydettiği etkinlikler (`saved_events`, yalnızca sahibine açık).
abstract class SavedEventsRepository {
  /// Kayıtlı etkinlik kimlikleri; oturum yoksa boş.
  Future<Set<String>> ids();

  /// Kayıtlı etkinlikler, başlangıç saatine göre (geçmişler dahil).
  Future<List<MapEvent>> list();

  Future<void> save(MapEvent event);
  Future<void> remove(String eventId);
}

class SupabaseSavedEventsRepository implements SavedEventsRepository {
  SupabaseSavedEventsRepository(this._client);
  final SupabaseClient _client;

  String? get _uid => _client.auth.currentUser?.id;

  @override
  Future<Set<String>> ids() async {
    if (_uid == null) return {};
    final rows = await _guard(
      () => _client.from('saved_events').select('event_id'),
    );
    return {for (final r in rows) r['event_id'] as String};
  }

  @override
  Future<List<MapEvent>> list() async {
    if (_uid == null) return const [];
    final rows = await _guard(
      () => _client.rpc<List<dynamic>>('my_saved_events'),
    );
    return [for (final r in rows) MapEvent.fromRow(r as Map<String, dynamic>)];
  }

  @override
  Future<void> save(MapEvent event) async {
    final uid = _uid;
    if (uid == null) {
      throw const SavedEventsFailure('Kaydetmek için giriş yapmalısın.');
    }
    await _guard(
      () => _client.from('saved_events').upsert({
        'user_id': uid,
        'event_id': event.id,
      }, ignoreDuplicates: true),
    );
  }

  @override
  Future<void> remove(String eventId) async {
    final uid = _uid;
    if (uid == null) return;
    await _guard(
      () => _client
          .from('saved_events')
          .delete()
          .eq('user_id', uid)
          .eq('event_id', eventId),
    );
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException {
      throw const SavedEventsFailure('Kayıtlı etkinlikler güncellenemedi.');
    }
  }
}

/// Supabase olmadan (demo modu ve testler) bellek içi kayıtlar.
class DemoSavedEventsRepository implements SavedEventsRepository {
  final Map<String, MapEvent> _saved = {};

  @override
  Future<Set<String>> ids() async => {..._saved.keys};

  @override
  Future<List<MapEvent>> list() async =>
      _saved.values.toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  @override
  Future<void> save(MapEvent event) async => _saved[event.id] = event;

  @override
  Future<void> remove(String eventId) async => _saved.remove(eventId);
}
