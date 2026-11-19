"""Kaynak adapter'ları için taban sınıflar.

Her kaynak ayrı bir dosyada, bir SourceAdapter alt sınıfı olarak yaşar. Kaynak bozulursa
yalnızca o adapter etkilenir; hata crawl_runs.error_log'a yazılır.
"""
from __future__ import annotations

import logging
import re
from abc import ABC, abstractmethod
from collections.abc import Iterator
from urllib.parse import urldefrag, urljoin, urlsplit, urlunsplit

import feedparser

from ..models import RawItem
from . import fetchers

log = logging.getLogger(__name__)


class SourceAdapter(ABC):
    slug: str
    max_items: int = 40
    # Pipeline koşudan önce doldurur: daha önce işlenmiş öğeler yeniden çekilmez
    # (Firecrawl kredisi harcanmaz). Atlananların sayısı `skipped`a yazılır.
    skip_ids: frozenset[str] = frozenset()
    skipped: int = 0
    fetch_errors: tuple[tuple[str, Exception], ...] = ()

    def fetch_error(self, url: str, exc: Exception) -> None:
        self.fetch_errors += ((url, exc),)
        log.warning("%s: %s alınamadı: %s", self.slug, url, exc)

    @abstractmethod
    def fetch(self) -> Iterator[RawItem]:
        """Kaynaktaki ham öğeleri üretir. Bir öğe hata verirse atlanır, tüm koşu durmaz."""


def _scrape(mode: str, url: str, wait_ms: int = 3000) -> tuple[str, list[str]]:
    if mode == "firecrawl":
        return fetchers.firecrawl_scrape(url)
    if mode == "playwright":
        return fetchers.playwright_render(url, wait_ms=wait_ms)
    if mode == "http":
        html = fetchers.http_get(url)
        return html[: fetchers.MAX_TEXT_CHARS], fetchers.html_links(html, url)
    raise ValueError(f"bilinmeyen çekme modu: {mode}")


class RssAdapter(SourceAdapter):
    """Resmi RSS/Atom beslemesi: en ucuz ve en kararlı yol."""

    feed_urls: list[str] = []

    def fetch(self) -> Iterator[RawItem]:
        for feed_url in self.feed_urls:
            fetchers.check_robots(feed_url)
            feed = feedparser.parse(feed_url, agent=fetchers.USER_AGENT)
            for entry in feed.entries[: self.max_items]:
                link = entry.get("link") or feed_url
                text = "\n".join(
                    filter(None, [entry.get("title"), entry.get("published"), entry.get("summary"), link])
                )
                yield RawItem(url=link, external_id=entry.get("id") or link, text=text)


class ListingAdapter(SourceAdapter):
    """Liste sayfasından detay linklerini bulur, her detay sayfası bir RawItem olur."""

    listing_urls: list[str] = []
    link_pattern: str = r"."
    listing_mode: str = "http"
    detail_mode: str = "firecrawl"
    hint: dict = {}
    allowed_hosts: frozenset[str] = frozenset()

    def listing_links(self, url: str) -> list[str]:
        return _scrape(self.listing_mode, url)[1]

    def canonical_detail_url(self, link: str, listing: str) -> str | None:
        url = urldefrag(urljoin(listing, link))[0]
        parts = urlsplit(url)
        if self.allowed_hosts:
            if parts.scheme not in ("http", "https") or parts.netloc.lower() not in self.allowed_hosts:
                return None
            # Bu kaynaklarda kimlik path'tedir; kampanya parametreleri yeni öğe değildir.
            url = urlunsplit(("https", parts.netloc.lower(), parts.path.rstrip("/"), "", ""))
        return url

    def discover_urls(self) -> list[str]:
        pattern = re.compile(self.link_pattern)
        urls: dict[str, None] = {}
        for listing in self.listing_urls:
            for link in self.listing_links(listing):
                url = self.canonical_detail_url(link, listing)
                if url and pattern.search(url):
                    urls[url] = None
        return list(urls)

    def fetch(self) -> Iterator[RawItem]:
        self.skipped = 0
        self.fetch_errors = ()
        detail_urls = self.discover_urls()
        new_urls = [u for u in detail_urls if u not in self.skip_ids]
        self.skipped = len(detail_urls) - len(new_urls)
        for url in new_urls[: self.max_items]:
            try:
                text, _ = _scrape(self.detail_mode, url)
                if not text.strip():
                    raise RuntimeError("Detay sayfası boş; yeniden denenecek")
            except Exception as exc:  # tek sayfa hatası koşuyu durdurmaz
                self.fetch_error(url, exc)
                continue
            yield RawItem(url=url, external_id=url, text=text, hint={**self.hint, "detail_page": True})
            fetchers.polite_sleep()


class DynamicListingAdapter(ListingAdapter):
    """Yalnızca etkinlik kartlarını okuyarak JS listeyi sınırlı sayıda sayfalar."""

    listing_mode = "playwright"
    link_selector: str
    ready_selector: str
    load_more_selector: str | None = None
    empty_selector: str | None = None
    empty_text_pattern: str | None = None

    def listing_links(self, url: str) -> list[str]:
        # Görülmüş kartlar limiti tüketmesin: en fazla 10 yüklemede yeni kart aranır.
        return fetchers.playwright_listing(
            url, link_selector=self.link_selector, ready_selector=self.ready_selector,
            load_more_selector=self.load_more_selector,
            empty_selector=self.empty_selector, empty_text_pattern=self.empty_text_pattern,
            max_links=self.max_items + len(self.skip_ids),
        )


class PageAdapter(SourceAdapter):
    """Tek sayfada çok etkinlik listeleyen kaynaklar (SPA ya da kategori sayfaları)."""

    page_urls: list[str] = []
    mode: str = "firecrawl"
    wait_ms: int = 3000
    hint: dict = {}

    def fetch(self) -> Iterator[RawItem]:
        for url in self.page_urls:
            try:
                text, _ = _scrape(self.mode, url, self.wait_ms)
            except Exception as exc:
                self.fetch_error(url, exc)
                continue
            yield RawItem(url=url, external_id=url, text=text, hint=dict(self.hint))
            fetchers.polite_sleep()
