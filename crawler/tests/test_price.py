"""Fiyat ajanı testleri: Claude, Firecrawl ve DB sahteleriyle (ağ yok)."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest

from crawler import db, pipeline
from crawler.extract import normalize
from crawler.models import NormalizedEvent, RawItem
from crawler.price import PriceAgent
from crawler.price.agent import PriceEstimate, PriceFinding
from crawler.sources import fetchers
from crawler.tests.test_pipeline import SOURCE, FakeAdapter, FakeDb, _claude_returning, _extracted

NEXT_WEEK = datetime.now(timezone(timedelta(hours=3))) + timedelta(days=7)
TICKET = "https://biletinial.com/tr-tr/muzik/senfoni"


class FakeClaude:
    """messages.parse çağrılarını kaydeder; şemaya göre sıradaki cevabı döndürür."""

    def __init__(self, finds=(), estimate=None):
        self.finds = list(finds)
        self.estimate = estimate
        self.calls: list[dict] = []
        self.messages = self

    def parse(self, *, model, max_tokens, system, messages, output_format):
        self.calls.append({"schema": output_format, "user": messages[0]["content"]})
        if output_format is PriceFinding:
            out = self.finds.pop(0) if self.finds else _not_found()
        else:
            out = self.estimate
        return SimpleNamespace(parsed_output=out, stop_reason="end_turn",
                               usage=SimpleNamespace(input_tokens=10, output_tokens=5))


def _found(lo, hi=None, idx=0, free=False):
    return PriceFinding(found=True, is_free=free, price_min=lo, price_max=hi, source_index=idx, evidence="x")


def _not_found():
    return PriceFinding(found=False, is_free=None, price_min=None, price_max=None, source_index=None, evidence=None)


def _event(title="Senfoni Konseri", ticket=TICKET, start=NEXT_WEEK):
    return NormalizedEvent(
        title=title, description=None, starts_at=start, ends_at=None,
        venue_name="Ahmet Adnan Saygun Sanat Merkezi", address=None, category="concert",
        price_min=None, price_max=None, price_status="unknown", ticket_url=ticket,
    )


@pytest.fixture
def web(monkeypatch):
    """Sahte Firecrawl: scrape edilen ve aranan her şeyi kaydeder."""
    w = SimpleNamespace(pages={}, results=[], scraped=[], searches=[])

    def scrape(url):
        w.scraped.append(url)
        if url not in w.pages:
            raise fetchers.RobotsDisallowed(url)
        return w.pages[url], []

    def search(query, limit=3):
        w.searches.append(query)
        return w.results

    monkeypatch.setattr(fetchers, "firecrawl_scrape", scrape)
    monkeypatch.setattr(fetchers, "firecrawl_search", search)
    return w


# ---------------------------------------------------------------- normalize


def test_fiyatsiz_etkinlik_listed_degil_unknown():
    item = RawItem(url="u", external_id="u", text="", hint={"default_venue": "AASSM"})
    no_price = _extracted().model_copy(update={"price_min": None, "price_max": None})
    free = _extracted().model_copy(update={"price_min": None, "price_max": None, "is_free": True})

    assert normalize(no_price, item).price_status == "unknown"
    assert normalize(_extracted(), item).price_status == "listed"
    ev = normalize(free, item)
    assert (ev.price_status, ev.price_min) == ("listed", 0.0)


# ---------------------------------------------------------------- akış


def test_bilet_sayfasinda_bulursa_looked_up_ve_kaynak_url(web):
    web.pages[TICKET] = "Bilet: 250 TL / Öğrenci 150 TL"
    claude = FakeClaude(finds=[_found(150, 250)])
    ev = PriceAgent(claude, similar=lambda v, c: []).fill(_event())

    assert (ev.price_status, ev.price_min, ev.price_max) == ("looked_up", 150, 250)
    assert ev.price_source_url == TICKET
    assert web.searches == []  # bilet sayfası yetti: arama yapılmaz
    assert "250 TL" in claude.calls[0]["user"]


def test_bilet_sayfasinda_yoksa_firecrawl_search(web):
    web.pages[TICKET] = "Satışta değil"
    web.pages["https://kultursanat.izmir.bel.tr/e/1"] = "Senfoni Konseri — 300 TL"
    web.results = [(TICKET, "zaten denendi"), ("https://kultursanat.izmir.bel.tr/e/1", "özet")]
    claude = FakeClaude(finds=[_not_found(), _found(300)])
    ev = PriceAgent(claude, similar=lambda v, c: []).fill(_event())

    assert ev.price_status == "looked_up"
    assert (ev.price_min, ev.price_max) == (300, 300)
    assert ev.price_source_url == "https://kultursanat.izmir.bel.tr/e/1"
    assert web.scraped.count(TICKET) == 1  # denenen sayfa yeniden çekilmez
    assert "Senfoni Konseri" in web.searches[0] and "İzmir" in web.searches[0]


def test_ucretsiz_bulunursa_sifir(web):
    web.pages[TICKET] = "Giriş serbesttir"
    ev = PriceAgent(FakeClaude(finds=[_found(None, free=True)]), similar=lambda v, c: []).fill(_event())
    assert (ev.price_status, ev.price_min, ev.price_max) == ("looked_up", 0, 0)


def test_bulamazsa_benzer_etkinliklerden_tahmin(web):
    seen = {}

    def similar(venue, category):
        seen["args"] = (venue, category)
        return [{"title": "Oda Müziği", "category": "concert", "venue": venue, "price_min": 200, "price_max": 400}]

    claude = FakeClaude(estimate=PriceEstimate(price_min=400, price_max=200, reasoning="aynı salon"))
    ev = PriceAgent(claude, search=False, similar=similar).fill(_event(ticket=None))

    assert (ev.price_status, ev.price_min, ev.price_max) == ("estimated", 200, 400)  # sıra düzeltilir
    assert ev.price_source_url is None
    assert seen["args"] == ("Ahmet Adnan Saygun Sanat Merkezi", "concert")
    assert "Oda Müziği" in claude.calls[-1]["user"]
    assert web.scraped == [] and web.searches == []


def test_ayni_etkinligin_farkli_tarihleri_bir_kez_aranir(web):
    web.pages[TICKET] = "200 TL"
    claude = FakeClaude(finds=[_found(200)])
    agent = PriceAgent(claude, similar=lambda v, c: [])
    a = agent.fill(_event())
    b = agent.fill(_event(start=NEXT_WEEK + timedelta(days=1)))

    assert a.price_min == b.price_min == 200
    assert len(claude.calls) == 1 and web.scraped == [TICKET]
    assert agent.usage.input_tokens == 10


def test_fiyati_olan_etkinlige_dokunmaz(web):
    claude = FakeClaude()
    ev = _event().model_copy(update={"price_min": 100.0, "price_max": 100.0, "price_status": "listed"})
    assert PriceAgent(claude).fill(ev) is ev
    assert claude.calls == []


# ---------------------------------------------------------------- pipeline


@pytest.fixture
def fake(monkeypatch):
    f = FakeDb()
    f.install(monkeypatch)
    monkeypatch.delenv("MAPBOX_SECRET_TOKEN", raising=False)
    return f


def _no_price(**kw):
    return _extracted().model_copy(update={"price_min": None, "price_max": None, "ticket_url": TICKET, **kw})


def test_pipeline_fiyatsiz_etkinligi_ajanla_yazar(fake, monkeypatch, web):
    web.pages[TICKET] = "350 TL"
    _claude_returning(monkeypatch, lambda item: [_no_price()])
    agent = PriceAgent(FakeClaude(finds=[_found(350)]), similar=lambda v, c: [])
    stats = pipeline.run_source(SOURCE, FakeAdapter([("u1", "sayfa")]), claude=None, price_agent=agent)

    (ev,) = fake.events.values()
    assert ev["price_status"] == "looked_up" and ev["price_min"] == 350
    assert ev["price_source_url"] == TICKET
    assert stats.usage.input_tokens == 100 + 10  # çıkarım + fiyat ajanı
    assert fake.runs["run-1"]["tokens_input"] == 110


def test_pipeline_ajan_hatasi_etkinligi_dusurmez(fake, monkeypatch):
    class Broken(PriceAgent):
        def fill(self, ev, *, page_url=None):
            raise RuntimeError("Firecrawl kotası doldu")

    _claude_returning(monkeypatch, lambda item: [_no_price()])
    stats = pipeline.run_source(SOURCE, FakeAdapter([("u1", "sayfa")]), claude=None, price_agent=Broken(None))

    (ev,) = fake.events.values()
    assert ev["price_status"] == "unknown" and ev["price_min"] is None
    assert stats.events_upserted == 1 and stats.errors == 1
    assert ("src-1", "u1") in fake.seen  # fiyat hatası sayfayı yeniden crawl ettirmez


def test_backfill_eski_fiyatsiz_etkinlikleri_gunceller(fake, monkeypatch, web):
    fake.events["ev-9"] = {"title": "Senfoni Konseri", "price_status": "unknown"}
    rows = [{
        "id": "ev-9", "title": "Senfoni Konseri", "description": None,
        "starts_at": NEXT_WEEK.isoformat(), "ends_at": None, "category": "concert",
        "ticket_url": None, "venue": {"name": "Ahmet Adnan Saygun Sanat Merkezi", "address": None},
    }]
    monkeypatch.setattr(db, "unknown_price_events", lambda limit: rows[:limit])
    agent = PriceAgent(FakeClaude(estimate=PriceEstimate(price_min=150, price_max=300, reasoning="r")),
                       search=False, similar=lambda v, c: [])
    stats = pipeline.backfill_prices(None, limit=5, price_agent=agent)

    assert stats.events_upserted == 1
    ev = fake.events["ev-9"]
    assert (ev["price_status"], ev["price_min"], ev["price_max"]) == ("estimated", 150, 300)
