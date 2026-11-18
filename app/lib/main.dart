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

  runApp(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        eventsRepositoryProvider.overrideWithValue(events),
        adminRepositoryProvider.overrideWithValue(admin),
      ],
      child: const EventMapApp(),
    ),
  );
}
