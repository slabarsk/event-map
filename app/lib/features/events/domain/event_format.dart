import 'package:intl/intl.dart';

import 'event.dart';

/// Tarih ve fiyat metinleri. Saatler her zaman İzmir saatiyle gösterilir,
/// cihazın saat diliminden bağımsız.
abstract final class EventFormat {
  /// Türkiye 2016'dan beri yaz saati uygulamadan sabit UTC+3'tedir; bu yüzden
  /// tam bir saat dilimi veritabanı gerekmez.
  static const istanbulOffset = Duration(hours: 3);

  /// UTC anı İstanbul duvar saatine çevirir. Dönen değerin yalnızca
  /// yıl/ay/gün/saat alanları anlamlıdır.
  static DateTime toIstanbul(DateTime instant) =>
      instant.toUtc().add(istanbulOffset);

  /// İstanbul'da [now] gününün başlangıcı, UTC olarak.
  static DateTime istanbulDayStart(DateTime now) {
    final local = toIstanbul(now);
    return DateTime.utc(
      local.year,
      local.month,
      local.day,
    ).subtract(istanbulOffset);
  }

  /// "Bugün 20:00", "Yarın 19:30", "Cumartesi 14:00" ya da "12 Aralık Cuma 20:00".
  static String when(DateTime startsAt, {required DateTime now}) {
    final day = istanbulDayStart(startsAt);
    final today = istanbulDayStart(now);
    final diff = day.difference(today).inHours ~/ 24;
    final local = toIstanbul(startsAt);
    final time = DateFormat.Hm('tr').format(local);
    final label = switch (diff) {
      0 => 'Bugün',
      1 => 'Yarın',
      > 1 && < 7 => DateFormat.EEEE('tr').format(local),
      _ => DateFormat('d MMMM EEEE', 'tr').format(local),
    };
    return '$label $time';
  }

  /// "Ücretsiz", "250 ₺", "250–450 ₺" ya da "Fiyat bilinmiyor".
  static String price(MapEvent e) {
    final min = e.priceMin;
    final max = e.priceMax;
    if (min == null && max == null) return 'Fiyat bilinmiyor';
    if (e.isFree) return 'Ücretsiz';
    final lo = min ?? max!;
    final hi = max ?? min!;
    if (lo == hi) return '${_amount(lo)} ₺';
    return '${_amount(lo)}–${_amount(hi)} ₺';
  }

  /// Fiyatın yanında gösterilen rozet. [PriceStatus.estimated] için her zaman
  /// "Tahmini" döner (yol haritası kuralı).
  static String? priceBadge(MapEvent e) => switch (e.priceStatus) {
    PriceStatus.estimated => 'Tahmini',
    PriceStatus.lookedUp => 'Bilet sayfasından',
    PriceStatus.listed => null,
  };

  static String _amount(double v) =>
      NumberFormat.decimalPattern('tr').format(v.round());
}
