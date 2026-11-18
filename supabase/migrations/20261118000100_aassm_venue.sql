-- AASSM'in konumu sabit: adresi geocode etmek yanlış sonuç veriyordu (Alsancak'a düşüyordu).
-- Kaynak: Wikipedia, 38°23'49"N 27°04'42"E. Crawler önce DB'deki mekânı eşleştirdiği için
-- bu satır varken Mapbox'a hiç gidilmez.
insert into public.venues (name, normalized_name, address, location)
values (
  'Ahmet Adnan Saygun Sanat Merkezi',
  public.normalize_text('Ahmet Adnan Saygun Sanat Merkezi'),
  'Mehmet Ali Akman Mah., Mithatpaşa Cad. No:1087, Konak/İzmir',
  extensions.st_setsrid(extensions.st_makepoint(27.07833, 38.39694), 4326)::extensions.geography
)
on conflict (normalized_name) do update
  set address = excluded.address,
      location = excluded.location;
