"""Düşük seviye çekme araçları: HTTP/RSS, Firecrawl, Playwright.

Kaynak önceliği (ROADMAP): resmi API/RSS -> Firecrawl -> en son Playwright.
Her istekten önce robots.txt kontrol edilir.
"""
from __future__ import annotations

import re
import time
from functools import lru_cache
from html.parser import HTMLParser
from urllib.parse import urljoin, urlparse
from urllib.robotparser import RobotFileParser

import httpx
from tenacity import retry, stop_after_attempt, wait_exponential

from ..config import REQUEST_DELAY_S, USER_AGENT, env

MAX_TEXT_CHARS = 60_000  # tek öğede Claude'a gidecek en fazla karakter (maliyet koruması)


class RobotsDisallowed(Exception):
    pass


@lru_cache(maxsize=32)
def _robots(origin: str) -> RobotFileParser:
    rp = RobotFileParser()
    try:
        res = httpx.get(f"{origin}/robots.txt", headers={"User-Agent": USER_AGENT}, timeout=15, follow_redirects=True)
        # robots.txt yoksa bazı siteler 200 + HTML döner; bunu "kural yok" say.
        if res.status_code == 200 and "<html" not in res.text[:500].lower():
            rp.parse(res.text.splitlines())
        else:
            rp.parse([])
    except httpx.HTTPError:
        rp.parse([])
    return rp


def check_robots(url: str) -> None:
    p = urlparse(url)
    if not _robots(f"{p.scheme}://{p.netloc}").can_fetch(USER_AGENT, url):
        raise RobotsDisallowed(f"robots.txt bu adrese izin vermiyor: {url}")


@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=1, max=10), reraise=True)
def http_get(url: str) -> str:
    check_robots(url)
    res = httpx.get(url, headers={"User-Agent": USER_AGENT}, timeout=30, follow_redirects=True)
    res.raise_for_status()
    return res.text


def html_links(html: str, base_url: str) -> list[str]:
    """HTML içindeki href'leri mutlak URL olarak döndürür (sıra korunur, tekrarsız)."""
    seen: dict[str, None] = {}
    for href in re.findall(r'href=["\']([^"\'#]+)["\']', html):
        seen[urljoin(base_url, href.replace("&amp;", "&"))] = None
    return list(seen)


def section_links(html: str, base_url: str, section_id: str) -> list[str]:
    """Belirli bir bölümdeki anchor'lar; boş bölüm geçerli, kayıp bölüm site değişikliğidir."""
    class SectionParser(HTMLParser):
        void_tags = {"area", "base", "br", "col", "embed", "hr", "img", "input",
                     "link", "meta", "param", "source", "track", "wbr"}

        def __init__(self):
            super().__init__(convert_charrefs=True)
            self.depth = 0
            self.section_depth = None
            self.found = False
            self.links: dict[str, None] = {}

        def handle_starttag(self, tag, attrs):
            attrs = dict(attrs)
            if attrs.get("id") == section_id:
                self.section_depth = self.depth
                self.found = True
            if self.section_depth is not None and tag == "a" and attrs.get("href"):
                self.links[urljoin(base_url, attrs["href"])] = None
            if tag not in self.void_tags:
                self.depth += 1

        def handle_startendtag(self, tag, attrs):
            self.handle_starttag(tag, attrs)
            if tag not in self.void_tags:
                self.handle_endtag(tag)

        def handle_endtag(self, tag):
            if tag not in self.void_tags:
                self.depth -= 1
                if self.depth == self.section_depth:
                    self.section_depth = None

    parser = SectionParser()
    parser.feed(html)
    if not parser.found:
        raise RuntimeError(f"Etkinlik bölümü bulunamadı: #{section_id} ({base_url})")
    return list(parser.links)


@lru_cache(maxsize=1)
def _firecrawl():
    from firecrawl import Firecrawl

    return Firecrawl(api_key=env("FIRECRAWL_API_KEY", required=True))


@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=2, min=2, max=20), reraise=True)
def firecrawl_scrape(url: str) -> tuple[str, list[str]]:
    """(markdown, links) döndürür."""
    check_robots(url)
    doc = _firecrawl().scrape(url, formats=["markdown", "links"], only_main_content=True)
    markdown = getattr(doc, "markdown", None) or ""
    links = list(getattr(doc, "links", None) or [])
    return markdown[:MAX_TEXT_CHARS], links


