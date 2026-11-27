import 'package:latlong2/latlong.dart';

import '../domain/event.dart';
import '../domain/event_format.dart';
import 'events_repository.dart';

/// Supabase olmadan çalışırken kullanılan veri. `supabase/seed.sql` ile aynı
/// mekân ve etkinlikleri üretir; tarihler seed'deki gibi bugüne göre hesaplanır
/// (İstanbul gün başı + gün farkı + saat, süre 2 saat).
class DemoEventsRepository implements EventsRepository {
  DemoEventsRepository({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  @override
  Future<List<MapEvent>> upcoming({
    required DateTime from,
    DateTime? to,
    Set<String> categories = const {},
    int? maxPrice,
    LatLng? location,
    int? radiusM,
  }) async {
    final dayStart = EventFormat.istanbulDayStart(_clock());
    final events = [
      for (final (i, s) in _seed.indexed) s.toEvent('seed-${i + 1}', dayStart),
    ];
    // events_near ile aynı süzgeç: bitişi (yoksa başlangıç + 3 saat) from'dan
    // sonra olanlar; to verildiyse ondan önce başlayanlar.
    return events.where((e) {
      if (categories.isNotEmpty && !categories.contains(e.category)) {
        return false;
      }
      final price = e.priceMin ?? e.priceMax;
      if (maxPrice != null && (price == null || price > maxPrice)) return false;
      if (location != null &&
          const Distance().as(
                LengthUnit.Meter,
                location,
                LatLng(e.lat, e.lng),
              ) >
              (radiusM ?? 5000)) {
        return false;
      }
      final end = e.endsAt ?? e.startsAt.add(const Duration(hours: 3));
      return !end.isBefore(from) && (to == null || !e.startsAt.isAfter(to));
    }).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }
}

typedef _Venue = (
  String id,
  String name,
  String address,
  double lat,
  double lng,
);

const _aassm = (
  'venue-aassm',
  'Ahmet Adnan Saygun Sanat Merkezi',
  'Mehmet Ali Akman Mah., Mithatpaşa Cad. No:1087, Konak/İzmir',
  38.39694,
  27.07833,
);
const _kulturpark = (
  'venue-kulturpark',
  'Kültürpark Açık Hava Tiyatrosu',
  'Kültürpark, Konak/İzmir',
  38.4343,
  27.1463,
);
const _konakPier = (
  'venue-konak-pier',
  'Konak Pier',
  'Kemeraltı, Konak/İzmir',
  38.4205,
  27.1288,
);
const _opera = (
  'venue-opera',
  'İzmir Devlet Opera ve Balesi',
  'Cumhuriyet Blv., Alsancak/İzmir',
  38.4358,
  27.1426,
);
const _karsiyaka = (
  'venue-karsiyaka',
  'Karşıyaka Sahil Sahnesi',
  'Karşıyaka Sahili, Karşıyaka/İzmir',
  38.4588,
  27.1172,
);
const _bornova = (
  'venue-bornova',
  'Bornova Kültür Merkezi',
  'Bornova/İzmir',
  38.4625,
  27.2197,
);
const _urla = (
  'venue-urla',
  'Urla Bağ Evi Galerisi',
  'Urla/İzmir',
  38.3225,
  26.7647,
);
const _alsancak = (
  'venue-alsancak',
  'Alsancak Kıbrıs Şehitleri Caddesi',
  'Alsancak/İzmir',
  38.4361,
  27.1431,
);

class _SeedEvent {
  const _SeedEvent(
    this.title,
    this.description,
    this.dayOffset,
    this.hour,
    this.venue,
    this.category,
    this.priceMin,
    this.priceMax,
    this.priceStatus, {
    this.priceSourceUrl,
    this.ticketUrl,
  });

  final String title;
  final String description;
  final int dayOffset;
  final int hour;
  final _Venue venue;
  final String category;
  final double priceMin;
  final double priceMax;
  final PriceStatus priceStatus;
  final String? priceSourceUrl;
  final String? ticketUrl;

  MapEvent toEvent(String id, DateTime dayStart) {
    final starts = dayStart.add(Duration(days: dayOffset, hours: hour));
    final (venueId, venueName, address, lat, lng) = venue;
    return MapEvent(
      id: id,
      title: title,
      description: description,
      startsAt: starts,
      endsAt: starts.add(const Duration(hours: 2)),
      category: category,
      priceMin: priceMin,
      priceMax: priceMax,
      priceStatus: priceStatus,
      priceSourceUrl: priceSourceUrl,
      ticketUrl: ticketUrl,
      venueId: venueId,
      venueName: venueName,
      venueAddress: address,
      lat: lat,
      lng: lng,
      sourceCount: 1,
    );
  }
}

const _seed = <_SeedEvent>[
  _SeedEvent(
    'Açık Hava Caz Gecesi',
    "Kültürpark'ta ücretsiz caz konseri.",
    0,
    20,
    _kulturpark,
    'concert',
    0,
    0,
    PriceStatus.listed,
  ),
  _SeedEvent(
    'Senfoni Orkestrası: Beethoven 5',
    'İzmir Devlet Senfoni Orkestrası sezon konseri.',
    1,
    20,
    _aassm,
    'concert',
    250,
    450,
    PriceStatus.listed,
    ticketUrl: 'https://www.aassm.org.tr',
  ),
  _SeedEvent(
    'Sahilde Akustik Akşam',
    'Karşıyaka sahilinde ücretsiz akustik sahne.',
    0,
    19,
    _karsiyaka,
    'concert',
    0,
    0,
    PriceStatus.listed,
  ),
  _SeedEvent(
    'Bir Yaz Gecesi Rüyası',
    'Devlet Tiyatroları sezon oyunu.',
    2,
    20,
    _opera,
    'theatre',
    120,
    180,
    PriceStatus.lookedUp,
    priceSourceUrl: 'https://example.org/bilet',
    ticketUrl: 'https://example.org/bilet',
  ),
  _SeedEvent(
    'Stand-up: İzmir Gecesi',
    "Konak Pier'de stand-up gösterisi.",
    3,
    21,
    _konakPier,
    'talk',
    300,
    500,
    PriceStatus.estimated,
  ),
  _SeedEvent(
    'Hafta Sonu Sokak Festivali',
    "Alsancak'ta müzik, yemek ve atölyeler.",
    4,
    14,
    _alsancak,
    'festival',
    0,
    0,
    PriceStatus.listed,
  ),
  _SeedEvent(
    'Seramik Atölyesi',
    'Başlangıç seviyesi seramik atölyesi.',
    5,
    11,
    _bornova,
    'workshop',
    150,
    150,
    PriceStatus.listed,
  ),
  _SeedEvent(
    'Çağdaş Resim Sergisi',
    'Yerel sanatçılardan karma sergi.',
    1,
    10,
    _urla,
    'exhibition',
    0,
    0,
    PriceStatus.listed,
  ),
  _SeedEvent(
    'Çocuklar İçin Kukla Tiyatrosu',
    '4-9 yaş için kukla gösterisi.',
    5,
    15,
    _bornova,
    'family',
    80,
    120,
    PriceStatus.estimated,
  ),
  _SeedEvent(
    'Elektronik Müzik Gecesi',
    "Konak Pier'de DJ setleri.",
    4,
    23,
    _konakPier,
    'party',
    200,
    400,
    PriceStatus.estimated,
  ),
  _SeedEvent(
    'Ücretsiz Rock Konseri',
    'Yerel gruplardan açık hava rock gecesi.',
    0,
    21,
    _kulturpark,
    'concert',
    0,
    0,
    PriceStatus.listed,
  ),
  _SeedEvent(
    'Opera Galası',
    'Verdi ve Puccini aryaları.',
    6,
    20,
    _opera,
    'concert',
    180,
    320,
    PriceStatus.listed,
  ),
];
