"""Supabase erişimi (service_role). Yalnızca crawler'da kullanılır."""
from __future__ import annotations

import hashlib
from datetime import datetime, timezone
from functools import lru_cache
from typing import Any

from supabase import Client, create_client

from .config import env


@lru_cache(maxsize=1)
def client() -> Client:
    return create_client(env("SUPABASE_URL", required=True), env("SUPABASE_SERVICE_ROLE_KEY", required=True))


def content_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def get_source(slug: str) -> dict[str, Any]:
    res = client().table("sources").select("*").eq("slug", slug).single().execute()
    return res.data


def enabled_sources() -> list[dict[str, Any]]:
    res = client().table("sources").select("*").eq("enabled", True).in_("type", ["api", "rss", "firecrawl", "playwright"]).execute()
    return res.data or []


def seen_hash(source_id: str, external_id: str) -> str | None:
    res = (
        client().table("seen_items").select("content_hash")
        .eq("source_id", source_id).eq("external_id", external_id).limit(1).execute()
    )
    return res.data[0]["content_hash"] if res.data else None


def seen_ids(source_id: str) -> set[str]:
    """Bu kaynakta daha önce işlenmiş öğeler. Listing adapter'ları bunları yeniden çekmez."""
    res = client().table("seen_items").select("external_id").eq("source_id", source_id).execute()
    return {r["external_id"] for r in res.data or []}


def mark_seen(source_id: str, external_id: str, chash: str, event_count: int) -> None:
    client().table("seen_items").upsert(
        {
            "source_id": source_id, "external_id": external_id, "content_hash": chash,
            "event_count": event_count, "last_seen_at": now_iso(),
        }
    ).execute()


def touch_seen(source_id: str, external_id: str) -> None:
    client().table("seen_items").update({"last_seen_at": now_iso()}).eq("source_id", source_id).eq(
        "external_id", external_id
    ).execute()


def start_run(source_id: str) -> str:
    res = client().table("crawl_runs").insert({"source_id": source_id}).execute()
    return res.data[0]["id"]


def finish_run(run_id: str, **fields: Any) -> None:
    client().table("crawl_runs").update({"finished_at": now_iso(), **fields}).eq("id", run_id).execute()


def event_id_for_source(source_id: str, external_id: str, idx: int) -> str | None:
    """Bu kaynak öğesinden daha önce yazılmış etkinliğin id'si (yeniden crawl'da günceller)."""
    res = (
        client().table("event_sources").select("event_id")
        .eq("source_id", source_id).eq("external_id", external_id).eq("idx", idx)
        .limit(1).execute()
    )
    return res.data[0]["event_id"] if res.data else None


def insert_event(row: dict[str, Any]) -> str:
    return client().table("events").insert(row).execute().data[0]["id"]


def update_event(event_id: str, row: dict[str, Any]) -> None:
    client().table("events").update(row).eq("id", event_id).execute()


def upsert_event_source(row: dict[str, Any]) -> None:
    client().table("event_sources").upsert(row, on_conflict="source_id,external_id,idx").execute()


def match_venue(name: str) -> str | None:
    data = client().rpc("match_venue", {"p_name": name}).execute().data
    return data[0]["id"] if data else None


def upsert_venue(name: str, address: str | None, lat: float, lng: float) -> str:
    return client().rpc(
        "upsert_venue", {"p_name": name, "p_address": address, "p_lat": lat, "p_lng": lng}
    ).execute().data


def similar_priced_events(venue_name: str, category: str, limit: int = 15) -> list[dict[str, Any]]:
    """Fiyat tahmini için örnekler: aynı mekân ya da aynı kategorideki fiyatı bilinen etkinlikler.
    Tahminler örnek olarak kullanılmaz (tahminden tahmin üretilmesin)."""
    venue_id = match_venue(venue_name)
    flt = f"category.eq.{category}" + (f",venue_id.eq.{venue_id}" if venue_id else "")
    res = (
        client().table("events")
        .select("title,category,price_min,price_max,starts_at,venue:venues(name)")
        .in_("price_status", ["listed", "looked_up"])
        .or_(flt)
        .order("starts_at", desc=True)
        .limit(limit)
        .execute()
    )
    return [
        {**{k: r[k] for k in ("title", "category", "price_min", "price_max")},
         "venue": (r.get("venue") or {}).get("name")}
        for r in res.data or []
    ]


def unknown_price_events(limit: int) -> list[dict[str, Any]]:
    """Fiyat ajanının geriye dönük iş listesi: yaklaşan, yayınlanmış, fiyatı bilinmeyen etkinlikler."""
    res = (
        client().table("events")
        .select("id,title,description,starts_at,ends_at,category,ticket_url,venue:venues(name,address)")
        # price_status = 'unknown' ile aynı (constraint); migration öncesi satırları da yakalar.
        .is_("price_min", "null").is_("price_max", "null").eq("status", "published")
        .gte("starts_at", now_iso())
        .order("starts_at")
        .limit(limit)
        .execute()
    )
    return res.data or []
