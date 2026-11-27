import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/map_filters.dart';

final mapFiltersProvider = NotifierProvider<MapFilterController, MapFilters>(
  MapFilterController.new,
);

class MapFilterController extends Notifier<MapFilters> {
  @override
  MapFilters build() => const MapFilters();

  void apply(MapFilters filters) => state = filters;
  void clear() => state = const MapFilters();

  /// Ana sayfadaki kategori seçimi yeni bir harita keşfi başlatır.
  void selectCategory(String category) =>
      state = MapFilters(categories: Set.unmodifiable({category}));
}
