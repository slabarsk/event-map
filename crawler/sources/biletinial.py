"""İzmir şehir listesi JS ile yüklenir; yalnızca bu listedeki etkinlik detayları çekilir."""
from .base import DynamicListingAdapter


class BiletinialAdapter(DynamicListingAdapter):
    slug = "biletinial"
    allowed_hosts = frozenset({"biletinial.com"})
    listing_urls = ["https://biletinial.com/tr-tr/SehrineOzel/izmir"]
    link_pattern = r"^https://biletinial\.com/tr-tr/(?:tiyatro|muzik|etkinlik|gosteri|stand-up|opera-bale|operabale|egitim|seminer|spor|eglence)/[^/]+$"
    # Sinema film sayfaları etkinlik değil: şehirler arası binlerce seans içerir.
    link_selector = "#homeCityEventsList .hpv2-event-card a[href]"
    ready_selector = ('#homeCityEventsList[aria-busy="false"] .hpv2-event-card a[href], '
                      '#homeCityEventsList[aria-busy="false"] .hpv2-events__message')
    load_more_selector = "#homeCityEventsLoadMore"
    empty_selector = "#homeCityEventsList .hpv2-events__message"
    empty_text_pattern = r"(?i)etkinlik.*bulunamad"
    hint = {"only_city": "İzmir"}
