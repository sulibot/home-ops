#!/usr/bin/env python3

from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

from docx import Document
from docx.document import Document as DocumentObject
from docx.oxml.ns import qn
from docx.oxml.table import CT_Tbl
from docx.oxml.text.paragraph import CT_P
from docx.table import Table
from docx.text.paragraph import Paragraph


def iter_block_items(parent: DocumentObject):
    parent_elm = parent.element.body
    for child in parent_elm.iterchildren():
        if isinstance(child, CT_P):
            yield Paragraph(child, parent)
        elif isinstance(child, CT_Tbl):
            yield Table(child, parent)


def para_num_info(paragraph: Paragraph) -> tuple[int | None, int | None]:
    ppr = paragraph._p.pPr
    if ppr is None:
        return None, None
    numpr = ppr.numPr
    if numpr is None:
        return None, None
    ilvl = numpr.ilvl
    numid = numpr.numId
    level = int(ilvl.val) if ilvl is not None else 0
    number_id = int(numid.val) if numid is not None else None
    return number_id, level


def paragraph_text(paragraph: Paragraph) -> str:
    text = "".join(run.text for run in paragraph.runs).strip()
    return re.sub(r"\s+", " ", text)


def heading_prefix(style_name: str) -> str | None:
    match = re.match(r"Heading (\d+)", style_name)
    if not match:
        return None
    level = max(1, min(6, int(match.group(1))))
    return "#" * level


def markdown_for_table(table: Table) -> list[str]:
    rows = []
    for row in table.rows:
        cells = [re.sub(r"\s+", " ", cell.text.strip()) for cell in row.cells]
        rows.append(cells)

    if not rows:
        return []

    width = max(len(r) for r in rows)
    normalized = [r + [""] * (width - len(r)) for r in rows]
    header = normalized[0]
    sep = ["---"] * width
    lines = [
        "| " + " | ".join(header) + " |",
        "| " + " | ".join(sep) + " |",
    ]
    for row in normalized[1:]:
        lines.append("| " + " | ".join(row) + " |")
    return lines


def convert_docx_to_markdown(source: Path) -> str:
    doc = Document(source)
    lines: list[str] = []
    list_counters: dict[tuple[int, int], int] = {}

    for block in iter_block_items(doc):
        if isinstance(block, Paragraph):
            text = paragraph_text(block)
            if not text:
                if lines and lines[-1] != "":
                    lines.append("")
                continue

            style_name = block.style.name if block.style is not None else ""
            heading = heading_prefix(style_name)
            if heading:
                if lines and lines[-1] != "":
                    lines.append("")
                lines.append(f"{heading} {text}")
                lines.append("")
                continue

            num_id, level = para_num_info(block)
            if num_id is not None:
                fmt = None
                numdefs = doc.part.numbering_part.numbering_definitions._numbering
                xpath = (
                    f'.//w:num[@w:numId="{num_id}"]/w:abstractNumId'
                )
                nodes = numdefs.xpath(xpath)
                if nodes:
                    abstract_id = nodes[0].get(qn("w:val"))
                    lvl_xpath = (
                        f'.//w:abstractNum[@w:abstractNumId="{abstract_id}"]'
                        f'/w:lvl[@w:ilvl="{level}"]/w:numFmt'
                    )
                    lvl_nodes = numdefs.xpath(lvl_xpath)
                    if lvl_nodes:
                        fmt = lvl_nodes[0].get(qn("w:val"))

                indent = "  " * level
                if fmt == "bullet":
                    lines.append(f"{indent}- {text}")
                else:
                    key = (num_id, level)
                    list_counters[key] = list_counters.get(key, 0) + 1
                    lines.append(f"{indent}{list_counters[key]}. {text}")
                continue

            if style_name == "Checkbox Statements":
                lines.append(f"- [ ] {text}")
                continue

            lines.append(text)
            lines.append("")
        elif isinstance(block, Table):
            table_lines = markdown_for_table(block)
            if table_lines:
                if lines and lines[-1] != "":
                    lines.append("")
                lines.extend(table_lines)
                lines.append("")

    while lines and lines[-1] == "":
        lines.pop()

    output = "\n".join(lines) + "\n"
    output = re.sub(r"\n{3,}", "\n\n", output)
    return output


def main() -> int:
    if len(sys.argv) > 2:
        print("usage: docx_to_md_batch.py [target_dir]", file=sys.stderr)
        return 2

    target_dir = (
        Path(sys.argv[1])
        if len(sys.argv) == 2
        else Path("/Users/sulibot/repos/github/handy")
    )
    orig_dir = target_dir / "orig"
    orig_dir.mkdir(exist_ok=True)

    for source in sorted(target_dir.glob("*.docx")):
        markdown = convert_docx_to_markdown(source)
        dest = target_dir / f"{source.stem}.md"
        dest.write_text(markdown, encoding="utf-8")
        shutil.move(str(source), str(orig_dir / source.name))
        print(f"converted {source.name} -> {dest.name}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
