-- RPC'ler
--   events_near       : harita, near me, nl-search (security invoker, RLS geçerli)
--   match_venue       : crawler mekân eşleştirme (service_role)
--   upsert_venue      : crawler mekân ekleme (service_role)
--   approve_event     : admin, pending etkinliği yayınlar
--   set_organizer_status : admin, organizatör başvurusunu onaylar/reddeder

-- ---------------------------------------------------------------------------
-- events_near
-- p_lat/p_lng null ise mesafe filtresi uygulanmaz (şehir geneli).
-- Zaman: etkinliğin bitişi (yoksa başlangıç + 3 saat) p_from'dan sonra, ve
-- p_to verildiyse başlangıcı p_to'dan önce. Devam eden etkinlikler de gelir.
-- p_max_price: coalesce(price_min, price_max) <= p_max_price (0 -> yalnızca ücretsiz).
-- Kullanıcı konumu yalnızca sorguda kullanılır, hiçbir yere yazılmaz.
-- ---------------------------------------------------------------------------
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
  source_count     bigint
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
    (select count(*) from public.event_sources es where es.event_id = e.id)
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

-- ---------------------------------------------------------------------------
-- Mekân eşleştirme (crawler). Önce birebir normalize ad, sonra trigram benzerliği.
-- Eşleşme varsa geocoding çağrısı yapılmaz.
-- ---------------------------------------------------------------------------
create function public.match_venue(p_name text)
returns table (id uuid, name text, address text, lat double precision, lng double precision)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with q as (select public.normalize_text(p_name) as n)
  select v.id, v.name, v.address,
         st_y(v.location::geometry), st_x(v.location::geometry)
  from public.venues v, q
  where v.location is not null
    and q.n <> ''
    and (v.normalized_name = q.n or similarity(v.normalized_name, q.n) >= 0.75)
  order by (v.normalized_name = q.n) desc, similarity(v.normalized_name, q.n) desc
  limit 1;
$$;

create function public.upsert_venue(
  p_name    text,
  p_address text,
  p_lat     double precision,
  p_lng     double precision
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_norm text := public.normalize_text(p_name);
  v_id   uuid;
  v_loc  geography := case when p_lat is null or p_lng is null then null
                           else st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography end;
begin
  if v_norm = '' then
    raise exception 'venue name is empty';
  end if;

  insert into public.venues (name, normalized_name, address, location)
  values (trim(p_name), v_norm, p_address, v_loc)
  on conflict (normalized_name) do update
    set address  = coalesce(public.venues.address, excluded.address),
        location = coalesce(public.venues.location, excluded.location)
  returning id into v_id;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin işlemleri
-- ---------------------------------------------------------------------------
create function public.approve_event(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;
  update public.events set status = 'published' where id = p_event_id;
end;
$$;

create function public.set_organizer_status(p_user_id uuid, p_status public.organizer_status)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;
  update public.profiles
     set organizer_status = p_status, updated_at = now()
   where id = p_user_id and role = 'organizer';
end;
$$;

-- ---------------------------------------------------------------------------
-- Yetkiler
-- ---------------------------------------------------------------------------
revoke all on function public.match_venue(text) from public, anon, authenticated;
revoke all on function public.upsert_venue(text, text, double precision, double precision) from public, anon, authenticated;
grant execute on function public.match_venue(text) to service_role;
grant execute on function public.upsert_venue(text, text, double precision, double precision) to service_role;

revoke all on function public.approve_event(uuid) from public, anon;
revoke all on function public.set_organizer_status(uuid, public.organizer_status) from public, anon;
grant execute on function public.approve_event(uuid) to authenticated;
grant execute on function public.set_organizer_status(uuid, public.organizer_status) to authenticated;