def playwright_render(url: str, *, wait_ms: int = 3000) -> tuple[str, list[str]]:
    """JavaScript ile çizilen sayfalar için. (görünen metin, linkler) döndürür."""
    from playwright.sync_api import sync_playwright

    check_robots(url)
    with sync_playwright() as p:
        browser = p.chromium.launch()
        try:
            page = browser.new_page(user_agent=USER_AGENT, locale="tr-TR", timezone_id="Europe/Istanbul")
            response = page.goto(url, wait_until="domcontentloaded", timeout=45_000)
            if response is None or not response.ok:
                raise RuntimeError(f"Sayfa alınamadı: {url} (HTTP {response.status if response else '?'})")
            page.wait_for_timeout(wait_ms)
            text = page.inner_text("body")
            links = page.eval_on_selector_all("a[href]", "els => els.map(e => e.href)")
        finally:
            browser.close()
    return text[:MAX_TEXT_CHARS], list(dict.fromkeys(links))


def playwright_listing(
    url: str, *, link_selector: str, ready_selector: str,
    load_more_selector: str | None = None, max_links: int = 40,
    empty_selector: str | None = None, empty_text_pattern: str | None = None,
    timeout_ms: int = 20_000,
) -> list[str]:
    """Görünür etkinlik listesi. Analitik isteklerinin bitmesini beklemez, site API'sini doğrudan çağırmaz.
    En fazla 10 kez 'daha fazla' tıklanır; kart sayısı artmazsa açık hata döner.
    """
    from playwright.sync_api import sync_playwright

    check_robots(url)
    with sync_playwright() as p:
        browser = p.chromium.launch()
        try:
            page = browser.new_page(user_agent=USER_AGENT, locale="tr-TR", timezone_id="Europe/Istanbul")
            response = page.goto(url, wait_until="domcontentloaded", timeout=45_000)
            if response is None or not response.ok:
                raise RuntimeError(f"Liste alınamadı: {url} (HTTP {response.status if response else '?'})")
            page.locator(ready_selector).first.wait_for(state="attached", timeout=timeout_ms)

            def links() -> list[str]:
                return list(dict.fromkeys(page.locator(link_selector).evaluate_all("els => els.map(e => e.href)")))

            result = links()
            if not result:
                empty = page.locator(empty_selector).first if empty_selector else None
                message = empty.inner_text(timeout=timeout_ms) if empty is not None and empty.count() else ""
                if not empty_text_pattern or not re.search(empty_text_pattern, message):
                    raise RuntimeError(f"Etkinlik listesi yüklenemedi: {url} ({message[:200]})")
            for _ in range(10):
                if len(result) >= max_links or not load_more_selector:
                    break
                more = page.locator(load_more_selector).first
                if not more.is_visible() or not more.is_enabled():
                    break
                before = page.locator(link_selector).count()
                polite_sleep()
                more.click(timeout=10_000)
                page.wait_for_function(
                    """({selector, before, moreSelector}) => {
                        if (document.querySelectorAll(selector).length > before) return true;
                        const more = document.querySelector(moreSelector);
                        return !more || more.hidden || getComputedStyle(more).display === 'none';
                    }""",
                    arg={"selector": link_selector, "before": before, "moreSelector": load_more_selector},
                    timeout=timeout_ms,
                )
                updated = links()
                if updated == result:
                    break
                result = updated
            return result
        finally:
            browser.close()


def polite_sleep() -> None:
    time.sleep(REQUEST_DELAY_S)


@retry(stop=stop_after_attempt(2), wait=wait_exponential(multiplier=2, min=2, max=10), reraise=True)
def firecrawl_search(query: str, *, limit: int = 3) -> list[tuple[str, str]]:
    """Web araması. (url, kısa açıklama) listesi döndürür; sayfalar burada çekilmez,
    çağıran robots.txt kontrolüyle firecrawl_scrape eder."""
    data = _firecrawl().search(query, limit=limit, location="Turkey", country="TR")
    out = []
    for r in getattr(data, "web", None) or []:
        url = getattr(r, "url", None) or getattr(getattr(r, "metadata", None), "url", None)
        if url:
            out.append((url, f"{getattr(r, 'title', '') or ''} — {getattr(r, 'description', '') or ''}"))
    return out
