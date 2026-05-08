#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
from pathlib import Path


def load_blocks(path: Path) -> list[str]:
    lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    blocks: list[str] = []
    cur: list[str] = []
    for line in lines:
        if line.strip():
            cur.append(line.rstrip())
        else:
            if cur:
                blocks.append("\n".join(cur).strip())
                cur = []
    if cur:
        blocks.append("\n".join(cur).strip())
    return blocks


def is_heading(block: str) -> bool:
    return block.startswith(("# ", "## ", "### ", "#### "))


def is_image(block: str) -> bool:
    return block.startswith("![")


def is_quote(block: str) -> bool:
    return block.startswith(">")


def is_list(block: str) -> bool:
    return bool(re.match(r"^(- |\d+\. )", block))


def is_codeish(block: str) -> bool:
    return block.startswith("```")


def is_special(block: str) -> bool:
    return any([is_heading(block), is_image(block), is_quote(block), is_list(block), is_codeish(block)])


def clean_heading_text(text: str) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    text = re.sub(r"\s+[A-Z]$", "", text)
    text = text.replace("Case Studies Chinese J-31", "Case Studies: Chinese J-31")
    text = text.replace("NARA ISOO National Archives and Records Administration (NARA)", "NARA ISOO")
    text = text.replace("Controlled Unclassified Information (CUI) LRP Drivers Legal Authority", "Controlled Unclassified Information (CUI) LRP Drivers")
    text = text.replace("CMMC LRP Drivers Legal Authority", "CMMC LRP Drivers")
    text = text.replace("NIST SP 800-171 Basis in NIST SP 800-53 NIST SP 800-53", "NIST SP 800-171 Basis in NIST SP 800-53")
    text = text.replace("NIST SP 800-171A Assessment Guidelines NIST SP 800-171A", "NIST SP 800-171A Assessment Guidelines")
    text = text.replace("NIST SP 800-172 Enhanced Security Requirements for CUI NIST SP 800-172", "NIST SP 800-172 Enhanced Security Requirements for CUI")
    text = text.replace("Legal, Regulatory, & Policy (LRP) Drivers L", "Legal, Regulatory, & Policy (LRP) Drivers")
    text = text.replace("The CMMC-AB Approved Training Materials (CATM) logo signifies that this content was developed by a CMMC-AB Approved Publ", "CMMC-AB Approved Training Materials Notice")
    text = text.replace("During the Delta period, a candidate's process for completing the certification exam requirements is:", "Delta Period Certification Path")
    return text


def normalize_headings(blocks: list[str]) -> list[str]:
    out: list[str] = []
    for block in blocks:
        if is_heading(block):
            marks, title = block.split(" ", 1)
            out.append(f"{marks} {clean_heading_text(title)}")
        else:
            out.append(block)
    return out


def promote_front_matter(blocks: list[str]) -> list[str]:
    replacements = {
        "### Certified CMMC Professional": "## Certified CMMC Professional",
        "### Certified CMMC Professional (CCP) Part Number: 093200": "### Edition Information",
        "Acknowledgements": "## Acknowledgements",
        "PROJECT TEAM": "### Project Team",
        "Notices": "## Notices",
        "DISCLAIMER": "### Disclaimer",
        "TRADEMARK NOTICES": "### Trademark Notices",
        "Copyright": "### Copyright",
        "Lesson Introduction": "### Lesson Introduction",
        "Lesson Objectives": "### Lesson Objectives",
        "The CHOICE Home Screen": "### The CHOICE Home Screen",
    }
    out: list[str] = []
    inserted_meta = False
    for block in blocks:
        if block in replacements:
            out.append(replacements[block])
            continue
        if block == "(CCP)":
            continue
        if block == "Course Edition: 2.3":
            if not inserted_meta:
                out.append("Part Number: `093200`")
                out.append("Course Edition: `2.3`")
                inserted_meta = True
            continue
        if block == "Part Number: 093200":
            if not inserted_meta:
                out.append("Part Number: `093200`")
            continue
        if block == "©":
            continue
        out.append(block)
    return out


