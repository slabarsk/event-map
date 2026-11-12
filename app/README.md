# app/

Event Map'in Flutter uygulaması (Android, iOS, web).

## Çalıştırma

**Demo modu** (Supabase gerekmez, hesaplar yalnızca bu cihazda saklanır):

```bash
flutter pub get
flutter run -d chrome
```

**Supabase ile:**

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://<proje>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable-key>
```

Önce `supabase/migrations/` altındaki migration'ları uygulayın (`profiles` tablosu, RLS, rol fonksiyonları).

## Akış

```
Karşılama → Kullanıcı / Organizatör seçimi
  → Giriş · Kayıt (e-posta, Google) + KVKK açık rızası
  → 3 adımlı onboarding (role göre farklı)
  → Özet → Ana sayfa  ya da  Profil ayarları → Ana sayfa
```

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
    profile/     profil ve ayarlar
```

## Kontroller

```bash
flutter analyze
flutter test
```
