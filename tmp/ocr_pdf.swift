import AppKit
import Foundation
import PDFKit
import Vision

struct OCRConfig {
    let inputPath: String
    let outputPath: String
    let startPage: Int
    let endPage: Int?
    let scale: CGFloat
}

enum OCRToolError: Error, CustomStringConvertible {
    case usage
    case invalidPDF(String)
    case invalidPageRange
    case renderFailed(Int)

    var description: String {
        switch self {
        case .usage:
            return "Usage: swift ocr_pdf.swift <input.pdf> <output.txt> [start_page] [end_page]"
        case .invalidPDF(let path):
            return "Unable to open PDF: \(path)"
        case .invalidPageRange:
            return "Invalid page range."
        case .renderFailed(let pageNumber):
            return "Failed to render page \(pageNumber)."
        }
    }
}

func parseArgs() throws -> OCRConfig {
    let args = CommandLine.arguments
    guard args.count >= 3 else {
        throw OCRToolError.usage
    }

    let startPage = args.count >= 4 ? (Int(args[3]) ?? 1) : 1
    let endPage = args.count >= 5 ? Int(args[4]) : nil
    guard startPage >= 1 else {
        throw OCRToolError.invalidPageRange
    }

    return OCRConfig(
        inputPath: args[1],
        outputPath: args[2],
        startPage: startPage,
        endPage: endPage,
        scale: 2.0
    )
}

func renderPage(_ page: PDFPage, scale: CGFloat, pageNumber: Int) throws -> CGImage {
    let mediaBox = page.bounds(for: .mediaBox)
    let width = Int(mediaBox.width * scale)
    let height = Int(mediaBox.height * scale)

    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    else {
        throw OCRToolError.renderFailed(pageNumber)
    }

    bitmap.size = NSSize(width: mediaBox.width, height: mediaBox.height)

    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw OCRToolError.renderFailed(pageNumber)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer {
        NSGraphicsContext.restoreGraphicsState()
    }

    guard let cgContext = context.cgContext else {
        throw OCRToolError.renderFailed(pageNumber)
    }

    cgContext.setFillColor(NSColor.white.cgColor)
    cgContext.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

    cgContext.saveGState()
    cgContext.scaleBy(x: scale, y: scale)
    page.draw(with: .mediaBox, to: cgContext)
    cgContext.restoreGState()

    guard let image = bitmap.cgImage else {
        throw OCRToolError.renderFailed(pageNumber)
    }

    return image
}

func ocrPage(_ image: CGImage) throws -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["en-US"]

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])

    let observations = (request.results ?? []).sorted {
        let yDiff = abs($0.boundingBox.minY - $1.boundingBox.minY)
        if yDiff > 0.02 {
            return $0.boundingBox.minY > $1.boundingBox.minY
        }
        return $0.boundingBox.minX < $1.boundingBox.minX
    }

    let lines = observations.compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    return lines.joined(separator: "\n")
}

do {
    let config = try parseArgs()
    guard let document = PDFDocument(url: URL(fileURLWithPath: config.inputPath)) else {
        throw OCRToolError.invalidPDF(config.inputPath)
    }

    let pageCount = document.pageCount
    let lastPage = config.endPage ?? pageCount
    guard config.startPage <= lastPage, lastPage <= pageCount else {
        throw OCRToolError.invalidPageRange
    }

    let outputURL = URL(fileURLWithPath: config.outputPath)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    FileManager.default.createFile(atPath: config.outputPath, contents: nil)
    guard let handle = try? FileHandle(forWritingTo: outputURL) else {
        fatalError("Unable to open output file for writing.")
    }
    defer { try? handle.close() }

    for pageIndex in (config.startPage - 1)..<lastPage {
        autoreleasepool {
            let pageNumber = pageIndex + 1
            fputs("OCR page \(pageNumber)/\(pageCount)\n", stderr)

            guard let page = document.page(at: pageIndex) else {
                return
            }

            do {
                let image = try renderPage(page, scale: config.scale, pageNumber: pageNumber)
                let text = try ocrPage(image)
                let pageBlock = "\n=== Page \(pageNumber) ===\n\(text)\n"
                if let data = pageBlock.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } catch {
                let errorBlock = "\n=== Page \(pageNumber) ===\n[OCR failed: \(error)]\n"
                if let data = errorBlock.data(using: .utf8) {
                    try? handle.write(contentsOf: data)
                }
            }
        }
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
