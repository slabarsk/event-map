import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/domain/app_user.dart';
import '../data/admin_repository.dart';
import '../domain/organizer_application.dart';

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
