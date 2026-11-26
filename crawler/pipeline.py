"""Bir kaynağın uçtan uca işlenmesi.

fetch -> içerik hash'i değişmediyse atla (Claude çağrılmaz) -> Claude ile çıkarım
-> doğrulama -> fiyat yoksa fiyat ajanı (price/) -> mekân eşleştirme / geocode
-> upsert (events + event_sources) -> crawl_runs kaydı.

Stage 5'te eklenecek: kaynaklar arası duplicate merge (dedup/).
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
from .price import PriceAgent
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
    limit: int | None = None,
    refresh: bool = False,
    price_agent: PriceAgent | None = None,
) -> RunStats:
    stats = RunStats()
    prices = price_agent or PriceAgent(claude)
    adapter.skipped = 0
    adapter.fetch_errors = ()
    adapter.skip_ids = frozenset()
    run_id = None if dry_run else db.start_run(source["id"])
    if limit is not None:
        adapter.max_items = limit
    if not dry_run and not refresh:
        adapter.skip_ids = frozenset(db.seen_ids(source["id"]))
    try:
        for item in adapter.fetch():
            stats.items_fetched += 1
            try:
                _process_item(source, item, claude, stats, dry_run, prices)
            except Exception as exc:  # tek öğe hatası koşuyu durdurmaz
                stats.error(item.url, exc)
    except Exception as exc:  # adapter tümden bozuldu (site değişti, engellendi...)
        stats.fatal = True
        stats.error(f"adapter:{source['slug']}", exc)
    finally:
        for url, exc in adapter.fetch_errors:
            stats.error(url, exc)
        if adapter.fetch_errors and stats.items_fetched == 0:
            stats.fatal = True
        stats.items_skipped += adapter.skipped
        stats.usage.add(prices.usage)
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
    source: dict[str, Any], item: RawItem, claude: anthropic.Anthropic, stats: RunStats, dry_run: bool,
    prices: PriceAgent,
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
        if ev is None:  # geçmiş/tarihsiz/İzmir dışı: yazılmaz
            log.info("elendi: %s | %s | izmir=%s", raw.title, raw.starts_at, raw.in_izmir)
            continue
        ev = _fill_price(prices, ev, item.url, stats)
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


def _fill_price(prices: PriceAgent, ev: NormalizedEvent, page_url: str | None, stats: RunStats) -> NormalizedEvent:
    """Fiyat ajanı hatası etkinliği düşürmez: fiyat bilinmiyor olarak yazılır."""
    try:
        return prices.fill(ev, page_url=page_url)
    except Exception as exc:
        stats.error(f"fiyat:{ev.title}", exc)
        return ev


def backfill_prices(claude: anthropic.Anthropic, *, limit: int, dry_run: bool = False,
                    price_agent: PriceAgent | None = None) -> RunStats:
    """Daha önce fiyatsız yazılmış yaklaşan etkinlikler için fiyat ajanını çalıştırır.
    Bu sayfalar seen_items'ta olduğu için normal crawl onları yeniden işlemez."""
    stats = RunStats()
    prices = price_agent or PriceAgent(claude)
    for row in db.unknown_price_events(limit):
        stats.items_fetched += 1
        venue = row.get("venue") or {}
        ev = NormalizedEvent(
            title=row["title"], description=row.get("description"),
            starts_at=row["starts_at"], ends_at=row.get("ends_at"),
            venue_name=venue.get("name") or "", address=venue.get("address"),
            category=row["category"], price_min=None, price_max=None,
            ticket_url=row.get("ticket_url"),
            requires_registration=bool(row.get("requires_registration")),
        )
        ev = _fill_price(prices, ev, None, stats)
        if ev.price_status == "unknown":
            continue
        stats.events_found += 1
        if dry_run:
            print(ev.model_dump_json(indent=2))
            continue
        try:
            db.update_event(row["id"], {
                "price_min": ev.price_min, "price_max": ev.price_max,
                "price_status": ev.price_status, "price_source_url": ev.price_source_url,
            })
            stats.events_upserted += 1
        except Exception as exc:
            stats.error(f"fiyat-yaz:{row['id']}", exc)
    stats.usage.add(prices.usage)
    return stats


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
        "requires_registration": ev.requires_registration,
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
