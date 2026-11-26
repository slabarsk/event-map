-- Organizatör paneli, admin etkinlik onayı ve kayıtlı etkinlikler.
--
--   submit_event          : onaylı organizatör etkinlik gönderir (pending)
--   reject_event          : admin, pending etkinliği gerekçeyle reddeder
--   my_saved_events       : kullanıcının kayıtlı etkinlikleri (harita satırı biçiminde)
--   organizer_stats       : organizatörün yayında / bekleyen / reddedilen / kaydedilme sayıları
--
-- Etkinlik durumu 'rejected' eklendi. Organizatör kendi etkinliklerini her
-- durumda görür (red gerekçesi dahil); yalnızca pending olanı düzenler/siler.

-- ---------------------------------------------------------------------------
-- events: rejected durumu ve inceleme notu
-- ---------------------------------------------------------------------------
alter table public.events drop constraint if exists events_status_check;
alter table public.events
  add constraint events_status_check check (status in ('pending', 'published', 'rejected')),
  add column review_note text,
  add column reviewed_at timestamptz;

drop policy if exists events_select on public.events;
create policy events_select on public.events
  for select using (
    status = 'published'
    or created_by = auth.uid()
    or public.is_admin()
  );

-- Admin onay listesi: en eski bekleyen önce.
create index if not exists events_pending_idx on public.events (created_at) where status = 'pending';

