# app/

Event Map'in Flutter uygulaması (Android, iOS, web).

## Çalıştırma

Gerekli sürüm: Flutter **3.50.0** stable veya üstü (Dart 3.14). Daha eski SDK'larda `flutter pub get` çözümlenmez.

**Demo modu** (Supabase gerekmez, hesaplar yalnızca bu cihazda saklanır, haritada `supabase/seed.sql` ile aynı örnek etkinlikler görünür):

```bash
flutter pub get
flutter run -d chrome
```

**Supabase ile:**

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://<proje>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable-key> \
  --dart-define=MAPBOX_PUBLIC_TOKEN=<pk.…>
```

Önce `supabase/migrations/` altındaki migration'ları uygulayın (`profiles`, etkinlik şeması, RLS, `events_near`). Lokalde `supabase db reset` migration'larla birlikte `supabase/seed.sql`'i de yükler; haritada demo moddakiyle aynı etkinlikler görünür. `events_near` projede yoksa harita başlığında "Etkinlik verisi henüz hazır değil" yazar.

`MAPBOX_PUBLIC_TOKEN` verilmezse harita geliştirme için OpenStreetMap tile'larını kullanır. OSM'nin kullanım politikası yoğun trafiğe izin vermediği için yayında (web linki, APK) token verilmelidir.

## Akış

```
Karşılama → Kullanıcı / Organizatör seçimi
  → Giriş · Kayıt (e-posta, Google) + KVKK açık rızası
  → 3 adımlı onboarding (role göre farklı)
  → Özet → Ana sayfa  ya da  Profil ayarları → Ana sayfa
Alt menü: Ana sayfa · Harita · Profil
```

**Harita:** Yaklaşan yayınlanmış etkinlikler mekân başına tek pin olarak gösterilir. Pin rengi mekândaki ilk etkinliğin kategorisinden gelir, birden çok etkinlik varsa adet rozeti çıkar. Pine dokununca mekândaki etkinlikler tarih (İzmir saati), fiyat ve fiyat rozetiyle listelenir: `estimated` her zaman **Tahmini**, `looked_up` **Bilet sayfasından** olarak etiketlenir. Bilet yerine başvuru formu ya da ön kayıtla katılınan etkinliklerde **Başvuru ile** etiketi çıkar; bunlara fiyat tahmini yapılmaz.

| Rol | Onboarding adımları |
|---|---|
| Kullanıcı | İlgi alanları · Bölge ve mesafe · Bütçe ve bildirimler |
| Organizatör | Organizasyon bilgisi · Kategoriler ve bağlantılar · İletişim ve onay süreci |

Organizatör hesapları `pending` durumunda başlar; onaylanana kadar etkinlik gönderemez.

## Yapı

```
lib/
  core/        tema, renkler, router, katalog (kategoriler, ilçeler), ortak bileşenler
  features/
    auth/        model, repository (Supabase + demo), giriş/kayıt/KVKK ekranları
    onboarding/  3 adımlı akış ve tekrar kullanılan tercih seçicileri
    home/        kullanıcı ana sayfası, organizatör paneli
    events/      etkinlik modeli, events_near repository (Supabase + demo), mekân sayfası
    map/         flutter_map ekranı ve mekân pinleri
    profile/     profil ve ayarlar
```

## Kontroller

```bash
flutter analyze
flutter test
```
