import Foundation
import PDFKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    fputs("Usage: swift search_pdf.swift <input.pdf> <term> [term ...]\n", stderr)
    exit(1)
}

let path = args[1]
let terms = args.dropFirst(2).map { $0.lowercased() }

guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else {
    fputs("Unable to open PDF.\n", stderr)
    exit(1)
}

for term in terms {
    print("=== TERM: \(term) ===")
    var hits = 0
    for index in 0..<doc.pageCount {
        guard let page = doc.page(at: index), let text = page.string?.lowercased() else {
            continue
        }
        if let range = text.range(of: term) {
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let lower = max(0, start - 180)
            let upper = min(text.count, start + 320)
            let startIndex = text.index(text.startIndex, offsetBy: lower)
            let endIndex = text.index(text.startIndex, offsetBy: upper)
            let snippet = text[startIndex..<endIndex].replacingOccurrences(of: "\n", with: " ")
            print("page \(index + 1): \(snippet)")
            hits += 1
            if hits >= 8 {
                break
            }
        }
    }
    if hits == 0 {
        print("no hits")
    }
}
