import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../search/application/search_providers.dart';
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
/// Filtreler ve "near me" Stage 5'te bu sorgunun parametreleri olarak eklenir.
final upcomingEventsProvider = FutureProvider<List<MapEvent>>((ref) {
  final now = ref.read(clockProvider)();
  return ref.read(eventsRepositoryProvider).upcoming(from: now);
});

/// Haritada pin olarak gösterilen mekân grupları. Bir arama sonucu haritaya
/// gönderildiyse yalnızca onun etkinlikleri gösterilir.
final venueGroupsProvider = Provider<AsyncValue<List<VenueGroup>>>((ref) {
  final search = ref.watch(mapSearchProvider);
  if (search != null) return AsyncData(VenueGroup.fromEvents(search.events));
  return ref.watch(upcomingEventsProvider).whenData(VenueGroup.fromEvents);
});
