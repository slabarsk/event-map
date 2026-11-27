import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../search/application/search_providers.dart';
import '../../map/application/map_filter_provider.dart';
import '../data/events_repository.dart';
import '../domain/event.dart';

/// main.dart içinde Supabase ya da demo repository ile override edilir.
final eventsRepositoryProvider = Provider<EventsRepository>(
  (ref) =>
      throw UnimplementedError('eventsRepositoryProvider override edilmedi'),
);

/// Saat kaynağı; testlerde sabit bir anla override edilir.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Şu andan itibaren şehir genelindeki yayınlanmış etkinlikler.
/// Harita ve ana sayfa aynı veri kaynağını kullanır.
final upcomingEventsProvider = FutureProvider<List<MapEvent>>((ref) {
  final now = ref.read(clockProvider)();
  return ref.read(eventsRepositoryProvider).upcoming(from: now);
});

/// Filtreler RPC'de de uygulanır; 500 sonuç sınırı öncesinde daraltılır.
final mapEventsProvider = FutureProvider<List<MapEvent>>((ref) {
  final filters = ref.watch(mapFiltersProvider);
  if (filters.activeCount == 0) return ref.watch(upcomingEventsProvider.future);
  final (from, to) = filters.window(ref.read(clockProvider)());
  return ref
      .read(eventsRepositoryProvider)
      .upcoming(
        from: from,
        to: to,
        categories: filters.categories,
        maxPrice: filters.freeOnly ? 0 : filters.maxPrice,
        location: filters.radiusKm == null ? null : filters.location,
        radiusM: filters.radiusKm == null ? null : filters.radiusKm! * 1000,
      );
});

/// Haritada pin olarak gösterilen mekân grupları. Bir arama sonucu haritaya
/// gönderildiyse yalnızca onun etkinlikleri gösterilir.
final venueGroupsProvider = Provider<AsyncValue<List<VenueGroup>>>((ref) {
  final search = ref.watch(mapSearchProvider);
  final filters = ref.watch(mapFiltersProvider);
  final now = ref.read(clockProvider)();
  final source = search != null
      ? AsyncData(search.events)
      : ref.watch(mapEventsProvider);
  return source.whenData(
    (events) => VenueGroup.fromEvents(filters.apply(events, now)),
  );
});
