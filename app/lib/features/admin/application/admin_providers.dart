import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/domain/app_user.dart';
import '../data/admin_repository.dart';
import '../domain/organizer_application.dart';
import '../domain/review_event.dart';

/// main.dart içinde Supabase ya da demo repository ile override edilir.
final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) =>
      throw UnimplementedError('adminRepositoryProvider override edilmedi'),
);

final organizerApplicationsProvider = FutureProvider.autoDispose
    .family<List<OrganizerApplication>, OrganizerStatus>(
      (ref, status) => ref.read(adminRepositoryProvider).applications(status),
    );

final organizerApplicationProvider = FutureProvider.autoDispose
    .family<OrganizerApplication?, String>(
      (ref, id) => ref.read(adminRepositoryProvider).application(id),
    );

final organizerEmailProvider = FutureProvider.autoDispose
    .family<String?, String>(
      (ref, id) => ref.read(adminRepositoryProvider).organizerEmail(id),
    );

/// Onay/red sonrası listeleri ve detayı tazeler.
Future<void> decideApplication(
  WidgetRef ref,
  String id,
  OrganizerStatus status,
) async {
  await ref.read(adminRepositoryProvider).setStatus(id, status);
  ref.invalidate(organizerApplicationsProvider);
  ref.invalidate(organizerApplicationProvider(id));
}

/// Riverpod 3 hataları varsayılan olarak sessizce yeniden dener ve bu sürede
/// ekran yükleniyor görünür. Sunucu hataları kalıcı olduğundan hemen
/// gösterilir; kullanıcı "Tekrar dene" ile yeniler.
Duration? _noRetry(int _, Object _) => null;

final pendingEventsProvider = FutureProvider.autoDispose<List<ReviewEvent>>(
  (ref) => ref.read(adminRepositoryProvider).pendingEvents(),
  retry: _noRetry,
);

/// Etkinliği yayınlar ya da reddeder, sonra listeyi tazeler.
Future<void> decideEvent(
  WidgetRef ref,
  String id, {
  required bool approve,
  String? note,
}) async {
  final repo = ref.read(adminRepositoryProvider);
  if (approve) {
    await repo.approveEvent(id);
  } else {
    await repo.rejectEvent(id, note: note);
  }
  ref.invalidate(pendingEventsProvider);
}
