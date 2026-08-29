import Foundation
import Observation
import SwiftUI

extension StudyCalculatorAngleMode {
    var calculatorTitle: String {
        switch self {
        case .degrees: "DEG"
        case .radians: "RAD"
        }
    }
}

struct StudyScientificCalculatorProfileUI: Equatable, Sendable {
    var title: String
    var formulaCard: [String]
    var allowsHistory: Bool

    static let lesson = StudyScientificCalculatorProfileUI(
        title: "Scientific calculator",
        formulaCard: [],
        allowsHistory: true
    )

    static let moduleOneAssessment = StudyScientificCalculatorProfileUI(
        title: "Assessment calculator",
        formulaCard: [
            "v = v₀ + at",
            "x = x₀ + v₀t + ½at²",
            "v² = v₀² + 2a(x − x₀)",
            "Fₙₑₜ = ma"
        ],
        allowsHistory: true
    )
}

struct StudyCalculatorHistoryEntry: Identifiable, Equatable, Sendable {
    let id = UUID()
    let expression: String
    let result: String
}

enum StudyScientificCalculatorError: LocalizedError, Equatable {
    case emptyExpression
    case unexpectedCharacter(Character)
    case unexpectedToken
    case missingClosingParenthesis
    case unknownFunction(String)
    case invalidNumber
    case divisionByZero
    case domainError
    case nonFiniteResult

    var errorDescription: String? {
        switch self {
        case .emptyExpression: "Enter a calculation."
        case .unexpectedCharacter(let character): "The character “\(character)” is not supported."
        case .unexpectedToken: "Check the order of numbers, functions, and parentheses."
        case .missingClosingParenthesis: "A closing parenthesis is missing."
        case .unknownFunction(let name): "The function “\(name)” is not available."
        case .invalidNumber: "One of the numbers is incomplete."
        case .divisionByZero: "Division by zero is undefined."
        case .domainError: "That input is outside this function’s domain."
        case .nonFiniteResult: "The result is too large or is not a real number."
        }
    }
}

/// A deliberately small scientific-expression parser. It does not use `eval`,
/// `NSExpression`, a network service, or a symbolic algebra system.
struct StudyScientificCalculatorEngine: Sendable {
    func evaluate(
        _ expression: String,
        angleMode: StudyCalculatorAngleMode = .degrees
    ) throws -> Double {
        let tokens = try Lexer(expression: expression).lex()
        guard !tokens.isEmpty else { throw StudyScientificCalculatorError.emptyExpression }
        var parser = Parser(tokens: tokens, angleMode: angleMode)
        let value = try parser.parse()
        guard value.isFinite else { throw StudyScientificCalculatorError.nonFiniteResult }
        return value
    }

    func format(_ value: Double) -> String {
        if value == 0 { return "0" }
        let absolute = abs(value)
        if absolute >= 1_000_000_000 || absolute < 0.000_000_1 {
            return value.formatted(.number.notation(.scientific).precision(.significantDigits(1...12)))
        }
        return value.formatted(.number.grouping(.never).precision(.significantDigits(1...12)))
    }

    private enum Token: Equatable, Sendable {
        case number(Double)
        case identifier(String)
        case plus
        case minus
        case multiply
        case divide
        case power
        case leftParenthesis
        case rightParenthesis

        var endsPrimary: Bool {
            switch self {
            case .number, .rightParenthesis: true
            case .identifier(let name): name == "pi" || name == "e"
            default: false
            }
        }

        var beginsPrimary: Bool {
            switch self {
            case .number, .identifier, .leftParenthesis: true
            default: false
            }
        }
    }

    private struct Lexer {
        let expression: String

