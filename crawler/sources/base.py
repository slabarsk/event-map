"""Kaynak adapter'ları için taban sınıflar.

Her kaynak ayrı bir dosyada, bir SourceAdapter alt sınıfı olarak yaşar. Kaynak bozulursa
yalnızca o adapter etkilenir; hata crawl_runs.error_log'a yazılır.
"""
from __future__ import annotations

import logging
import re
from abc import ABC, abstractmethod
from collections.abc import Iterator

import feedparser

from ..models import RawItem
from . import fetchers

log = logging.getLogger(__name__)


class SourceAdapter(ABC):
    slug: str
    max_items: int = 40

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

    def fetch(self) -> Iterator[RawItem]:
        pattern = re.compile(self.link_pattern)
        detail_urls: dict[str, None] = {}
        for listing in self.listing_urls:
            _, links = _scrape(self.listing_mode, listing)
            for link in links:
                if pattern.search(link):
                    detail_urls[link] = None

        for url in list(detail_urls)[: self.max_items]:
            try:
                text, _ = _scrape(self.detail_mode, url)
            except Exception as exc:  # tek sayfa hatası koşuyu durdurmaz
                log.warning("%s: %s alınamadı: %s", self.slug, url, exc)
                continue
            yield RawItem(url=url, external_id=url, text=text, hint=dict(self.hint))
            fetchers.polite_sleep()


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
                log.warning("%s: %s alınamadı: %s", self.slug, url, exc)
                continue
            yield RawItem(url=url, external_id=url, text=text, hint=dict(self.hint))
            fetchers.polite_sleep()
