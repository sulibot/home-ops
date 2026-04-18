from pathlib import Path
import re
import sys
import zipfile
from xml.etree import ElementTree as ET


NS = {
    "draw": "urn:oasis:names:tc:opendocument:xmlns:drawing:1.0",
    "text": "urn:oasis:names:tc:opendocument:xmlns:text:1.0",
}


def collect_text(node):
    parts = []

    def walk(el):
        if el.text:
            parts.append(el.text)
        for child in el:
            walk(child)
            if child.tail:
                parts.append(child.tail)

    walk(node)
    text = "".join(parts)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def main():
    if len(sys.argv) != 3:
        print("Usage: python3 extract_odg_text.py <input.odg> <output.txt>", file=sys.stderr)
        sys.exit(1)

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    with zipfile.ZipFile(input_path) as zf:
        content = zf.read("content.xml")

    root = ET.fromstring(content)
    pages = root.findall(".//draw:page", NS)

    output_path.parent.mkdir(parents=True, exist_ok=True)

    with output_path.open("w", encoding="utf-8") as f:
        for idx, page in enumerate(pages, start=1):
            texts = []
            for p in page.findall(".//text:p", NS):
                t = collect_text(p)
                if t:
                    texts.append(t)
            f.write(f"--- PAGE {idx} ---\n")
            for line in texts:
                f.write(line + "\n")
            f.write("\n")

    print(f"Extracted {len(pages)} pages to {output_path}")


if __name__ == "__main__":
    main()
