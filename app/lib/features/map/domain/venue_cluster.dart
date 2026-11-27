import 'dart:ui';

import '../../events/domain/event.dart';

/// Ekranda birbirine yakın mekânlar. Komşu hücreler de kontrol edilir;
/// hücre sınırına denk gelen pinler üst üste bırakılmaz.
class VenueCluster {
  VenueCluster(VenueGroup first, this.anchor) : groups = [first];

  final Offset anchor;
  final List<VenueGroup> groups;
  double get lat => groups.fold(0.0, (sum, g) => sum + g.lat) / groups.length;
  double get lng => groups.fold(0.0, (sum, g) => sum + g.lng) / groups.length;

  static List<VenueCluster> build(
    List<VenueGroup> groups,
    Offset Function(VenueGroup) project, {
    double radius = 56,
  }) {
    final cells = <(int, int), List<VenueCluster>>{};
    final clusters = <VenueCluster>[];
    final sorted = [...groups]..sort((a, b) => a.venueId.compareTo(b.venueId));
    for (final group in sorted) {
      final point = project(group);
      final x = (point.dx / radius).floor();
      final y = (point.dy / radius).floor();
      VenueCluster? closest;
      var nearest = radius * radius;
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          for (final cluster in cells[(x + dx, y + dy)] ?? <VenueCluster>[]) {
            final distance = (point - cluster.anchor).distanceSquared;
            if (distance <= nearest) {
              nearest = distance;
              closest = cluster;
            }
          }
        }
      }
      if (closest != null) {
        closest.groups.add(group);
      } else {
        final cluster = VenueCluster(group, point);
        clusters.add(cluster);
        cells.putIfAbsent((x, y), () => []).add(cluster);
      }
    }
    return clusters;
  }
}
