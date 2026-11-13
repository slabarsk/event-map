"""Mapbox Geocoding v6 (forward), İzmir ile sınırlı."""
from __future__ import annotations

import unicodedata
from dataclasses import dataclass

import httpx
from tenacity import retry, stop_after_attempt, wait_exponential

from ..config import env

IZMIR_BBOX = "26.2,37.8,27.9,39.1"  # minLng,minLat,maxLng,maxLat
IZMIR_CENTER = "27.1428,38.4237"  # lng,lat


@dataclass
class GeoPoint:
    lat: float
    lng: float
    label: str


@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=1, max=8), reraise=True)
def geocode(query: str) -> GeoPoint | None:
    folded = "".join(c for c in unicodedata.normalize("NFKD", query) if not unicodedata.combining(c)).lower()
    q = query if "izmir" in folded else f"{query}, İzmir"
    res = httpx.get(
        "https://api.mapbox.com/search/geocode/v6/forward",
        params={
            "q": q, "country": "tr", "bbox": IZMIR_BBOX, "proximity": IZMIR_CENTER,
            "language": "tr", "limit": 1, "access_token": env("MAPBOX_SECRET_TOKEN", required=True),
        },
        timeout=20,
    )
    if res.status_code == 429 or res.status_code >= 500:
        res.raise_for_status()  # tenacity yeniden dener
    if res.status_code != 200:
        return None
    features = res.json().get("features") or []
    if not features:
        return None
    lng, lat = features[0]["geometry"]["coordinates"]
    props = features[0].get("properties", {})
    return GeoPoint(lat=lat, lng=lng, label=props.get("full_address") or props.get("name") or q)
