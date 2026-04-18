# CMMC Handbook Working Set

This folder turns the handbook source files into a local reference package for planning and architecture work.

Primary source of truth:
- [`/Users/sulibot/Downloads/CMMC Class Handbook Clean.odg`](/Users/sulibot/Downloads/CMMC%20Class%20Handbook%20Clean.odg)

Visual fallback:
- [`/Users/sulibot/Downloads/CMMC Class Handbook OCR.pdf`](/Users/sulibot/Downloads/CMMC%20Class%20Handbook%20OCR.pdf)

Files:
- `handbook-pages-odg.txt`: primary page-by-page text extraction from the `.odg`.
- `handbook-pages.txt`: OCR-based page-by-page text export from the PDF, retained as a fallback.
- `handbook-index.md`: first-pass semantic chunk map by lesson/topic/page range.
- `lesson-summaries.md`: lesson-by-lesson summaries for quick reference.
- `architecture-view.md`: systems-architect reading of the handbook, with emphasis on scoping, boundaries, enclaves, asset categories, shared services, and evidence.

Notes:
- Page references in the working set refer to handbook page numbers as aligned to the extracted `.odg` pages and the visual PDF pages.
- The `.odg` extraction is the preferred textual source because it preserves embedded text without OCR artifacts.
- This package is now suitable as a local source of truth for targeted design work and can later be expanded into a richer knowledge base if additional source documents are added.
