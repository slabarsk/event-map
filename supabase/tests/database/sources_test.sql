-- Migration + seed birlikte beş adapter'ı açar, desteklenmeyen adayları kapalı tutar.
begin;
create extension if not exists pgtap with schema extensions;
select plan(3);

select is((select count(*)::int from public.sources
  where enabled and slug in ('aassm', 'biletinial', 'bornova', 'karsiyaka', 'izmirkultur')), 5,
  'beş desteklenen kaynak migration ve seed sonrası açık');
select is((select count(*)::int from public.sources
  where enabled and type = 'playwright' and slug in ('biletinial', 'bornova')), 2,
  'JS kaynakları Playwright olarak işaretli');
select is((select count(*)::int from public.sources
  where enabled and slug in ('kultursanat', 'devtiyatro', 'passo')), 0,
  'doğrulanmamış eski adaylar açılmaz');

select * from finish();
rollback;
