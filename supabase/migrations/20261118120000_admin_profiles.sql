-- Admin paneli: organizatör başvurularını okuma.
--
-- 20261113000000_events.sql'deki profiles_select_admin admin'e TÜM profilleri
-- (normal kullanıcıların tercihleri dahil) açıyordu. Panel yalnızca organizatör
-- başvurularına ihtiyaç duyar; KVKK veri minimizasyonu gereği politika
-- organizatör satırlarıyla daraltılır. Admin kendi profilini
-- profiles_select_own ile okumaya devam eder. is_admin() security definer
-- olduğu için politika profiles üzerinde özyinelemeye yol açmaz.
drop policy if exists profiles_select_admin on public.profiles;

create policy "profiles_select_admin_organizers" on public.profiles
  for select using (role = 'organizer' and public.is_admin());

-- Başvuru detayında organizatörle iletişim için e-posta. KVKK gereği
-- auth.users'tan yalnızca e-posta döner ve yalnızca organizatör hesapları için;
-- normal kullanıcıların e-postası admin'e açılmaz.
create function public.admin_organizer_email(p_user_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;
  select u.email into v_email
    from auth.users u
    join public.profiles p on p.id = u.id
   where u.id = p_user_id
     and p.role = 'organizer';
  return v_email;
end;
$$;

revoke all on function public.admin_organizer_email(uuid) from public, anon;
grant execute on function public.admin_organizer_email(uuid) to authenticated;
