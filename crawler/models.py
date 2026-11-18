"""Pipeline veri modelleri."""
from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

# supabase/migrations/20261113000000_events.sql içindeki event_category ile aynı.
Category = Literal[
    "concert", "theatre", "exhibition", "festival", "standup", "workshop",
    "cinema", "talk", "sports", "family", "party", "other",
]

# unknown: fiyat yok (fiyat ajanı arar). Bkz. 20261118000200_price_status_unknown.sql
PriceStatus = Literal["unknown", "listed", "looked_up", "estimated"]


class RawItem(BaseModel):
    """Bir kaynaktan çekilen ham içerik birimi (genelde bir sayfa)."""

    url: str
    external_id: str  # kaynak içinde kararlı anahtar (genelde URL)
    text: str  # temiz markdown / metin
    hint: dict = Field(default_factory=dict)  # adapter'ın bildiği ek ipuçları


class ExtractedEvent(BaseModel):
    """Claude'un sayfadan çıkardığı etkinlik (structured output şeması)."""

    title: str
    description: str | None
    starts_at: str | None  # ISO 8601, Türkiye saati (+03:00)
    ends_at: str | None
    venue_name: str | None
    address: str | None
    category: Category
    price_min: float | None
    price_max: float | None
    is_free: bool | None
    ticket_url: str | None
    image_url: str | None
    in_izmir: bool  # etkinlik İzmir'de mi
    requires_registration: bool  # bilet yerine başvuru formu / ön kayıtla katılım


class ExtractionResult(BaseModel):
    events: list[ExtractedEvent]


class Usage(BaseModel):
    input_tokens: int = 0
    output_tokens: int = 0

    def add(self, other: "Usage") -> None:
        self.input_tokens += other.input_tokens
        self.output_tokens += other.output_tokens


class NormalizedEvent(BaseModel):
    """Doğrulanmış, DB'ye yazılmaya hazır etkinlik."""

    title: str
    description: str | None
    starts_at: datetime
    ends_at: datetime | None
    venue_name: str
    address: str | None
    category: Category
    price_min: float | None
    price_max: float | None
    price_status: PriceStatus = "unknown"
    price_source_url: str | None = None
    ticket_url: str | None = None
    image_url: str | None = None
    requires_registration: bool = False
