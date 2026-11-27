-- Duplicate merge: organizatör kaydı hiçbir zaman silinmez.
--
-- Organizatör kaydı = origin = 'organizer' ya da created_by dolu. merge_events
-- silinecek kayıt organizatöre aitse ve tutulacak kayıt değilse ikisinin yerini
-- değiştirir; iki kayıt da organizatöre aitse hiç birleştirmez.
--
-- Dönüş değeri void yerine silinen kaydın id'si oldu (birleştirme yapılmadıysa null),
-- böylece crawler yer değiştirmeyi ve atlanan birleştirmeyi doğru sayar.

drop function if exists public.merge_events(uuid, uuid);

create function public.merge_events(p_keep uuid, p_drop uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_keep public.events%rowtype;
  v_drop public.events%rowtype;
  v_tmp  public.events%rowtype;
  v_keep_org boolean;
  v_drop_org boolean;
  v_keep_rank int;
  v_drop_rank int;
begin
  if p_keep is null or p_drop is null or p_keep = p_drop then
    return null;
  end if;

  select * into v_keep from public.events where id = p_keep;
  select * into v_drop from public.events where id = p_drop;
  if v_keep.id is null or v_drop.id is null then
    return null;
  end if;

  v_keep_org := v_keep.origin = 'organizer' or v_keep.created_by is not null;
  v_drop_org := v_drop.origin = 'organizer' or v_drop.created_by is not null;

  if v_keep_org and v_drop_org then
    return null; -- iki organizatör kaydı: hiçbiri silinmez, birleştirme admin'e kalır
  end if;

  if v_drop_org then
    v_tmp  := v_keep;
    v_keep := v_drop;
    v_drop := v_tmp;
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
   where id = v_keep.id;

  -- Aynı (source_id, external_id, idx) varsa silinecek taraftakini sil.
  delete from public.event_sources d
   using public.event_sources k
   where d.event_id = v_drop.id and k.event_id = v_keep.id
     and d.source_id = k.source_id and d.external_id = k.external_id and d.idx = k.idx;

  update public.event_sources set event_id = v_keep.id where event_id = v_drop.id;

  insert into public.saved_events (user_id, event_id, created_at)
  select user_id, v_keep.id, created_at from public.saved_events where event_id = v_drop.id
  on conflict (user_id, event_id) do nothing;

  delete from public.events where id = v_drop.id;
  return v_drop.id;
end;
$$;

revoke all on function public.merge_events(uuid, uuid) from public, anon, authenticated;
grant execute on function public.merge_events(uuid, uuid) to service_role;
