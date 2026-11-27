import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/location/location_service.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/widgets/auth_widgets.dart';
import '../../events/application/events_providers.dart';
import '../../events/presentation/venue_events_sheet.dart';
import '../../map/application/map_filter_provider.dart';
import '../application/search_providers.dart';
import '../domain/search_result.dart';

/// Doğal dil araması: "Bu akşam yakınımdaki ücretsiz konserler".
///
/// Soru "yakınımda" içeriyorsa sunucu `needs_location` döner; o zaman konum
/// izni istenir ve soru konumla tekrar gönderilir. İzin yoksa şehir geneli
/// sonuçlar gösterilir.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery});
  final String? initialQuery;

  static const suggestions = [
    'Bu akşam yakınımdaki ücretsiz konserler',
    'Hafta sonu çocuklarla gidilecek etkinlikler',
    'Yarın akşam tiyatro',
    'Bu hafta 300 TL altı stand-up',
  ];

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  SearchResult? _result;
  String? _error;
  bool _loading = false;
  bool _locationDenied = false;

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuery?.trim() ?? '';
    if (q.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _run(q));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run(String raw) async {
    final query = raw.trim();
    if (query.isEmpty || _loading) return;
    _controller.text = query;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _locationDenied = false;
    });
    final repo = ref.read(searchRepositoryProvider);
    final radiusKm =
        ref.read(authControllerProvider).value?.preferences.radiusKm ?? 5;
    final radiusM = radiusKm * 1000;
    try {
      var result = await repo.search(query, defaultRadiusM: radiusM);
      var denied = false;
      if (result.needsLocation) {
        final here = await ref.read(locationServiceProvider).current();
        if (here != null) {
          result = await repo.search(
            query,
            location: here,
            defaultRadiusM: radiusM,
          );
        } else {
          denied = true;
        }
      }
      if (!mounted) return;
      setState(() {
        _result = result;
        _locationDenied = denied;
      });
    } on SearchFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showOnMap(SearchResult result) {
    // Yeni aramada önceki elle seçilen filtreler sonuçları gizlemesin.
    ref.read(mapFiltersProvider.notifier).clear();
    ref.read(mapSearchProvider.notifier).show(result);
    context.go(Routes.map);
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authControllerProvider).value?.role ?? UserRole.user;
    final text = Theme.of(context).textTheme;
    final result = _result;
    final now = ref.read(clockProvider)();

    return Scaffold(
      body: AuroraBackground(
        colors: AppColors.blobsFor(role),
        intensity: 0.6,
        child: SafeArea(
          child: MaxWidth(
            width: 560,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      GlassIconButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Geri',
                        onPressed: () => context.canPop()
                            ? context.pop()
                            : context.go(Routes.home),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('search-field'),
                          controller: _controller,
                          autofocus: widget.initialQuery == null,
                          textInputAction: TextInputAction.search,
                          maxLength: 300,
                          onSubmitted: _run,
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: 'Bu akşam yakınımda ne var?',
                            prefixIcon: const Icon(Icons.auto_awesome_rounded),
                            suffixIcon: IconButton(
                              tooltip: 'Ara',
                              icon: const Icon(Icons.search_rounded),
                              onPressed: () => _run(_controller.text),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: [
                      if (_error != null)
                        _Notice(
                          icon: Icons.error_outline_rounded,
                          color: AppColors.error,
                          text: _error!,
                        ),
                      if (result == null && !_loading) ...[
                        const SectionLabel('Örnek sorular'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final s in SearchScreen.suggestions)
                              ActionChip(
                                label: Text(s),
                                avatar: const Icon(
                                  Icons.north_west_rounded,
                                  size: 16,
                                ),
                                onPressed: () => _run(s),
                              ),
                          ],
                        ),
                      ],
                      if (result != null) ...[
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final l in result.labels)
                              Chip(
                                label: Text(l),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                        if (_locationDenied) ...[
                          const SizedBox(height: 10),
                          const _Notice(
                            icon: Icons.location_off_outlined,
                            color: AppColors.amber,
                            text: 'Konum izni olmadığı için şehir genelindeki sonuçlar gösteriliyor.',
                          ),
                        ],
                        const SizedBox(height: 14),
                        if (result.events.isEmpty)
                          const _Notice(
                            icon: Icons.event_busy_rounded,
                            color: AppColors.inkSoft,
                            text: 'Bu aramaya uyan etkinlik bulunamadı. Zamanı ya da mesafeyi genişletmeyi dene.',
                          )
                        else ...[
                          PrimaryButton(
                            label: 'Haritada göster (${result.events.length})',
                            icon: Icons.map_rounded,
                            onPressed: () => _showOnMap(result),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '${result.events.length} etkinlik',
                            style: text.titleSmall,
                          ),
                          const SizedBox(height: 10),
                          for (final e in result.events) ...[
                            EventCard(event: e, now: now, showVenue: true),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      radius: 20,
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