        func lex() throws -> [Token] {
            let characters = Array(
                expression
                    .replacingOccurrences(of: "−", with: "-")
                    .replacingOccurrences(of: "×", with: "*")
                    .replacingOccurrences(of: "÷", with: "/")
            )
            var raw: [Token] = []
            var index = 0

            while index < characters.count {
                let character = characters[index]
                if character.isWhitespace {
                    index += 1
                    continue
                }

                switch character {
                case "+": raw.append(.plus); index += 1
                case "-": raw.append(.minus); index += 1
                case "*": raw.append(.multiply); index += 1
                case "/": raw.append(.divide); index += 1
                case "^": raw.append(.power); index += 1
                case "(": raw.append(.leftParenthesis); index += 1
                case ")": raw.append(.rightParenthesis); index += 1
                case "π": raw.append(.identifier("pi")); index += 1
                case "√": raw.append(.identifier("sqrt")); index += 1
                default:
                    if character.isNumber || character == "." {
                        let start = index
                        var hasDecimal = false
                        var hasExponent = false
                        while index < characters.count {
                            let current = characters[index]
                            if current.isNumber {
                                index += 1
                            } else if current == ".", !hasDecimal, !hasExponent {
                                hasDecimal = true
                                index += 1
                            } else if (current == "e" || current == "E"), !hasExponent {
                                hasExponent = true
                                index += 1
                                if index < characters.count, characters[index] == "+" || characters[index] == "-" {
                                    index += 1
                                }
                            } else {
                                break
                            }
                        }
                        let literal = String(characters[start..<index])
                        guard let value = Double(literal) else {
                            throw StudyScientificCalculatorError.invalidNumber
                        }
                        raw.append(.number(value))
                    } else if character.isLetter {
                        let start = index
                        while index < characters.count, characters[index].isLetter { index += 1 }
                        raw.append(.identifier(String(characters[start..<index]).lowercased()))
                    } else {
                        throw StudyScientificCalculatorError.unexpectedCharacter(character)
                    }
                }
            }

            var normalized: [Token] = []
            for token in raw {
                if let previous = normalized.last,
                   previous.endsPrimary,
                   token.beginsPrimary,
                   !Self.isFunctionCall(previous: previous, next: token) {
                    normalized.append(.multiply)
                }
                normalized.append(token)
            }
            return normalized
        }

        private static func isFunctionCall(previous: Token, next: Token) -> Bool {
            guard case .identifier(let name) = previous, case .leftParenthesis = next else { return false }
            return name != "pi" && name != "e"
        }
    }

    private struct Parser {
        let tokens: [Token]
        let angleMode: StudyCalculatorAngleMode
        var index = 0

        mutating func parse() throws -> Double {
            let value = try expression()
            guard index == tokens.count else { throw StudyScientificCalculatorError.unexpectedToken }
            return value
        }

        private mutating func expression() throws -> Double {
            var value = try term()
            while let token = current {
                switch token {
                case .plus:
                    advance()
                    value += try term()
                case .minus:
                    advance()
                    value -= try term()
                default:
                    return value
                }
            }
            return value
        }

        private mutating func term() throws -> Double {
            var value = try power()
            while let token = current {
                switch token {
                case .multiply:
                    advance()
                    value *= try power()
                case .divide:
                    advance()
                    let divisor = try power()
                    guard divisor != 0 else { throw StudyScientificCalculatorError.divisionByZero }
                    value /= divisor
                default:
                    return value
                }
            }
            return value
        }

        private mutating func power() throws -> Double {
            let base = try unary()
            guard current == .power else { return base }
            advance()
            let exponent = try power()
            let result = Foundation.pow(base, exponent)
            guard result.isFinite else { throw StudyScientificCalculatorError.domainError }
            return result
        }

        private mutating func unary() throws -> Double {
            if current == .plus {
                advance()
                return try unary()
            }
            if current == .minus {
                advance()
                return -(try unary())
            }
            return try primary()
        }

        private mutating func primary() throws -> Double {
            guard let token = current else { throw StudyScientificCalculatorError.unexpectedToken }
            switch token {
            case .number(let value):
                advance()
                return value
            case .identifier(let name):
                advance()
                if name == "pi" { return .pi }
                if name == "e" { return Foundation.exp(1) }
                let argument: Double
                if current == .leftParenthesis {
                    advance()
                    argument = try expression()
                    guard current == .rightParenthesis else {
                        throw StudyScientificCalculatorError.missingClosingParenthesis
                    }
                    advance()
                } else {
                    argument = try unary()
                }
                return try apply(function: name, to: argument)
            case .leftParenthesis:
                advance()
                let value = try expression()
                guard current == .rightParenthesis else {
                    throw StudyScientificCalculatorError.missingClosingParenthesis
                }
                advance()
                return value
            default:
                throw StudyScientificCalculatorError.unexpectedToken
            }
        }

