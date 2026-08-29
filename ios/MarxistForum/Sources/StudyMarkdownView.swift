import Foundation
import SwiftUI

/// A lightweight native block renderer for authored course Markdown.
/// It keeps the existing Study Center typography while retaining headings,
/// lists, quotations, code, and tables that a single AttributedString loses.
struct StudyMarkdownDocument: View {
    let markdown: String
    /// Optional serif prose size for reading surfaces (the text-edition
    /// reader). Nil keeps the Study Center's default system typography.
    var bodyFontSize: CGFloat?
    private let blocks: [StudyMarkdownBlock]

    init(markdown: String, bodyFontSize: CGFloat? = nil) {
        self.markdown = markdown
        self.bodyFontSize = bodyFontSize
        self.blocks = StudyMarkdownParser.parse(markdown)
    }

    private var proseFont: Font {
        guard let bodyFontSize else { return .body }
        return .system(size: bodyFontSize, design: .serif)
    }

    private var proseScale: CGFloat {
        guard let bodyFontSize else { return 1 }
        return bodyFontSize / 17
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 13) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: StudyMarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            inlineText(block.text)
                .font(headingFont(level))
                .padding(.top, level <= 2 ? 8 : 3)
                .accessibilityAddTraits(.isHeader)
        case .paragraph:
            if StudyMarkdownParser.containsInlineMath(block.text) {
                StudyScientificDocumentView(document: .init(blocks: [
                    .paragraph(
                        id: "markdown-paragraph-\(block.id)",
                        html: StudyMarkdownParser.scientificInlineHTML(block.text)
                    )
                ]))
                .accessibilityLabel(StudyMarkdownParser.plainMathDescription(block.text))
            } else {
                inlineText(block.text)
                    .font(proseFont)
                    .lineSpacing(3)
            }
        case .unorderedList:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(block.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("•").foregroundStyle(Brand.redSoft)
                        inlineText(item).font(proseFont)
                    }
                }
            }
        case .orderedList:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(block.items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("\(index + 1).")
                            .font(proseFont.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Brand.redSoft)
                        inlineText(item).font(proseFont)
                    }
                }
            }
        case .quotation:
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(Brand.red.opacity(0.55))
                    .frame(width: 3)
                inlineText(block.text)
                    .font(proseFont.italic())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
        case .code:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(Brand.controlFill, in: RoundedRectangle(cornerRadius: 10))
        case .equation:
            StudyScientificDocumentView(document: .init(blocks: [
                .equation(
                    id: "markdown-equation-\(block.id)",
                    latex: block.text,
                    spokenText: StudyMarkdownParser.plainMathDescription(block.text),
                    number: nil
                )
            ]))
            .accessibilityLabel(StudyMarkdownParser.plainMathDescription(block.text))
        case .table:
            StudyMarkdownTable(rows: block.rows)
        case .divider:
            Divider().padding(.vertical, 3)
        }
    }

    private func inlineText(_ value: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        let attributed = (try? AttributedString(markdown: value, options: options)) ?? AttributedString(value)
        return Text(attributed)
    }

    private func headingFont(_ level: Int) -> Font {
        guard bodyFontSize != nil else {
            return Self.defaultHeadingFont(level)
        }
        let base: CGFloat
        switch level {
        case 1: base = 28
        case 2: base = 22
        case 3: base = 20
        default: base = 17
        }
        return .system(size: base * proseScale, weight: .semibold, design: .serif)
    }

    private static func defaultHeadingFont(_ level: Int) -> Font {
        switch level {
        case 1: .system(.title, design: .serif, weight: .semibold)
        case 2: .system(.title2, design: .serif, weight: .semibold)
        case 3: .system(.title3, design: .serif, weight: .semibold)
        default: .system(.headline, design: .serif, weight: .semibold)
        }
    }
}

private struct StudyMarkdownTable: View {
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(inline(cell))
                                .font(rowIndex == 0 ? .caption.weight(.bold) : .caption)
                                .frame(minWidth: 150, maxWidth: 230, alignment: .topLeading)
                                .padding(9)
                                .background(rowIndex == 0 ? Brand.red.opacity(0.08) : Color.clear)
                                .overlay(alignment: .trailing) { Divider() }
                        }
                    }
                    if rowIndex < rows.count - 1 { Divider() }
                }
            }
            .background(Brand.subtleFill.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Brand.separator.opacity(0.55), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func inline(_ value: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: value, options: options)) ?? AttributedString(value)
    }
}

private struct StudyMarkdownBlock: Identifiable {
    enum Kind {
        case heading(Int)
        case paragraph
        case unorderedList
        case orderedList
        case quotation
        case code
        case equation
        case table
        case divider
    }

    let id: Int
    let kind: Kind
    var text = ""
    var items: [String] = []
    var rows: [[String]] = []
}

