import Foundation
import ReadiumZIPFoundation

struct EpubChapter: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let fileURL: URL
}

struct EpubPublication: Hashable, Sendable {
    let bookId: String
    let title: String
    let rootURL: URL
    let chapters: [EpubChapter]
}

enum EpubReaderError: LocalizedError {
    case missingContainer
    case missingPackageDocument(String)
    case noReadableChapters
    case invalidXML(String)

    var errorDescription: String? {
        switch self {
        case .missingContainer:
            "The EPUB is missing its container metadata."
        case .missingPackageDocument(let path):
            "The EPUB package document could not be found at \(path)."
        case .noReadableChapters:
            "The EPUB does not contain readable XHTML chapters."
        case .invalidXML(let file):
            "The EPUB metadata in \(file) could not be read."
        }
    }
}

enum EpubArchiveParser {
    static func prepare(bookId: String, title: String, epubURL: URL) async throws -> EpubPublication {
        let rootURL = try readerDirectory(bookId: bookId)
        let markerURL = rootURL.appending(path: ".unpacked")
        if !FileManager.default.fileExists(atPath: markerURL.path) {
            if FileManager.default.fileExists(atPath: rootURL.path) {
                try FileManager.default.removeItem(at: rootURL)
            }
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try await FileManager.default.unzipItem(at: epubURL, to: rootURL, skipCRC32: true)
            FileManager.default.createFile(atPath: markerURL.path, contents: Data())
        }

        let containerURL = rootURL.appending(path: "META-INF/container.xml")
        guard FileManager.default.fileExists(atPath: containerURL.path) else {
            throw EpubReaderError.missingContainer
        }

        let opfPath = try parseContainerXML(Data(contentsOf: containerURL))
        let opfURL = rootURL.appendingEPUBPath(opfPath)
        guard FileManager.default.fileExists(atPath: opfURL.path) else {
            throw EpubReaderError.missingPackageDocument(opfPath)
        }

        let package = try parsePackageDocument(Data(contentsOf: opfURL))
        let opfBaseURL = opfURL.deletingLastPathComponent()
        let chapters = package.spine.compactMap { idref -> EpubChapter? in
            guard let item = package.manifest[idref],
                  item.isReadableDocument else {
                return nil
            }

            let fileURL = opfBaseURL.appendingEPUBPath(item.href)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }

            return EpubChapter(
                id: idref,
                title: chapterTitle(from: fileURL) ?? item.href.epubDisplayTitle,
                fileURL: fileURL
            )
        }

        guard !chapters.isEmpty else {
            throw EpubReaderError.noReadableChapters
        }

        return EpubPublication(
            bookId: bookId,
            title: package.title?.nilIfBlank ?? title,
            rootURL: rootURL,
            chapters: chapters
        )
    }

    static func parseContainerXML(_ data: Data) throws -> String {
        let delegate = EpubContainerXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let opfPath = delegate.opfPath?.nilIfBlank else {
            throw EpubReaderError.invalidXML("container.xml")
        }
        return opfPath
    }

    static func parsePackageDocument(_ data: Data) throws -> EpubPackageDocument {
        let delegate = EpubPackageXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw EpubReaderError.invalidXML("content.opf")
        }
        return delegate.package
    }

    private static func readerDirectory(bookId: String) throws -> URL {
        let safeBookId = bookId.slugified.nilIfBlank ?? UUID().uuidString
        let directory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "epub_reader", directoryHint: .isDirectory)
            .appending(path: safeBookId, directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private static func chapterTitle(from fileURL: URL) -> String? {
        guard let html = try? String(contentsOf: fileURL, encoding: .utf8),
              let range = html.range(of: #"(?is)<title[^>]*>(.*?)</title>"#, options: .regularExpression) else {
            return nil
        }
        return String(html[range])
            .strippedHTML
            .decodedHTMLEntities
            .nilIfBlank
    }
}

struct EpubManifestItem: Hashable, Sendable {
    let id: String
    let href: String
    let mediaType: String?
    let properties: String?

    var isReadableDocument: Bool {
        guard let mediaType else { return true }
        return mediaType.localizedCaseInsensitiveContains("xhtml")
            || mediaType.localizedCaseInsensitiveContains("html")
            || mediaType.localizedCaseInsensitiveContains("xml")
    }
}

struct EpubPackageDocument: Hashable, Sendable {
    var title: String?
    var manifest: [String: EpubManifestItem] = [:]
    var spine: [String] = []
}

private final class EpubContainerXMLDelegate: NSObject, XMLParserDelegate {
    var opfPath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.xmlElementName == "rootfile", opfPath == nil else { return }
        opfPath = attributeDict["full-path"]
    }
}

private final class EpubPackageXMLDelegate: NSObject, XMLParserDelegate {
    var package = EpubPackageDocument()

    private var isInsideMetadata = false
    private var isReadingTitle = false
    private var textBuffer = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let element = elementName.xmlElementName
        switch element {
        case "metadata":
            isInsideMetadata = true
        case "title" where isInsideMetadata && package.title == nil:
            isReadingTitle = true
            textBuffer = ""
        case "item":
            guard let id = attributeDict["id"]?.nilIfBlank,
                  let href = attributeDict["href"]?.nilIfBlank else {
                return
            }
            package.manifest[id] = EpubManifestItem(
                id: id,
                href: href,
                mediaType: attributeDict["media-type"],
                properties: attributeDict["properties"]
            )
        case "itemref":
            if let idref = attributeDict["idref"]?.nilIfBlank {
                package.spine.append(idref)
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isReadingTitle {
            textBuffer += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let element = elementName.xmlElementName
        if element == "title", isReadingTitle {
            package.title = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines).decodedHTMLEntities.nilIfBlank
            isReadingTitle = false
            textBuffer = ""
        } else if element == "metadata" {
            isInsideMetadata = false
        }
    }
}

private extension URL {
    func appendingEPUBPath(_ path: String) -> URL {
        let pathWithoutFragment = (path.components(separatedBy: "#").first ?? path)
        let decodedPath = pathWithoutFragment.removingPercentEncoding ?? pathWithoutFragment
        return URL(fileURLWithPath: decodedPath, relativeTo: self).standardizedFileURL
    }
}

private extension String {
    var xmlElementName: String {
        components(separatedBy: ":").last?.lowercased() ?? lowercased()
    }

    var epubDisplayTitle: String {
        let lastComponent = (components(separatedBy: "#").first ?? self)
            .removingPercentEncoding ?? self
        let stem = URL(fileURLWithPath: lastComponent).deletingPathExtension().lastPathComponent
        return stem
            .replacingOccurrences(of: #"[_-]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