        private func apply(function name: String, to value: Double) throws -> Double {
            let radians = angleMode == .degrees ? value * .pi / 180 : value
            let result: Double
            switch name {
            case "sin": result = Foundation.sin(radians)
            case "cos": result = Foundation.cos(radians)
            case "tan": result = Foundation.tan(radians)
            case "asin":
                guard (-1...1).contains(value) else { throw StudyScientificCalculatorError.domainError }
                let raw = Foundation.asin(value)
                result = angleMode == .degrees ? raw * 180 / .pi : raw
            case "acos":
                guard (-1...1).contains(value) else { throw StudyScientificCalculatorError.domainError }
                let raw = Foundation.acos(value)
                result = angleMode == .degrees ? raw * 180 / .pi : raw
            case "atan":
                let raw = Foundation.atan(value)
                result = angleMode == .degrees ? raw * 180 / .pi : raw
            case "log":
                guard value > 0 else { throw StudyScientificCalculatorError.domainError }
                result = Foundation.log10(value)
            case "ln":
                guard value > 0 else { throw StudyScientificCalculatorError.domainError }
                result = Foundation.log(value)
            case "sqrt":
                guard value >= 0 else { throw StudyScientificCalculatorError.domainError }
                result = Foundation.sqrt(value)
            case "abs": result = Swift.abs(value)
            case "exp": result = Foundation.exp(value)
            default: throw StudyScientificCalculatorError.unknownFunction(name)
            }
            guard result.isFinite else { throw StudyScientificCalculatorError.nonFiniteResult }
            return result
        }

        private var current: Token? {
            index < tokens.count ? tokens[index] : nil
        }

        private mutating func advance() { index += 1 }
    }
}

@MainActor
@Observable
final class StudyScientificCalculatorState {
    var expression = ""
    var result = "0"
    var angleMode: StudyCalculatorAngleMode = .degrees
    var memory: Double?
    var history: [StudyCalculatorHistoryEntry] = []
    var errorMessage: String?

    private let engine = StudyScientificCalculatorEngine()

    func append(_ token: String) {
        errorMessage = nil
        expression.append(token)
    }

    func deleteBackward() {
        errorMessage = nil
        guard !expression.isEmpty else { return }
        expression.removeLast()
    }

    func clear() {
        expression = ""
        result = "0"
        errorMessage = nil
    }

    func toggleSign() {
        errorMessage = nil
        expression = expression.hasPrefix("-")
            ? String(expression.dropFirst())
            : "-(\(expression.isEmpty ? "0" : expression))"
    }

