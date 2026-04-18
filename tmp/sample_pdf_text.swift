import Foundation
import PDFKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: swift sample_pdf_text.swift <input.pdf> [page ...]\n", stderr)
    exit(1)
}

let path = args[1]
guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else {
    fputs("Unable to open PDF.\n", stderr)
    exit(1)
}

let pageNumbers: [Int]
if args.count > 2 {
    pageNumbers = args.dropFirst(2).compactMap(Int.init)
} else {
    pageNumbers = [1, 2, 3, 10, 50, 100]
}

print("pages \(doc.pageCount)")
for pageNumber in pageNumbers where pageNumber >= 1 && pageNumber <= doc.pageCount {
    let index = pageNumber - 1
    let text = doc.page(at: index)?.string ?? ""
    print("--- PAGE \(pageNumber) ---")
    print(String(text.prefix(2000)))
}
