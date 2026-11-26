"""Kaynak adapter kayıt defteri.

Yeni kaynak: sources/ altına dosya ekle, buraya kaydet, `sources` tablosunda
satırını enabled = true yap. Kaynak denetimi: docs/sources.md.
"""
from .aassm import AassmAdapter
from .base import SourceAdapter
from .biletinial import BiletinialAdapter
from .bornova import BornovaAdapter
from .izmirkultur import IzmirKulturAdapter
from .karsiyaka import KarsiyakaAdapter

ADAPTERS: dict[str, type[SourceAdapter]] = {
    cls.slug: cls for cls in (AassmAdapter, BiletinialAdapter, BornovaAdapter, KarsiyakaAdapter, IzmirKulturAdapter)
}


def get_adapter(slug: str) -> SourceAdapter:
    try:
        return ADAPTERS[slug]()
    except KeyError:
        raise KeyError(f"'{slug}' için adapter yok. Mevcut: {', '.join(sorted(ADAPTERS))}") from None
