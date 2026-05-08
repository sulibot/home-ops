#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
from pathlib import Path


def load_blocks(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8", errors="ignore")
    return [b.strip() for b in re.split(r"\n\s*\n", text) if b.strip()]


def write_blocks(path: Path, blocks: list[str]) -> None:
    path.write_text("\n\n".join(blocks).rstrip() + "\n", encoding="utf-8")


def is_heading(block: str) -> bool:
    return block.startswith("#")


def is_image(block: str) -> bool:
    return block.startswith("![](")


def is_list(block: str) -> bool:
    return block.startswith(("- ", "* ", "1. ", "2. ", "3. "))


def is_special(block: str) -> bool:
    return is_heading(block) or is_image(block) or is_list(block) or block.startswith(">")


def is_short_label(block: str) -> bool:
    if is_special(block):
        return False
    if len(block) > 50:
        return False
    if block.endswith((".", ":", "?", "!")):
        return False
    words = block.split()
    if not words or len(words) > 6:
        return False
    return True


def is_sentence(block: str) -> bool:
    return not is_special(block) and bool(re.search(r"[.?!]$", block))


def title_caseish(block: str) -> bool:
    cleaned = re.sub(r"[^A-Za-z0-9&()/' -]", "", block).strip()
    if not cleaned:
        return False
    words = cleaned.split()
    return all(w[:1].isupper() or w.isupper() or any(ch.isdigit() for ch in w) for w in words)


def normalize_inline_figure(block: str) -> str:
    m = re.match(r"^\*(Figure [^*]+)\*\s+(.+)$", block)
    if m:
        return f"*{m.group(1)} {m.group(2)}*"
    return block


def should_bulletize(block: str) -> bool:
    if is_special(block):
        return False
    if len(block) > 140:
        return False
    if block.startswith(("Source:", "For ", "This ", "It ", "They ", "The ")):
        return False
    return True


def cleanup(blocks: list[str]) -> list[str]:
    blocks = [normalize_inline_figure(b) for b in blocks]

    out: list[str] = []
    i = 0
    while i < len(blocks):
        block = blocks[i]

        # Join figure captions split across the next short block.
        if block.startswith("*Figure ") and i + 1 < len(blocks):
            nxt = blocks[i + 1]
            if not is_special(nxt) and len(nxt) < 100 and not title_caseish(nxt):
                block = block.rstrip("*") + " " + nxt.lstrip()
                if not block.endswith("*"):
                    block += "*"
                i += 1

        # Convert stacked noun/sentence phrases after a colon into bullets.
        if block.endswith(":"):
            j = i + 1
            collected: list[str] = []
            while j < len(blocks):
                candidate = blocks[j]
                if is_special(candidate):
                    break
                if candidate.endswith(":") and j != i + 1:
                    break
                if len(candidate) > 160:
                    break
                if candidate.startswith(("Source:", "Figure ", "*Figure ")):
                    break
                collected.append(candidate)
                j += 1

            if len(collected) >= 2 and all(should_bulletize(c) for c in collected):
                out.append(block)
                for c in collected:
                    out.append(f"- {c.rstrip('.')}")
                i = j
                continue

        out.append(block)
        i += 1

    # Remove duplicate visual labels around figures/images.
    cleaned: list[str] = []
    i = 0
    while i < len(out):
        block = out[i]

        # Remove short title fragments directly before figure captions.
        if (
            i + 1 < len(out)
            and out[i + 1].startswith("*Figure ")
            and is_short_label(block)
            and title_caseish(block)
        ):
            i += 1
            continue

        # Remove duplicate figure-adjacent labels between caption and first image.
        if block.startswith("*Figure "):
            cleaned.append(block)
            i += 1
            while i < len(out) and not is_image(out[i]) and not is_heading(out[i]):
                if is_short_label(out[i]) and title_caseish(out[i]):
                    i += 1
                    continue
                cleaned.append(out[i])
                i += 1
            continue

        cleaned.append(block)
        i += 1

    return cleaned


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: publish_slide_md.py <file>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1]).resolve()
    blocks = load_blocks(path)
    blocks = cleanup(blocks)
    write_blocks(path, blocks)
    print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
