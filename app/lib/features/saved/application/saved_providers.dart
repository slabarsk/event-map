import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../events/domain/event.dart';
import '../data/saved_events_repository.dart';

/// main.dart içinde Supabase repository ile override edilir; varsayılan bellek
/// içi demo (testler bunu kullanır).
final savedEventsRepositoryProvider = Provider<SavedEventsRepository>(
  (ref) => DemoSavedEventsRepository(),
);

/// Kayıtlı etkinlik kimlikleri. Kaydet/kaldır anında arayüze yansır, sunucu
/// hata verirse geri alınır. Oturum kapanınca ekranlar kapandığı için
/// autoDispose ile sıfırlanır.
final savedIdsProvider =
    AsyncNotifierProvider.autoDispose<SavedIds, Set<String>>(SavedIds.new);

class SavedIds extends AsyncNotifier<Set<String>> {
  SavedEventsRepository get _repo => ref.read(savedEventsRepositoryProvider);

  @override
  Future<Set<String>> build() => _repo.ids();

  bool isSaved(String id) => state.value?.contains(id) ?? false;

  /// Kaydedildiyse true, kaldırıldıysa false döner.
  Future<bool> toggle(MapEvent event) async {
    final before = state.value ?? const <String>{};
    final saving = !before.contains(event.id);
    state = AsyncData(
      saving ? {...before, event.id} : ({...before}..remove(event.id)),
    );
    try {
      if (saving) {
        await _repo.save(event);
      } else {
        await _repo.remove(event.id);
      }
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
    ref.invalidate(savedEventsProvider);
    return saving;
  }
}

/// Kayıtlı etkinlikler listesi (Kayıtlı sekmesi).
final savedEventsProvider = FutureProvider.autoDispose<List<MapEvent>>(
  (ref) => ref.read(savedEventsRepositoryProvider).list(),
);
