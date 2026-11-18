-- Admin paneli RLS testleri: organizatör başvurularını yalnızca admin listeler.
-- Çalıştırma: `supabase test db`. Tek transaction, sonda geri alınır.
begin;
create extension if not exists pgtap with schema extensions;

select plan(13);

insert into auth.users (id, email, raw_user_meta_data) values
  ('20000000-0000-0000-0000-00000000000a', 'kullanici@test.local', '{"full_name": "Kullanıcı"}'),
  ('20000000-0000-0000-0000-00000000000b', 'onayli@test.local',    '{"full_name": "Onaylı", "role": "organizer", "org_name": "Sahne"}'),
  ('20000000-0000-0000-0000-00000000000c', 'bekleyen@test.local',  '{"full_name": "Bekleyen", "role": "organizer", "org_name": "Kulüp"}'),
  ('20000000-0000-0000-0000-00000000000d', 'admin@test.local',     '{"full_name": "Admin"}');

update public.profiles set organizer_status = 'approved' where id = '20000000-0000-0000-0000-00000000000b';
update public.profiles set role = 'admin' where id = '20000000-0000-0000-0000-00000000000d';

-- ---------------------------------------------------------------- normal kullanıcı
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "20000000-0000-0000-0000-00000000000a", "role": "authenticated"}', true);

select is((select count(*) from public.profiles where id::text like '20000000-%')::int, 1,
  'normal kullanıcı yalnızca kendi profilini görür');
select is((select count(*) from public.profiles where role = 'organizer' and id::text like '20000000-%')::int, 0,
  'normal kullanıcı organizatör başvurularını listeleyemez');
select throws_ok($$ select public.admin_organizer_email('20000000-0000-0000-0000-00000000000c') $$,
  '42501', null, 'normal kullanıcı organizatör e-postasını okuyamaz');
select throws_ok($$ select public.set_organizer_status('20000000-0000-0000-0000-00000000000c', 'approved') $$,
  '42501', null, 'normal kullanıcı başvuru onaylayamaz');

-- ---------------------------------------------------------------- onaylı organizatör
select set_config('request.jwt.claims', '{"sub": "20000000-0000-0000-0000-00000000000b", "role": "authenticated"}', true);

select is((select count(*) from public.profiles where id::text like '20000000-%')::int, 1,
  'organizatör yalnızca kendi profilini görür');
select throws_ok($$ select public.admin_organizer_email('20000000-0000-0000-0000-00000000000c') $$,
  '42501', null, 'organizatör başka organizatörün e-postasını okuyamaz');

-- ---------------------------------------------------------------- admin
select set_config('request.jwt.claims', '{"sub": "20000000-0000-0000-0000-00000000000d", "role": "authenticated"}', true);

select is((select count(*) from public.profiles where role = 'organizer' and id::text like '20000000-%')::int, 2,
  'admin tüm organizatör başvurularını listeler');
select is((select count(*) from public.profiles where role = 'organizer' and organizer_status = 'pending' and id::text like '20000000-%')::int, 1,
  'admin pending filtresiyle listeler');
select is((select count(*) from public.profiles where id = '20000000-0000-0000-0000-00000000000a')::int, 0,
  'admin normal kullanıcı profillerini göremez (KVKK)');
select is(public.admin_organizer_email('20000000-0000-0000-0000-00000000000c'), 'bekleyen@test.local',
  'admin organizatörün e-postasını okur');
select is(public.admin_organizer_email('20000000-0000-0000-0000-00000000000a'), null,
  'admin normal kullanıcının e-postasını okuyamaz');

select lives_ok($$ select public.set_organizer_status('20000000-0000-0000-0000-00000000000c', 'rejected') $$,
  'admin başvuruyu reddeder');
select is((select organizer_status::text from public.profiles where id = '20000000-0000-0000-0000-00000000000c'),
  'rejected', 'red durumu kaydedilir');

select * from finish();
rollback;
