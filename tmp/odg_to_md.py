#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET


NS = {
    "draw": "urn:oasis:names:tc:opendocument:xmlns:drawing:1.0",
    "text": "urn:oasis:names:tc:opendocument:xmlns:text:1.0",
    "xlink": "http://www.w3.org/1999/xlink",
}


def collapse_ws(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def page_title(paragraphs: list[str], page_no: int) -> str:
    for candidate in paragraphs:
        cleaned = collapse_ws(candidate)
        if cleaned:
            return cleaned[:120]
    return f"Page {page_no}"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: odg_to_md.py <input.odg>", file=sys.stderr)
        return 2

    source = Path(sys.argv[1])
    if not source.exists():
        print(f"missing file: {source}", file=sys.stderr)
        return 1

    out_md = source.with_suffix(".md")
    images_dir = source.parent / "images" / "cmmc_class_handbook_clean"
    images_dir.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(source) as zf:
        root = ET.fromstring(zf.read("content.xml"))
        pages = root.findall(".//draw:page", NS)

        lines: list[str] = [
            f"# {source.stem}",
            "",
            f"Source: `{source.name}`",
            "",
            f"Pages extracted: {len(pages)}",
            "",
            "This Markdown export was generated from the OpenDocument Drawing package. Text is grouped by drawing page, and embedded images referenced by a page are extracted below that page.",
            "",
        ]

        extracted_images: set[str] = set()

        for idx, page in enumerate(pages, 1):
            paras = []
            for el in page.findall(".//text:p", NS):
                text = collapse_ws("".join(el.itertext()))
                if text:
                    paras.append(text)

            title = page_title(paras, idx)
            lines.append(f"## Page {idx}: {title}")
            lines.append("")

            if paras:
                for text in paras:
                    if text in {"•", "-", "·"}:
                        continue
                    if re.fullmatch(r"\d+\.", text):
                        lines.append(text)
                    elif text.startswith(("• ", "- ")):
                        lines.append(f"- {text[2:].strip()}")
                    else:
                        lines.append(text)
                    lines.append("")
            else:
                lines.append("_No extractable text on this page._")
                lines.append("")

            image_refs = []
            for image in page.findall(".//draw:image", NS):
                href = image.get(f"{{{NS['xlink']}}}href")
                if not href or not href.startswith("Pictures/"):
                    continue
                image_refs.append(href)

            seen_page_images: set[str] = set()
            for href in image_refs:
                if href in seen_page_images:
                    continue
                seen_page_images.add(href)
                dest = images_dir / Path(href).name
                if href not in extracted_images:
                    with zf.open(href) as src_fh, dest.open("wb") as dst_fh:
                        dst_fh.write(src_fh.read())
                    extracted_images.add(href)
                rel = dest.relative_to(source.parent)
                lines.append(f"![{Path(href).name}]({rel.as_posix()})")
                lines.append("")

        out_md.write_text("\n".join(lines), encoding="utf-8")

    print(f"wrote {out_md}")
    print(f"extracted_images {len(extracted_images)} to {images_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