private enum StudyMarkdownParser {
    private static let heading = try! NSRegularExpression(pattern: #"^(#{1,6})\s+(.+?)\s*$"#)
    private static let unordered = try! NSRegularExpression(pattern: #"^\s*[-*+]\s+(.+)$"#)
    private static let ordered = try! NSRegularExpression(pattern: #"^\s*\d+[.)]\s+(.+)$"#)
    private static let tableDivider = try! NSRegularExpression(pattern: #"^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|?\s*$"#)

    static func parse(_ markdown: String) -> [StudyMarkdownBlock] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [StudyMarkdownBlock] = []
        var index = 0

        func append(_ kind: StudyMarkdownBlock.Kind, text: String = "", items: [String] = [], rows: [[String]] = []) {
            blocks.append(StudyMarkdownBlock(id: blocks.count, kind: kind, text: text, items: items, rows: rows))
        }

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                append(.divider)
                index += 1
                continue
            }
            if line.hasPrefix("```") {
                index += 1
                var code: [String] = []
                while index < lines.count, !lines[index].hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                append(.code, text: code.joined(separator: "\n"))
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("$$") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.count > 4, trimmed.hasSuffix("$$") {
                    append(.equation, text: String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines))
                    index += 1
                } else {
                    index += 1
                    var equation: [String] = []
                    while index < lines.count,
                          !lines[index].trimmingCharacters(in: .whitespaces).hasSuffix("$$") {
                        equation.append(lines[index])
                        index += 1
                    }
                    if index < lines.count {
                        let closingLine = lines[index].trimmingCharacters(in: .whitespaces)
                        if closingLine != "$$" {
                            equation.append(String(closingLine.dropLast(2)))
                        }
                        index += 1
                    }
                    append(.equation, text: equation.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
                }
                continue
            }
            if let match = capture(heading, in: line), match.count == 2 {
                append(.heading(match[0].count), text: match[1])
                index += 1
                continue
            }
            if index + 1 < lines.count,
               line.contains("|"),
               capture(tableDivider, in: lines[index + 1]) != nil {
                var rows = [tableCells(line)]
                index += 2
                while index < lines.count, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(tableCells(lines[index]))
                    index += 1
                }
                append(.table, rows: rows)
                continue
            }
            if capture(unordered, in: line) != nil {
                var items: [String] = []
                while index < lines.count, let values = capture(unordered, in: lines[index]) {
                    items.append(values[0])
                    index += 1
                }
                append(.unorderedList, items: items)
                continue
            }
            if capture(ordered, in: line) != nil {
                var items: [String] = []
                while index < lines.count, let values = capture(ordered, in: lines[index]) {
                    items.append(values[0])
                    index += 1
                }
                append(.orderedList, items: items)
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                var quote: [String] = []
                while index < lines.count {
                    let value = lines[index].trimmingCharacters(in: .whitespaces)
                    guard value.hasPrefix(">") else { break }
                    quote.append(String(value.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                append(.quotation, text: quote.joined(separator: "\n"))
                continue
            }

            var paragraph = [line]
            index += 1
            while index < lines.count,
                  !lines[index].trimmingCharacters(in: .whitespaces).isEmpty,
                  !startsBlock(lines, at: index) {
                paragraph.append(lines[index])
                index += 1
            }
            append(.paragraph, text: paragraph.joined(separator: "\n"))
        }
        return blocks
    }

    private static func startsBlock(_ lines: [String], at index: Int) -> Bool {
        let line = lines[index]
        if line.hasPrefix("```")
            || line.trimmingCharacters(in: .whitespaces) == "---"
            || line.trimmingCharacters(in: .whitespaces).hasPrefix("$$") { return true }
        if capture(heading, in: line) != nil || capture(unordered, in: line) != nil || capture(ordered, in: line) != nil { return true }
        if line.trimmingCharacters(in: .whitespaces).hasPrefix(">") { return true }
        return index + 1 < lines.count && line.contains("|") && capture(tableDivider, in: lines[index + 1]) != nil
    }

    private static func capture(_ regex: NSRegularExpression, in value: String) -> [String]? {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range), match.range.location != NSNotFound else { return nil }
        if match.numberOfRanges == 1 { return [] }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return String(value[range])
        }
    }

    private static func tableCells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func containsInlineMath(_ value: String) -> Bool {
        var delimiterCount = 0
        var previous: Character?
        for character in value {
            if character == "$", previous != "\\" { delimiterCount += 1 }
            previous = character
        }
        return delimiterCount >= 2
    }

    static func scientificInlineHTML(_ value: String) -> String {
        var result = value.replacingOccurrences(of: "\n", with: "<br>")
        result = paired(result, marker: "**", opening: "<strong>", closing: "</strong>")
        result = paired(result, marker: "__", opening: "<strong>", closing: "</strong>")
        result = paired(result, marker: "`", opening: "<code>", closing: "</code>")
        result = paired(result, marker: "*", opening: "<em>", closing: "</em>")
        return result
    }

    static func plainMathDescription(_ value: String) -> String {
        value
            .replacingOccurrences(of: "$$", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "\\vec", with: "vector")
            .replacingOccurrences(of: "\\Delta", with: "delta")
            .replacingOccurrences(of: "\\theta", with: "theta")
            .replacingOccurrences(of: "\\cdot", with: "times")
            .replacingOccurrences(of: "\\times", with: "times")
            .replacingOccurrences(of: "\\", with: " ")
    }

    private static func paired(
        _ value: String,
        marker: String,
        opening: String,
        closing: String
    ) -> String {
        let pieces = value.components(separatedBy: marker)
        guard pieces.count > 2 else { return value }
        return pieces.enumerated().map { index, piece in
            guard index > 0 else { return piece }
            return (index.isMultiple(of: 2) ? closing : opening) + piece
        }.joined()
    }
}
