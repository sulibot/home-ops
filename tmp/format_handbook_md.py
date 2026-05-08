#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
from pathlib import Path


PAGE_RE = re.compile(r"^## Page (\d+): (.+)$")


def slugify(text: str) -> str:
    text = text.strip().lower()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"\s+", "-", text)
    return text


def split_blocks(lines: list[str]) -> list[str]:
    blocks: list[str] = []
    current: list[str] = []
    for line in lines:
        line = line.strip()
        if not line:
            if current:
                blocks.append(" ".join(current).strip())
                current = []
            continue
        current.append(line)
    if current:
        blocks.append(" ".join(current).strip())
    return blocks


def is_running_header_or_footer(block: str) -> bool:
    patterns = [
        r"^\|.*\|$",
        r"^Certified CMMC Professional \(CCP\)( \| .+)?$",
        r"^\d+ \| Certified CMMC Professional \(CCP\)$",
        r"^Lesson \d+: .* \| Topic [A-Z]$",
        r"^Appendix [A-Z] ?: .* \|$",
        r"^Page \d+$",
        r"^Notes$",
        r"^Activity$",
        r"^Table of Contents$",
    ]
    return any(re.match(p, block) for p in patterns)


def is_title_continuation(block: str) -> bool:
    if len(block) > 80:
        return False
    if "*" in block:
        return False
    if block.startswith(("Lesson Time", "Lesson Objectives", "Lesson Introduction", "Scenario", "Overview")):
        return False
    if re.match(r"^(Figure|Table|Appendix|Topic|Lesson|Activity)\b", block):
        return False
    if block.endswith((".", ":", "?", "!")):
        return False
    words = block.split()
    return 1 <= len(words) <= 8


def looks_like_note(block: str) -> bool:
    return block.startswith(("IMPORTANT NOTE", "*NOTE:", "NOTE:", "WARNING:", "CAUTION:"))


def title_level(title: str) -> int:
    if re.match(r"^Lesson \d+:", title):
        return 2
    if re.match(r"^Appendix [A-Z]", title):
        return 2
    if title in {"About This Course", "As You Review"}:
        return 2
    if re.match(r"^Topic [A-Z]:", title):
        return 3
    if re.match(r"^Activity \d+-\d+:", title):
        return 4
    return 3


def clean_blocks(blocks: list[str], image_base: Path) -> list[str]:
    cleaned: list[str] = []
    i = 0
    while i < len(blocks):
        block = blocks[i]

        if is_running_header_or_footer(block):
            i += 1
            continue
        if block == "_No extractable text on this page._":
            i += 1
            continue

        if re.fullmatch(r"!\[[^\]]*\]\(([^)]+)\)", block):
            m = re.fullmatch(r"!\[([^\]]*)\]\(([^)]+)\)", block)
            assert m is not None
            alt, rel = m.groups()
            img_path = (image_base / rel).resolve()
            cleaned.append(f"![{alt}]({img_path})")
            i += 1
            continue

        if block in {"•", "-", "·"} and i + 1 < len(blocks):
            cleaned.append(f"- {blocks[i + 1]}")
            i += 2
            continue

        if re.fullmatch(r"\d+\.?", block) and i + 1 < len(blocks):
            num = block.rstrip(".")
            cleaned.append(f"{num}. {blocks[i + 1]}")
            i += 2
            continue

        if looks_like_note(block):
            label, _, body = block.partition(":")
            label = label.replace("*", "").strip().title()
            body = body.strip()
            cleaned.append(f"> **{label}:** {body}" if body else f"> **{label}**")
            i += 1
            continue

        if block == "As a Reference":
            cleaned.append("### As a Reference")
            i += 1
            continue

        if block == "Course Icons":
            cleaned.append("### Course Icons")
            i += 1
            continue

        if block == "Scenario":
            cleaned.append("**Scenario**")
            i += 1
            continue

        if block in {"Question", "Questions"}:
            cleaned.append(f"### {block}")
            i += 1
            continue

        if block.startswith("Figure "):
            cleaned.append(f"*{block}*")
            i += 1
            continue

        cleaned.append(block)
        i += 1

    return cleaned


