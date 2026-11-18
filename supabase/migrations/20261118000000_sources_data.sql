-- Kaynak listesi: crawler yalnızca enabled = true ve adapter'ı olan kaynakları çalıştırır.
-- Canlı veritabanına seed gitmediği için kaynaklar migration ile eklenir.
-- seed.sql'deki aynı insert 'on conflict do nothing' ile çakışmaz.
insert into public.sources (slug, name, type, base_url, enabled, notes) values
  ('aassm',          'AASSM',                    'firecrawl',  'https://www.aassm.org.tr',         true,  'Statik HTML; detay linkleri /tr/Etkinlikler/Detay/<id>'),
  ('kultursanat',    'İzmir Kültürsanat',        'playwright', 'https://kultursanat.izmir.bel.tr', false, 'React SPA, tarayıcı gerekir'),
  ('biletinial',     'Biletinial',               'firecrawl',  'https://biletinial.com',           false, 'robots.txt: yalnızca WebLogin ve kino yasak'),
  ('devtiyatro',     'Devlet Tiyatroları İzmir', 'firecrawl',  'https://devtiyatro.gov.tr',        false, 'robots.txt: /api/ yasak'),
  ('passo',          'Passo',                    'playwright', 'https://www.passo.com.tr',         false, 'Açmadan önce kullanım şartları kontrol edilmeli'),
  ('user-share',     'Kullanıcı paylaşımı',      'user',       null,                               true,  'Kullanıcı onaylı paylaşımlar (Stage 7)'),
  ('organizer-form', 'Organizatör formu',        'organizer',  null,                               true,  'Organizatör paneli (Stage 5)')
on conflict (slug) do nothing;
