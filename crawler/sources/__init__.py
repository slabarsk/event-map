"""Kaynak adapter kayıt defteri.

Yeni kaynak: sources/ altına dosya ekle, buraya kaydet, `sources` tablosunda
satırını enabled = true yap. Stage 4'te tek kaynak var: AASSM.
"""
from .aassm import AassmAdapter
from .base import SourceAdapter

ADAPTERS: dict[str, type[SourceAdapter]] = {cls.slug: cls for cls in (AassmAdapter,)}


def get_adapter(slug: str) -> SourceAdapter:
    try:
        return ADAPTERS[slug]()
    except KeyError:
        raise KeyError(f"'{slug}' için adapter yok. Mevcut: {', '.join(sorted(ADAPTERS))}") from None
