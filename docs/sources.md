# Stage 5 kaynakları

19 Kasım 2026'da herkese açık liste sayfaları HTTP ve gerçek Chromium ile kontrol edildi.
Beş adapter kayıtlıdır. Yeni dört kaynağı açan migration
`20261119000000_stage5_sources.sql` canlıya uygulanana kadar mevcut cron değişmez.
Bu kontrolde Claude, Firecrawl ve canlı veritabanı kullanılmadı; çıkarım, fiyat ve geocoding
sonuçları için ayrıca küçük bir `--dry-run` gerekir.

| Slug / liste | API/RSS ve yöntem | robots.txt | Kapsam |
|---|---|---|---|
| [aassm](https://www.aassm.org.tr/tr/EtkinlikTakvimi/Index) | HTTP liste → Firecrawl detay; açık API/RSS doğrulanmadı | Kural dosyası yerine HTML/404 | `/tr/Etkinlikler/Detay/<id>`; tek mekân |
| [biletinial](https://biletinial.com/tr-tr/SehrineOzel/izmir) | JS liste → Playwright → Firecrawl detay; açık API/RSS doğrulanmadı | Etkinlik yolları açık; `WebLogin` ve `kino` yasak | Yalnızca şehir listesindeki kartlar; sinema film sayfaları hariç; çok şehirli detaylarda yalnızca İzmir gösterimleri çıkarılır |
| [bornova](https://bornova.bel.tr/etkinlikler) | JS liste → Playwright → Firecrawl detay; açık API/RSS doğrulanmadı | `/services/` ve `/api/` yasak; herkese açık `/etkinlikler` sayfası okunur | `#loadEvents .event-container`; haber menüsü ve geçmiş sekmesi okunmaz; site içi servis doğrudan çağrılmaz |
| [karsiyaka](https://www.karsiyaka.bel.tr/etkinlikler) | HTTP liste → Firecrawl detay; açık API/RSS doğrulanmadı | Kontrolde okunabildi; listeye engel yok | Yalnızca `#nav-1`; `#nav-2` arşivi dışarıda kalır; güncel bölüm boşsa 0 sonuç geçerlidir |
| [izmirkultur](https://izmirkultursanatfabrikasi.gov.tr/tr/etkinlikler) | Sunucuda çizilen HTML → HTTP liste → Firecrawl detay; açık API/RSS doğrulanmadı | `/tr/robots.txt` 404 | UUID'li detaylar; dil öneki tekilleştirilir; yerleşke tek mekân olarak kullanılır |

Kullanım/politika sayfaları: [Biletinial](https://biletinial.com/tr-tr/sayfa/sozlesme-ve-politikalar),
[Bornova](https://bornova.bel.tr/kvkk-ve-bilgi-guevenligi),
[Kültür Sanat Fabrikası](https://izmirkultursanatfabrikasi.gov.tr/tr/kvkk).
Bu sayfalar açık veri lisansı olarak yorumlanmaz. Kaynak detay URL'si `event_sources.url`
altında korunur. Fabrika'nın varsayılan adresi [resmi iletişim sayfasından](https://izmirkultursanatfabrikasi.gov.tr/tr/hakkimizda/iletisim) alınır.

## Canlı liste kontrolü

```bash
python -m playwright install chromium
python -m crawler.run --discover --source aassm --source biletinial --source bornova --source karsiyaka --source izmirkultur --limit 3
```

`--discover` anahtar gerektirmez; yalnızca listeyi açıp detay URL'lerini JSON olarak yazar.
`--limit` kaynak başına döndürülen URL sayısını sınırlar. JS listelerde önce yüklenen
kart grubu daha büyük olabilir; en fazla 10 kez "daha fazla" tıklanır. Alan adı, detay yolu,
fragment ve kampanya parametreleri süzülür; aynı sayfa iki kimlikle işlenmez.

İlk kontrolde dönen sayılar: AASSM **3**, Biletinial **3**, Bornova **2**,
Karşıyaka **0**, Fabrika **3** (kaynak başına limit **3**). Bu sayılar etkinlik/adet veya
veritabanına yazım sayısı değildir. Karşıyaka'nın güncel takvimi o anda boştu.

Anahtarlar tanımlandıktan sonra çıkarım hattını DB'ye yazmadan denemek için:

```bash
python -m crawler.run --source biletinial --dry-run --limit 1
python -m crawler.run --source bornova --dry-run --limit 1
python -m crawler.run --source izmirkultur --dry-run --limit 1
```

`--dry-run` Firecrawl/Claude kredisi harcayabilir; `--discover` bu servisleri çağırmaz.
Normal koşu, görülmüş URL'leri detay isteğinden önce atlar. `--refresh` bunları yeniden
çeker; içerik hash'i aynıysa Claude yine çağrılmaz.
Detay isteği hataları `crawl_runs.error_log` ve `errors` alanlarına gider. Tüm yeni
detaylar alınamazsa kaynak fatal olur ve komut hata koduyla çıkar; diğer kaynaklar devam eder.

## Kapalı kalan adaylar

| Kaynak | Son kontrol / karar |
|---|---|
| [İzmir Kültürsanat açık veri API](https://acikveri.bizizmir.com/tr/dataset/kultur-sanat-etkinlikleri) | Resmi API önceliği araştırıldı. Katalogdaki `acikveriwapi.izmir.bel.tr` ve eski `openapi.izmir.bel.tr` adresleri bu ortamda DNS hatası verdi. Erişim ve güncel yanıt şeması doğrulanamadığı için adapter eklenmedi. |
| [Devlet Tiyatroları](https://www.devtiyatro.gov.tr/) | Güncel ana sayfa yapısı değişmiş; İzmir gösterim listesi doğrulanamadı. `/api/` robots tarafından yasak. |
| [Passo](https://www.passo.com.tr/tr) | HTTP 403; erişim engeli aşılmadı. |

## Tekrarlanabilir test

```bash
python -m pytest crawler -q
supabase test db
```

`crawler/tests/fixtures/` gerçek sayfalardaki DOM yapısını örnekleyen küçük sentetik
HTML'ler içerir. Chromium testleri yerel HTTP sunucusunda JS yüklenmesini, sayfalamayı,
haber/film/arşiv ayrımını ve hata yanıtlarını doğrular; dış ağ veya anahtar kullanmaz.
`sources_test.sql` migration ve seed sonrasında beş adapter kaynağının açık olduğunu kontrol eder.

19 Kasım yerel doğrulaması: **50 crawler/Chromium testi** ve **32 pgTAP testi** geçti.
Supabase temiz yerel veritabanında tüm migration'ları ve seed'i başarıyla uyguladı.
