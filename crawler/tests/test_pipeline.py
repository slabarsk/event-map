"""Pipeline'ın DB ve Claude olmadan testi: db modülü bellek içi sahteyle değiştirilir."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from crawler import db, pipeline
from crawler.models import ExtractedEvent, RawItem, Usage
from crawler.sources.base import SourceAdapter

SOURCE = {"id": "src-1", "slug": "aassm"}
# normalize() yalnızca önümüzdeki bir yıl içindeki etkinlikleri kabul eder.
NEXT_WEEK = (datetime.now(timezone(timedelta(hours=3))) + timedelta(days=7)).isoformat()


class FakeDb:
    def __init__(self):
        self.seen: dict[tuple, str] = {}
        self.events: dict[str, dict] = {}
        self.event_sources: dict[tuple, dict] = {}
        self.runs: dict[str, dict] = {}
        self.venues = {"ahmet adnan saygun sanat merkezi": "venue-aassm"}

    def install(self, monkeypatch):
        monkeypatch.setattr(db, "start_run", self.start_run)
        monkeypatch.setattr(db, "finish_run", self.finish_run)
        monkeypatch.setattr(db, "seen_hash", lambda s, e: self.seen.get((s, e)))
        monkeypatch.setattr(db, "touch_seen", lambda s, e: None)
        monkeypatch.setattr(db, "seen_ids", lambda s: {e for (src, e) in self.seen if src == s})
        monkeypatch.setattr(db, "mark_seen", lambda s, e, h, n: self.seen.__setitem__((s, e), h))
        monkeypatch.setattr(db, "event_id_for_source", self.event_id_for_source)
        monkeypatch.setattr(db, "insert_event", self.insert_event)
        monkeypatch.setattr(db, "update_event", lambda i, row: self.events[i].update(row))
        monkeypatch.setattr(db, "upsert_event_source", self.upsert_event_source)
        monkeypatch.setattr(db, "match_venue", lambda name: self.venues.get(name.lower()))
        monkeypatch.setattr(db, "get_event", lambda i: self.events.get(i))
        monkeypatch.setattr(db, "find_event_candidates", self.find_event_candidates)
        monkeypatch.setattr(db, "merge_events", self.merge_events)
        monkeypatch.setattr(db, "upcoming_published_events", self.upcoming_published_events)
        self.candidates: list[dict] = []
        self.merged_pairs: list[tuple[str, str]] = []

    def start_run(self, source_id):
        self.runs["run-1"] = {"source_id": source_id}
        return "run-1"

    def finish_run(self, run_id, **fields):
        self.runs[run_id].update(fields)

    def event_id_for_source(self, s, e, idx):
        row = self.event_sources.get((s, e, idx))
        return row["event_id"] if row else None

    def insert_event(self, row):
        eid = f"ev-{len(self.events) + 1}"
        self.events[eid] = dict(row)
        return eid

    def upsert_event_source(self, row):
        self.event_sources[(row["source_id"], row["external_id"], row["idx"])] = row

    def find_event_candidates(self, title, starts_at, venue_id, exclude_id=None):
        return [c for c in self.candidates if c["id"] != exclude_id]

    def merge_events(self, keep_id, drop_id):
        """SQL merge_events gibi: organizatör kaydı silinmez, silinen id döner."""
        def is_org(eid):
            ev = self.events.get(eid) or {}
            return ev.get("origin") == "organizer" or ev.get("created_by") is not None

        if is_org(keep_id) and is_org(drop_id):
            return None
        if is_org(drop_id):
            keep_id, drop_id = drop_id, keep_id
        self.merged_pairs.append((keep_id, drop_id))
        for row in self.event_sources.values():
            if row["event_id"] == drop_id:
                row["event_id"] = keep_id
        self.events.pop(drop_id, None)
        return drop_id

    def upcoming_published_events(self, limit=200):
        return [{"id": k, "venue": {"name": "Ahmet Adnan Saygun Sanat Merkezi"}, **v}
                for k, v in list(self.events.items())[:limit]]


class FakeAdapter(SourceAdapter):
    slug = "aassm"

    def __init__(self, pages):
        self.pages = pages

    def fetch(self):
        for url, text in self.pages:
            yield RawItem(url=url, external_id=url, text=text,
                          hint={"default_venue": "Ahmet Adnan Saygun Sanat Merkezi"})


def _extracted(title="Senfoni Konseri", venue=None):
    return ExtractedEvent(
        title=title, description=None, starts_at=NEXT_WEEK, ends_at=None,
        venue_name=venue, address=None, category="concert", price_min=250, price_max=450,
        is_free=None, ticket_url=None, image_url=None, in_izmir=True, requires_registration=False,
    )


@pytest.fixture
def fake(monkeypatch):
    f = FakeDb()
    f.install(monkeypatch)
    monkeypatch.delenv("MAPBOX_SECRET_TOKEN", raising=False)
    return f


def _claude_returning(monkeypatch, events_per_call):
    calls = []

    def fake_extract(client, item):
        calls.append(item.url)
        return events_per_call(item), Usage(input_tokens=100, output_tokens=20)

    monkeypatch.setattr(pipeline, "extract_events", fake_extract)
    return calls


def test_uctan_uca_yazar_ve_crawl_runs_loglar(fake, monkeypatch):
    calls = _claude_returning(monkeypatch, lambda item: [_extracted()])
    stats = pipeline.run_source(SOURCE, FakeAdapter([("u1", "sayfa 1")]), claude=None)

    assert stats.events_upserted == 1 and stats.errors == 0
    assert len(calls) == 1
    (ev,) = fake.events.values()
    assert ev["status"] == "published" and ev["venue_id"] == "venue-aassm"
    assert ev["price_min"] == 250 and ev["price_status"] == "listed"
    run = fake.runs["run-1"]
    assert run["events_upserted"] == 1 and run["tokens_input"] == 100


def test_icerik_degismediyse_claude_cagrilmaz(fake, monkeypatch):
    calls = _claude_returning(monkeypatch, lambda item: [_extracted()])
    pipeline.run_source(SOURCE, FakeAdapter([("u1", "aynı")]), claude=None)
    stats = pipeline.run_source(SOURCE, FakeAdapter([("u1", "aynı")]), claude=None)

    assert len(calls) == 1
    assert stats.items_skipped == 1 and stats.usage.input_tokens == 0


def test_sayfa_degisince_ayni_kayit_guncellenir(fake, monkeypatch):
    titles = iter(["Eski Başlık", "Yeni Başlık"])
    _claude_returning(monkeypatch, lambda item: [_extracted(title=next(titles))])
    pipeline.run_source(SOURCE, FakeAdapter([("u1", "v1")]), claude=None)
    pipeline.run_source(SOURCE, FakeAdapter([("u1", "v2")]), claude=None)

    assert len(fake.events) == 1
    assert next(iter(fake.events.values()))["title"] == "Yeni Başlık"


def test_mekan_bulunamazsa_hata_loglanir_ve_sayfa_tekrar_denenir(fake, monkeypatch):
    calls = _claude_returning(monkeypatch, lambda item: [_extracted(venue="Bilinmeyen Bar")])
    stats = pipeline.run_source(SOURCE, FakeAdapter([("u1", "x")]), claude=None)

    assert stats.errors == 1 and stats.events_upserted == 0
    assert "Bilinmeyen Bar" in stats.error_log[0]["error"]
    pipeline.run_source(SOURCE, FakeAdapter([("u1", "x")]), claude=None)
    assert len(calls) == 2  # görüldü işaretlenmedi


def test_adapter_cokerse_kosu_fatal_olur(fake, monkeypatch):
    class Broken(SourceAdapter):
        slug = "aassm"

        def fetch(self):
            raise ConnectionError("site kapalı")
            yield  # noqa

    stats = pipeline.run_source(SOURCE, Broken(), claude=None)
    assert stats.fatal and fake.runs["run-1"]["errors"] == 1


def test_daha_once_islenen_sayfa_yeniden_cekilmez(fake, monkeypatch):
    from crawler.sources import base

    scraped = []

    def fake_scrape(mode, url, wait_ms=3000):
        if url == "liste":
            return "", ["d/1", "d/2", "d/3"]
        scraped.append(url)
        return f"sayfa {url}", []

    monkeypatch.setattr(base, "_scrape", fake_scrape)
    monkeypatch.setattr(base.fetchers, "polite_sleep", lambda: None)

    class Listing(base.ListingAdapter):
        slug = "aassm"
        listing_urls = ["liste"]
        link_pattern = r"^d/"
        hint = {"default_venue": "Ahmet Adnan Saygun Sanat Merkezi"}

    _claude_returning(monkeypatch, lambda item: [_extracted()])
    pipeline.run_source(SOURCE, Listing(), claude=None, limit=2)
    assert scraped == ["d/1", "d/2"]  # --limit

    scraped.clear()
    stats = pipeline.run_source(SOURCE, Listing(), claude=None)
    assert scraped == ["d/3"]  # görülenler Firecrawl'a gitmez
    assert stats.items_skipped == 2

    scraped.clear()
    pipeline.run_source(SOURCE, Listing(), claude=None, refresh=True)
    assert scraped == ["d/1", "d/2", "d/3"]
