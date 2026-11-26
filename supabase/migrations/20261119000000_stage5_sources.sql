-- Stage 5: erişimi doğrulanmış beş kaynak. Eski adaylardan API'sine ulaşılamayan
-- kultursanat, değişen devtiyatro ve erişimi engelleyen passo kapalı kalır.
-- Canlıya migration uygulanana kadar cron yalnızca mevcut açık kaynakları kullanır.
insert into public.sources (slug, name, type, base_url, enabled, notes) values
  ('biletinial', 'Biletinial İzmir', 'playwright', 'https://biletinial.com', true,
   'İzmir şehir listesi Playwright; sadece etkinlik kartları, sinema hariç. Detay Firecrawl, yalnızca İzmir seansları.'),
  ('bornova', 'Bornova Belediyesi', 'playwright', 'https://bornova.bel.tr', true,
   'Güncel Etkinlikler sekmesi (#loadEvents); site API/services uçları doğrudan çağrılmaz. Detay Firecrawl.'),
  ('karsiyaka', 'Karşıyaka Belediyesi', 'firecrawl', 'https://www.karsiyaka.bel.tr', true,
   'HTTP takviminde yalnızca #nav-1 (güncel) okunur; #nav-2 arşivi alınmaz. Detay Firecrawl.'),
  ('izmirkultur', 'İzmir Kültür Sanat Fabrikası', 'firecrawl', 'https://izmirkultursanatfabrikasi.gov.tr', true,
   'Sunucuda çizilen güncel takvim; /tr/etkinlikler/tum-etkinlikler/<uuid> detayları Firecrawl.')
on conflict (slug) do update set
  name = excluded.name, type = excluded.type, base_url = excluded.base_url,
  enabled = excluded.enabled, notes = excluded.notes;
