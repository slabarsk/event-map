"""AASSM (Ahmet Adnan Saygun Sanat Merkezi) - statik HTML.

Takvim: /tr/EtkinlikTakvimi/Index, detay: /tr/Etkinlikler/Detay/<id>.
robots.txt yok (404 yerine HTML döner -> kural yok sayılır). Liste HTTP ile, detay Firecrawl ile.
"""
from .base import ListingAdapter


class AassmAdapter(ListingAdapter):
    slug = "aassm"
    allowed_hosts = frozenset({"www.aassm.org.tr"})
    listing_urls = [
        "https://www.aassm.org.tr/",
        "https://www.aassm.org.tr/tr/EtkinlikTakvimi/Index",
    ]
    link_pattern = r"/tr/Etkinlikler/Detay/-?\d+"
    listing_mode = "http"
    detail_mode = "firecrawl"
    hint = {
        "single_venue": True,
        "default_venue": "Ahmet Adnan Saygun Sanat Merkezi",
        "default_address": "Mehmet Ali Akman Mah., Mithatpaşa Cad. No:1087, Konak/İzmir",
    }
