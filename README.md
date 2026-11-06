# Event Map

İzmir'deki etkinlikleri her gün web'den toplayıp tarih, mekân, kategori ve fiyat bilgisiyle konum tabanlı bir haritada gösteren mobil uygulama. Fiyat yoksa ajan arar; bulamazsa tahmin eder ve **"Tahmini"** olarak etiketler.

> Durum: **Stage 1 – Kickoff.** Aşama aşama plan için [ROADMAP.md](ROADMAP.md), mimari için [docs/architecture.html](docs/architecture.html).

## Demo Day hedefleri

- **a)** Bu hafta sonunun İzmir etkinlikleri, 5+ kaynaktan haritada
- **b)** "Bu akşam yakınımdaki ücretsiz konserler" doğal dil sorgusuyla cevaplanır
- **c)** Instagram'dan paylaşılan bir gönderi haritada pin olur

## MVP özellikleri

- İzmir için 5+ kaynaktan günlük toplama
- Yapılandırılmış çıkarım: ad, tarih, mekân, fiyat
- Harita pinleri, filtreler ve "near me tonight" araması
- Organizatör girişi ve etkinlik gönderme; kullanıcılar için kayıtlı etkinlikler
- Kaynaklar arası duplicate birleştirme

## Mimari

```
[Kaynaklar: API/RSS → Firecrawl → Playwright]
        │  (günlük cron, GitHub Actions)
        ▼
[Crawler worker – Python]  ── Claude (çıkarım, fiyat tahmini, dedup kararı)
        │  service_role ile yazar
        ▼
[Supabase] Auth · Postgres+PostGIS · RLS · Edge Functions
        ▲            (nl-search, ingest-share, lookup-price, delete-account)
        │
[Flutter app] harita (Mapbox) · filtreler · near me · kayıtlı etkinlikler · share intent
```

| Katman | Teknoloji |
|---|---|
| Frontend | Flutter (Android, iOS, web), `flutter_map` + Mapbox |
| Backend ve auth | Supabase: Auth, Postgres + PostGIS, RLS, Edge Functions |
| Crawl | Python worker: Firecrawl, Playwright; GitHub Actions cron |
| AI | Claude: çıkarım, fiyat arama/tahmini, doğal dil → filtre |
| Harita ve geocoding | Mapbox |

Detaylı diyagramlar (mimari, veri modeli, akışlar): [docs/architecture.html](docs/architecture.html)

## Repo yapısı

```
app/                    Flutter uygulaması (mobil + web)
supabase/
  migrations/           Şema, RLS politikaları, events_near RPC
  functions/            Edge Functions: nl-search, ingest-share, lookup-price, delete-account
crawler/
  sources/              Kaynak başına bir adapter
  extract/              Claude ile yapılandırılmış çıkarım
  price/                Fiyat arama ve tahmini
  dedup/                Duplicate birleştirme
  geocode/              Mekân eşleştirme ve Mapbox geocoding
  requirements.txt
eval/
  datasets/             Etiketlenmiş test setleri
  results/              Ölçüm sonuçları
  requirements.txt
docs/                   Mimari diyagram, teknik rapor
.github/workflows/      Günlük crawl cron'u
.env.example            Gerekli anahtarların adları (değer yok)
```

## Kurulum

### Gereksinimler

- Flutter SDK (stable)
- Python 3.11+
- [Supabase CLI](https://supabase.com/docs/guides/cli)
- Anthropic, Firecrawl ve Mapbox hesapları (her birinde spending limit açık)

### Adımlar

```bash
git clone https://github.com/slabarsk/event-map.git
cd event-map
cp .env.example .env        # anahtarları doldurun, .env asla commit edilmez
```

**Backend (Supabase):**

```bash
supabase start
supabase db reset           # migration'lar + seed
```

**Crawler:**

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r crawler/requirements.txt
playwright install chromium
```

**Uygulama:**

```bash
cd app
flutter pub get
flutter run
```

**Eval:**

```bash
pip install -r eval/requirements.txt
pytest eval
```

> Uygulama kodu, migration'lar ve crawler adapter'ları ilgili aşamalarda eklenecek. Bkz. [ROADMAP.md](ROADMAP.md).

## Güvenlik ve veri

- API anahtarları repoda tutulmaz; yalnızca `.env` (bkz. `.env.example`).
- `SUPABASE_SERVICE_ROLE_KEY` yalnızca crawler ve Edge Functions'ta kullanılır, uygulamaya girmez.
- **KVKK:** açık rıza ve aydınlatma metni, hesap silme seçeneği, kullanıcı konumu saklanmaz.
- Instagram scraping yapılmaz; yalnızca kullanıcının paylaştığı gönderiler işlenir.
- Kaynak sitelerin kullanım şartlarına ve robots.txt'ye uyulur; önce resmi API/RSS.

## Ekip

| Üye | Sorumluluk |
|---|---|
| A | Mobil: Flutter, harita, auth ekranları, share intent, organizatör formu |
| B | Backend/AI: Supabase şeması, crawler, Claude pipeline'ları, eval |
