import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'features/admin/application/admin_providers.dart';
import 'features/admin/data/admin_repository.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/local_auth_repository.dart';
import 'features/auth/data/supabase_auth_repository.dart';
import 'features/events/application/events_providers.dart';
import 'features/events/data/demo_events_repository.dart';
import 'features/events/data/events_repository.dart';
import 'features/events/data/supabase_events_repository.dart';
import 'features/organizer/application/organizer_providers.dart';
import 'features/organizer/data/organizer_repository.dart';
import 'features/saved/application/saved_providers.dart';
import 'features/saved/data/saved_events_repository.dart';
import 'features/search/application/search_providers.dart';
import 'features/search/data/search_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr');
  final prefs = await SharedPreferences.getInstance();

  final AuthRepository repository;
  final EventsRepository events;
  final AdminRepository admin;
  if (Env.hasSupabase) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
    repository = SupabaseAuthRepository(Supabase.instance.client, prefs);
    events = SupabaseEventsRepository(Supabase.instance.client);
    admin = SupabaseAdminRepository(Supabase.instance.client);
  } else {
    repository = LocalAuthRepository(prefs);
    events = DemoEventsRepository();
    admin = DemoAdminRepository();
  }

  // Supabase yoksa arama, kayıtlılar ve organizatör paneli varsayılan bellek
  // içi demo repository'leriyle çalışır (bkz. ilgili provider'lar).
  final client = Env.hasSupabase ? Supabase.instance.client : null;

  runApp(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        eventsRepositoryProvider.overrideWithValue(events),
        adminRepositoryProvider.overrideWithValue(admin),
        if (client != null) ...[
          searchRepositoryProvider.overrideWithValue(
            SupabaseSearchRepository(client),
          ),
          savedEventsRepositoryProvider.overrideWithValue(
            SupabaseSavedEventsRepository(client),
          ),
          organizerRepositoryProvider.overrideWithValue(
            SupabaseOrganizerRepository(client),
          ),
        ],
      ],
      child: const EventMapApp(),
    ),
  );
}
