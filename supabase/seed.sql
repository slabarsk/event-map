-- Event Map: lokal geliştirme verisi (`supabase db reset` ile yüklenir).
-- Etkinlik tarihleri now()'a göre hesaplanır, seed her zaman "yaklaşan" etkinlik üretir.
-- Mekân ve etkinlikler app/lib/features/events/data/demo_events_repository.dart ile aynıdır.
-- Koordinatlar yaklaşıktır; gerçek veri crawler'dan gelir.

-- Kaynaklar -------------------------------------------------------------------
-- Crawler yalnızca enabled = true ve adapter'ı olan kaynakları çalıştırır.
-- Stage 4: tek kaynak (AASSM). Diğerleri adapter'ları yazıldıkça Stage 5'te açılır.
insert into public.sources (slug, name, type, base_url, enabled, notes) values
  ('aassm',          'AASSM',                    'firecrawl',  'https://www.aassm.org.tr',         true,  'Statik HTML; detay linkleri /tr/Etkinlikler/Detay/<id>'),
  ('kultursanat',    'İzmir Kültürsanat',        'playwright', 'https://kultursanat.izmir.bel.tr', false, 'React SPA, tarayıcı gerekir'),
  ('biletinial',     'Biletinial',               'firecrawl',  'https://biletinial.com',           false, 'robots.txt: yalnızca WebLogin ve kino yasak'),
  ('devtiyatro',     'Devlet Tiyatroları İzmir', 'firecrawl',  'https://devtiyatro.gov.tr',        false, 'robots.txt: /api/ yasak'),
  ('passo',          'Passo',                    'playwright', 'https://www.passo.com.tr',         false, 'Açmadan önce kullanım şartları kontrol edilmeli'),
  ('user-share',     'Kullanıcı paylaşımı',      'user',       null,                               true,  'Kullanıcı onaylı paylaşımlar (Stage 7)'),
  ('organizer-form', 'Organizatör formu',        'organizer',  null,                               true,  'Organizatör paneli (Stage 5)')
on conflict (slug) do nothing;

-- Mekânlar --------------------------------------------------------------------
select public.upsert_venue('Ahmet Adnan Saygun Sanat Merkezi', 'Mimar Kemalettin, Gazi Osman Paşa Blv., Konak/İzmir', 38.4230, 27.1387);
select public.upsert_venue('Kültürpark Açık Hava Tiyatrosu',   'Kültürpark, Konak/İzmir',                              38.4343, 27.1463);
select public.upsert_venue('Konak Pier',                       'Kemeraltı, Konak/İzmir',                                38.4205, 27.1288);
select public.upsert_venue('İzmir Devlet Opera ve Balesi',     'Cumhuriyet Blv., Alsancak/İzmir',                       38.4358, 27.1426);
select public.upsert_venue('Karşıyaka Sahil Sahnesi',          'Karşıyaka Sahili, Karşıyaka/İzmir',                     38.4588, 27.1172);
select public.upsert_venue('Bornova Kültür Merkezi',           'Bornova/İzmir',                                         38.4625, 27.2197);
select public.upsert_venue('Urla Bağ Evi Galerisi',            'Urla/İzmir',                                            38.3225, 26.7647);
select public.upsert_venue('Alsancak Kıbrıs Şehitleri Caddesi','Alsancak/İzmir',                                        38.4361, 27.1431);

-- Etkinlikler -----------------------------------------------------------------
-- price_status: listed (ücretsiz dahil), looked_up, estimated
insert into public.events (title, description, starts_at, ends_at, venue_id, category,
                           price_min, price_max, price_status, price_source_url, ticket_url, status, origin)
select t.title, t.descr,
       date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul'
         + (t.day_offset * interval '1 day') + (t.hour * interval '1 hour'),
       date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul'
         + (t.day_offset * interval '1 day') + ((t.hour + 2) * interval '1 hour'),
       (select id from public.venues where normalized_name = public.normalize_text(t.venue)),
       t.cat, t.pmin, t.pmax, t.pstatus, t.psrc, t.ticket, 'published', 'crawl'
from (values
  ('Açık Hava Caz Gecesi',               'Kültürpark''ta ücretsiz caz konseri.',                 0, 20, 'Kültürpark Açık Hava Tiyatrosu',    'concert',   0::numeric,   0::numeric,   'listed',    null,                         null),
  ('Senfoni Orkestrası: Beethoven 5',    'İzmir Devlet Senfoni Orkestrası sezon konseri.',       1, 20, 'Ahmet Adnan Saygun Sanat Merkezi',  'concert',   250,          450,          'listed',    null,                         'https://www.aassm.org.tr'),
  ('Sahilde Akustik Akşam',              'Karşıyaka sahilinde ücretsiz akustik sahne.',          0, 19, 'Karşıyaka Sahil Sahnesi',           'concert',   0,            0,            'listed',    null,                         null),
  ('Bir Yaz Gecesi Rüyası',              'Devlet Tiyatroları sezon oyunu.',                      2, 20, 'İzmir Devlet Opera ve Balesi',      'theatre',   120,          180,          'looked_up', 'https://example.org/bilet',  'https://example.org/bilet'),
  ('Stand-up: İzmir Gecesi',             'Konak Pier''de stand-up gösterisi.',                   3, 21, 'Konak Pier',                        'talk',      300,          500,          'estimated', null,                         null),
  ('Hafta Sonu Sokak Festivali',         'Alsancak''ta müzik, yemek ve atölyeler.',              4, 14, 'Alsancak Kıbrıs Şehitleri Caddesi', 'festival',  0,            0,            'listed',    null,                         null),
  ('Seramik Atölyesi',                   'Başlangıç seviyesi seramik atölyesi.',                 5, 11, 'Bornova Kültür Merkezi',            'workshop',  150,          150,          'listed',    null,                         null),
  ('Çağdaş Resim Sergisi',               'Yerel sanatçılardan karma sergi.',                     1, 10, 'Urla Bağ Evi Galerisi',             'exhibition',0,            0,            'listed',    null,                         null),
  ('Çocuklar İçin Kukla Tiyatrosu',      '4-9 yaş için kukla gösterisi.',                        5, 15, 'Bornova Kültür Merkezi',            'family',    80,           120,          'estimated', null,                         null),
  ('Elektronik Müzik Gecesi',            'Konak Pier''de DJ setleri.',                           4, 23, 'Konak Pier',                        'party',     200,          400,          'estimated', null,                         null),
  ('Ücretsiz Rock Konseri',              'Yerel gruplardan açık hava rock gecesi.',              0, 21, 'Kültürpark Açık Hava Tiyatrosu',    'concert',   0,            0,            'listed',    null,                         null),
  ('Opera Galası',                       'Verdi ve Puccini aryaları.',                           6, 20, 'İzmir Devlet Opera ve Balesi',      'concert',   180,          320,          'listed',    null,                         null)
) as t(title, descr, day_offset, hour, venue, cat, pmin, pmax, pstatus, psrc, ticket);

-- Seed etkinliklerini örnek kaynaklara bağla (uygulamada "kaynak sayısı" için)
with numbered as (
  select e.id, row_number() over (order by e.title) as n
  from public.events e
)
insert into public.event_sources (event_id, source_id, url, external_id, idx)
select n.id, s.id, 'https://example.org/seed/' || n.id, 'seed-' || n.id, 0
from numbered n
join public.sources s
  on s.slug = (array['aassm', 'kultursanat', 'biletinial', 'devtiyatro'])[1 + (n.n % 4)::int];
