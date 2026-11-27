import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../events/application/events_providers.dart';
import '../../events/domain/event.dart';
import '../../map/presentation/widgets/event_map_view.dart';

/// Ana sayfadaki önizleme, tam ekran haritayla aynı etkinlik verisini kullanır.
class EventMapPreview extends ConsumerWidget {
  const EventMapPreview({
    super.key,
    required this.onOpen,
    this.showTiles = true,
  });
  final VoidCallback onOpen;
  final bool showTiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(upcomingEventsProvider);
    final groups = VenueGroup.fromEvents(events.value ?? const []);
    final points = [for (final group in groups) LatLng(group.lat, group.lng)];
    final canFit = points.length > 1 && points.any((p) => p != points.first);
    final fit = points.isEmpty
        ? null
        : canFit
        ? CameraFit.coordinates(
            coordinates: points,
            padding: const EdgeInsets.all(48),
            maxZoom: 13,
          )
        : CameraFit.bounds(
            bounds: LatLngBounds(
              LatLng(
                points.first.latitude - 0.004,
                points.first.longitude - 0.004,
              ),
              LatLng(
                points.first.latitude + 0.004,
                points.first.longitude + 0.004,
              ),
            ),
            maxZoom: 13,
          );

    return Semantics(
      button: true,
      label: 'Haritayı aç',
      child: GestureDetector(
        key: const ValueKey('home-map-preview'),
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: Container(
          height: 280,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: EventMapView(
                      // Veri yüklenince kamera gerçek mekânlara oturur.
                      key: ValueKey(
                        points
                            .map((p) => '${p.latitude},${p.longitude}')
                            .join(';'),
                      ),
                      groups: groups,
                      fit: fit,
                      showTiles: showTiles,
                      interactive: false,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      events.hasError
                          ? 'Etkinlikler yüklenemedi'
                          : events.isLoading
                          ? 'Etkinlikler yükleniyor…'
                          : groups.isEmpty
                          ? 'Yaklaşan etkinlik bulunamadı'
                          : '${events.value!.length} etkinlik · ${groups.length} mekân',
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: showTiles ? 28 : 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Haritayı keşfet',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
              if (showTiles)
                const Positioned(right: 6, bottom: 4, child: MapAttribution()),
            ],
          ),
        ),
      ),
    );
  }
}
