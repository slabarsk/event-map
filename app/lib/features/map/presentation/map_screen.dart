import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/env.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common.dart';
import '../../events/application/events_providers.dart';
import '../../events/domain/event.dart';
import '../../events/presentation/venue_events_sheet.dart';
import 'widgets/venue_pin.dart';

/// Konak / Alsancak civarı; ilk açılışta şehir merkezini gösterir.
const izmirCenter = LatLng(38.4300, 27.1400);
const _initialZoom = 12.0;

/// Tam ekran etkinlik haritası: mekân başına bir pin, dokununca o mekândaki
/// etkinlikler. Filtreler ve "near me" Stage 5'te üst karta eklenecek.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, this.showTiles = true});

  /// Testlerde ağ isteği atmamak için kapatılır.
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

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(venueGroupsProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: const MapOptions(
            initialCenter: izmirCenter,
            initialZoom: _initialZoom,
            minZoom: 8,
            maxZoom: 18,
            backgroundColor: Color(0xFFF4EEEA),
            interactionOptions: InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            if (widget.showTiles) _tiles(),
            MarkerLayer(
              markers: [
                for (final g in groups.value ?? const <VenueGroup>[])
                  Marker(
                    key: ValueKey('pin-${g.venueId}'),
                    point: LatLng(g.lat, g.lng),
                    width: VenuePin.width,
                    height: VenuePin.height,
                    alignment: Alignment.topCenter,
                    child: VenuePin(
                      group: g,
                      onTap: () => VenueEventsSheet.show(context, g),
                    ),
                  ),
              ],
            ),
          ],
        ),
        // Yalnızca üst şeridi kaplar; haritanın geri kalanı dokunuşa açık kalır.
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
                child: Row(
                  children: [
                    Expanded(child: _HeaderCard(groups: groups)),
                    const SizedBox(width: 10),
                    GlassIconButton(
                      icon: Icons.center_focus_strong_rounded,
                      tooltip: 'Şehir merkezine dön',
                      onPressed: () => _map.move(izmirCenter, _initialZoom),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Pinch ve çift dokunma da çalışır; butonlar fare/trackpad (web, simülatör) için.
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
            // Alttaki yüzen menünün (66 + 16 boşluk) üstünde kalsın.
            bottom: bottomInset + 92,
            child: const _Attribution(),
          ),
      ],
    );
  }

  void _zoomBy(double delta) {
    final camera = _map.camera;
    _map.move(camera.center, (camera.zoom + delta).clamp(8.0, 18.0));
  }

  TileLayer _tiles() {
    if (Env.hasMapbox) {
      return TileLayer(
        urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/light-v11/tiles/256/{z}/{x}/{y}@2x?access_token={accessToken}',
        additionalOptions: const {'accessToken': Env.mapboxPublicToken},
        userAgentPackageName: 'com.eventmap.event_map',
        maxNativeZoom: 20,
      );
    }
    // Yalnızca geliştirme için: OSM tile kullanım politikası yoğun trafiğe
    // izin vermez. Yayında MAPBOX_PUBLIC_TOKEN verilmelidir.
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.eventmap.event_map',
      maxNativeZoom: 19,
    );
  }
}

class _HeaderCard extends ConsumerWidget {
  const _HeaderCard({required this.groups});
  final AsyncValue<List<VenueGroup>> groups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final subtitle = switch (groups) {
      AsyncData(:final value) when value.isEmpty =>
        'Yaklaşan etkinlik bulunamadı',
      AsyncData(:final value) =>
        '${value.fold(0, (n, g) => n + g.events.length)} etkinlik · '
            '${value.length} mekân',
      AsyncError(:final error) => error.toString(),
      _ => 'Etkinlikler yükleniyor…',
    };
    return GlassCard(
      radius: 999,
      opacity: 0.85,
      padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
      child: Row(
        children: [
          const Icon(Icons.map_rounded, color: AppColors.coral),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('İzmir etkinlikleri', style: text.titleSmall),
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
              ],
            ),
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
              onPressed: () => ref.invalidate(upcomingEventsProvider),
            ),
        ],
      ),
    );
  }
}

class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        Env.hasMapbox ? '© Mapbox © OpenStreetMap' : '© OpenStreetMap',
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: AppColors.inkSoft),
      ),
    );
  }
}
