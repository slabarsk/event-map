from datetime import datetime, timedelta, timezone

from crawler.extract import normalize
from crawler.models import ExtractedEvent, RawItem

NOW = datetime(2026, 11, 13, 9, 0, tzinfo=timezone.utc)
ITEM = RawItem(
    url="https://www.aassm.org.tr/tr/Etkinlikler/Detay/1",
    external_id="x",
    text="...",
    hint={"default_venue": "Ahmet Adnan Saygun Sanat Merkezi", "default_address": "Konak/İzmir"},
)


def _ev(**kw) -> ExtractedEvent:
    base = dict(
        title="Senfoni Konseri", description=None, starts_at="2026-11-14T20:00:00+03:00",
        ends_at=None, venue_name=None, address=None, category="concert", price_min=None,
        price_max=None, is_free=None, ticket_url=None, image_url=None, in_izmir=True, requires_registration=False,
    )
    return ExtractedEvent(**{**base, **kw})


def test_adapter_ipucundan_mekan_doldurulur():
    ev = normalize(_ev(), ITEM, now=NOW)
    assert ev is not None
    assert ev.venue_name == "Ahmet Adnan Saygun Sanat Merkezi"
    assert ev.address == "Konak/İzmir"
    assert ev.starts_at.utcoffset() == timedelta(hours=3)


def test_ucretsiz_sifir_fiyat_olur():
    ev = normalize(_ev(is_free=True), ITEM, now=NOW)
    assert (ev.price_min, ev.price_max, ev.price_status) == (0, 0, "listed")


def test_tek_fiyat_iki_uca_yazilir_ve_ters_aralik_duzelir():
    assert normalize(_ev(price_max=300), ITEM, now=NOW).price_min == 300
    ev = normalize(_ev(price_min=500, price_max=200), ITEM, now=NOW)
    assert (ev.price_min, ev.price_max) == (200, 500)


def test_fiyat_yoksa_bos_kalir():
    ev = normalize(_ev(), ITEM, now=NOW)
    assert ev.price_min is None and ev.price_max is None


def test_izmir_disi_tarihsiz_ve_gecmis_etkinlikler_atlanir():
    assert normalize(_ev(in_izmir=False), ITEM, now=NOW) is None
    assert normalize(_ev(starts_at=None), ITEM, now=NOW) is None
    assert normalize(_ev(starts_at="2026-10-01T20:00:00+03:00"), ITEM, now=NOW) is None
    assert normalize(_ev(starts_at="tarih değil"), ITEM, now=NOW) is None


def test_saat_dilimi_yoksa_istanbul_kabul_edilir():
    ev = normalize(_ev(starts_at="2026-11-14T20:00:00"), ITEM, now=NOW)
    assert ev.starts_at == datetime(2026, 11, 14, 17, 0, tzinfo=timezone.utc)


def test_bitis_baslangictan_onceyse_atilir():
    ev = normalize(_ev(ends_at="2026-11-14T18:00:00+03:00"), ITEM, now=NOW)
    assert ev.ends_at is None


def test_tek_mekanli_kaynakta_salon_adi_mekan_acmaz():
    item = ITEM.model_copy(update={"hint": {**ITEM.hint, "single_venue": True}})
    ev = normalize(_ev(venue_name="AASSM Büyük Salon", address="Salon girişi"), item, now=NOW)
    assert ev.venue_name == "Ahmet Adnan Saygun Sanat Merkezi"
    assert ev.address == "Konak/İzmir"


def test_suren_sergi_kalir_bitmis_etkinlik_elenir():
    suren = _ev(category="exhibition", starts_at="2026-10-15T16:00:00+03:00", ends_at="2026-11-30T18:00:00+03:00")
    assert normalize(suren, ITEM, now=NOW) is not None
    bitmis = _ev(starts_at="2026-11-06T20:00:00+03:00")
    assert normalize(bitmis, ITEM, now=NOW) is None
