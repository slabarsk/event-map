-- Fiyatı bilinmeyen etkinlik için price_status = 'unknown'.
--
-- Önceden fiyatsız etkinlikler de 'listed' yazılıyordu; bu, "kaynakta fiyat
-- yazıyor" anlamına geldiği için yanlıştı. Artık:
--   unknown   : fiyat yok (price_min ve price_max boş); fiyat ajanı bunları arar
--   listed    : kaynakta yazıyor (ücretsiz = 0)
--   looked_up : fiyat ajanı bilet/detay sayfasında buldu (price_source_url dolu)
--   estimated : benzer etkinliklerden tahmin; uygulamada her zaman "Tahmini"
-- Durum ile fiyat alanları tutarlı olmak zorunda: unknown <=> iki fiyat da boş.

alter table public.events drop constraint if exists events_price_status_check;

update public.events
set price_status = 'unknown'
where price_min is null and price_max is null;

alter table public.events
  alter column price_status set default 'unknown',
  add constraint events_price_status_check
    check (price_status in ('unknown', 'listed', 'looked_up', 'estimated')),
  add constraint price_status_matches_price
    check ((price_status = 'unknown') = (price_min is null and price_max is null));

-- Fiyat ajanının iş listesi: yaklaşan, fiyatı bilinmeyen etkinlikler.
create index if not exists events_price_unknown_idx
  on public.events (starts_at)
  where price_status = 'unknown';
