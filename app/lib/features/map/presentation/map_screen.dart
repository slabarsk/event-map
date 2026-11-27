import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common.dart';
import '../../events/application/events_providers.dart';
import '../../events/domain/event.dart';
import '../../events/presentation/event_visuals.dart';
import '../../search/application/search_providers.dart';
import '../application/map_filter_provider.dart';
import '../domain/map_filters.dart';
import 'widgets/event_map_view.dart';
import 'widgets/map_filter_sheet.dart';

export 'widgets/event_map_view.dart' show izmirCenter;

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, this.showTiles = true});
  final bool showTiles;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _map = MapController();

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  CameraFit? _fit(List<VenueGroup> groups, LatLng? location) {
    final size = MediaQuery.sizeOf(context);
    final points = [for (final g in groups) LatLng(g.lat, g.lng), ?location];
    if (points.isEmpty) return null;
    // Tek koordinat da sabit zoom ile kadraja alınır.
    if (points.every((p) => p == points.first)) {
      return CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(points.first.latitude - 0.004, points.first.longitude - 0.004),
          LatLng(points.first.latitude + 0.004, points.first.longitude + 0.004),
        ),
        maxZoom: 15,
      );
    }
    return CameraFit.coordinates(
      coordinates: points,
      padding: EdgeInsets.fromLTRB(
        48,
        (size.height * 0.35).clamp(0.0, 210.0),
        48,
        (size.height * 0.25).clamp(0.0, 180.0),
      ),
      maxZoom: 15,
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(venueGroupsProvider);
    final search = ref.watch(mapSearchProvider);
    final filters = ref.watch(mapFiltersProvider);
    final values = groups.value ?? const <VenueGroup>[];
    final here = filters.location ?? search?.location;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    // Filtreler/aramanın değişmesi mevcut haritanın kamerasını da günceller.
    ref.listen(venueGroupsProvider, (_, next) {
      if (ref.read(mapFiltersProvider).activeCount == 0 &&
          ref.read(mapSearchProvider) == null) {
        return;
      }
      final fit = _fit(
        next.value ?? const [],
        ref.read(mapFiltersProvider).location ??
            ref.read(mapSearchProvider)?.location,
      );
      if (fit != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _map.fitCamera(fit);
        });
      }
    });

    return Stack(
      children: [
        EventMapView(
          controller: _map,
          groups: values,
          location: here,
          fit: search != null || filters.activeCount > 0
              ? _fit(values, here)
              : null,
          showTiles: widget.showTiles,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: MaxWidth(
                width: 560,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _HeaderCard(groups: groups)),
                        const SizedBox(width: 10),
                        GlassIconButton(
                          icon: Icons.center_focus_strong_rounded,
                          tooltip: 'Şehir merkezine dön',
                          onPressed: () => _map.move(izmirCenter, 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('open-map-filters'),
                          onPressed: () => MapFilterSheet.show(context),
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: Text(
                            filters.activeCount == 0
                                ? 'Filtreler'
                                : 'Filtreler · ${filters.activeCount}',
                          ),
                        ),
                        if (filters.activeCount > 0) ...[
                          ActionChip(
                            avatar: const Icon(Icons.close_rounded, size: 16),
                            label: const Text('Sıfırla'),
                            onPressed: () =>
                                ref.read(mapFiltersProvider.notifier).clear(),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (groups.hasValue && values.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GlassCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search_off_rounded, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      filters.activeCount > 0
                          ? 'Bu filtrelere uygun etkinlik bulunamadı.'
                          : 'Gösterilecek etkinlik bulunamadı.',
                    ),
                    if (filters.activeCount > 0)
                      TextButton(
                        onPressed: () =>
                            ref.read(mapFiltersProvider.notifier).clear(),
                        child: const Text('Filtreleri temizle'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          right: 16,
          bottom: bottomInset + 124,
          child: Column(
            children: [
              GlassIconButton(
                icon: Icons.add_rounded,
                tooltip: 'Yakınlaştır',
                onPressed: () => _zoomBy(1),
              ),
              const SizedBox(height: 10),
              GlassIconButton(
                icon: Icons.remove_rounded,
                tooltip: 'Uzaklaştır',
                onPressed: () => _zoomBy(-1),
              ),
            ],
          ),
        ),
        if (widget.showTiles)
          Positioned(
            right: 10,
            bottom: bottomInset + 92,
            child: const MapAttribution(),
          ),
      ],
    );
  }

  void _zoomBy(double delta) {
    final camera = _map.camera;
    _map.move(camera.center, (camera.zoom + delta).clamp(8.0, 18.0));
  }
}

class _HeaderCard extends ConsumerWidget {
  const _HeaderCard({required this.groups});
  final AsyncValue<List<VenueGroup>> groups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = ref.watch(mapSearchProvider);
    final filters = ref.watch(mapFiltersProvider);
    final text = Theme.of(context).textTheme;
    final subtitle = switch (groups) {
      AsyncData(:final value) when value.isEmpty => 'Etkinlik bulunamadı',
      AsyncData(:final value) =>
        '${value.fold(0, (n, g) => n + g.events.length)} etkinlik · ${value.length} mekân',
      AsyncError(:final error) => error.toString(),
      _ => 'Etkinlikler yükleniyor…',
    };
    final labels = [
      if (search != null) ...search.labels,
      if (filters.date != MapDateFilter.upcoming) filters.date.label,
      for (final category in filters.categories)
        eventCategoryOf(category).label,
      if (filters.freeOnly) 'Ücretsiz',
      if (!filters.freeOnly && filters.maxPrice != null)
        '${filters.maxPrice} ₺ ve altı',
      if (filters.radiusKm != null) '${filters.radiusKm} km',
    ];
    return GlassCard(
      radius: 24,
      opacity: 0.9,
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(
        children: [
          Icon(
            search == null ? Icons.map_rounded : Icons.auto_awesome_rounded,
            color: AppColors.coral,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  search?.query ?? 'İzmir etkinlikleri',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall,
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: groups.hasError
                        ? AppColors.error
                        : AppColors.inkSoft,
                  ),
                ),
                if (labels.isNotEmpty)
                  Text(
                    labels.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
              ],
            ),
          ),
          if (search != null)
            IconButton(
              tooltip: 'Aramayı temizle',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => ref.read(mapSearchProvider.notifier).clear(),
            ),
          if (groups.isLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (groups.hasError)
            IconButton(
              tooltip: 'Tekrar dene',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                ref.invalidate(upcomingEventsProvider);
                ref.invalidate(mapEventsProvider);
              },
            ),
        ],
      ),
    );
  }
}