def should_merge(prev: str, cur: str) -> bool:
    if any(is_special(x) for x in (prev, cur)):
        return False
    if prev.endswith(":"):
        return False
    if cur in {
        "Authors",
        "Instructional Design",
        "Production",
        "Scenario",
        "Overview",
        "Includes:",
        "Exemptions include:",
        "Characteristics include:",
    }:
        return False
    if re.fullmatch(r"[A-Z][A-Za-z0-9&/()' -]{0,80}", cur) and cur == cur.title() and len(cur.split()) <= 6:
        return False
    if re.fullmatch(r"\d{1,3}", prev) or re.fullmatch(r"\d{1,3}", cur):
        return False
    if cur[:1].islower():
        return True
    if prev.split()[-1].lower() in {
        "a",
        "an",
        "and",
        "any",
        "as",
        "at",
        "by",
        "for",
        "from",
        "in",
        "into",
        "is",
        "of",
        "on",
        "or",
        "our",
        "the",
        "their",
        "to",
        "with",
    }:
        return True
    if prev.endswith((",", ";", "(", "/", "—", "-", "the", "and", "of", "to", "for", "with", "by", "or")):
        return True
    if len(prev) < 70 and len(cur) < 90 and not prev.endswith((".", "?", "!")) and cur[:1].islower():
        return True
    return False


def reflow_blocks(blocks: list[str]) -> list[str]:
    out: list[str] = []
    for block in blocks:
        if out and should_merge(out[-1], block):
            out[-1] = f"{out[-1]} {block}".replace("  ", " ")
        else:
            out.append(block)
    return out


def tidy_lists(blocks: list[str]) -> list[str]:
    out: list[str] = []
    bullet_after = {
        "In this lesson, you will:",
        "Includes:",
        "Exemptions include:",
        "Characteristics include:",
    }
    i = 0
    while i < len(blocks):
        block = blocks[i]
        out.append(block)
        if block in bullet_after:
            i += 1
            while i < len(blocks) and not is_special(blocks[i]) and not blocks[i].endswith(":") and len(blocks[i]) < 160:
                out.append(f"- {blocks[i].rstrip('.')}")
                i += 1
            continue
        i += 1
    return out


def clean_bullets(blocks: list[str]) -> list[str]:
    out: list[str] = []
    for block in blocks:
        if block == "- 1":
            continue
        if out and out[-1].startswith("- ") and block.startswith("- "):
            prev = out[-1][2:]
            cur = block[2:]
            if len(prev) < 90 and len(cur) < 40 and not prev.endswith((".", "?", "!", ":")):
                out[-1] = f"- {prev} {cur}"
                continue
        out.append(block)
    return out


def remove_toc_duplicates(blocks: list[str]) -> list[str]:
    out: list[str] = []
    in_toc = False
    seen: set[str] = set()
    for block in blocks:
        if block == "## Table of Contents":
            in_toc = True
            out.append(block)
            continue
        if in_toc:
            if block.startswith("- ["):
                if block in seen:
                    continue
                seen.add(block)
                out.append(block)
                continue
            in_toc = False
        out.append(block)
    return out


def write_blocks(path: Path, blocks: list[str]) -> None:
    path.write_text("\n\n".join(blocks).rstrip() + "\n", encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: publish_handbook_cleanup.py <markdown_file>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1]).resolve()
    blocks = load_blocks(path)
    blocks = normalize_headings(blocks)
    blocks = promote_front_matter(blocks)
    blocks = reflow_blocks(blocks)
    blocks = tidy_lists(blocks)
    blocks = clean_bullets(blocks)
    blocks = remove_toc_duplicates(blocks)
    write_blocks(path, blocks)
    print(f"published {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