-- ---------------------------------------------------------------------------
-- submit_event
-- Mekân: p_venue_id verilirse o mekân; yoksa ad + konumla yeni mekân (aynı
-- normalize adda mekân varsa o kullanılır, konumu değişmez).
-- Fiyat: p_is_free -> 0 ve 'listed'; fiyat girildiyse 'listed'; yoksa 'unknown'.
-- ---------------------------------------------------------------------------
create function public.submit_event(
  p_title                 text,
  p_starts_at             timestamptz,
  p_category              text,
  p_description           text default null,
  p_ends_at               timestamptz default null,
  p_venue_id              uuid default null,
  p_venue_name            text default null,
  p_venue_address         text default null,
  p_lat                   double precision default null,
  p_lng                   double precision default null,
  p_is_free               boolean default false,
  p_price_min             numeric default null,
  p_price_max             numeric default null,
  p_ticket_url            text default null,
  p_image_url             text default null,
  p_requires_registration boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_venue  uuid := p_venue_id;
  v_event  uuid;
  v_min    numeric := case when p_is_free then 0 else p_price_min end;
  v_max    numeric := case when p_is_free then 0 else coalesce(p_price_max, p_price_min) end;
  v_source uuid;
begin
  if not public.is_approved_organizer() then
    raise exception 'approved organizer only' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_title, ''))) = 0 then
    raise exception 'title is required' using errcode = '22023';
  end if;
  if p_starts_at is null or p_starts_at < now() - interval '1 hour' then
    raise exception 'start time must be in the future' using errcode = '22023';
  end if;
  if v_min is null and v_max is not null then
    v_min := v_max;
  end if;

  if v_venue is null then
    if length(trim(coalesce(p_venue_name, ''))) = 0 or p_lat is null or p_lng is null then
      raise exception 'venue name and location are required' using errcode = '22023';
    end if;
    if p_lat not between 35 and 43 or p_lng not between 25 and 45 then
      raise exception 'venue location is outside Turkey' using errcode = '22023';
    end if;
    v_venue := public.upsert_venue(p_venue_name, nullif(trim(coalesce(p_venue_address, '')), ''), p_lat, p_lng);
  elsif not exists (select 1 from public.venues where id = v_venue) then
    raise exception 'venue not found' using errcode = '22023';
  end if;

  insert into public.events (
    title, description, starts_at, ends_at, venue_id, category,
    price_min, price_max, price_status, ticket_url, image_url,
    requires_registration, status, origin, created_by
  ) values (
    trim(p_title), nullif(trim(coalesce(p_description, '')), ''), p_starts_at, p_ends_at, v_venue,
    coalesce(p_category, 'other'),
    v_min, v_max,
    case when v_min is null and v_max is null then 'unknown' else 'listed' end,
    nullif(trim(coalesce(p_ticket_url, '')), ''), nullif(trim(coalesce(p_image_url, '')), ''),
    coalesce(p_requires_registration, false), 'pending', 'organizer', auth.uid()
  )
  returning id into v_event;

  select id into v_source from public.sources where slug = 'organizer-form';
  if v_source is not null then
    insert into public.event_sources (event_id, source_id, url, external_id)
    values (v_event, v_source, coalesce(nullif(trim(coalesce(p_ticket_url, '')), ''), 'organizer:' || v_event), v_event::text);
  end if;

  return v_event;
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin: onay / red. approve_event yalnızca pending etkinliği yayınlar.
-- ---------------------------------------------------------------------------
create or replace function public.approve_event(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;
  update public.events
     set status = 'published', review_note = null, reviewed_at = now()
   where id = p_event_id and status = 'pending';
end;
$$;

create function public.reject_event(p_event_id uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;
  update public.events
     set status = 'rejected', review_note = nullif(trim(coalesce(p_note, '')), ''), reviewed_at = now()
   where id = p_event_id and status = 'pending';
end;
$$;

-- ---------------------------------------------------------------------------
-- my_saved_events: events_near ile aynı satır biçimi + saved_at. Geçmiş
-- etkinlikler de döner (uygulama "geçmiş" olarak ayırır). security invoker:
-- saved_events ve events RLS'i geçerli.
-- ---------------------------------------------------------------------------
create function public.my_saved_events()
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
  requires_registration boolean,
  saved_at         timestamptz
)
language sql
stable
security invoker
set search_path = public, extensions
as $$
  select
    e.id, e.title, e.description, e.starts_at, e.ends_at, e.category::text,
    e.price_min, e.price_max, e.price_status, e.price_source_url, e.image_url, e.ticket_url,
    v.id, v.name, v.address,
    st_y(v.location::geometry), st_x(v.location::geometry),
    null::double precision,
    (select count(*) from public.event_sources es where es.event_id = e.id),
    e.requires_registration,
    s.created_at
  from public.saved_events s
  join public.events e on e.id = s.event_id
  join public.venues v on v.id = e.venue_id
  where s.user_id = auth.uid()
    and v.location is not null
  order by e.starts_at;
$$;

-- ---------------------------------------------------------------------------
-- organizer_stats: kaydedilme sayısı başka kullanıcıların satırlarından gelir;
-- saved_events RLS'i bunu gizlediği için security definer ve yalnızca toplam.
-- ---------------------------------------------------------------------------
create function public.organizer_stats()
returns table (published int, pending int, rejected int, saves int)
language sql
stable
security definer
set search_path = public
as $$
  select
    count(*) filter (where e.status = 'published')::int,
    count(*) filter (where e.status = 'pending')::int,
    count(*) filter (where e.status = 'rejected')::int,
    coalesce((select count(*) from public.saved_events s
               join public.events e2 on e2.id = s.event_id
              where e2.created_by = auth.uid()), 0)::int
  from public.events e
  where e.created_by = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- Yetkiler
-- ---------------------------------------------------------------------------
revoke all on function public.submit_event(text, timestamptz, text, text, timestamptz, uuid, text, text,
  double precision, double precision, boolean, numeric, numeric, text, text, boolean) from public, anon;
grant execute on function public.submit_event(text, timestamptz, text, text, timestamptz, uuid, text, text,
  double precision, double precision, boolean, numeric, numeric, text, text, boolean) to authenticated;

revoke all on function public.reject_event(uuid, text) from public, anon;
grant execute on function public.reject_event(uuid, text) to authenticated;

revoke all on function public.my_saved_events() from public, anon;
grant execute on function public.my_saved_events() to authenticated;

revoke all on function public.organizer_stats() from public, anon;
grant execute on function public.organizer_stats() to authenticated;
