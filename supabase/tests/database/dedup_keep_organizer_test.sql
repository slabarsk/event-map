-- merge_events: organizatör kaydı (origin = 'organizer' ya da created_by dolu) hiç silinmez.
begin;
create extension if not exists pgtap with schema extensions;

select plan(12);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000e1', 'org-dedup@test.local', '{"full_name": "Org", "role": "organizer", "org_name": "Sahne"}'),
  ('00000000-0000-0000-0000-0000000000e2', 'fan-dedup@test.local', '{"full_name": "Fan"}');

select public.upsert_venue('Dedup Organizatör Sahnesi', 'Konak', 38.4100, 27.1300) as v_id \gset
select id as src_bilet from public.sources where slug = 'biletinial' \gset

insert into public.events (
  id, title, description, starts_at, venue_id, category,
  price_min, price_max, price_status, ticket_url, status, origin, created_by
) values
  -- Çift A: organizatör kaydı (A1) + crawl kaydı (A2)
  ('30000000-0000-0000-0000-0000000000a1', 'Caz Gecesi', null,
   '2026-12-20 21:00:00+03', :'v_id', 'concert', null, null, 'listed', null, 'published', 'organizer',
   '00000000-0000-0000-0000-0000000000e1'),
  ('30000000-0000-0000-0000-0000000000a2', 'Caz Gecesi', 'Biletinial açıklaması',
   '2026-12-20 21:00:00+03', :'v_id', 'concert', 300, 500, 'listed', 'https://bilet.example/caz', 'published', 'crawl',
   null),
  -- Çift B: iki organizatör kaydı (biri origin, biri created_by ile)
  ('30000000-0000-0000-0000-0000000000b1', 'Şiir Dinletisi', null,
   '2026-12-21 19:00:00+03', :'v_id', 'other', 0, 0, 'listed', null, 'published', 'organizer', null),
  ('30000000-0000-0000-0000-0000000000b2', 'Şiir Dinletisi', null,
   '2026-12-21 19:00:00+03', :'v_id', 'other', 0, 0, 'listed', null, 'published', 'crawl',
   '00000000-0000-0000-0000-0000000000e1'),
  -- Çift C: iki crawl kaydı (eski davranış)
  ('30000000-0000-0000-0000-0000000000c1', 'Tiyatro Oyunu', null,
   '2026-12-22 20:00:00+03', :'v_id', 'theatre', 100, 100, 'listed', null, 'published', 'crawl', null),
  ('30000000-0000-0000-0000-0000000000c2', 'Tiyatro Oyunu', null,
   '2026-12-22 20:00:00+03', :'v_id', 'theatre', 100, 100, 'listed', null, 'published', 'crawl', null);

insert into public.event_sources (event_id, source_id, url, external_id, idx) values
  ('30000000-0000-0000-0000-0000000000a2', :'src_bilet', 'https://bilet.example/caz', 'caz-1', 0);

insert into public.saved_events (user_id, event_id) values
  ('00000000-0000-0000-0000-0000000000e2', '30000000-0000-0000-0000-0000000000a2');

-- 1) Organizatör kaydı p_drop olarak verilse de silinmez: yer değiştirir, crawl kaydı silinir.
select is(
  public.merge_events('30000000-0000-0000-0000-0000000000a2', '30000000-0000-0000-0000-0000000000a1'),
  '30000000-0000-0000-0000-0000000000a2'::uuid,
  'merge_events: organizatör kaydı p_drop ise yer değiştirir ve silinen crawl kaydının id''sini döner'
);

select is(
  (select count(*) from public.events where id = '30000000-0000-0000-0000-0000000000a1')::int,
  1,
  'merge_events: organizatör kaydı (origin = organizer) korunur'
);

select is(
  (select count(*) from public.events where id = '30000000-0000-0000-0000-0000000000a2')::int,
  0,
  'merge_events: crawl kaydı silinir'
);

select is(
  (select row(origin, created_by, description, ticket_url, price_min)::text
     from public.events where id = '30000000-0000-0000-0000-0000000000a1'),
  row('organizer', '00000000-0000-0000-0000-0000000000e1'::uuid, 'Biletinial açıklaması',
      'https://bilet.example/caz', 300::numeric(10,2))::text,
  'merge_events: organizatör kaydının sahibi kalır, eksik alanları crawl kaydından tamamlanır'
);

select is(
  (select event_id from public.event_sources where external_id = 'caz-1'),
  '30000000-0000-0000-0000-0000000000a1'::uuid,
  'merge_events: crawl kaynağı organizatör kaydına taşınır'
);

select is(
  (select count(*) from public.saved_events
    where user_id = '00000000-0000-0000-0000-0000000000e2'
      and event_id = '30000000-0000-0000-0000-0000000000a1')::int,
  1,
  'merge_events: kullanıcının kaydı organizatör etkinliğine taşınır'
);

-- 2) İki kayıt da organizatöre aitse birleştirme yapılmaz.
select is(
  public.merge_events('30000000-0000-0000-0000-0000000000b1', '30000000-0000-0000-0000-0000000000b2'),
  null::uuid,
  'merge_events: iki organizatör kaydında null döner'
);

select is(
  (select count(*) from public.events
    where id in ('30000000-0000-0000-0000-0000000000b1', '30000000-0000-0000-0000-0000000000b2'))::int,
  2,
  'merge_events: iki organizatör kaydının ikisi de korunur (created_by dolu olan dahil)'
);

-- 3) İki crawl kaydında eski davranış: p_drop silinir, id'si döner.
select is(
  public.merge_events('30000000-0000-0000-0000-0000000000c1', '30000000-0000-0000-0000-0000000000c2'),
  '30000000-0000-0000-0000-0000000000c2'::uuid,
  'merge_events: iki crawl kaydında p_drop silinir ve id''si döner'
);

select is(
  (select count(*) from public.events where id = '30000000-0000-0000-0000-0000000000c1')::int,
  1,
  'merge_events: iki crawl kaydında p_keep korunur'
);

-- 4) Olmayan kayıt ya da aynı id verilirse hiçbir şey yapmaz.
select is(
  public.merge_events('30000000-0000-0000-0000-0000000000c1', '30000000-0000-0000-0000-0000000000c1'),
  null::uuid,
  'merge_events: p_keep = p_drop ise null döner'
);

select is(
  public.merge_events('30000000-0000-0000-0000-0000000000c1', '30000000-0000-0000-0000-0000000000ff'),
  null::uuid,
  'merge_events: olmayan p_drop için null döner'
);

select * from finish();
rollback;
