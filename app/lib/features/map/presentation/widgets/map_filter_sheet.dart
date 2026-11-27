import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/catalog.dart';
import '../../../../core/location/location_service.dart';
import '../../../../core/widgets/common.dart';
import '../../../events/presentation/event_visuals.dart';
import '../../application/map_filter_provider.dart';
import '../../domain/map_filters.dart';

class MapFilterSheet extends ConsumerStatefulWidget {
  const MapFilterSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => const MapFilterSheet(),
  );

  @override
  ConsumerState<MapFilterSheet> createState() => _MapFilterSheetState();
}

class _MapFilterSheetState extends ConsumerState<MapFilterSheet> {
  late MapFilters _draft = ref.read(mapFiltersProvider);
  bool _locating = false;
  String? _locationError;

  Future<void> _selectRadius(int? km) async {
    if (_locating) return;
    if (km == null) {
      setState(() {
        _draft = _draft.copyWith(clearRadius: true);
        _locationError = null;
      });
      return;
    }
    if (_draft.location != null) {
      setState(() => _draft = _draft.copyWith(radiusKm: km));
      return;
    }
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final here = await ref.read(locationServiceProvider).current();
      if (!mounted) return;
      setState(() {
        if (here == null) {
          _locationError = 'Konum alınamadı. Konum iznini ve cihazının konum ayarını kontrol et.';
        } else {
          _draft = _draft.copyWith(radiusKm: km, location: here);
        }
      });
    } on Exception {
      if (mounted) {
        setState(
          () => _locationError = 'Konum alınamadı. Tekrar deneyebilirsin.',
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.82,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Harita filtreleri',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: _locating
                      ? null
                      : () => setState(() {
                          _draft = const MapFilters();
                          _locationError = null;
                        }),
                  child: const Text('Sıfırla'),
                ),
                IconButton(
                  tooltip: 'Kapat',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Tarih'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final date in MapDateFilter.values)
                        ChoiceChip(
                          label: Text(date.label),
                          selected: _draft.date == date,
                          onSelected: (_) => setState(
                            () => _draft = _draft.copyWith(date: date),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const SectionLabel('Kategori'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Tüm kategoriler'),
                        selected: _draft.categories.isEmpty,
                        onSelected: (_) => setState(
                          () => _draft = _draft.copyWith(categories: {}),
                        ),
                      ),
                      for (final category in [
                        ...Catalog.categories,
                        eventCategoryOf('party'),
                        eventCategoryOf('other'),
                      ])
                        FilterChip(
                          label: Text(category.label),
                          avatar: Icon(
                            category.icon,
                            size: 18,
                            color: category.color,
                          ),
                          selected: _draft.categories.contains(category.id),
                          onSelected: (selected) => setState(() {
                            final categories = {..._draft.categories};
                            selected
                                ? categories.add(category.id)
                                : categories.remove(category.id);
                            _draft = _draft.copyWith(categories: categories);
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const SectionLabel('Fiyat'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Tüm fiyatlar'),
                        selected: !_draft.freeOnly && _draft.maxPrice == null,
                        onSelected: (_) => setState(
                          () => _draft = _draft.copyWith(
                            freeOnly: false,
                            clearPrice: true,
                          ),
                        ),
                      ),
                      ChoiceChip(
                        label: const Text('Ücretsiz'),
                        selected: _draft.freeOnly,
                        onSelected: (_) => setState(
                          () => _draft = _draft.copyWith(
                            freeOnly: true,
                            clearPrice: true,
                          ),
                        ),
                      ),
                      for (final cap in Catalog.priceCaps.whereType<int>())
                        ChoiceChip(
                          label: Text('$cap ₺ ve altı'),
                          selected: !_draft.freeOnly && _draft.maxPrice == cap,
                          onSelected: (_) => setState(
                            () => _draft = _draft.copyWith(
                              freeOnly: false,
                              maxPrice: cap,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Fiyat sınırında başlangıç fiyatı esas alınır; fiyatı bilinmeyenler gösterilmez.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  const SectionLabel('Mesafe'),
                  Text('Konumuna göre filtrelemek için mesafe seç.'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Tüm İzmir'),
                        selected: _draft.radiusKm == null,
                        onSelected: _locating
                            ? null
                            : (_) => _selectRadius(null),
                      ),
                      for (final km in Catalog.radiusOptionsKm)
                        ChoiceChip(
                          label: Text('$km km'),
                          selected: _draft.radiusKm == km,
                          onSelected: _locating
                              ? null
                              : (_) => _selectRadius(km),
                        ),
                    ],
                  ),
                  if (_locating)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        children: [
                          SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Konum alınıyor…'),
                        ],
                      ),
                    ),
                  if (_locationError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _locationError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: FilledButton(
              key: const ValueKey('apply-map-filters'),
              onPressed: _locating
                  ? null
                  : () {
                      ref.read(mapFiltersProvider.notifier).apply(_draft);
                      Navigator.pop(context);
                    },
              child: const Text('Sonuçları göster'),
            ),
          ),
        ],
      ),
    ),
  );
}
