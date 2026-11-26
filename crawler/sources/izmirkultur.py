"""İzmir Kültür Sanat Fabrikası: sunucuda çizilen güncel takvim ve UUID'li detaylar."""
import re

from .base import ListingAdapter


class IzmirKulturAdapter(ListingAdapter):
    slug = "izmirkultur"
    allowed_hosts = frozenset({"izmirkultursanatfabrikasi.gov.tr"})
    listing_urls = ["https://izmirkultursanatfabrikasi.gov.tr/tr/etkinlikler"]
    link_pattern = r"^https://izmirkultursanatfabrikasi\.gov\.tr/tr/etkinlikler/tum-etkinlikler/[0-9a-f-]{36}$"
    hint = {
        "only_city": "İzmir",
        "single_venue": True,
        "default_venue": "İzmir Kültür Sanat Fabrikası",
        "default_address": "Mimar Sinan Mah., Ziya Gökalp Bulvarı No:36, Konak/İzmir",
    }

    def canonical_detail_url(self, link: str, listing: str) -> str | None:
        url = super().canonical_detail_url(link, listing)
        # Takvim kartları /tr olmadan link verir; JSON-LD ve detay kanoniği /tr içerir.
        return re.sub(r"\.gov\.tr/etkinlikler/", ".gov.tr/tr/etkinlikler/", url) if url else None
