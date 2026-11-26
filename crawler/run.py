"""Günlük crawl giriş noktası.

Kullanım (repo kökünden):
    python -m crawler.run                       # etkinleştirilmiş tüm kaynaklar
    python -m crawler.run --source aassm        # tek kaynak
    python -m crawler.run --source aassm --dry-run --limit 2   # DB'ye yazmadan, 2 sayfayla dene
    python -m crawler.run --refresh             # daha önce işlenmiş sayfaları da yeniden çek
    python -m crawler.run --discover --source bornova --limit 3  # anahtarsız liste keşfi
    python -m crawler.run --price-backfill --limit 5   # fiyatı bilinmeyen eski etkinliklere fiyat ajanı
"""
from __future__ import annotations

import argparse
import json
import logging
import sys

import anthropic

from . import db
from .config import env
from .pipeline import backfill_prices, dedup_existing_events, run_source
from .sources import ADAPTERS, get_adapter
from .sources.base import ListingAdapter


def positive_int(value: str) -> int:
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("sıfırdan büyük olmalı")
    return number


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Event Map crawler")
    ap.add_argument("--source", action="append", help="kaynak slug'ı (tekrarlanabilir); verilmezse hepsi")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="DB'ye yazma, çıkarılan etkinlikleri yazdır (API ücreti olabilir)")
    mode.add_argument("--discover", action="store_true", help="yalnızca detay URL'lerini bul; DB, Claude ve Firecrawl kullanma")
    ap.add_argument("--limit", type=positive_int, help="kaynak başına en fazla bu kadar yeni sayfa çek (maliyet testi)")
    ap.add_argument("--refresh", action="store_true", help="daha önce işlenmiş sayfaları da yeniden çek")
    ap.add_argument("--price-backfill", action="store_true",
                    help="crawl etmeden, fiyatı bilinmeyen yaklaşan etkinliklere fiyat ajanını çalıştır (--limit ile)")
    ap.add_argument("--dedup", action="store_true",
                    help="veritabanındaki yaklaşan etkinlikler arasında duplicate birleştirmeyi çalıştır (--limit ile)")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args(argv)

    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    unknown = set(args.source or []) - ADAPTERS.keys()
    if unknown:
        ap.error(f"adapter yok: {', '.join(sorted(unknown))}")

    if args.discover:
        if not args.source or args.price_backfill or args.dedup:
            ap.error("--discover için --source verin; --price-backfill veya --dedup ile kullanılamaz")
        failed = 0
        for slug in dict.fromkeys(args.source):
            adapter = get_adapter(slug)
            if args.limit is not None:
                adapter.max_items = args.limit
            try:
                if not isinstance(adapter, ListingAdapter):
                    raise ValueError(f"{slug}: liste keşfi desteklenmiyor")
                urls = adapter.discover_urls()[:adapter.max_items]
                print(json.dumps({"source": slug, "urls": urls, "count": len(urls)}, ensure_ascii=False))
            except Exception:
                logging.exception("%s: liste keşfi başarısız", slug)
                failed += 1
        return 1 if failed else 0

    if args.price_backfill and args.dedup:
        ap.error("--price-backfill ve --dedup birlikte kullanılamaz")

    if args.dedup:
        claude = anthropic.Anthropic(api_key=env("ANTHROPIC_API_KEY", required=True))
        stats = dedup_existing_events(claude, limit=args.limit or 200, dry_run=args.dry_run)
        logging.info(
            "dedup: taranan=%d eşleşen=%d birleştirilen=%d hata=%d token=%d/%d",
            stats.items_fetched, stats.events_found, stats.events_merged, stats.errors,
            stats.usage.input_tokens, stats.usage.output_tokens,
        )
        return 0

    if args.price_backfill:
        if args.limit is None:
            ap.error("--price-backfill için --limit verin (maliyet koruması)")
        claude = anthropic.Anthropic(api_key=env("ANTHROPIC_API_KEY", required=True))
        stats = backfill_prices(claude, limit=args.limit, dry_run=args.dry_run)
        logging.info(
            "fiyat: etkinlik=%d fiyatlanan=%d yazılan=%d hata=%d token=%d/%d",
            stats.items_fetched, stats.events_found, stats.events_upserted, stats.errors,
            stats.usage.input_tokens, stats.usage.output_tokens,
        )
        return 0

    if args.dry_run:
        sources = [{"id": "dry", "slug": s} for s in (args.source or [])]
        if not sources:
            ap.error("--dry-run için --source verin")
    else:
        sources = db.enabled_sources()
        if args.source:
            sources = [s for s in sources if s["slug"] in args.source]
            missing = set(args.source) - {s["slug"] for s in sources}
            if missing:
                ap.error(f"bulunamadı ya da kapalı: {', '.join(sorted(missing))}")

    claude = anthropic.Anthropic(api_key=env("ANTHROPIC_API_KEY", required=True))
    failed = 0
    for source in sources:
        if source["slug"] not in ADAPTERS:
            logging.warning("%s: adapter yok, atlandı", source["slug"])
            continue
        logging.info("== %s", source["slug"])
        stats = run_source(source, get_adapter(source["slug"]), claude, dry_run=args.dry_run, limit=args.limit, refresh=args.refresh)
        logging.info(
            "%s: öğe=%d atlanan=%d bulunan=%d yazılan=%d birleşen=%d hata=%d token=%d/%d",
            source["slug"], stats.items_fetched, stats.items_skipped, stats.events_found,
            stats.events_upserted, stats.events_merged, stats.errors,
            stats.usage.input_tokens, stats.usage.output_tokens,
        )
        failed += stats.fatal

    # Bir kaynağın tümden bozulması CI'ı kırmızı yapar (alarm). Öğe bazlı hatalar yapmaz.
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
