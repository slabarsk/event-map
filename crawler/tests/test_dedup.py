"""Duplicate merge (Stage 5) birim testleri: otomatik eşleşme, Claude kararı,
alan zenginleştirme, pipeline entegrasyonu ve geriye dönük --dedup taraması."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest

from crawler import db, pipeline, run
from crawler.dedup import DedupAgent, SameEvent, enrich_patch
from crawler.models import NormalizedEvent
from crawler.tests.test_pipeline import SOURCE, FakeAdapter, FakeDb, _claude_returning, _extracted

NEXT_WEEK = datetime.now(timezone(timedelta(hours=3))) + timedelta(days=7)


class FakeDedupClaude:
    def __init__(self, answers=()):
        self.answers = list(answers)
        self.calls: list[str] = []
        self.messages = self

    def parse(self, *, model, max_tokens, system, messages, output_format):
        assert output_format is SameEvent
        self.calls.append(messages[0]["content"])
        same = self.answers.pop(0) if self.answers else False
        return SimpleNamespace(
            parsed_output=SameEvent(same_event=same, reasoning="test kararı"),
            stop_reason="end_turn",
            usage=SimpleNamespace(input_tokens=15, output_tokens=5),
        )


def _event(
    title="İzmir Devlet Senfoni Orkestrası Konseri",
    price_min=250.0,
    price_max=450.0,
    price_status="listed",
    description="Senfonik konser",
    ticket_url="https://bilet.example/1",
):
    return NormalizedEvent(
        title=title,
        description=description,
        starts_at=NEXT_WEEK,
        ends_at=None,
        venue_name="Ahmet Adnan Saygun Sanat Merkezi",
        address=None,
        category="concert",
        price_min=price_min,
        price_max=price_max,
        price_status=price_status,
        ticket_url=ticket_url,
    )


@pytest.fixture
def fake(monkeypatch):
    f = FakeDb()
    f.install(monkeypatch)
    monkeypatch.delenv("MAPBOX_SECRET_TOKEN", raising=False)
    return f


def test_yuksek_benzerlikte_claude_cagrilmadan_otomatik_birlesir():
    claude = FakeDedupClaude(answers=[False])
    candidates = [
        {
            "id": "ev-existing",
            "title": "İzmir Devlet Senfoni Orkestrası Konseri",
            "starts_at": NEXT_WEEK.isoformat(),
            "venue_id": "venue-aassm",
            "title_sim": 0.92,
            "distance_m": 0.0,
            "same_venue": True,
        }
    ]
    agent = DedupAgent(claude, candidates_fn=lambda *a: candidates)
    dup_id, kind = agent.find_duplicate(_event(), "venue-aassm")

    assert (dup_id, kind) == ("ev-existing", "auto")
    assert claude.calls == []
    assert agent.usage.input_tokens == 0


def test_belirsiz_benzerlikte_claude_evet_derse_birlesir():
    claude = FakeDedupClaude(answers=[True])
    candidates = [
        {
            "id": "ev-existing",
            "title": "İDSO: Beethoven 5. Senfoni Gecesi",
            "starts_at": NEXT_WEEK.isoformat(),
            "venue_id": "venue-aassm",
            "title_sim": 0.38,
            "distance_m": 45.0,
            "same_venue": False,
        }
    ]
    agent = DedupAgent(claude, candidates_fn=lambda *a: candidates)
    dup_id, kind = agent.find_duplicate(_event(), "venue-aassm")

    assert (dup_id, kind) == ("ev-existing", "claude")
    assert len(claude.calls) == 1
    assert "İDSO: Beethoven 5. Senfoni Gecesi" in claude.calls[0]
    assert agent.usage.input_tokens == 15


def test_belirsiz_benzerlikte_claude_hayir_derse_ayri_kalir():
    claude = FakeDedupClaude(answers=[False])
    candidates = [
        {
            "id": "ev-other",
            "title": "Başka Bir Oda Müziği Dinletisi",
            "starts_at": NEXT_WEEK.isoformat(),
            "venue_id": "venue-aassm",
            "title_sim": 0.30,
            "distance_m": 0.0,
            "same_venue": True,
        }
    ]
    agent = DedupAgent(claude, candidates_fn=lambda *a: candidates)
    dup_id, kind = agent.find_duplicate(_event(), "venue-aassm")

    assert (dup_id, kind) == (None, "none")
    assert len(claude.calls) == 1


def test_ayni_baslik_cifti_icin_claude_ikinci_kez_cagrilmaz():
    claude = FakeDedupClaude(answers=[True])
    candidates = [
        {
            "id": "ev-1",
            "title": "İDSO Konseri",
            "starts_at": NEXT_WEEK.isoformat(),
            "venue_id": "venue-aassm",
            "title_sim": 0.40,
        }
    ]
    agent = DedupAgent(claude, candidates_fn=lambda *a: candidates)
    agent.find_duplicate(_event(), "venue-aassm")
    agent.find_duplicate(_event(), "venue-aassm")

    assert len(claude.calls) == 1


def test_enrich_patch_eksik_alanlari_ve_daha_guvenilir_fiyati_tamamlar():
    existing = {
        "id": "ev-1",
        "title": "Senfoni Konseri",
        "description": None,
        "ticket_url": None,
        "image_url": "https://mevcut.example/img.jpg",
        "price_min": 200.0,
        "price_max": 400.0,
        "price_status": "estimated",
        "price_source_url": None,
        "requires_registration": False,
    }
    ev = _event(
        description="Yeni açıklama",
        ticket_url="https://biletinial.com/tr-tr/muzik/senfoni",
        price_min=250.0,
        price_max=450.0,
        price_status="listed",
    )
    patch = enrich_patch(existing, ev)

    assert patch["description"] == "Yeni açıklama"
    assert patch["ticket_url"] == "https://biletinial.com/tr-tr/muzik/senfoni"
    assert "image_url" not in patch  # mevcut görsel korunur
    assert (patch["price_min"], patch["price_max"], patch["price_status"]) == (250.0, 450.0, "listed")


def test_enrich_patch_listed_fiyati_estimated_ile_ezmez():
    existing = {
        "id": "ev-1",
        "description": "Mevcut",
        "ticket_url": "https://mevcut.example/bilet",
        "image_url": "https://mevcut.example/img.jpg",
        "price_min": 300.0,
        "price_max": 300.0,
        "price_status": "listed",
        "price_source_url": None,
    }
    ev = _event(price_min=150.0, price_max=350.0, price_status="estimated")
    assert enrich_patch(existing, ev) == {}


def test_pipeline_farkli_kaynaktan_gelen_ayni_etkinligi_birlestirir(fake, monkeypatch):
    # 1. kaynak (AASSM): tahmini fiyatlı ve bilet linksiz etkinlik yazar.
    _claude_returning(
        monkeypatch,
        lambda item: [
            _extracted(title="Senfoni Konseri").model_copy(
                update={"description": None, "ticket_url": None, "price_min": 200, "price_max": 400}
            )
        ],
    )
    pipeline.run_source({"id": "src-aassm", "slug": "aassm"}, FakeAdapter([("u1", "sayfa 1")]), claude=None)
    assert len(fake.events) == 1
    fake.events["ev-1"]["price_status"] = "estimated"

    # 2. kaynak (Biletinial): aynı etkinliği listed fiyat ve bilet linkiyle getirir.
    fake.candidates = [
        {
            "id": "ev-1",
            "title": "Senfoni Konseri",
            "starts_at": NEXT_WEEK.isoformat(),
            "venue_id": "venue-aassm",
            "title_sim": 1.0,
            "distance_m": 0.0,
            "same_venue": True,
        }
    ]
    _claude_returning(
        monkeypatch,
        lambda item: [
            _extracted(title="Senfoni Konseri").model_copy(
                update={
                    "description": "Detaylı açıklama",
                    "ticket_url": "https://biletinial.com/senfoni",
                    "price_min": 250,
                    "price_max": 500,
                }
            )
        ],
    )
    stats = pipeline.run_source(
        {"id": "src-bilet", "slug": "biletinial"}, FakeAdapter([("u2", "sayfa 2")]), claude=None
    )

    assert stats.events_upserted == 1 and stats.events_merged == 1
    assert len(fake.events) == 1  # yeni etkinlik satırı açılmadı
    ev = fake.events["ev-1"]
    assert ev["description"] == "Detaylı açıklama"
    assert ev["ticket_url"] == "https://biletinial.com/senfoni"
    assert (ev["price_min"], ev["price_max"], ev["price_status"]) == (250, 500, "listed")
    # İki kaynağın da event_sources kaydı aynı event_id altında toplandı.
    source_event_ids = {r["event_id"] for r in fake.event_sources.values()}
    assert len(fake.event_sources) == 2 and source_event_ids == {"ev-1"}


def test_dedup_existing_events_mevcut_ciftleri_birlestirir(fake):
    fake.events["ev-1"] = {
        "title": "Senfoni Konseri",
        "starts_at": NEXT_WEEK.isoformat(),
        "venue_id": "venue-aassm",
        "category": "concert",
        "price_min": 200,
        "price_max": 400,
        "price_status": "estimated",
    }
    fake.events["ev-2"] = {
        "title": "Senfoni Konseri - İDSO",
        "starts_at": NEXT_WEEK.isoformat(),
        "venue_id": "venue-aassm",
        "category": "concert",
        "price_min": 250,
        "price_max": 450,
        "price_status": "listed",
    }
    fake.candidates = [
        {
            "id": "ev-2",
            "title": "Senfoni Konseri - İDSO",
            "starts_at": NEXT_WEEK.isoformat(),
            "venue_id": "venue-aassm",
            "title_sim": 0.45,
        }
    ]
    claude = FakeDedupClaude(answers=[True])
    agent = DedupAgent(claude)
    stats = pipeline.dedup_existing_events(claude, dedup_agent=agent)

    assert stats.events_merged == 1
    assert fake.merged_pairs == [("ev-2", "ev-1")]
    assert "ev-1" not in fake.events and "ev-2" in fake.events


def _senfoni_pair(fake, ev1_extra=None, ev2_extra=None):
    base = {
        "starts_at": NEXT_WEEK.isoformat(),
        "venue_id": "venue-aassm",
        "category": "concert",
        "price_min": 200,
        "price_max": 400,
        "price_status": "listed",
    }
    fake.events["ev-1"] = {**base, "title": "Senfoni Konseri", **(ev1_extra or {})}
    fake.events["ev-2"] = {**base, "title": "Senfoni Konseri - İDSO", **(ev2_extra or {})}
    fake.candidates = [
        {"id": "ev-2", "title": "Senfoni Konseri - İDSO", "starts_at": NEXT_WEEK.isoformat(),
         "venue_id": "venue-aassm", "title_sim": 0.45},
    ]


def test_dedup_existing_events_organizator_kaydini_silmez(fake):
    # ev-1 (taranan, silinecek taraf) organizatöre ait: SQL yer değiştirir, ev-2 silinir.
    _senfoni_pair(fake, ev1_extra={"origin": "organizer", "created_by": "user-1"})
    claude = FakeDedupClaude(answers=[True])
    stats = pipeline.dedup_existing_events(claude, dedup_agent=DedupAgent(claude))

    assert stats.events_merged == 1
    assert fake.merged_pairs == [("ev-1", "ev-2")]
    assert "ev-1" in fake.events and "ev-2" not in fake.events


def test_dedup_existing_events_iki_organizator_kaydini_birlestirmez(fake):
    _senfoni_pair(fake, ev1_extra={"origin": "organizer"}, ev2_extra={"created_by": "user-2"})
    claude = FakeDedupClaude(answers=[True])
    stats = pipeline.dedup_existing_events(claude, dedup_agent=DedupAgent(claude))

    assert stats.events_found == 1 and stats.events_merged == 0
    assert fake.merged_pairs == []
    assert {"ev-1", "ev-2"} <= set(fake.events)


def test_cli_dedup_bayragi_discover_ve_price_backfill_ile_cakismaz():
    with pytest.raises(SystemExit) as exc:
        run.main(["--discover", "--source", "bornova", "--dedup"])
    assert exc.value.code == 2

    with pytest.raises(SystemExit) as exc:
        run.main(["--price-backfill", "--limit", "5", "--dedup"])
    assert exc.value.code == 2
