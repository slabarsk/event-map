-- Stage 5: Duplicate merge (kaynaklar arası tekilleştirme).
--
--   find_event_candidates : aynı mekân ya da 200 m içinde (ST_DWithin),
--                           başlangıç saati ±2 saat, pg_trgm başlık benzerliği >= 0.25.
--   merge_events          : iki kaydı birleştirir; event_sources ve saved_events
--                           taşınır, eksik alanlar ve daha güvenilir fiyat tamamlanır.

create index if not exists events_norm_title_trgm
  on public.events using gin (public.normalize_text(title) extensions.gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- find_event_candidates
-- ---------------------------------------------------------------------------
create or replace function public.find_event_candidates(
  p_title     text,
  p_starts_at timestamptz,
  p_venue_id  uuid,
  p_exclude   uuid default null
)
returns table (
  id          uuid,
  title       text,
  description text,
  starts_at   timestamptz,
  venue_id    uuid,
  venue_name  text,
  category    text,
  title_sim   real,
  distance_m  double precision,
  same_venue  boolean
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with me as (
    select location, public.normalize_text(p_title) as norm_title
      from public.venues where id = p_venue_id
  )
  select
    e.id, e.title, e.description, e.starts_at, e.venue_id, v.name, e.category::text,
    greatest(
      similarity(public.normalize_text(e.title), me.norm_title),
      similarity(lower(e.title), lower(coalesce(p_title, '')))
    )::real as title_sim,
    case when me.location is null or v.location is null then null
         else st_distance(v.location, me.location) end as distance_m,
    (e.venue_id = p_venue_id) as same_venue
  from public.events e
  join public.venues v on v.id = e.venue_id
  cross join me
  where e.status = 'published'
    and me.norm_title <> ''
    and (p_exclude is null or e.id <> p_exclude)
    and e.starts_at between p_starts_at - interval '2 hours' and p_starts_at + interval '2 hours'
    and (
      e.venue_id = p_venue_id
      or (me.location is not null and v.location is not null and st_dwithin(v.location, me.location, 200))
    )
    and greatest(
      similarity(public.normalize_text(e.title), me.norm_title),
      similarity(lower(e.title), lower(coalesce(p_title, '')))
    ) >= 0.25
  order by
    (public.normalize_text(e.title) = me.norm_title) desc,
    title_sim desc,
    (e.venue_id = p_venue_id) desc,
    e.created_at asc
  limit 5;
$$;

-- ---------------------------------------------------------------------------
-- merge_events: p_drop kaydının kaynaklarını ve kullanıcı kayıtlarını p_keep
-- kaydına taşır, p_keep'in eksik alanlarını p_drop'tan tamamlar ve p_drop'u siler.
-- ---------------------------------------------------------------------------
create or replace function public.merge_events(p_keep uuid, p_drop uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_keep public.events%rowtype;
  v_drop public.events%rowtype;
  v_keep_rank int;
  v_drop_rank int;
begin
  if p_keep is null or p_drop is null or p_keep = p_drop then
    return;
  end if;

  select * into v_keep from public.events where id = p_keep;
  select * into v_drop from public.events where id = p_drop;
  if not found or v_keep.id is null then
    return;
  end if;

  v_keep_rank := case v_keep.price_status when 'listed' then 3 when 'looked_up' then 2 when 'estimated' then 1 else 0 end;
  v_drop_rank := case v_drop.price_status when 'listed' then 3 when 'looked_up' then 2 when 'estimated' then 1 else 0 end;

  update public.events
     set description           = coalesce(v_keep.description, v_drop.description),
         ends_at               = case when v_keep.ends_at is not null then v_keep.ends_at
                                      when v_drop.ends_at is not null and v_drop.ends_at >= v_keep.starts_at then v_drop.ends_at
                                      else null end,
         ticket_url            = coalesce(v_keep.ticket_url, v_drop.ticket_url),
         image_url             = coalesce(v_keep.image_url, v_drop.image_url),
         requires_registration = v_keep.requires_registration or v_drop.requires_registration,
         price_min             = case when v_drop_rank > v_keep_rank and v_drop.price_min is not null then v_drop.price_min else v_keep.price_min end,
         price_max             = case when v_drop_rank > v_keep_rank and v_drop.price_min is not null then v_drop.price_max else v_keep.price_max end,
         price_status          = case when v_drop_rank > v_keep_rank and v_drop.price_min is not null then v_drop.price_status else v_keep.price_status end,
         price_source_url      = case when v_drop_rank > v_keep_rank and v_drop.price_min is not null then v_drop.price_source_url else v_keep.price_source_url end
   where id = p_keep;

  -- Aynı (source_id, external_id, idx) varsa p_drop tarafındakini sil.
  delete from public.event_sources d
   using public.event_sources k
   where d.event_id = p_drop and k.event_id = p_keep
     and d.source_id = k.source_id and d.external_id = k.external_id and d.idx = k.idx;

  update public.event_sources set event_id = p_keep where event_id = p_drop;

  insert into public.saved_events (user_id, event_id, created_at)
  select user_id, p_keep, created_at from public.saved_events where event_id = p_drop
  on conflict (user_id, event_id) do nothing;

  delete from public.events where id = p_drop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Yetkiler: yalnızca service_role (crawler) çağırabilir.
-- ---------------------------------------------------------------------------
revoke all on function public.find_event_candidates(text, timestamptz, uuid, uuid) from public, anon, authenticated;
revoke all on function public.merge_events(uuid, uuid) from public, anon, authenticated;
grant execute on function public.find_event_candidates(text, timestamptz, uuid, uuid) to service_role;
grant execute on function public.merge_events(uuid, uuid) to service_role;
