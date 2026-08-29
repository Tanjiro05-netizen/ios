import Foundation
import JavaScriptCore

struct StudyMathEquivalenceResult: Equatable, Sendable {
    let isEquivalent: Bool
    let mathJSON: String?
    let message: String
}

/// Runs the bundled Cortex Compute Engine in a data-only JavaScriptCore context.
/// The context has no DOM, fetch API, app cookies, authentication tokens, or
/// course-provided executable code.
actor StudyComputeEngineEvaluator {
    static let shared = StudyComputeEngineEvaluator()

    private var context: JSContext?
    private var loadFailure: String?

    func evaluate(submittedLaTeX: String, acceptedLaTeX: [String]) -> StudyMathEquivalenceResult {
        guard !acceptedLaTeX.isEmpty else {
            return .init(
                isEquivalent: false,
                mathJSON: nil,
                message: "This activity has no locally verifiable reference expression. Your draft was saved for review."
            )
        }
        guard let context = loadContext() else {
            return normalizedFallback(submittedLaTeX: submittedLaTeX, acceptedLaTeX: acceptedLaTeX)
        }

        let payload: [String: Any] = [
            "submitted": String(submittedLaTeX.prefix(4_096)),
            "accepted": acceptedLaTeX.map { String($0.prefix(4_096)) }
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return .init(isEquivalent: false, mathJSON: nil, message: "The expression could not be checked.")
        }

        var exception: String?
        context.exceptionHandler = { _, value in exception = value?.toString() }
        let script = """
        (() => {
          const payload = \(json);
          const ce = new ComputeEngine.ComputeEngine();
          const submitted = ce.parse(payload.submitted, { canonical: true });
          const equivalent = payload.accepted.some((candidate) => {
            const expected = ce.parse(candidate, { canonical: true });
            return submitted.isSame(expected) === true || submitted.isEqual(expected) === true;
          });
          return JSON.stringify({ equivalent, mathJSON: submitted.json });
        })()
        """
        guard let value = context.evaluateScript(script)?.toString(), exception == nil,
              let resultData = value.data(using: .utf8),
              let result = try? JSONDecoder().decode(JavaScriptResult.self, from: resultData) else {
            return .init(
                isEquivalent: false,
                mathJSON: nil,
                message: exception.map { "The local math checker reported: \($0)" }
                    ?? "The expression could not be parsed by the local math checker."
            )
        }
        let mathJSON = result.mathJSON.flatMap { value -> String? in
            guard let data = try? JSONSerialization.data(withJSONObject: value.foundationValue, options: [.sortedKeys]) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        return .init(
            isEquivalent: result.equivalent,
            mathJSON: mathJSON,
            message: result.equivalent
                ? "Equivalent expression confirmed by the offline symbolic checker."
                : "The expression is not equivalent yet. Check each term, sign, exponent, and subscript."
        )
    }

    private func loadContext() -> JSContext? {
        if let context { return context }
        if loadFailure != nil { return nil }
        guard let url = StudyScienceRuntimeResources.url(
            named: "compute-engine.min",
            extension: "js",
            subdirectory: "ScienceRuntime/compute-engine"
        ), let source = try? String(contentsOf: url, encoding: .utf8),
           let context = JSContext() else {
            loadFailure = "The bundled symbolic runtime is unavailable."
            return nil
        }
        var exception: String?
        context.exceptionHandler = { _, value in exception = value?.toString() }
        context.evaluateScript(source)
        guard exception == nil,
              context.objectForKeyedSubscript("ComputeEngine")?.isUndefined == false else {
            loadFailure = exception ?? "The bundled symbolic runtime failed to initialize."
            return nil
        }
        self.context = context
        return context
    }

    private func normalizedFallback(
        submittedLaTeX: String,
        acceptedLaTeX: [String]
    ) -> StudyMathEquivalenceResult {
        let submitted = Self.normalize(submittedLaTeX)
        let equivalent = !submitted.isEmpty && acceptedLaTeX.map(Self.normalize).contains(submitted)
        return .init(
            isEquivalent: equivalent,
            mathJSON: nil,
            message: equivalent
                ? "Expression matched the authored form. The symbolic checker was unavailable."
                : (loadFailure ?? "The symbolic checker was unavailable; compare your expression with the authored form.")
        )
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\\left", with: "")
            .replacingOccurrences(of: "\\right", with: "")
            .lowercased()
    }

    private struct JavaScriptResult: Decodable {
        let equivalent: Bool
        let mathJSON: JSONValue?
    }

    private enum JSONValue: Decodable {
        case array([JSONValue])
        case object([String: JSONValue])
        case string(String)
        case number(Double)
        case bool(Bool)
        case null

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .null }
            else if let value = try? container.decode(Bool.self) { self = .bool(value) }
            else if let value = try? container.decode(Double.self) { self = .number(value) }
            else if let value = try? container.decode(String.self) { self = .string(value) }
            else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
            else { self = .object(try container.decode([String: JSONValue].self)) }
        }

        var foundationValue: Any {
            switch self {
            case .array(let value): value.map(\.foundationValue)
            case .object(let value): value.mapValues { $0.foundationValue }
            case .string(let value): value
            case .number(let value): value
            case .bool(let value): value
            case .null: NSNull()
            }
        }
    }
}
