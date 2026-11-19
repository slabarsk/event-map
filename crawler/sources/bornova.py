"""Bornova'nın Güncel Etkinlikler sekmesi; haber ve geçmiş etkinlik linkleri alınmaz."""
from .base import DynamicListingAdapter


class BornovaAdapter(DynamicListingAdapter):
    slug = "bornova"
    allowed_hosts = frozenset({"bornova.bel.tr"})
    listing_urls = ["https://bornova.bel.tr/etkinlikler"]
    link_pattern = r"^https://bornova\.bel\.tr/[^/]+$"
    link_selector = "#loadEvents .event-container a[href]"
    ready_selector = "#loadEvents .event-container, #loadEvents .itemAlert"
    load_more_selector = "#loadMore"
    empty_selector = "#loadEvents .itemAlert"
    empty_text_pattern = r"(?i)güncel etkinlik bulunmamaktadır"
    hint = {"only_city": "İzmir", "district": "Bornova"}
