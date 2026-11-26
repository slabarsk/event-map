"""Kaynak kapsamı, kimlik kararlılığı, limit/cache ve hata izolasyonu (ağ/AI yok)."""
from pathlib import Path

import pytest

from crawler import db, pipeline, run
from crawler.sources import ADAPTERS, get_adapter
from crawler.sources import base, fetchers
from crawler.sources.biletinial import BiletinialAdapter
from crawler.sources.bornova import BornovaAdapter
from crawler.sources.izmirkultur import IzmirKulturAdapter
from crawler.sources.karsiyaka import KarsiyakaAdapter
from crawler.tests.test_pipeline import FakeDb, SOURCE, _claude_returning, _extracted

FIXTURES = Path(__file__).parent / "fixtures"


def test_bes_kaynak_kaydi_ayri_ornekler_uretir():
    assert set(ADAPTERS) == {"aassm", "biletinial", "bornova", "karsiyaka", "izmirkultur"}
    assert get_adapter("biletinial") is not get_adapter("biletinial")


def test_karsiyaka_arsiv_ve_menu_icin_detay_cagrisi_yapmaz(monkeypatch):
    monkeypatch.setattr(fetchers, "http_get", lambda url: (FIXTURES / "karsiyaka.html").read_text(encoding="utf-8"))
    assert KarsiyakaAdapter().discover_urls() == ["https://www.karsiyaka.bel.tr/yeni-konser"]


def test_bos_guncel_bolum_gecerli_kayip_bolum_hata(monkeypatch):
    monkeypatch.setattr(fetchers, "http_get", lambda url: '<div id="nav-1"></div><div id="nav-2"><a href="/eski">Eski</a></div>')
    assert KarsiyakaAdapter().discover_urls() == []
    monkeypatch.setattr(fetchers, "http_get", lambda url: '<html>Site bakımdadır</html>')
    with pytest.raises(RuntimeError, match="bölümü bulunamadı"):
        KarsiyakaAdapter().discover_urls()


def test_fabrika_dil_ve_kampanya_linkleri_tek_kimlik_olur(monkeypatch):
    html = (FIXTURES / "izmirkultur.html").read_text(encoding="utf-8")
    monkeypatch.setattr(base, "_scrape", lambda mode, url: (html, fetchers.html_links(html, url)))
    assert IzmirKulturAdapter().discover_urls() == [
        "https://izmirkultursanatfabrikasi.gov.tr/tr/etkinlikler/tum-etkinlikler/4e782d0b-339d-4d71-ab47-f5ad9b5821d8"
    ]


def test_biletinial_sehir_kartlarinda_sinema_kino_mekan_ve_harici_linkler_elenir(monkeypatch):
    monkeypatch.setattr(fetchers, "playwright_listing", lambda *a, **kw: [
        "https://biletinial.com/tr-tr/tiyatro/oyun?utm_source=site#seans",
        "https://biletinial.com/tr-tr/tiyatro/oyun/",
        "https://biletinial.com/tr-tr/muzik/konser",
        "https://biletinial.com/tr-tr/sinema/film",
        "https://biletinial.com/tr-tr/kino/film",
        "https://biletinial.com/tr-tr/WebLogin/MyProfile",
        "https://biletinial.com/tr-tr/mekan/sahne",
        "https://biletinial.com.evil.test/tr-tr/tiyatro/oyun",
    ])
    assert BiletinialAdapter().discover_urls() == [
        "https://biletinial.com/tr-tr/tiyatro/oyun", "https://biletinial.com/tr-tr/muzik/konser",
    ]


def test_cache_detay_kredisi_harcamaz_ve_limit_yeni_sayfalara_uygulanir(monkeypatch):
    adapter = BornovaAdapter()
    urls = ["https://bornova.bel.tr/" + name for name in ("goruldu", "yeni", "sonraki")]
    adapter.skip_ids = frozenset(urls[:1])
    adapter.max_items = 1
    calls = []
    monkeypatch.setattr(fetchers, "playwright_listing", lambda *a, **kw: urls)
    monkeypatch.setattr(base, "_scrape", lambda mode, url: (calls.append(url) or "Etkinlik metni", []))
    monkeypatch.setattr(fetchers, "polite_sleep", lambda: None)
    (item,) = list(adapter.fetch())
    assert calls == [urls[1]]
    assert adapter.skipped == 1
    assert item.external_id == urls[1]
    assert item.hint["detail_page"] and item.hint["only_city"] == "İzmir"


@pytest.mark.parametrize("all_fail", [False, True])
@pytest.mark.parametrize("failure", ["network", "empty"])
def test_detay_hatasi_loglanir_diger_ogeler_devam_eder(monkeypatch, all_fail, failure):
    fake = FakeDb()
    fake.install(monkeypatch)
    monkeypatch.delenv("MAPBOX_SECRET_TOKEN", raising=False)
    _claude_returning(monkeypatch, lambda item: [_extracted(venue="Ahmet Adnan Saygun Sanat Merkezi")])
    adapter = BornovaAdapter()
    monkeypatch.setattr(adapter, "discover_urls", lambda: ["https://bornova.bel.tr/bozuk", "https://bornova.bel.tr/iyi"])
    monkeypatch.setattr(fetchers, "polite_sleep", lambda: None)

    def scrape(mode, url):
        if all_fail or url.endswith("bozuk"):
            if failure == "empty":
                return "  \n", []
            raise ConnectionError("site hatası")
        return "etkinlik", []

    monkeypatch.setattr(base, "_scrape", scrape)
    stats = pipeline.run_source(SOURCE, adapter, claude=None)
    assert stats.errors == (2 if all_fail else 1)
    assert stats.events_upserted == (0 if all_fail else 1)
    assert stats.fatal is all_fail
    assert fake.runs["run-1"]["errors"] == stats.errors
    assert (SOURCE["id"], "https://bornova.bel.tr/bozuk") not in fake.seen


def test_discover_anahtarsiz_db_ve_ai_kullanmadan_calisir(monkeypatch, capsys):
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.setattr(BornovaAdapter, "discover_urls", lambda self: ["https://bornova.bel.tr/etkinlik"])
    monkeypatch.setattr(db, "enabled_sources", lambda: pytest.fail("DB çağrılmamalı"))
    monkeypatch.setattr(run.anthropic, "Anthropic", lambda **kw: pytest.fail("Claude çağrılmamalı"))
    assert run.main(["--discover", "--source", "bornova"]) == 0
    assert '"count": 1' in capsys.readouterr().out


def test_discover_bozuk_kaynakta_digerlerini_dener_ve_hata_kodu_verir(monkeypatch, capsys):
    monkeypatch.setattr(BornovaAdapter, "discover_urls", lambda self: (_ for _ in ()).throw(ConnectionError("kapalı")))
    monkeypatch.setattr(KarsiyakaAdapter, "discover_urls", lambda self: [])
    assert run.main(["--discover", "--source", "bornova", "--source", "karsiyaka"]) == 1
    assert '"source": "karsiyaka"' in capsys.readouterr().out


@pytest.mark.parametrize("args", [
    ["--discover"], ["--discover", "--source", "yok"],
    ["--discover", "--source", "bornova", "--limit", "0"],
    ["--source", "bornova", "--limit", "-2"],
    ["--discover", "--source", "bornova", "--price-backfill"],
])
def test_gecersiz_cli_api_cagrisindan_once_reddedilir(args):
    with pytest.raises(SystemExit) as exc:
        run.main(args)
    assert exc.value.code == 2