def parse_pages(lines: list[str]) -> list[tuple[int, str, list[str]]]:
    pages: list[tuple[int, str, list[str]]] = []
    current_num: int | None = None
    current_title: str | None = None
    current_lines: list[str] = []

    for line in lines:
        m = PAGE_RE.match(line)
        if m:
            if current_num is not None and current_title is not None:
                pages.append((current_num, current_title, current_lines))
            current_num = int(m.group(1))
            current_title = m.group(2).strip()
            current_lines = []
        elif current_num is not None:
            current_lines.append(line)

    if current_num is not None and current_title is not None:
        pages.append((current_num, current_title, current_lines))
    return pages


def build_section_title(page_num: int, page_title: str, blocks: list[str]) -> tuple[str | None, list[str], bool]:
    title = page_title.strip()
    is_lesson_open = any(b.startswith("Lesson Time") for b in blocks)

    if page_num in {5, 6, 7, 8}:
        return None, [], False

    if title == f"Page {page_num}":
        title = ""

    while blocks and blocks[0] == title:
        blocks.pop(0)

    if title in {"TOPIC A", "TOPIC B", "TOPIC C", "TOPIC D", "TOPIC E"} and blocks:
        subtitle = blocks.pop(0)
        title = f"{title.title()}: {subtitle}"
    elif re.match(r"^ACTIVITY \d+-\d+$", title) and blocks:
        subtitle = blocks.pop(0)
        title = f"{title.title()}: {subtitle}"

    if title and blocks and is_title_continuation(blocks[0]):
        title = f"{title} {blocks.pop(0)}"

    title = re.sub(r"\.{2,}\s*\d+$", "", title).strip()
    title = title.replace("ACTIVITY", "Activity").replace("TOPIC", "Topic")

    if title in {"Certified CMMC", "Page 4", "Page 8"}:
        title = ""

    return title or None, blocks, is_lesson_open


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: format_handbook_md.py <markdown_file>", file=sys.stderr)
        return 2

    md_path = Path(sys.argv[1]).resolve()
    image_base = md_path.parent
    lines = md_path.read_text(encoding="utf-8", errors="ignore").splitlines()
    pages = parse_pages(lines)

    toc_entries: list[tuple[int, str]] = []
    rendered_sections: list[str] = []
    lesson_counter = 0

    intro = [
        "# CMMC Class Handbook Clean",
        "",
        "_Technical writer cleanup of the OpenDocument export. Page numbering and slide framing were removed; headings, callouts, and image links were normalized for long-form reading._",
        "",
        f"Source file: `{md_path.with_suffix('.odg').name}`",
        "",
    ]

    for page_num, raw_title, raw_lines in pages:
        blocks = split_blocks(raw_lines)
        blocks = clean_blocks(blocks, image_base)
        title, blocks, is_lesson_open = build_section_title(page_num, raw_title, blocks)

        if not title and not blocks:
            continue

        if title:
            if is_lesson_open and not re.match(r"^Lesson \d+:", title):
                lesson_counter += 1
                title = f"Lesson {lesson_counter}: {title}"

            level = 2 if is_lesson_open else title_level(title)
            rendered_sections.append(f"{'#' * level} {title}")
            rendered_sections.append("")
            if re.match(r"^(Lesson \d+:|Topic [A-Z]:|Activity \d+-\d+:|Appendix [A-Z])", title) or title in {"About This Course", "As You Review"}:
                toc_entries.append((level, title))

        for block in blocks:
            if not block:
                continue
            rendered_sections.append(block)
            rendered_sections.append("")

    seen: set[str] = set()
    unique_toc: list[tuple[int, str]] = []
    for level, title in toc_entries:
        key = title.lower()
        if key in seen:
            continue
        seen.add(key)
        unique_toc.append((level, title))

    toc_lines = ["## Table of Contents", ""]
    for level, title in unique_toc:
        indent = "  " * max(0, level - 2)
        toc_lines.append(f"{indent}- [{title}](#{slugify(title)})")
    toc_lines.append("")

    output = intro + toc_lines + rendered_sections
    md_path.write_text("\n".join(output).rstrip() + "\n", encoding="utf-8")
    print(f"formatted {md_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
