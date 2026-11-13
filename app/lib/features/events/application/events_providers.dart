import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/events_repository.dart';
import '../domain/event.dart';

/// main.dart içinde Supabase ya da demo repository ile override edilir.
final eventsRepositoryProvider = Provider<EventsRepository>(
  (ref) =>
      throw UnimplementedError('eventsRepositoryProvider override edilmedi'),
);

/// Şu andan itibaren şehir genelindeki yayınlanmış etkinlikler.
/// Filtreler ve "near me" Stage 5'te bu sorgunun parametreleri olarak eklenir.
final upcomingEventsProvider = FutureProvider<List<MapEvent>>((ref) {
  return ref.read(eventsRepositoryProvider).upcoming(from: DateTime.now());
});

/// Haritada pin olarak gösterilen mekân grupları.
final venueGroupsProvider = Provider<AsyncValue<List<VenueGroup>>>((ref) {
  return ref.watch(upcomingEventsProvider).whenData(VenueGroup.fromEvents);
});
