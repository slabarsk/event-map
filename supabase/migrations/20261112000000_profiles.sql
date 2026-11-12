-- Kullanıcı profilleri: rol, onboarding durumu, tercihler, organizatör bilgisi, KVKK onayı.

create type public.user_role as enum ('user', 'organizer', 'admin');
create type public.organizer_status as enum ('pending', 'approved', 'rejected');

create table public.profiles (
  id                    uuid primary key references auth.users (id) on delete cascade,
  full_name             text not null default '',
  role                  public.user_role not null default 'user',
  organizer_status      public.organizer_status,
  onboarding_completed  boolean not null default false,
  preferences           jsonb not null default '{}'::jsonb,
  organization          jsonb,
  kvkk_consent_at       timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);

create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- Rol ve organizatör onayı yalnızca admin/service_role tarafından değişir.
revoke update on public.profiles from authenticated;
grant update (full_name, onboarding_completed, preferences, organization, updated_at)
  on public.profiles to authenticated;

-- Kayıt sırasında profil satırını oluşturur. Kullanıcı yalnızca 'user' veya
-- 'organizer' seçebilir; organizatörler admin onayına kadar 'pending' kalır.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  requested_role public.user_role :=
    case when new.raw_user_meta_data ->> 'role' = 'organizer'
         then 'organizer'::public.user_role
         else 'user'::public.user_role end;
begin
  insert into public.profiles (id, full_name, role, organizer_status, organization, kvkk_consent_at)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    requested_role,
    case when requested_role = 'organizer' then 'pending'::public.organizer_status end,
    case when requested_role = 'organizer'
         then jsonb_build_object('name', coalesce(new.raw_user_meta_data ->> 'org_name', '')) end,
    (new.raw_user_meta_data ->> 'kvkk_consent_at')::timestamptz
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Google ile kayıtta metadata taşınamadığı için rol ve KVKK onayı ilk girişte
-- bu iki fonksiyonla kaydedilir. Rol yalnızca onboarding bitmeden, user → organizer
-- yönünde değiştirilebilir.
create function public.request_organizer_role(org_name text)
returns void
language sql
security definer set search_path = public
as $$
  update public.profiles
     set role = 'organizer',
         organizer_status = 'pending',
         organization = coalesce(organization, '{}'::jsonb) || jsonb_build_object('name', org_name),
         updated_at = now()
   where id = auth.uid()
     and role = 'user'
     and onboarding_completed = false;
$$;

create function public.record_kvkk_consent()
returns void
language sql
security definer set search_path = public
as $$
  update public.profiles
     set kvkk_consent_at = coalesce(kvkk_consent_at, now()),
         updated_at = now()
   where id = auth.uid();
$$;

revoke execute on function public.request_organizer_role(text) from public, anon;
revoke execute on function public.record_kvkk_consent() from public, anon;
grant execute on function public.request_organizer_role(text) to authenticated;
grant execute on function public.record_kvkk_consent() to authenticated;
