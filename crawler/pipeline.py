"""Bir kaynağın uçtan uca işlenmesi (Stage 4: first flow).

fetch -> içerik hash'i değişmediyse atla (Claude çağrılmaz) -> Claude ile çıkarım
-> doğrulama -> mekân eşleştirme / geocode -> upsert (events + event_sources)
-> crawl_runs kaydı.

Stage 5'te eklenecekler: fiyat ajanı (price/) ve kaynaklar arası duplicate merge (dedup/).
O zamana kadar fiyatı olmayan etkinlik fiyatsız yazılır.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any

import anthropic

from . import db
from .config import PRICE_IN_PER_MTOK, PRICE_OUT_PER_MTOK
from .extract import extract_events, normalize
from .geocode import resolve_venue
from .models import NormalizedEvent, RawItem, Usage
from .sources.base import SourceAdapter

log = logging.getLogger(__name__)


@dataclass
class RunStats:
    items_fetched: int = 0
    items_skipped: int = 0
    events_found: int = 0
    events_upserted: int = 0
    errors: int = 0
    error_log: list[dict[str, str]] = field(default_factory=list)
    usage: Usage = field(default_factory=Usage)
    fatal: bool = False

    def error(self, where: str, exc: Exception) -> None:
        self.errors += 1
        if len(self.error_log) < 50:
            self.error_log.append({"where": where, "error": f"{type(exc).__name__}: {exc}"[:500]})
        log.error("%s: %s", where, exc)

    def cost_usd(self) -> float | None:
        if PRICE_IN_PER_MTOK is None or PRICE_OUT_PER_MTOK is None:
            return None
        return round(
            self.usage.input_tokens / 1e6 * PRICE_IN_PER_MTOK
            + self.usage.output_tokens / 1e6 * PRICE_OUT_PER_MTOK,
            4,
        )


def run_source(
    source: dict[str, Any],
    adapter: SourceAdapter,
    claude: anthropic.Anthropic,
    *,
    dry_run: bool = False,
) -> RunStats:
    stats = RunStats()
    run_id = None if dry_run else db.start_run(source["id"])
    try:
        for item in adapter.fetch():
            stats.items_fetched += 1
            try:
                _process_item(source, item, claude, stats, dry_run)
            except Exception as exc:  # tek öğe hatası koşuyu durdurmaz
                stats.error(item.url, exc)
    except Exception as exc:  # adapter tümden bozuldu (site değişti, engellendi...)
        stats.fatal = True
        stats.error(f"adapter:{source['slug']}", exc)
    finally:
        if run_id:
            db.finish_run(
                run_id,
                items_fetched=stats.items_fetched,
                items_skipped=stats.items_skipped,
                events_found=stats.events_found,
                events_upserted=stats.events_upserted,
                errors=stats.errors,
                error_log=stats.error_log,
                tokens_input=stats.usage.input_tokens,
                tokens_output=stats.usage.output_tokens,
                cost_usd=stats.cost_usd(),
            )
    return stats


def _process_item(
    source: dict[str, Any], item: RawItem, claude: anthropic.Anthropic, stats: RunStats, dry_run: bool
) -> None:
    chash = db.content_hash(item.text)
    if not dry_run and db.seen_hash(source["id"], item.external_id) == chash:
        db.touch_seen(source["id"], item.external_id)
        stats.items_skipped += 1  # içerik değişmedi: Claude çağrılmaz
        return

    extracted, usage = extract_events(claude, item)
    stats.usage.add(usage)
    stats.events_found += len(extracted)

    item_failed = False
    for idx, raw in enumerate(extracted):
        ev = normalize(raw, item)
        if ev is None:
            continue
        if dry_run:
            print(ev.model_dump_json(indent=2))
            continue
        try:
            _store_event(source, item, idx, ev, chash)
            stats.events_upserted += 1
        except Exception as exc:
            item_failed = True
            stats.error(f"{item.url}#{idx}", exc)

    # Hatalı öğeyi "görüldü" işaretleme: bir sonraki koşuda yeniden denensin.
    if not dry_run and not item_failed:
        db.mark_seen(source["id"], item.external_id, chash, len(extracted))


def event_row(ev: NormalizedEvent, venue_id: str) -> dict[str, Any]:
    return {
        "title": ev.title,
        "description": ev.description,
        "starts_at": ev.starts_at.isoformat(),
        "ends_at": ev.ends_at.isoformat() if ev.ends_at else None,
        "venue_id": venue_id,
        "category": ev.category,
        "price_min": ev.price_min,
        "price_max": ev.price_max,
        "price_status": ev.price_status,
        "price_source_url": ev.price_source_url,
        "ticket_url": ev.ticket_url,
        "image_url": ev.image_url,
    }


def _store_event(source: dict[str, Any], item: RawItem, idx: int, ev: NormalizedEvent, chash: str) -> None:
    venue_id = resolve_venue(ev.venue_name, ev.address)
    if venue_id is None:
        raise RuntimeError(f"mekân konumu çözülemedi: {ev.venue_name}")

    row = event_row(ev, venue_id)
    event_id = db.event_id_for_source(source["id"], item.external_id, idx)
    if event_id:
        db.update_event(event_id, row)  # sayfa değişti: aynı kaydı güncelle
    else:
        # Crawl edilen etkinlik doğrudan yayınlanır; organizatör gönderileri pending başlar.
        event_id = db.insert_event({**row, "status": "published", "origin": "crawl"})

    db.upsert_event_source(
        {
            "event_id": event_id,
            "source_id": source["id"],
            "url": item.url,
            "external_id": item.external_id,
            "idx": idx,
            "content_hash": chash,
            "last_seen_at": db.now_iso(),
        }
    )
