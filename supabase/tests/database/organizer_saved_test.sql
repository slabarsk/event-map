-- submit_event, reject_event, my_saved_events ve organizer_stats testleri.
-- Çalıştırma: `supabase test db`. Her şey tek transaction içinde, sonda geri alınır.
begin;
create extension if not exists pgtap with schema extensions;

select plan(22);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a1', 'u1@test.local',  '{"full_name": "Kullanıcı"}'),
  ('00000000-0000-0000-0000-0000000000a2', 'u2@test.local',  '{"full_name": "Diğer"}'),
  ('00000000-0000-0000-0000-0000000000b1', 'o1@test.local',  '{"full_name": "Org", "role": "organizer", "org_name": "Sahne"}'),
  ('00000000-0000-0000-0000-0000000000b2', 'o2@test.local',  '{"full_name": "Org2", "role": "organizer", "org_name": "Bekleyen"}'),
  ('00000000-0000-0000-0000-0000000000c1', 'ad@test.local',  '{"full_name": "Admin"}');

update public.profiles set organizer_status = 'approved' where id = '00000000-0000-0000-0000-0000000000b1';
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-0000000000c1';

select public.upsert_venue('Org Test Sahnesi', 'Konak/İzmir', 38.4230, 27.1387) as venue_id \gset

set local role authenticated;

-- ---------------------------------------------------------------- normal kullanıcı
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000a1", "role": "authenticated"}', true);
select throws_ok(
  format($$ select public.submit_event('X', now() + interval '1 day', 'concert', p_venue_id => %L) $$, :'venue_id'),
  '42501', null, 'normal kullanıcı submit_event çağıramaz');

-- ---------------------------------------------------------------- onaysız organizatör
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000b2", "role": "authenticated"}', true);
select throws_ok(
  format($$ select public.submit_event('X', now() + interval '1 day', 'concert', p_venue_id => %L) $$, :'venue_id'),
  '42501', null, 'onay bekleyen organizatör submit_event çağıramaz');

-- ---------------------------------------------------------------- onaylı organizatör
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000b1", "role": "authenticated"}', true);

select public.submit_event(
  'Org Konseri', now() + interval '1 day', 'concert',
  p_venue_id => :'venue_id', p_is_free => true, p_ticket_url => 'https://bilet.example/1'
) as ev1 \gset

select is(
  (select row(status, origin, created_by, price_min, price_max, price_status)::text
     from public.events where id = :'ev1'),
  row('pending', 'organizer', '00000000-0000-0000-0000-0000000000b1'::uuid, 0::numeric(10,2), 0::numeric(10,2), 'listed')::text,
  'kayıtlı mekânla gönderilen etkinlik pending, ücretsiz ve organizatöre ait');
select is(
  (select count(*) from public.event_sources es join public.sources s on s.id = es.source_id
    where es.event_id = :'ev1' and s.slug = 'organizer-form')::int,
  1, 'etkinlik organizer-form kaynağına bağlanır');

select public.submit_event(
  'Yeni Mekânda Atölye', now() + interval '2 days', 'workshop',
  p_venue_name => 'Bostanlı Test Atölyesi', p_venue_address => 'Karşıyaka',
  p_lat => 38.4560, p_lng => 27.0970, p_price_min => 150
) as ev2 \gset

select is(
  (select v.name from public.events e join public.venues v on v.id = e.venue_id where e.id = :'ev2'),
  'Bostanlı Test Atölyesi', 'yeni mekân oluşturulur');
select is(
  (select row(price_min, price_max, price_status)::text from public.events where id = :'ev2'),
  row(150::numeric(10,2), 150::numeric(10,2), 'listed')::text,
  'tek fiyat aralığın iki ucuna yazılır');

select public.submit_event('Fiyatsız', now() + interval '3 days', 'talk', p_venue_id => :'venue_id') as ev3 \gset
select is((select price_status from public.events where id = :'ev3'), 'unknown',
  'fiyat girilmezse unknown');

select throws_ok(
  $$ select public.submit_event('Konumsuz', now() + interval '1 day', 'concert', p_venue_name => 'Yer') $$,
  '22023', null, 'yeni mekân konumsuz gönderilemez');
select throws_ok(
  format($$ select public.submit_event('Geçmiş', now() - interval '1 day', 'concert', p_venue_id => %L) $$, :'venue_id'),
  '22023', null, 'geçmiş tarihli etkinlik gönderilemez');
select throws_ok(
  $$ select public.submit_event('Uzak', now() + interval '1 day', 'concert',
       p_venue_name => 'Paris', p_lat => 48.85, p_lng => 2.35) $$,
  '22023', null, 'Türkiye dışı konum reddedilir');

select is((select count(*) from public.events where created_by = auth.uid())::int, 3,
  'organizatör kendi etkinliklerini görür');

-- ---------------------------------------------------------------- başka kullanıcı
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000a1", "role": "authenticated"}', true);
select is((select count(*) from public.events where id in (:'ev1', :'ev2', :'ev3'))::int, 0,
  'pending etkinlikler başkalarına görünmez');
select throws_ok(format($$ select public.reject_event(%L, 'x') $$, :'ev2'),
  '42501', null, 'normal kullanıcı reject_event çağıramaz');

-- ---------------------------------------------------------------- admin
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000c1", "role": "authenticated"}', true);
select lives_ok(format($$ select public.approve_event(%L) $$, :'ev1'), 'admin yayınlar');
select lives_ok(format($$ select public.reject_event(%L, '  Tarih yanlış  ') $$, :'ev2'), 'admin reddeder');
select lives_ok(format($$ select public.approve_event(%L) $$, :'ev2'),
  'reddedilmiş etkinlik için approve_event hata vermez');
select is((select status from public.events where id = :'ev2'), 'rejected',
  'reddedilmiş etkinlik approve_event ile yayınlanmaz (yalnızca pending)');

-- ---------------------------------------------------------------- kayıtlar
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000a1", "role": "authenticated"}', true);
insert into public.saved_events (user_id, event_id) values ('00000000-0000-0000-0000-0000000000a1', :'ev1');
select is((select count(*) from public.my_saved_events() where id = :'ev1')::int, 1,
  'my_saved_events kullanıcının kaydını döner');
select is((select venue_name from public.my_saved_events() where id = :'ev1'), 'Org Test Sahnesi',
  'my_saved_events mekân bilgisini taşır');

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000a2", "role": "authenticated"}', true);
select is((select count(*) from public.my_saved_events())::int, 0,
  'başkasının kayıtları my_saved_events ile görünmez');

-- ---------------------------------------------------------------- organizatör paneli
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000b1", "role": "authenticated"}', true);
select is(
  (select row(published, pending, rejected, saves)::text from public.organizer_stats()),
  row(1, 1, 1, 1)::text,
  'organizer_stats: yayında, bekleyen, reddedilen ve kaydedilme sayısı');
select is((select review_note from public.events where id = :'ev2'), 'Tarih yanlış',
  'organizatör red gerekçesini görür');

select * from finish();
rollback;
