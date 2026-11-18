"""Günlük crawl giriş noktası.

Kullanım (repo kökünden):
    python -m crawler.run                       # etkinleştirilmiş tüm kaynaklar
    python -m crawler.run --source aassm        # tek kaynak
    python -m crawler.run --source aassm --dry-run --limit 2   # DB'ye yazmadan, 2 sayfayla dene
    python -m crawler.run --refresh             # daha önce işlenmiş sayfaları da yeniden çek
"""
from __future__ import annotations

import argparse
import logging
import sys

import anthropic

from . import db
from .config import env
from .pipeline import run_source
from .sources import ADAPTERS, get_adapter


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Event Map crawler")
    ap.add_argument("--source", action="append", help="kaynak slug'ı (tekrarlanabilir); verilmezse hepsi")
    ap.add_argument("--dry-run", action="store_true", help="DB'ye yazma, çıkarılan etkinlikleri yazdır")
    ap.add_argument("--limit", type=int, help="kaynak başına en fazla bu kadar yeni sayfa çek (maliyet testi)")
    ap.add_argument("--refresh", action="store_true", help="daha önce işlenmiş sayfaları da yeniden çek")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args(argv)

    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    claude = anthropic.Anthropic(api_key=env("ANTHROPIC_API_KEY", required=True))

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

    failed = 0
    for source in sources:
        if source["slug"] not in ADAPTERS:
            logging.warning("%s: adapter yok, atlandı", source["slug"])
            continue
        logging.info("== %s", source["slug"])
        stats = run_source(source, get_adapter(source["slug"]), claude, dry_run=args.dry_run, limit=args.limit, refresh=args.refresh)
        logging.info(
            "%s: öğe=%d atlanan=%d bulunan=%d yazılan=%d hata=%d token=%d/%d",
            source["slug"], stats.items_fetched, stats.items_skipped, stats.events_found,
            stats.events_upserted, stats.errors,
            stats.usage.input_tokens, stats.usage.output_tokens,
        )
        failed += stats.fatal

    # Bir kaynağın tümden bozulması CI'ı kırmızı yapar (alarm). Öğe bazlı hatalar yapmaz.
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
