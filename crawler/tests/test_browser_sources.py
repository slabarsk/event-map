"""Gerçek Chromium + yerel HTML: JS bekleme, kart kapsamı ve sayfalama.

AI/Firecrawl/harici ağ gerekmez. `python -m playwright install chromium` ile açılır;
CI'da tests.yml bu kurulumu yapar.
"""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread

import pytest
from playwright.sync_api import sync_playwright

from crawler.sources import fetchers
from crawler.sources.biletinial import BiletinialAdapter
from crawler.sources.bornova import BornovaAdapter


@pytest.fixture(scope="module")
def local_site():
    with sync_playwright() as p:
        if not Path(p.chromium.executable_path).exists():
            pytest.skip("Chromium yok: python -m playwright install chromium")

    class Handler(SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass

    handler = partial(Handler, directory=str(Path(__file__).parent / "fixtures"))
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


@pytest.fixture(autouse=True)
def no_external_requests(monkeypatch):
    monkeypatch.setattr(fetchers, "check_robots", lambda url: None)
    monkeypatch.setattr(fetchers, "polite_sleep", lambda: None)


def test_biletinial_js_tamamlanir_sayfalar_bos_son_sayfada_durur(local_site):
    adapter = BiletinialAdapter()
    adapter.listing_urls = [local_site + "/biletinial.html"]
    assert adapter.discover_urls() == [
        "https://biletinial.com/tr-tr/tiyatro/yeni-oyun",
        "https://biletinial.com/tr-tr/muzik/yeni-konser",
    ]


def test_bornova_gercek_kart_selectoru_haber_ve_tekrari_eler(local_site):
    adapter = BornovaAdapter()
    adapter.listing_urls = [local_site + "/bornova.html"]
    assert adapter.discover_urls() == ["https://bornova.bel.tr/yeni-sergi"]


def test_http_hatasi_bos_takvim_sayilmaz(local_site):
    with pytest.raises(RuntimeError, match="HTTP 404"):
        fetchers.playwright_listing(local_site + "/yok.html", link_selector="a", ready_selector="body")


@pytest.mark.parametrize("message, valid", [
    ("Etkinlik bulunamadı.", True), ("Etkinlikler yüklenirken hata oluştu.", False),
])
def test_bos_liste_ile_yukleme_hatasi_ayrilir(local_site, message, valid, monkeypatch):
    # Aynı DOM sınıfını kullanan gerçek sitenin iki yanıtı, URL'ye göre yerel sunucudan döner.
    original = SimpleHTTPRequestHandler.do_GET

    def respond(handler):
        if handler.path != "/mesaj":
            return original(handler)
        body = f'<div id="list"><p class="message">{message}</p></div>'.encode("utf-8")
        handler.send_response(200)
        handler.send_header("Content-Type", "text/html; charset=utf-8")
        handler.end_headers()
        handler.wfile.write(body)

    monkeypatch.setattr(SimpleHTTPRequestHandler, "do_GET", respond)
    kwargs = dict(link_selector="#list a", ready_selector=".message",
                  empty_selector=".message", empty_text_pattern=r"(?i)etkinlik.*bulunamad")
    if valid:
        assert fetchers.playwright_listing(local_site + "/mesaj", **kwargs) == []
    else:
        with pytest.raises(RuntimeError, match="yüklenemedi"):
            fetchers.playwright_listing(local_site + "/mesaj", **kwargs)
