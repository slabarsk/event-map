-- RLS ve events_near testleri. Çalıştırma: `supabase test db`
-- Her şey tek transaction içinde, sonda geri alınır.
begin;
create extension if not exists pgtap with schema extensions;

select plan(16);

-- Test kullanıcıları: iki normal kullanıcı, onaylı ve onaysız organizatör, admin.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'ayse@test.local',  '{"full_name": "Ayşe"}'),
  ('00000000-0000-0000-0000-00000000000b', 'burak@test.local', '{"full_name": "Burak"}'),
  ('00000000-0000-0000-0000-00000000000c', 'org@test.local',   '{"full_name": "Org", "role": "organizer", "org_name": "Sahne"}'),
  ('00000000-0000-0000-0000-00000000000d', 'org2@test.local',  '{"full_name": "Org2", "role": "organizer", "org_name": "Bekleyen"}'),
  ('00000000-0000-0000-0000-00000000000e', 'admin@test.local', '{"full_name": "Admin"}');

update public.profiles set organizer_status = 'approved' where id = '00000000-0000-0000-0000-00000000000c';
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-00000000000e';

-- Veri: bir mekân, bir yayınlanmış ve bir pending etkinlik.
select public.upsert_venue('Test Sahnesi', 'Konak/İzmir', 38.4230, 27.1387) as venue_id \gset
insert into public.events (id, title, starts_at, venue_id, category, price_min, price_max, status, origin) values
  ('10000000-0000-0000-0000-000000000001', 'Yayında Konser', now() + interval '2 hours', :'venue_id', 'concert', 0, 0, 'published', 'crawl'),
  ('10000000-0000-0000-0000-000000000002', 'Bekleyen Oyun',  now() + interval '1 day',   :'venue_id', 'theatre', 100, 150, 'pending', 'crawl');

-- Ayşe bir etkinliği kaydetmiş.
insert into public.saved_events (user_id, event_id)
values ('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------- anon
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);

-- Seed verisi de yüklü olabilir; yalnızca bu testin kayıtları sayılır.
select is((select count(*) from public.events where id::text like '10000000-%')::int, 1,
  'anon yalnızca yayınlanmış etkinliği görür');
select is((select count(*) from public.events_near() where id::text like '10000000-%')::int, 1,
  'anon events_near ile yalnızca yayınlanmışı okur');
select is((select count(*) from public.saved_events)::int, 0, 'anon kayıtlı etkinlik göremez');
select is((select count(*) from public.crawl_runs)::int, 0, 'anon crawl_runs göremez');
select throws_ok($$ select public.upsert_venue('X', null, 38, 27) $$, '42501', null, 'anon upsert_venue çağıramaz');

-- ---------------------------------------------------------------- Burak (başka kullanıcı)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000b", "role": "authenticated"}', true);

select is((select count(*) from public.saved_events)::int, 0, 'Burak, Ayşe''nin kayıtlarını göremez');
select throws_ok(
  $$ insert into public.saved_events (user_id, event_id)
     values ('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001') $$,
  '42501', null, 'Burak başkası adına kayıt ekleyemez');
select lives_ok(
  $$ insert into public.saved_events (user_id, event_id)
     values ('00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000001') $$,
  'Burak kendi adına kayıt ekler');
select throws_ok(
  $$ insert into public.events (title, starts_at, status, origin, created_by)
     values ('Sahte', now(), 'pending', 'organizer', '00000000-0000-0000-0000-00000000000b') $$,
  '42501', null, 'normal kullanıcı etkinlik gönderemez');

-- ---------------------------------------------------------------- Ayşe
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000a", "role": "authenticated"}', true);
select is((select count(*) from public.saved_events)::int, 1, 'Ayşe yalnızca kendi kaydını görür');

-- ---------------------------------------------------------------- onaysız organizatör
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000d", "role": "authenticated"}', true);
select throws_ok(
  $$ insert into public.events (title, starts_at, status, origin, created_by)
     values ('Erken', now(), 'pending', 'organizer', '00000000-0000-0000-0000-00000000000d') $$,
  '42501', null, 'onay bekleyen organizatör etkinlik gönderemez');

-- ---------------------------------------------------------------- onaylı organizatör
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000c", "role": "authenticated"}', true);
select lives_ok(
  $$ insert into public.events (id, title, starts_at, status, origin, created_by)
     values ('10000000-0000-0000-0000-000000000003', 'Org Etkinliği', now() + interval '3 days',
             'pending', 'organizer', '00000000-0000-0000-0000-00000000000c') $$,
  'onaylı organizatör pending etkinlik gönderir');
select throws_ok(
  $$ insert into public.events (title, starts_at, status, origin, created_by)
     values ('Direkt Yayın', now(), 'published', 'organizer', '00000000-0000-0000-0000-00000000000c') $$,
  '42501', null, 'organizatör doğrudan yayınlayamaz');
select is((select count(*) from public.events where status = 'pending')::int, 1,
  'organizatör yalnızca kendi pending kaydını görür');

-- ---------------------------------------------------------------- admin
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000e", "role": "authenticated"}', true);
select lives_ok($$ select public.approve_event('10000000-0000-0000-0000-000000000003') $$, 'admin etkinliği yayınlar');

-- ---------------------------------------------------------------- events_near filtreleri
reset role;
select is(
  (select count(*) from public.events_near(p_lat => 38.4230, p_lng => 27.1387, p_radius_m => 1000,
                                           p_categories => array['concert'], p_max_price => 0)
    where id::text like '10000000-%')::int,
  1, 'events_near: konum + kategori + ücretsiz filtresi');

select * from finish();
rollback;
