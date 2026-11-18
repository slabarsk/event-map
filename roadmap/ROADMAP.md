# Event Map: Yol Haritası

İzmir'deki etkinlikleri her gün web'den toplayıp tarih, mekân, kategori ve fiyat bilgisiyle konum tabanlı bir haritada gösteren mobil uygulama. Fiyat yoksa ajan arar, bulamazsa tahmin eder ve "tahmini" olarak etiketler.

Plan 10 aşamadan oluşur. Her aşamada hedef, yapılacaklar ve haftalık sunumda gösterilecek çıktı yer alır.

---

## İçindekiler

- [0. Mimari kararlar](#0-mimari-kararlar)
- [Rol dağılımı](#rol-dağılımı)
- [Repo yapısı](#repo-yapısı)
- [Bağımlılıklar](#bağımlılıklar)
- [Stage 1: Kickoff](#stage-1-kickoff)
- [Stage 2: Know your users](#stage-2-know-your-users)
- [Stage 3: Foundations](#stage-3-foundations)
- [Stage 4: First flow](#stage-4-first-flow)
- [Stage 5: Core MVP](#stage-5-core-mvp)
- [Stage 6: AI quality](#stage-6-ai-quality)
- [Stage 7: Beta](#stage-7-beta)
- [Stage 8: Cross-testing](#stage-8-cross-testing)
- [Stage 9: Polish](#stage-9-polish)
- [Stage 10: Demo Day](#stage-10-demo-day)
- [Teslim edilecekler](#teslim-edilecekler)
- [Haftalık Google Drive raporu şablonu](#haftalık-google-drive-raporu-şablonu)
- [Riskler](#riskler)

---

## 0. Mimari kararlar

```
[Kaynaklar: API/RSS → Firecrawl → Playwright]
        │  (günlük cron)
        ▼
[Crawler worker – Python]  ── Claude (çıkarım, fiyat tahmini, dedup kararı)
        │  service_role ile yazar
        ▼
[Supabase] Auth · Postgres+PostGIS · RLS · Edge Functions
        ▲            (nl-search, ingest-share, lookup-price, delete-account)
        │
[Flutter app] harita (Mapbox) · filtreler · near me · kayıtlı etkinlikler · share intent
```

| Karar | Seçim | Gerekçe |
|---|---|---|
| Crawl nerede çalışacak | Ayrı Python worker, GitHub Actions cron (günlük) | Playwright, Supabase Edge Function'larında (Deno) çalışmaz. Actions ücretsiz ve loglu. |
| Kaynak önceliği | Resmi API/RSS → Firecrawl → en son Playwright | Brief'teki "Official APIs or RSS first" kuralı |
| Harita | `flutter_map` + Mapbox tile + Mapbox Geocoding | Flutter web build ile **public link** verebilmek için. Resmi Mapbox Flutter SDK'sının web desteği Stage 1'de kontrol edilecek. |
| Query-to-SQL | Claude ham SQL **üretmez**. Kullanıcının sorusunu JSON filtreye çevirir, bu filtre parametreli bir PostGIS RPC'ye gider. | SQL injection riski yok, test edilebilir, savunması kolay |
| Fiyat mantığı | `listed`, `looked_up`, `estimated` (ücretsiz etkinlik = `price=0`, `listed`) | Fiyat yoksa ajan arar. Bulamazsa tahmin eder ve **her zaman etiketler**. |
| Instagram | Scraping yok. Kullanıcı paylaşır: link + caption/görsel → Claude çıkarır → kullanıcı onaylar → pin | Meta'nın kullanım şartlarına uygun |
| Konum gizliliği | Kullanıcı konumu sorgu sırasında kullanılır, **saklanmaz** | KVKK açısından en temiz yol |

## Rol dağılımı

İki üye de düzenli commit atar.

- **A, Mobil:** Flutter, harita, auth ekranları, share intent, organizatör formu
- **B, Backend/AI:** Supabase şeması, crawler, Claude pipeline'ları, eval

## Repo yapısı

```
app/            Flutter (pubspec.yaml)
supabase/       migrations/, functions/, seed.sql, config.toml
crawler/        sources/, extract/, price/, dedup/, geocode/, requirements.txt
eval/           datasets/, run_eval.py, results/, requirements.txt
roadmap/        ROADMAP.md, architecture.html, wireframe.html
docs/           technical report
.env.example    .github/workflows/crawl.yml
```

## Bağımlılıklar

Sürümler Stage 1'de sabitlenir: Python'da `==`, Flutter'da `pubspec.lock` commit edilir. Böylece kurulum her makinede ve CI'da aynı sonucu verir.

### Geliştirme araçları

| Araç | Ne için |
|---|---|
| Flutter SDK (stable) | Mobil + web build |
| Python 3.11+ | Crawler ve eval |
| Supabase CLI | Lokal Supabase, migration'lar, Edge Function deploy (Deno'yu kendisi getirir) |
| Playwright Chromium | `playwright install chromium` ile kurulur, CI'da da aynı adım çalışır |
| Git + GitHub Actions | Repo ve günlük crawl cron'u |

### `crawler/requirements.txt`

| Paket | Ne için |
|---|---|
| `firecrawl-py` | Sayfa çekme ve temiz markdown, fiyat aramada search |
| `playwright` | Dinamik siteler için headless browser |
| `anthropic` | Claude: çıkarım, fiyat tahmini, dedup kararı |
| `supabase` | DB'ye yazma (service_role) |
| `pydantic` | Çıkarım JSON şeması ve doğrulama |
| `httpx` | Mapbox Geocoding ve RSS/API istekleri |
| `feedparser` | RSS kaynakları |
| `python-dotenv` | `.env` okuma |
| `tenacity` | Ağ hatalarında yeniden deneme |

### `eval/requirements.txt`

| Paket | Ne için |
|---|---|
| `-r ../crawler/requirements.txt` | Aynı pipeline'ı test etmek için |
| `pytest` | Test setlerini çalıştırma |
| `pandas` | Skor tabloları ve önce/sonra karşılaştırması |

### `app/pubspec.yaml`

| Paket | Ne için |
|---|---|
| `supabase_flutter` | Auth (e-posta, Google OAuth), DB, Edge Function çağrıları |
| `flutter_map` + `latlong2` | Harita (Mapbox tile ile, web dahil) |
| `flutter_map_marker_cluster` | Pin kümeleme |
| `geolocator` | "Near me" için cihaz konumu (saklanmaz) |
| `receive_sharing_intent` | Instagram'dan paylaşılan link/görseli alma |
| `image_picker` | Organizatör formu ve paylaşım için görsel seçme |
| `go_router` | Ekran yönlendirme |
| `flutter_riverpod` | State yönetimi |
| `intl` | Türkçe tarih/fiyat biçimi, `Europe/Istanbul` |
| `url_launcher` | Bilet/kaynak linklerini açma |
| `flutter_dotenv` | Mapbox public token gibi istemci ayarları |

### Supabase eklentileri ve Edge Functions

- Postgres eklentileri (migration ile açılır): `postgis`, `pg_trgm`
- Edge Functions (Deno/TypeScript): `nl-search`, `ingest-share`, `lookup-price`, `delete-account`. Anthropic ve Supabase istemcileri `npm:` import ile kullanılır, ayrı kurulum gerekmez.

### `.env.example` anahtarları

```
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=   # yalnızca crawler / Edge Functions
ANTHROPIC_API_KEY=
FIRECRAWL_API_KEY=
MAPBOX_PUBLIC_TOKEN=         # uygulama (tile)
MAPBOX_SECRET_TOKEN=         # crawler (geocoding)
```

---

## Stage 1: Kickoff

**Hedef:** Spec, kullanıcı akışı, repo, stack, backend ve auth planı.

- [ ] 1 sayfalık spec yaz: MVP must-have'ler ve Demo Day a/b/c kabul kriterleri.
- [ ] 3 kullanıcı akışı çiz: (1) haritada gez → filtrele → kaydet, (2) "near me tonight" sorgusu, (3) Instagram'dan paylaş → pin. Organizatör akışını da ekle: giriş → etkinlik gönder → yayın.
- [ ] **Kaynak listesi:** İzmir için 7–8 aday çıkar, en az 5'i kesinleşsin. Örnek adaylar: İzmir Büyükşehir Belediyesi kültür-sanat etkinlikleri, ilçe belediyeleri, AASSM, Devlet Tiyatroları ve Opera-Bale, bilet platformları (Biletix, Passo, Bubilet, Biletinial), üniversite etkinlik sayfaları. Her biri için tabloya şunları yaz: **API/RSS var mı, robots.txt, kullanım şartları, statik mi dinamik mi.**
- [ ] İlk ER diyagramı, Supabase projesi, GitHub repo, `.env.example`.
- [ ] Bağımlılık dosyalarını oluştur ve sürümleri sabitle: `crawler/requirements.txt`, `eval/requirements.txt`, `app/pubspec.yaml` (+ `pubspec.lock`). Bkz. [Bağımlılıklar](#bağımlılıklar).
- [ ] README'ye kurulum adımlarını yaz: `pip install -r crawler/requirements.txt`, `playwright install chromium`, `flutter pub get`, `supabase start`.
- [ ] Spending limit'leri **bugünden** ayarla: Anthropic, Firecrawl, Mapbox.

**Göster:** Spec, akış diyagramları, kaynak tablosu, boş ama çalışan repo, auth planı.

## Stage 2: Know your users

**Hedef:** En az 5 hedef kullanıcıyla görüşme.

- [ ] Karma bir grup seç: 3 etkinlik takipçisi (öğrenci ya da İzmir'e yeni gelmiş biri), en az 1 organizatör, en az 1 sık etkinliğe giden kişi.
- [ ] Sorular: Etkinlikleri şu an nereden buluyorlar? Instagram'ın payı ne? Fiyat bilgisi ne kadar önemli? "Tahmini fiyat" etiketine güvenirler mi? "Yakınımda bu akşam" ne anlama geliyor: kaç km, saat kaça kadar?
- [ ] Bulguları kategori listesine, varsayılan yarıçapa ve "tonight" tanımına yansıt.

**Göster:** Görüşme notları ve çıkarılan 5–7 karar.

## Stage 3: Foundations

**Hedef:** Backend, login ve veri modeli çalışır durumda.

**Şema (migration olarak):**

- `profiles`: role (`user`/`organizer`/`admin`), `kvkk_consent_at`
- `venues`: name, normalized_name, address, `location geography(Point,4326)`, GIST index
- `events`: title, description, starts_at, ends_at, venue_id, category, price_min/max, `price_status`, price_source_url, image_url, status (`pending`/`published`), created_by
- `event_sources`: event_id, source_id, url, external_id, content_hash (duplicate merge bu tabloya dayanır)
- `sources`, `crawl_runs` (sayaçlar, hatalar, token/maliyet), `saved_events`
- **RLS:** published etkinlikleri herkes okur. `saved_events` yalnızca sahibine açık. Organizatör yalnızca kendi `pending` kayıtlarını görür.
- RPC: `events_near(lat, lng, radius_m, from, to, categories[], max_price)`

**Yapılacaklar:**

- [x] Şema migration'ları ve RLS politikaları
- [x] Auth: e-posta ve Google girişi. Organizatör rolünü admin onaylar.
- [x] İlk açılışta KVKK aydınlatma metni ve açık rıza ekranı
- [x] Flutter: login, boş harita, `seed.sql` ile gelen sahte etkinliklerin pin olarak görünmesi

**Göster:** Canlı login, seed edilmiş pinler, RLS testi (başka kullanıcının kayıtlarına erişilemediğini göster).

## Stage 4: First flow

**Hedef:** **Tek** kaynak → çıkarım → DB → haritada pin, uçtan uca ve canlı.

- [x] En kolay kaynakla başla (tercihen belediye sayfası ya da RSS).
- [x] Pipeline: fetch → temiz markdown (Firecrawl) → Claude ile **structured output** (JSON şema: name, date, venue, address, price, category) → venue eşleştirme ve geocode → upsert.
- [x] `content_hash` değişmediyse Claude'u çağırma. Büyük maliyet tasarrufu buradan gelir.
- [x] GitHub Actions cron'u kur, her çalışma `crawl_runs` tablosuna loglansın.
- [x] İlk canlı koşu: canlı Supabase projesi (eu-west-1), secret'lar, AASSM dry-run ve ilk yazım (12 sayfa → 8 etkinlik). Cron haftalık: Cuma 06:17.

**Göster:** Cron tetiklenir, yeni etkinlik birkaç dakika içinde uygulamada pin olur.

## Stage 5: Core MVP

**Hedef:** Tüm must-have'ler çalışıyor. Midterm demo.

- [ ] **5+ kaynak:** Dinamik siteler için Playwright. Her kaynağın ayrı bir adapter dosyası olsun.
- [ ] **Fiyat ajanı:** Fiyat yoksa önce etkinliğin bilet/detay sayfasına gider, gerekirse Firecrawl search kullanır, bulursa `looked_up` ve kaynak URL'si yazar. Bulamazsa Claude aynı mekân, kategori ve benzer etkinliklerden bir aralık tahmin eder, `estimated` yazar. UI'da her zaman "Tahmini" rozeti gösterilir.
- [ ] **Duplicate merge:** Önce aday çiftler çıkarılır: aynı mekân ya da 200 m içinde (`ST_DWithin`), başlangıç saati ±2 saat, `pg_trgm` başlık benzerliği. Kesin eşleşmeler otomatik birleşir. Belirsiz olanlara Claude evet/hayır kararı verir. Kaynaklar `event_sources` altında toplanır.
- [ ] **Harita ve filtreler:** Tarih (bugün, bu hafta sonu), kategori, ücretsiz/fiyat, mesafe. Pin kümeleme (clustering) ve etkinlik detay kartı.
- [ ] **"Near me tonight":** `nl-search` Edge Function'ı. Claude soruyu `{categories, max_price, time_window, near_me, radius_m}` JSON'una çevirir, bu JSON `events_near` RPC'sine gider. Saat dilimi `Europe/Istanbul`. "Tonight" tanımı Stage 2 bulgularına göre konur.
- [ ] **Organizatör paneli** (etkinlik gönder, yayın için admin onayı) ve **kayıtlı etkinlikler**.

**Göster:** Midterm demosu, Demo Day a) ve b) senaryolarının ilk hali.

## Stage 6: AI quality

**Hedef:** Test setleri ve ölçülmüş sonuçlar (`eval/` klasörü, tekrar çalıştırılabilir script'ler).

| Test seti | Boyut | Metrik |
|---|---|---|
| Çıkarım (elle etiketlenmiş sayfalar) | ~50 sayfa | Alan bazlı doğruluk: ad, tarih, mekân, fiyat |
| Duplicate çiftleri | ~60 çift | Precision / recall |
| NL sorgular | 30–50 soru | Beklenen filtre JSON'uyla eşleşme oranı |
| Fiyat tahmini | Fiyatı bilinen ~30 etkinlik (fiyat gizlenerek) | Ortalama hata, aralığa düşme oranı |
| Geocoding | ~30 mekân | Metre cinsinden sapma |
| Instagram paylaşımı | 15–20 gönderi | Doğru pin oranı |

- [ ] Test setlerini hazırla ve `eval/run_eval.py` ile ölç.
- [ ] Prompt'ları iyileştir, önce/sonra skorlarını tabloya koy. Bu tablo haftalık rapordaki "işe yarayan ve yaramayan prompt'lar" bölümünün kanıtı olur.

**Göster:** Skor tablosu ve iyileştirme farkı.

## Stage 7: Beta

**Hedef:** 5 gerçek kullanıcı, bulgular ve düzeltmeler.

- [ ] **Share intent'i tamamla:** Paket olarak `receive_sharing_intent`. Demo için Android'e öncelik ver. iOS Share Extension zaman kalırsa yapılır.
- [ ] Akış: Instagram linki ve/veya görsel paylaşılır → `ingest-share` → Claude (görsel varsa vision ile afişi okur) → **önceden doldurulmuş onay formu** → geocode → pin.
- [ ] Görselde insan varsa görseli saklama, yalnızca çıkarılan metni tut (rıza kuralı).
- [ ] Beta kullanıcılarına görev listesi ver ve hataları kaydet.
- [ ] **Hesap silme** (`delete-account`) çalışıyor olsun.

**Göster:** Beta bulguları ve yapılan düzeltmeler. Demo Day c) senaryosu çalışıyor.

## Stage 8: Cross-testing

**Hedef:** Testing Agent ve diğer ekipler uygulamayı test eder.

- [ ] Hazırla: test hesapları (kullanıcı, organizatör, admin), APK/web linki, kısa test rehberi.
- [ ] Bulguları önceliklendir: kritik, orta, kozmetik. Kritikleri bu hafta kapat.

**Göster:** Gelen bulgular ve kapatılanlar.

## Stage 9: Polish

**Hedef:** Maliyet, güvenlik, dokümantasyon, demo provası.

- [ ] **Maliyet:** Günlük crawl için Batch API, sabit system prompt için prompt caching, çıkarımda ucuz model, yalnızca zor vakalarda güçlü model. `crawl_runs` tablosundan haftalık harcama raporu çıkar.
- [ ] **Güvenlik:** RLS denetimi, repoda secret taraması, Edge Function'larda rate limit, service_role anahtarı yalnızca worker'da.
- [ ] **Doküman:** README ve kurulum adımları, mimari diyagram, teknik rapor, eval raporu, maliyet raporu, kısa kullanıcı rehberi.
- [ ] Demo videosunu (2–3 dk) çek. Canlı demo aksarsa yedek olarak kullanılır.

## Stage 10: Demo Day

- [ ] **a)** Demodan bir gün önce crawl'u çalıştır. Bu hafta sonunun İzmir etkinlikleri haritada görünsün ve kaynak sayısını göster (5+).
- [ ] **b)** Uygulamaya "Bu akşam yakınımdaki ücretsiz konserler" yaz, sonuçlar haritada filtrelensin.
- [ ] **c)** Telefonda Instagram'dan bir gönderiyi paylaş → onayla → pin.
- [ ] Teslim: public link (Flutter web) ve APK, video, repo, doküman seti.

---

## Teslim edilecekler

**Her hafta: Google Drive raporu** (şablon aşağıda)

**Sonunda: ürün**

- [ ] Public linkte çalışan canlı ürün
- [ ] Yüksek kaliteli demo videosu (2–3 dk)
- [ ] README ve kurulum adımlarını içeren kod reposu
- [ ] `.env.example`, repoda secret yok
- [ ] Sürümleri sabitlenmiş `requirements.txt` ve `pubspec.lock`

**Sonunda: dokümantasyon**

- [ ] Detaylı teknik rapor
- [ ] Mimari diyagram
- [ ] Değerlendirme: test setleri ve kullanıcı testi bulguları
- [ ] Maliyet raporu: API ve hosting harcaması
- [ ] Kısa kullanıcı rehberi

## Haftalık Google Drive raporu şablonu

1. Yapılanlar ve gelecek hafta
2. Kullanılan sistemler/araçlar ve neden
3. İşe yarayan ve yaramayan prompt'lar (örnekleriyle)
4. Karşılaşılan hatalar ve nasıl çözüldükleri

## Riskler

| Risk | Önlem |
|---|---|
| Kaynak siteleri bozulabilir | Her kaynak için ayrı adapter. `crawl_runs` tablosundan hata alarmı. |
| Instagram linkinden caption alınamayabilir | Görsel/vision yolu ve kullanıcı onay formu her durumda çalışır. |
| Demo günü veri boş kalabilir | Crawl'u bir gün önce çalıştır, yedek video hazır olsun. |
| API maliyeti kontrolden çıkabilir | Her serviste spending limit, `content_hash` ile gereksiz çağrıları atlama, Batch API. |
