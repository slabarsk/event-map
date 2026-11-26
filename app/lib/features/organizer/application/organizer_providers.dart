import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/organizer_repository.dart';
import '../domain/organizer_event.dart';

/// main.dart içinde Supabase repository ile override edilir; varsayılan bellek
/// içi demo (testler bunu kullanır).
final organizerRepositoryProvider = Provider<OrganizerRepository>(
  (ref) => DemoOrganizerRepository(),
);

final myEventsProvider = FutureProvider.autoDispose<List<OrganizerEvent>>(
  (ref) => ref.read(organizerRepositoryProvider).myEvents(),
);

final organizerStatsProvider = FutureProvider.autoDispose<OrganizerStats>(
  (ref) => ref.read(organizerRepositoryProvider).stats(),
);

/// Gönderme ya da geri çekme sonrası paneli tazeler.
void refreshOrganizer(WidgetRef ref) {
  ref.invalidate(myEventsProvider);
  ref.invalidate(organizerStatsProvider);
}