    func evaluate(allowsHistory: Bool) {
        do {
            let value = try engine.evaluate(expression, angleMode: angleMode)
            let formatted = engine.format(value)
            result = formatted
            if allowsHistory {
                history.insert(.init(expression: expression, result: formatted), at: 0)
                history = Array(history.prefix(20))
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func memoryClear() { memory = nil }

    func memoryRecall() {
        guard let memory else { return }
        append(engine.format(memory))
    }

    func memoryAdd() {
        guard let value = try? engine.evaluate(result, angleMode: angleMode) else { return }
        memory = (memory ?? 0) + value
    }

    func useHistory(_ entry: StudyCalculatorHistoryEntry) {
        expression = entry.expression
        result = entry.result
        errorMessage = nil
    }

    func resetAttempt() {
        clear()
        memory = nil
        history = []
        angleMode = .degrees
    }
}

struct StudyScientificCalculatorView: View {
    let profile: StudyScientificCalculatorProfileUI
    var onUseResult: ((String) -> Void)?

    @State private var state = StudyScientificCalculatorState()
    @State private var selectedPanel: CalculatorPanel?

    private enum CalculatorPanel: String, Identifiable {
        case formulas
        case history
        var id: String { rawValue }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        VStack(spacing: 12) {
            calculatorHeader
            calculatorDisplay
            memoryRow
            LazyVGrid(columns: columns, spacing: 8) {
                functionButton("sin", token: "sin(")
                functionButton("cos", token: "cos(")
                functionButton("tan", token: "tan(")
                functionButton("log", token: "log(")
                functionButton("ln", token: "ln(")

                functionButton("sin⁻¹", token: "asin(")
                functionButton("cos⁻¹", token: "acos(")
                functionButton("tan⁻¹", token: "atan(")
                functionButton("√", token: "sqrt(")
                functionButton("xʸ", token: "^")

                inputButton("7")
                inputButton("8")
                inputButton("9")
                inputButton("(")
                inputButton(")")

                inputButton("4")
                inputButton("5")
                inputButton("6")
                operatorButton("×", token: "*")
                operatorButton("÷", token: "/")

                inputButton("1")
                inputButton("2")
                inputButton("3")
                operatorButton("+", token: "+")
                operatorButton("−", token: "-")

                inputButton("0")
                inputButton(".")
                functionButton("π", token: "pi")
                functionButton("e", token: "e")
                Button("=") { state.evaluate(allowsHistory: profile.allowsHistory) }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Brand.onAccent)
                    .background(Brand.red, in: RoundedRectangle(cornerRadius: 11))
                    .buttonStyle(PressableScaleButtonStyle(scale: 0.96))
                    .accessibilityLabel("Calculate")
            }

            if let onUseResult {
                Button {
                    onUseResult(state.result)
                } label: {
                    Label("Use result", systemImage: "arrow.down.doc")
                        .frame(maxWidth: .infinity)
                }
                .studyPrimaryActionStyle()
                .disabled(state.errorMessage != nil)
            }
        }
        .padding(16)
        .background(ScreenBackground())
        .sheet(item: $selectedPanel) { panel in
            NavigationStack {
                Group {
                    switch panel {
                    case .formulas: formulaCard
                    case .history: historyList
                    }
                }
                .navigationTitle(panel == .formulas ? "Formula card" : "Attempt history")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var calculatorHeader: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.title)
                    .font(.headline)
                Text("Offline · no graphing or algebra solver")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !profile.formulaCard.isEmpty {
                Button { selectedPanel = .formulas } label: {
                    Image(systemName: "function")
                        .toolbarIconChrome()
                }
                .accessibilityLabel("Open formula card")
            }
            if profile.allowsHistory {
                Button { selectedPanel = .history } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .toolbarIconChrome()
                }
                .accessibilityLabel("Open attempt calculator history")
            }
        }
    }

    private var calculatorDisplay: some View {
        VStack(alignment: .trailing, spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(state.expression.isEmpty ? "0" : state.expression)
                    .font(.title3.monospaced())
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Text(state.result)
                .font(.system(.largeTitle, design: .monospaced, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .accessibilityLabel("Result \(state.result)")
            if let errorMessage = state.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Brand.redSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                Picker("Angle mode", selection: $state.angleMode) {
                    ForEach(StudyCalculatorAngleMode.allCases) { Text($0.calculatorTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                Button("+/−") { state.toggleSign() }
                    .buttonStyle(.bordered)
                Button { state.deleteBackward() } label: { Image(systemName: "delete.left") }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Delete")
                Button("AC", role: .destructive) { state.clear() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .studyPaperSurface(cornerRadius: 16, emphasized: true)
    }

    private var memoryRow: some View {
        HStack {
            Button("MC") { state.memoryClear() }
            Button("MR") { state.memoryRecall() }
            Button("M+") { state.memoryAdd() }
            Spacer()
            Text(state.memory == nil ? "Memory empty" : "M stored")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.borderless)
    }

    private func inputButton(_ label: String) -> some View {
        Button(label) { state.append(label) }
            .calculatorKeyStyle(fill: Brand.surface)
    }

    private func functionButton(_ label: String, token: String) -> some View {
        Button(label) { state.append(token) }
            .calculatorKeyStyle(fill: Brand.controlFill)
    }

    private func operatorButton(_ label: String, token: String) -> some View {
        Button(label) { state.append(token) }
            .calculatorKeyStyle(fill: Brand.red.opacity(0.13), foreground: Brand.redSoft)
    }

    private var formulaCard: some View {
        List(profile.formulaCard, id: \.self) { formula in
            Text(formula)
                .font(.system(.body, design: .serif))
                .accessibilityLabel(formula)
        }
    }

    private var historyList: some View {
        Group {
            if state.history.isEmpty {
                ContentUnavailableView("No calculations yet", systemImage: "clock")
            } else {
                List(state.history) { entry in
                    Button {
                        state.useHistory(entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.expression).font(.body.monospaced())
                            Text("= \(entry.result)")
                                .font(.headline.monospaced())
                                .foregroundStyle(Brand.redSoft)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct StudyScientificCalculatorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let profile: StudyScientificCalculatorProfileUI
    var onUseResult: ((String) -> Void)?

    var body: some View {
        NavigationStack {
            StudyScientificCalculatorView(profile: profile) { result in
                onUseResult?(result)
                dismiss()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private extension View {
    func calculatorKeyStyle(fill: Color, foreground: Color = .primary) -> some View {
        self
            .font(.body.weight(.semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(fill, in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Brand.separator.opacity(0.55), lineWidth: 1)
            }
            .buttonStyle(PressableScaleButtonStyle(scale: 0.96))
    }
}

#Preview("Scientific calculator") {
    StudyScientificCalculatorView(profile: .moduleOneAssessment)
}
