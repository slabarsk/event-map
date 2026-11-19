"""Karşıyaka takvimi: #nav-1 güncel, #nav-2 dev arşivdir. Arşiv Claude'a gönderilmez."""
from . import fetchers
from .base import ListingAdapter


class KarsiyakaAdapter(ListingAdapter):
    slug = "karsiyaka"
    allowed_hosts = frozenset({"www.karsiyaka.bel.tr"})
    listing_urls = ["https://www.karsiyaka.bel.tr/etkinlikler"]
    link_pattern = r"^https://www\.karsiyaka\.bel\.tr/(?!etkinlikler$)[^/]+$"
    hint = {"only_city": "İzmir", "district": "Karşıyaka"}

    def listing_links(self, url: str) -> list[str]:
        return fetchers.section_links(fetchers.http_get(url), url, "nav-1")
