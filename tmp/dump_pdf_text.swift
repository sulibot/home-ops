import Foundation
import PDFKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    fputs("Usage: swift dump_pdf_text.swift <input.pdf> <output.txt>\n", stderr)
    exit(1)
}

let inputPath = args[1]
let outputPath = args[2]

guard let doc = PDFDocument(url: URL(fileURLWithPath: inputPath)) else {
    fputs("Unable to open PDF.\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
FileManager.default.createFile(atPath: outputPath, contents: nil)
let handle = try FileHandle(forWritingTo: outputURL)

for index in 0..<doc.pageCount {
    autoreleasepool {
        let pageNumber = index + 1
        let text = doc.page(at: index)?.string ?? ""
        let block = """
        --- PAGE \(pageNumber) ---
        \(text)

        """
        if let data = block.data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
        if pageNumber % 25 == 0 {
            fputs("Dumped \(pageNumber)/\(doc.pageCount)\n", stderr)
        }
    }
}

try? handle.close()
