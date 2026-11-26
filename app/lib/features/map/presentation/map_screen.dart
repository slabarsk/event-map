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
import '../../search/application/search_providers.dart';
import '../../search/domain/search_result.dart';
import 'widgets/venue_pin.dart';

/// Konak / Alsancak civarı; ilk açılışta şehir merkezini gösterir.
const izmirCenter = LatLng(38.4300, 27.1400);
const _initialZoom = 12.0;

/// Tam ekran etkinlik haritası: mekân başına bir pin, dokununca o mekândaki
/// etkinlikler. Bir arama sonucu gönderildiyse yalnızca onun etkinlikleri ve
/// (konumla arandıysa) kullanıcının konumu gösterilir.
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
    final search = ref.watch(mapSearchProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final here = search?.location;

    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: izmirCenter,
            initialZoom: _initialZoom,
            initialCameraFit: _fit(search),
            minZoom: 8,
            maxZoom: 18,
            backgroundColor: Color(0xFFF4EEEA),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            if (widget.showTiles)
              ColorFiltered(colorFilter: _softTiles, child: _tiles()),
            if (here != null)
              MarkerLayer(
                markers: [
                  Marker(
                    key: const ValueKey('my-location'),
                    point: here,
                    width: 22,
                    height: 22,
                    child: const _MyLocationDot(),
                  ),
                ],
              ),
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
                    Expanded(
                      child: search == null
                          ? _HeaderCard(groups: groups)
                          : _SearchHeader(result: search),
                    ),
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

  /// Arama sonucunun tüm pinlerini (ve kullanıcının konumunu) kadraja alır.
  static CameraFit? _fit(SearchResult? search) {
    if (search == null) return null;
    final points = [
      for (final e in search.events) LatLng(e.lat, e.lng),
      ?search.location,
    ];
    if (points.length < 2) return null;
    return CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.fromLTRB(48, 140, 48, 180),
      maxZoom: 15,
    );
  }

  void _zoomBy(double delta) {
    final camera = _map.camera;
    _map.move(camera.center, (camera.zoom + delta).clamp(8.0, 18.0));
  }

  /// Haritayı hafif renkli yapar: doygunluğu %55'e indirir ve %15 beyaza
  /// karıştırır. Böylece kategori renkli pinler altlıkta kaybolmaz.
  static const _softTiles = ColorFilter.matrix(<double>[
    // satır: R, G, B, A, ofset (0-255)
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
    0, 0, 0, 1, 0,
  ]);

  TileLayer _tiles() {
    if (Env.hasMapbox) {
      return TileLayer(
        // streets-v12 (su mavi, parklar yeşil); _softTiles ile soldurulur.
        urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token={accessToken}',
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

/// Haritada aktif arama: anlaşılan filtre ve temizleme butonu.
class _SearchHeader extends ConsumerWidget {
  const _SearchHeader({required this.result});
  final SearchResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return GlassCard(
      radius: 999,
      opacity: 0.85,
      padding: const EdgeInsets.fromLTRB(18, 10, 6, 10),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded, color: AppColors.coral),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.query,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall,
                ),
                Text(
                  '${result.events.length} etkinlik · ${result.labels.join(' · ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Aramayı temizle',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => ref.read(mapSearchProvider.notifier).clear(),
          ),
        ],
      ),
    );
  }
}

class _MyLocationDot extends StatelessWidget {
  const _MyLocationDot();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Konumun',
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.sky,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: AppColors.sky.withValues(alpha: 0.5),
              blurRadius: 10,
            ),
          ],
        ),
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
