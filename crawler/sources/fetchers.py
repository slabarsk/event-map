"""Düşük seviye çekme araçları: HTTP/RSS, Firecrawl, Playwright.

Kaynak önceliği (ROADMAP): resmi API/RSS -> Firecrawl -> en son Playwright.
Her istekten önce robots.txt kontrol edilir.
"""
from __future__ import annotations

import re
import time
from functools import lru_cache
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
            page.goto(url, wait_until="networkidle", timeout=45_000)
            page.wait_for_timeout(wait_ms)
            text = page.inner_text("body")
            links = page.eval_on_selector_all("a[href]", "els => els.map(e => e.href)")
        finally:
            browser.close()
    return text[:MAX_TEXT_CHARS], list(dict.fromkeys(links))


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
