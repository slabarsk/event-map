"""Ortam değişkenleri ve sabitler. Anahtarlar yalnızca .env'den okunur."""
from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent.parent / ".env")


def env(name: str, default: str | None = None, *, required: bool = False) -> str:
    value = os.getenv(name, default)
    if required and not value:
        raise RuntimeError(f"{name} tanımlı değil (.env dosyasına bakın)")
    return value or ""


# Modeller (Stage 9'da maliyet/kalite ayarı buradan yapılır)
MODEL_FAST = os.getenv("CLAUDE_MODEL_FAST", "claude-haiku-5-5")  # çıkarım ve fiyat ajanı

# Fiyat ajanı: bilet sayfasında fiyat yoksa Firecrawl search ile web'de ara.
# Firecrawl kredisi harcar; kapatmak için PRICE_SEARCH=0.
PRICE_SEARCH = os.getenv("PRICE_SEARCH", "1") != "0"

# Duplicate merge: pg_trgm başlık benzerliği bu değer ve üzerindeyse Claude'a
# sormadan otomatik birleşir. Alt eşik (0.25) SQL'de find_event_candidates içindedir.
DEDUP_AUTO_MERGE_SIM = float(os.getenv("DEDUP_AUTO_MERGE_SIM", "0.75"))

# Maliyet hesabı için $/1M token. Tanımlı değilse crawl_runs.cost_usd boş kalır.
# Güncel fiyatlar için Anthropic fiyat sayfasına bakın; kodda sabit tutulmaz.
PRICE_IN_PER_MTOK = float(os.getenv("CLAUDE_PRICE_IN_PER_MTOK", "0") or 0) or None
PRICE_OUT_PER_MTOK = float(os.getenv("CLAUDE_PRICE_OUT_PER_MTOK", "0") or 0) or None

USER_AGENT = "EventMapBot/0.1 (+https://github.com/slabarsk/event-map)"
REQUEST_DELAY_S = float(os.getenv("CRAWL_DELAY_SECONDS", "1.0"))  # sunuculara nazik davran

TZ_OFFSET = "+03:00"  # Europe/Istanbul (yaz saati yok)
