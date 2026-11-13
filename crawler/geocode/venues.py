"""Mekân eşleştirme: önce DB'deki bilinen mekân (geocoding maliyeti yok), yoksa Mapbox."""
from __future__ import annotations

import logging

from .. import db
from ..config import env
from .mapbox import geocode

log = logging.getLogger(__name__)


def resolve_venue(name: str, address: str | None) -> str | None:
    """venue_id döndürür; konum bulunamazsa None (etkinlik atlanır)."""
    venue_id = db.match_venue(name)
    if venue_id:
        return venue_id

    if not env("MAPBOX_SECRET_TOKEN"):
        log.warning("MAPBOX_SECRET_TOKEN yok, yeni mekân geocode edilemedi: %s", name)
        return None

    point = geocode(f"{name}, {address}" if address else name)
    if point is None and address:
        point = geocode(address)
    if point is None:
        log.info("konum bulunamadı: %s / %s", name, address)
        return None

    return db.upsert_venue(name, address or point.label, point.lat, point.lng)
