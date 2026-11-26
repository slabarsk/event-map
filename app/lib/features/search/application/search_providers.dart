import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../events/application/events_providers.dart';
import '../data/search_repository.dart';
import '../domain/search_result.dart';

/// main.dart içinde Supabase repository ile override edilir; varsayılan demo
/// etkinlikleri üzerinde çalışan kural tabanlı arama (testler bunu kullanır).
final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => DemoSearchRepository(
    ref.read(eventsRepositoryProvider),
    clock: ref.read(clockProvider),
  ),
);

/// Haritada gösterilen arama sonucu. null ise harita tüm yaklaşan
/// etkinlikleri gösterir.
final mapSearchProvider = NotifierProvider<MapSearch, SearchResult?>(
  MapSearch.new,
);

class MapSearch extends Notifier<SearchResult?> {
  @override
  SearchResult? build() => null;

  void show(SearchResult result) => state = result;
  void clear() => state = null;
}
