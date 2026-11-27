import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/config/env.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../events/domain/event.dart';
import '../../../events/presentation/venue_events_sheet.dart';
import '../../domain/venue_cluster.dart';
import 'venue_pin.dart';

const izmirCenter = LatLng(38.4300, 27.1400);

/// Ana sayfa ve tam ekran harita için aynı gerçek harita/pin katmanı.
class EventMapView extends StatelessWidget {
  const EventMapView({
    super.key,
    required this.groups,
    this.controller,
    this.location,
    this.fit,
    this.showTiles = true,
    this.interactive = true,
    this.initialZoom = 12,
  });

  final List<VenueGroup> groups;
  final MapController? controller;
  final LatLng? location;
  final CameraFit? fit;
  final bool showTiles;
  final bool interactive;
  final double initialZoom;

  @override
  Widget build(BuildContext context) => FlutterMap(
    mapController: controller,
    options: MapOptions(
      initialCenter: izmirCenter,
      initialZoom: initialZoom,
      initialCameraFit: fit,
      minZoom: 8,
      maxZoom: 18,
      backgroundColor: const Color(0xFFF4EEEA),
      interactionOptions: InteractionOptions(
        flags: interactive
            ? InteractiveFlag.all & ~InteractiveFlag.rotate
            : InteractiveFlag.none,
      ),
    ),
    children: [
      if (showTiles) ColorFiltered(colorFilter: _softTiles, child: mapTiles()),
      if (location case final here?)
        MarkerLayer(
          markers: [
            Marker(
              key: const ValueKey('my-location'),
              point: here,
              width: 22,
              height: 22,
              child: Semantics(
                label: 'Konumun',
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.sky,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
            ),
          ],
        ),
      _ClusterLayer(groups: groups),
    ],
  );

  static const _softTiles = ColorFilter.matrix(<double>[
    0.85 * (0.55 + 0.45 * 0.2126),
    0.85 * (0.45 * 0.7152),
    0.85 * (0.45 * 0.0722),
    0,
    38,
    0.85 * (0.45 * 0.2126),
    0.85 * (0.55 + 0.45 * 0.7152),
    0.85 * (0.45 * 0.0722),
    0,
    38,
    0.85 * (0.45 * 0.2126),
    0.85 * (0.45 * 0.7152),
    0.85 * (0.55 + 0.45 * 0.0722),
    0,
    38,
    0,
    0,
    0,
    1,
    0,
  ]);

  static TileLayer mapTiles() => TileLayer(
    urlTemplate: Env.hasMapbox
        ? 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token={accessToken}'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    additionalOptions: Env.hasMapbox
        ? const {'accessToken': Env.mapboxPublicToken}
        : const {},
    userAgentPackageName: 'com.eventmap.event_map',
    maxNativeZoom: Env.hasMapbox ? 20 : 19,
  );
}

class _ClusterLayer extends StatelessWidget {
  const _ClusterLayer({required this.groups});
  final List<VenueGroup> groups;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final clusters = VenueCluster.build(
      groups,
      (g) => camera.projectAtZoom(LatLng(g.lat, g.lng)),
    );
    return MarkerLayer(
      markers: [
        for (final cluster in clusters)
          if (cluster.groups.length == 1)
            Marker(
              key: ValueKey('pin-${cluster.groups.single.venueId}'),
              point: LatLng(cluster.lat, cluster.lng),
              width: VenuePin.width,
              height: VenuePin.height,
              alignment: Alignment.topCenter,
              child: VenuePin(
                group: cluster.groups.single,
                onTap: () =>
                    VenueEventsSheet.show(context, cluster.groups.single),
              ),
            )
          else
            Marker(
              key: ValueKey('cluster-${cluster.groups.first.venueId}'),
              point: LatLng(cluster.lat, cluster.lng),
              width: 52,
              height: 52,
              child: Tooltip(
                message: '${cluster.groups.length} mekânı göster',
                child: Semantics(
                  button: true,
                  label: '${cluster.groups.length} mekânı göster',
                  child: Material(
                    color: AppColors.coral,
                    shape: const CircleBorder(
                      side: BorderSide(color: Colors.white, width: 3),
                    ),
                    elevation: 4,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _openCluster(context, cluster, camera),
                      child: Center(
                        child: Text(
                          '${cluster.groups.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _openCluster(
    BuildContext context,
    VenueCluster cluster,
    MapCamera camera,
  ) async {
    if (camera.zoom < 17) {
      MapController.of(
        context,
      ).move(LatLng(cluster.lat, cluster.lng), (camera.zoom + 2).clamp(8, 18));
      return;
    }
    // Aynı koordinattaki farklı mekânlar en yüksek zoom'da da erişilebilir.
    final selected = await showModalBottomSheet<VenueGroup>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.65,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Bu bölgedeki mekânlar'),
              ),
              for (final group in cluster.groups)
                ListTile(
                  title: Text(group.venueName),
                  subtitle: Text('${group.events.length} etkinlik'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(sheetContext, group),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && context.mounted) {
      await VenueEventsSheet.show(context, selected);
    }
  }
}

class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      Env.hasMapbox ? '© Mapbox © OpenStreetMap' : '© OpenStreetMap',
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: AppColors.inkSoft),
    ),
  );
}
