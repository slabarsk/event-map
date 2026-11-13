-- Etkinlik veri modeli: mekânlar, kaynaklar, etkinlikler, kaynak eşlemeleri,
-- crawl kayıtları ve kayıtlı etkinlikler. RLS politikaları da burada.
-- profiles tablosu ve roller 20261112000000_profiles.sql içinde.

create extension if not exists postgis with schema extensions;
create extension if not exists pg_trgm with schema extensions;

-- Kategoriler uygulamadaki Catalog + event_visuals ile aynı kimliklerdir.
create domain public.event_category as text
  check (value in ('concert', 'theatre', 'exhibition', 'festival', 'standup', 'workshop',
                   'cinema', 'talk', 'sports', 'family', 'party', 'other'));

-- Mekân eşleştirme ve başlık karşılaştırması için tek normalizasyon:
-- küçük harf, Türkçe karakterler sadeleşir, harf/rakam dışı her şey tek boşluk.
create function public.normalize_text(t text)
returns text
language sql
immutable
set search_path = public
as $$
  select trim(regexp_replace(
    lower(translate(coalesce(t, ''), 'İIıŞşĞğÜüÖöÇç', 'iiissgguuoocc')),
    '[^a-z0-9]+', ' ', 'g'));
$$;

create function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select role = 'admin' from public.profiles where id = auth.uid()), false);
$$;

-- Onaylı organizatör mü (etkinlik gönderebilir).
create function public.is_approved_organizer()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select role = 'organizer' and organizer_status = 'approved'
      from public.profiles where id = auth.uid()), false);
$$;

create function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- venues
-- ---------------------------------------------------------------------------
create table public.venues (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  normalized_name text not null,
  address         text,
  location        extensions.geography(Point, 4326),
  created_at      timestamptz not null default now()
);

