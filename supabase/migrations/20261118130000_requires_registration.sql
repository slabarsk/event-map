-- Başvuru / kayıtla katılım.
--
-- Bazı etkinliklere bilet alınmaz, başvuru formu ya da ön kayıtla katılınır (çocuk
-- atölyeleri, kontenjanlı söyleşiler). Bunlar için fiyat tahmini yanıltıcıdır: fiyat
-- ajanı tahmin yapmaz, uygulama "Başvuru ile" etiketi gösterir. Fiyat kaynakta
-- yazıyorsa (ücretli başvuru) fiyat da gösterilir.

alter table public.events
  add column requires_registration boolean not null default false;

-- events_near dönüş tipine sütun eklemek için fonksiyon yeniden oluşturulur
-- (gövde 20261113000100_event_functions.sql ile aynı, sonda requires_registration).
drop function public.events_near(double precision, double precision, integer,
  timestamptz, timestamptz, text[], numeric);

create function public.events_near(
  p_lat        double precision default null,
  p_lng        double precision default null,
  p_radius_m   integer default 5000,
  p_from       timestamptz default now(),
  p_to         timestamptz default null,
  p_categories text[] default null,
  p_max_price  numeric default null
)
returns table (
  id               uuid,
  title            text,
  description      text,
  starts_at        timestamptz,
  ends_at          timestamptz,
  category         text,
  price_min        numeric,
  price_max        numeric,
  price_status     text,
  price_source_url text,
  image_url        text,
  ticket_url       text,
  venue_id         uuid,
  venue_name       text,
  venue_address    text,
  lat              double precision,
  lng              double precision,
  distance_m       double precision,
  source_count     bigint,
  requires_registration boolean
)
language sql
stable
security invoker
set search_path = public, extensions
as $$
  with origin as (
    select case when p_lat is null or p_lng is null then null
                else st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography end as g
  )
  select
    e.id, e.title, e.description, e.starts_at, e.ends_at, e.category::text,
    e.price_min, e.price_max, e.price_status, e.price_source_url, e.image_url, e.ticket_url,
    v.id, v.name, v.address,
    st_y(v.location::geometry), st_x(v.location::geometry),
    case when o.g is null then null else st_distance(v.location, o.g) end,
    (select count(*) from public.event_sources es where es.event_id = e.id),
    e.requires_registration
  from public.events e
  join public.venues v on v.id = e.venue_id
  cross join origin o
  where e.status = 'published'
    and v.location is not null
    and coalesce(e.ends_at, e.starts_at + interval '3 hours') >= coalesce(p_from, now())
    and (p_to is null or e.starts_at <= p_to)
    and (p_categories is null or cardinality(p_categories) = 0 or e.category = any (p_categories))
    and (p_max_price is null or coalesce(e.price_min, e.price_max) <= p_max_price)
    and (o.g is null or st_dwithin(v.location, o.g, greatest(coalesce(p_radius_m, 5000), 0)))
  order by
    case when o.g is null then null else st_distance(v.location, o.g) end nulls last,
    e.starts_at
  limit 500;
$$;

grant execute on function public.events_near(double precision, double precision, integer,
  timestamptz, timestamptz, text[], numeric) to anon, authenticated, service_role;
