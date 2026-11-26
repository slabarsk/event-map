-- find_event_candidates ve merge_events pgTAP testleri.
begin;
create extension if not exists pgtap with schema extensions;

select plan(10);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000d1', 'dedup@test.local', '{"full_name": "Dedup"}');

-- İki yakın mekân (~60 m) ve bir uzak mekân (~4 km).
select public.upsert_venue('AASSM Büyük Salon', 'Konak', 38.3983, 27.0811) as v_aassm \gset
select public.upsert_venue('Ahmed Adnan Saygun Sanat Mrk.', 'Güzelyalı', 38.3987, 27.0815) as v_near \gset
select public.upsert_venue('Karşıyaka Hikmet Şimşek', 'Karşıyaka', 38.4560, 27.1120) as v_far \gset

insert into public.events (
  id, title, description, starts_at, venue_id, category,
  price_min, price_max, price_status, ticket_url, status, origin
) values
  ('20000000-0000-0000-0000-000000000001', 'İzmir Devlet Senfoni Orkestrası Konseri', null,
   '2026-12-15 20:00:00+03', :'v_aassm', 'concert', 200, 400, 'estimated', null, 'published', 'crawl'),
  ('20000000-0000-0000-0000-000000000002', 'İzmir Devlet Senfoni Orkestrası Yılbaşı Konseri', 'Detaylı açıklama',
   '2026-12-15 20:30:00+03', :'v_near', 'concert', 250, 450, 'listed', 'https://bilet.example/idso', 'published', 'crawl'),
  ('20000000-0000-0000-0000-000000000003', 'İzmir Devlet Senfoni Orkestrası Konseri', null,
   '2026-12-15 23:30:00+03', :'v_aassm', 'concert', 200, 400, 'listed', null, 'published', 'crawl'),
  ('20000000-0000-0000-0000-000000000004', 'İzmir Devlet Senfoni Orkestrası Konseri', null,
   '2026-12-15 20:00:00+03', :'v_far', 'concert', 200, 400, 'listed', null, 'published', 'crawl'),
  ('20000000-0000-0000-0000-000000000005', 'Tamamen Farklı Tiyatro Oyunu', null,
   '2026-12-15 20:00:00+03', :'v_aassm', 'theatre', 100, 100, 'listed', null, 'published', 'crawl');

select id as src_aassm from public.sources where slug = 'aassm' \gset
select id as src_bilet from public.sources where slug = 'biletinial' \gset

insert into public.event_sources (event_id, source_id, url, external_id, idx) values
  ('20000000-0000-0000-0000-000000000001', :'src_aassm', 'https://aassm.example/1', 'a-1', 0),
  ('20000000-0000-0000-0000-000000000002', :'src_bilet', 'https://bilet.example/1', 'b-1', 0);

insert into public.saved_events (user_id, event_id) values
  ('00000000-0000-0000-0000-0000000000d1', '20000000-0000-0000-0000-000000000002');

-- 1) Aynı mekân ve 200m içindeki yakın mekân (±2 saat, benzer başlık) aday olarak döner.
--    >2 saat uzaktaki (0003), >200m uzaktaki (0004) ve benzemeyen başlık (0005) elenir.
select is(
  (select array_agg(id order by id)
     from public.find_event_candidates(
       'İzmir Devlet Senfoni Orkestrası Konseri',
       '2026-12-15 20:00:00+03',
       :'v_aassm'
     )
    where id::text like '20000000-%'),
  array[
    '20000000-0000-0000-0000-000000000001'::uuid,
    '20000000-0000-0000-0000-000000000002'::uuid
  ],
  'find_event_candidates: aynı mekân veya <=200m, ±2 saat ve pg_trgm >= 0.25 olanları döner'
);

-- 2) p_exclude verilen etkinliği dışarıda bırakır.
select is(
  (select count(*) from public.find_event_candidates(
    'İzmir Devlet Senfoni Orkestrası Konseri',
    '2026-12-15 20:00:00+03',
    :'v_aassm',
    '20000000-0000-0000-0000-000000000001'
  ) where id = '20000000-0000-0000-0000-000000000001')::int,
  0,
  'find_event_candidates: p_exclude kendisini hariç tutar'
);

-- 3) 200m içindeki yakın mekân için distance_m <= 200 ve same_venue = false döner.
select ok(
  (select distance_m < 200 and not same_venue
     from public.find_event_candidates(
       'İzmir Devlet Senfoni Orkestrası Konseri',
       '2026-12-15 20:00:00+03',
       :'v_aassm'
     )
    where id = '20000000-0000-0000-0000-000000000002'),
  'find_event_candidates: 200m içindeki farklı mekânı ST_DWithin ile yakalar'
);

-- 4) merge_events: 0002 -> 0001 birleştirildiğinde kaynaklar, kayıtlar ve eksik alanlar taşınır.
select lives_ok(
  $$ select public.merge_events('20000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002') $$,
  'merge_events hatasız çalışır'
);

select is(
  (select count(*) from public.events where id = '20000000-0000-0000-0000-000000000002')::int,
  0,
  'merge_events: birleştirilen ikinci etkinlik silinir'
);

select is(
  (select count(*) from public.event_sources where event_id = '20000000-0000-0000-0000-000000000001')::int,
  2,
  'merge_events: iki kaynağın satırları event_sources altında toplanır'
);

select is(
  (select row(description, ticket_url, price_min, price_max, price_status)::text
     from public.events where id = '20000000-0000-0000-0000-000000000001'),
  row('Detaylı açıklama', 'https://bilet.example/idso', 250::numeric(10,2), 450::numeric(10,2), 'listed')::text,
  'merge_events: eksik alanları tamamlar ve listed fiyatı estimated fiyatın önüne geçirir'
);

select is(
  (select count(*) from public.saved_events
    where user_id = '00000000-0000-0000-0000-0000000000d1'
      and event_id = '20000000-0000-0000-0000-000000000001')::int,
  1,
  'merge_events: kullanıcının saved_events kaydı korunan etkinliğe taşınır'
);

-- 5) Yetki kontrolü: anon ve authenticated çağıramaz.
set local role anon;
select throws_ok(
  format($$ select public.find_event_candidates('X', now(), %L) $$, :'v_aassm'),
  '42501', null, 'anon find_event_candidates çağıramaz'
);

set local role authenticated;
select throws_ok(
  $$ select public.merge_events('20000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000003') $$,
  '42501', null, 'authenticated merge_events çağıramaz'
);

select * from finish();
rollback;
