import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/event.dart';
import 'events_repository.dart';

/// Etkinlikleri `events_near` RPC'si üzerinden okur. RPC `security invoker`
/// olduğu için RLS geçerlidir: yalnızca yayınlanmış etkinlikler gelir.
class SupabaseEventsRepository implements EventsRepository {
  SupabaseEventsRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<MapEvent>> upcoming({
    required DateTime from,
    DateTime? to,
  }) async {
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'events_near',
        params: {
          'p_from': from.toUtc().toIso8601String(),
          'p_to': to?.toUtc().toIso8601String(),
        },
      );
      return [
        for (final row in rows) MapEvent.fromRow(row as Map<String, dynamic>),
      ];
    } on PostgrestException catch (e) {
      // PGRST202: fonksiyon yok, yani etkinlik migration'ları bu projeye
      // henüz uygulanmamış.
      if (e.code == 'PGRST202') {
        throw const EventsFailure(
          'Etkinlik verisi henüz hazır değil (events_near bulunamadı).',
        );
      }
      throw const EventsFailure('Etkinlikler yüklenemedi.');
    }
  }
}