create unique index venues_normalized_name_key on public.venues (normalized_name);
create index venues_location_gix on public.venues using gist (location);
create index venues_name_trgm on public.venues using gin (normalized_name extensions.gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- sources: crawl kaynakları + kullanıcı paylaşımı ve organizatör formu
-- ---------------------------------------------------------------------------
create table public.sources (
  id         uuid primary key default gen_random_uuid(),
  slug       text not null unique,
  name       text not null,
  type       text not null check (type in ('api', 'rss', 'firecrawl', 'playwright', 'user', 'organizer')),
  base_url   text,
  enabled    boolean not null default true,
  notes      text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------
create table public.events (
  id               uuid primary key default gen_random_uuid(),
  title            text not null check (length(trim(title)) > 0),
  description      text,
  starts_at        timestamptz not null,
  ends_at          timestamptz,
  venue_id         uuid references public.venues (id) on delete set null,
  category         public.event_category not null default 'other',
  price_min        numeric(10, 2) check (price_min >= 0),
  price_max        numeric(10, 2) check (price_max >= 0),
  -- listed: kaynakta yazıyor (ücretsiz = 0), looked_up: fiyat ajanı buldu,
  -- estimated: tahmin; uygulamada her zaman "Tahmini" rozetiyle gösterilir.
  price_status     text not null default 'listed' check (price_status in ('listed', 'looked_up', 'estimated')),
  price_source_url text,
  image_url        text,
  ticket_url       text,
  status           text not null default 'pending' check (status in ('pending', 'published')),
  origin           text not null default 'crawl' check (origin in ('crawl', 'organizer', 'share')),
  created_by       uuid references public.profiles (id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint price_range_ok check (price_min is null or price_max is null or price_min <= price_max),
  constraint ends_after_start check (ends_at is null or ends_at >= starts_at)
);

create index events_published_starts_idx on public.events (starts_at) where status = 'published';
create index events_venue_idx on public.events (venue_id);
create index events_created_by_idx on public.events (created_by);
create index events_title_trgm on public.events using gin (lower(title) extensions.gin_trgm_ops);

create trigger events_touch_updated_at
  before update on public.events
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- event_sources: bir etkinliğin geldiği tüm kaynaklar (Stage 5 duplicate merge buna dayanır).
-- external_id = kaynak içindeki öğe anahtarı (genelde URL), idx = o öğeden çıkan n. etkinlik.
-- ---------------------------------------------------------------------------
create table public.event_sources (
  id           uuid primary key default gen_random_uuid(),
  event_id     uuid not null references public.events (id) on delete cascade,
  source_id    uuid not null references public.sources (id) on delete cascade,
  url          text not null,
  external_id  text not null,
  idx          int not null default 0,
  content_hash text,
  last_seen_at timestamptz not null default now(),
  unique (source_id, external_id, idx)
);

create index event_sources_event_idx on public.event_sources (event_id);

-- ---------------------------------------------------------------------------
-- seen_items: sayfa içeriği değişmediyse Claude çağrılmaz (etkinlik çıkmayan sayfalar dahil).
-- ---------------------------------------------------------------------------
create table public.seen_items (
  source_id    uuid not null references public.sources (id) on delete cascade,
  external_id  text not null,
  content_hash text not null,
  event_count  int not null default 0,
  last_seen_at timestamptz not null default now(),
  primary key (source_id, external_id)
);

-- ---------------------------------------------------------------------------
-- crawl_runs: her koşunun sayaçları, hataları ve token/maliyet bilgisi.
-- ---------------------------------------------------------------------------
create table public.crawl_runs (
  id              uuid primary key default gen_random_uuid(),
  source_id       uuid not null references public.sources (id) on delete cascade,
  started_at      timestamptz not null default now(),
  finished_at     timestamptz,
  items_fetched   int not null default 0,
  items_skipped   int not null default 0,
  events_found    int not null default 0,
  events_upserted int not null default 0,
  errors          int not null default 0,
  error_log       jsonb not null default '[]'::jsonb,
  tokens_input    int not null default 0,
  tokens_output   int not null default 0,
  cost_usd        numeric(10, 4)
);

create index crawl_runs_source_started_idx on public.crawl_runs (source_id, started_at desc);

-- ---------------------------------------------------------------------------
-- saved_events
-- ---------------------------------------------------------------------------
create table public.saved_events (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  event_id   uuid not null references public.events (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, event_id)
);

create index saved_events_event_idx on public.saved_events (event_id);

-- ===========================================================================
-- RLS
-- Kural: yayınlanmış etkinlikleri herkes okur; saved_events yalnızca sahibine
-- açık; organizatör yalnızca kendi pending kayıtlarını görür ve düzenler.
-- Crawler service_role ile yazar (RLS'i atlar).
-- ===========================================================================
alter table public.venues        enable row level security;
alter table public.sources       enable row level security;
alter table public.events        enable row level security;
alter table public.event_sources enable row level security;
alter table public.seen_items    enable row level security;  -- politika yok: yalnızca service_role
alter table public.crawl_runs    enable row level security;
alter table public.saved_events  enable row level security;

-- Admin, organizatör başvurularını onaylamak için profilleri görebilir.
create policy profiles_select_admin on public.profiles
  for select using (public.is_admin());

-- venues
create policy venues_select_all on public.venues
  for select using (true);
create policy venues_admin_all on public.venues
  for all using (public.is_admin()) with check (public.is_admin());

-- sources
create policy sources_select_enabled on public.sources
  for select using (enabled or public.is_admin());
create policy sources_admin_all on public.sources
  for all using (public.is_admin()) with check (public.is_admin());

-- events
create policy events_select on public.events
  for select using (
    status = 'published'
    or (created_by = auth.uid() and status = 'pending')
    or public.is_admin()
  );

-- Onaylı organizatör yalnızca kendi adına, pending olarak gönderebilir.
create policy events_insert_organizer on public.events
  for insert to authenticated
  with check (
    public.is_approved_organizer()
    and created_by = auth.uid()
    and status = 'pending'
    and origin = 'organizer'
  );

-- Pending kayıt düzenlenebilir/silinebilir; yayınlanınca kilitlenir.
create policy events_update_own_pending on public.events
  for update to authenticated
  using (created_by = auth.uid() and status = 'pending')
  with check (created_by = auth.uid() and status = 'pending' and origin = 'organizer');

create policy events_delete_own_pending on public.events
  for delete to authenticated
  using (created_by = auth.uid() and status = 'pending');

create policy events_admin_all on public.events
  for all using (public.is_admin()) with check (public.is_admin());

-- event_sources: görünür etkinliğin kaynakları (alt sorgu da events RLS'ine tabidir)
create policy event_sources_select on public.event_sources
  for select using (exists (select 1 from public.events e where e.id = event_id));

-- crawl_runs: yalnızca admin okur
create policy crawl_runs_admin_select on public.crawl_runs
  for select using (public.is_admin());

-- saved_events: yalnızca sahibi, ve yalnızca görebildiği etkinliği kaydedebilir
create policy saved_events_select_own on public.saved_events
  for select using (user_id = auth.uid());
create policy saved_events_insert_own on public.saved_events
  for insert to authenticated
  with check (user_id = auth.uid()
              and exists (select 1 from public.events e where e.id = event_id));
create policy saved_events_delete_own on public.saved_events
  for delete using (user_id = auth.uid());

-- Politikalar çağıranın yetkisiyle değerlendirilir: anon da events okurken
-- is_admin()'i çalıştırabilmeli (anon için her zaman false döner).
revoke execute on function public.is_admin() from public;
revoke execute on function public.is_approved_organizer() from public;
grant execute on function public.is_admin() to anon, authenticated, service_role;
grant execute on function public.is_approved_organizer() to anon, authenticated, service_role;
