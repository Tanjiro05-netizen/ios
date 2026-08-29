import Charts
import SwiftUI

struct StudyScienceGraphPointUI: Identifiable, Equatable, Sendable {
    let id: String
    let x: Double
    let y: Double

    init(id: String? = nil, x: Double, y: Double) {
        self.id = id ?? "\(x.formatted(.number.precision(.fractionLength(12))))::\(y.formatted(.number.precision(.fractionLength(12))))"
        self.x = x
        self.y = y
    }
}

struct StudyScienceLineGraph: View {
    let points: [StudyScienceGraphPointUI]
    let xLabel: String
    let yLabel: String

    var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value(xLabel, point.x),
                y: .value(yLabel, point.y)
            )
            .foregroundStyle(Brand.red)
            PointMark(
                x: .value(xLabel, point.x),
                y: .value(yLabel, point.y)
            )
            .foregroundStyle(Brand.redSoft)
            .symbolSize(points.count > 100 ? 8 : 22)
        }
        .chartXAxisLabel(xLabel)
        .chartYAxisLabel(yLabel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(yLabel) plotted against \(xLabel)")
        .accessibilityValue("\(points.count) data points. Use the accessible data table for exact values.")
    }
}

struct StudyNumericGrade: Equatable, Sendable {
    let isCorrect: Bool
    let message: String
}

enum StudyNumericResponseGrader {
    static func grade(
        rawValue: String,
        unitID: String?,
        specification: StudyNumericAnswerSpecification
    ) -> StudyNumericGrade {
        guard let submitted = decimal(rawValue) else {
            return .init(isCorrect: false, message: "Enter a valid decimal number.")
        }
        if specification.requiresUnit,
           unitID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return .init(isCorrect: false, message: "Include a unit with this answer.")
        }

        let acceptedUnits = Set(
            ([specification.canonicalUnitID].compactMap { $0 } + specification.acceptedUnitIDs)
                .map(StudyUnitNormalizer.normalizeID)
        )
        let canonicalUnit = specification.canonicalUnitID.map(StudyUnitNormalizer.normalizeID)
        let submittedUnit = unitID.map(StudyUnitNormalizer.normalizeID)

        let canonicalized: Double
        if let submittedUnit, let canonicalUnit, submittedUnit != canonicalUnit {
            guard acceptedUnits.contains(submittedUnit),
                  let converted = StudyUnitNormalizer.convert(
                    submitted,
                    from: submittedUnit,
                    to: canonicalUnit
                  ) else {
                return .init(
                    isCorrect: false,
                    message: "Use \(specification.canonicalUnitID ?? "the requested unit") or an equivalent accepted unit."
                )
            }
            canonicalized = converted
        } else {
            canonicalized = submitted
        }

        let absoluteError = abs(canonicalized - specification.canonicalValue)
        let absoluteTolerance = specification.absoluteTolerance ?? 0
        let relativeTolerance = (specification.relativeTolerance ?? 0) * abs(specification.canonicalValue)
        let tolerance = max(absoluteTolerance, relativeTolerance, 1e-12)
        guard absoluteError <= tolerance else {
            return .init(
                isCorrect: false,
                message: specification.feedbackMarkdown ?? "Check the model, substitution, sign, and units, then try again."
            )
        }
        if let minimum = specification.minimumSignificantFigures,
           significantFigures(in: rawValue) < minimum {
            return .init(isCorrect: false, message: "Give at least \(minimum) significant figures.")
        }
        return .init(isCorrect: true, message: specification.feedbackMarkdown ?? "Correct.")
    }

    static func significantFigures(in rawValue: String) -> Int {
        let mantissa = rawValue.lowercased().split(separator: "e", maxSplits: 1).first.map(String.init) ?? rawValue
        let digits = mantissa.filter(\.isNumber)
        guard let firstNonZero = digits.firstIndex(where: { $0 != "0" }) else {
            return mantissa.contains(".") ? max(digits.count - 1, 1) : 1
        }
        return digits.distance(from: firstNonZero, to: digits.endIndex)
    }

    private static func decimal(_ value: String) -> Double? {
        Double(
            value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
                .replacingOccurrences(of: "−", with: "-")
        )
    }
}

enum StudyUnitNormalizer {
    private struct UnitDefinition {
        let dimension: String
        let scaleToBase: Double
    }

    private static let definitions: [String: UnitDefinition] = [
        "m": .init(dimension: "length", scaleToBase: 1),
        "cm": .init(dimension: "length", scaleToBase: 0.01),
        "mm": .init(dimension: "length", scaleToBase: 0.001),
        "km": .init(dimension: "length", scaleToBase: 1_000),
        "s": .init(dimension: "time", scaleToBase: 1),
        "ms": .init(dimension: "time", scaleToBase: 0.001),
        "min": .init(dimension: "time", scaleToBase: 60),
        "h": .init(dimension: "time", scaleToBase: 3_600),
        "kg": .init(dimension: "mass", scaleToBase: 1),
        "g": .init(dimension: "mass", scaleToBase: 0.001),
        "m/s": .init(dimension: "speed", scaleToBase: 1),
        "cm/s": .init(dimension: "speed", scaleToBase: 0.01),
        "km/h": .init(dimension: "speed", scaleToBase: 1 / 3.6),
        "m/s^2": .init(dimension: "acceleration", scaleToBase: 1),
        "cm/s^2": .init(dimension: "acceleration", scaleToBase: 0.01),
        "n": .init(dimension: "force", scaleToBase: 1),
        "kn": .init(dimension: "force", scaleToBase: 1_000),
        "rad": .init(dimension: "angle", scaleToBase: 1),
        "deg": .init(dimension: "angle", scaleToBase: .pi / 180)
    ]

    static func normalizeID(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "²", with: "^2")
            .replacingOccurrences(of: "⋅", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    static func convert(_ value: Double, from: String, to: String) -> Double? {
        guard let source = definitions[normalizeID(from)],
              let target = definitions[normalizeID(to)],
              source.dimension == target.dimension else { return nil }
        return value * source.scaleToBase / target.scaleToBase
    }
}

struct StudyNumericQuantityActivityView: View {
    let configuration: StudyNumericQuantityActivityConfiguration
    var initialResponse: StudyNumericQuantityResponse?
    var onDraft: (StudyInteractiveResponse) -> Void
    var onComplete: (StudyInteractiveResponse) -> Void

    @State private var values: [String: String]
    @State private var units: [String: String]
    @State private var grades: [String: StudyNumericGrade] = [:]

    init(
        configuration: StudyNumericQuantityActivityConfiguration,
        initialResponse: StudyNumericQuantityResponse? = nil,
        onDraft: @escaping (StudyInteractiveResponse) -> Void,
        onComplete: @escaping (StudyInteractiveResponse) -> Void
    ) {
        self.configuration = configuration
        self.initialResponse = initialResponse
        self.onDraft = onDraft
        self.onComplete = onComplete
        _values = State(initialValue: Dictionary(uniqueKeysWithValues: (initialResponse?.values ?? []).map { ($0.partID, $0.rawValue) }))
        _units = State(initialValue: Dictionary(uniqueKeysWithValues: (initialResponse?.values ?? []).compactMap { value in
            value.unitID.map { (value.partID, $0) }
        }))
    }

    private var response: StudyInteractiveResponse {
        .numericQuantity(.init(values: configuration.parts.map { part in
            let raw = values[part.id] ?? ""
            return StudyNumericResponseValue(
                partID: part.id,
                rawValue: raw,
                unitID: units[part.id],
                significantFigures: StudyNumericResponseGrader.significantFigures(in: raw)
            )
        }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let instructions = configuration.responseInstructionsMarkdown {
                StudyMarkdownDocument(markdown: instructions)
                    .foregroundStyle(.secondary)
            }

            ForEach(configuration.parts) { part in
                VStack(alignment: .leading, spacing: 9) {
                    Text(part.label)
                        .font(.headline)
                    StudyMarkdownDocument(markdown: part.promptMarkdown)
                    HStack {
                        TextField("Value", text: binding(for: part.id, in: $values))
                            .keyboardType(.numbersAndPunctuation)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("\(part.label) value")
                        TextField(part.answer.canonicalUnitID ?? "Unit", text: binding(for: part.id, in: $units))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 110)
                            .accessibilityLabel("\(part.label) unit")
                    }
                    if let grade = grades[part.id] {
                        Label(grade.message, systemImage: grade.isCorrect ? "checkmark.circle.fill" : "arrow.counterclockwise.circle")
                            .font(.caption)
                            .foregroundStyle(grade.isCorrect ? .green : Brand.redSoft)
                    }
                }
                .padding(14)
                .studyPaperSurface(cornerRadius: 14)
            }

            Button {
                grades = Dictionary(uniqueKeysWithValues: configuration.parts.map { part in
                    (part.id, StudyNumericResponseGrader.grade(
                        rawValue: values[part.id] ?? "",
                        unitID: units[part.id],
                        specification: part.answer
                    ))
                })
                onDraft(response)
                if grades.values.allSatisfy(\.isCorrect) { onComplete(response) }
            } label: {
                Label("Check answers", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .studyPrimaryActionStyle()
            .disabled(configuration.parts.contains { (values[$0.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty })
        }
        .onChange(of: values) { _, _ in onDraft(response) }
        .onChange(of: units) { _, _ in onDraft(response) }
    }

    private func binding(for key: String, in dictionary: Binding<[String: String]>) -> Binding<String> {
        Binding(
            get: { dictionary.wrappedValue[key] ?? "" },
            set: { dictionary.wrappedValue[key] = $0 }
        )
    }
}

struct StudyMathExpressionActivityView: View {
    let configuration: StudyMathExpressionActivityConfiguration
    var initialResponse: StudyMathExpressionResponse?
    var onDraft: (StudyInteractiveResponse) -> Void
    var onComplete: (StudyInteractiveResponse) -> Void

    @State private var latex: String
    @State private var mathJSON: String?
    @State private var feedback: String?
    @State private var isAccepted = false
    @State private var isChecking = false

    init(
        configuration: StudyMathExpressionActivityConfiguration,
        initialResponse: StudyMathExpressionResponse? = nil,
        onDraft: @escaping (StudyInteractiveResponse) -> Void,
        onComplete: @escaping (StudyInteractiveResponse) -> Void
    ) {
        self.configuration = configuration
        self.initialResponse = initialResponse
        self.onDraft = onDraft
        self.onComplete = onComplete
        _latex = State(initialValue: initialResponse?.latex ?? "")
        _mathJSON = State(initialValue: initialResponse?.mathJSON)
    }

    private var response: StudyInteractiveResponse {
        .mathExpression(.init(latex: latex, mathJSON: mathJSON))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudyMarkdownDocument(markdown: configuration.promptMarkdown)
            StudyMathExpressionField(title: "Your expression", prompt: "Enter an equation", latex: $latex)
            if let feedback {
                Label(feedback, systemImage: isAccepted ? "checkmark.circle.fill" : "arrow.counterclockwise.circle")
                    .font(.subheadline)
                    .foregroundStyle(isAccepted ? .green : Brand.redSoft)
            }
            Button {
                checkExpression()
            } label: {
                Label(isChecking ? "Checking equivalence…" : "Check expression", systemImage: "function")
                    .frame(maxWidth: .infinity)
            }
            .studyPrimaryActionStyle()
            .disabled(isChecking || latex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onChange(of: latex) { _, _ in
            isAccepted = false
            feedback = nil
            mathJSON = nil
            onDraft(response)
        }
    }

    private func checkExpression() {
        isChecking = true
        let submitted = latex
        Task {
            let result = await StudyComputeEngineEvaluator.shared.evaluate(
                submittedLaTeX: submitted,
                acceptedLaTeX: configuration.acceptedLaTeX
            )
            guard submitted == latex else {
                isChecking = false
                return
            }
            isChecking = false
            isAccepted = result.isEquivalent
            mathJSON = result.mathJSON
            feedback = result.isEquivalent
                ? (configuration.feedbackMarkdown ?? result.message)
                : result.message
            onDraft(response)
            if result.isEquivalent { onComplete(response) }
        }
    }
}

struct StudyGraphTableActivityView: View {
    let configuration: StudyGraphTableActivityConfiguration
    var initialResponse: StudyGraphTableResponse?
    var onDraft: (StudyInteractiveResponse) -> Void
    var onComplete: (StudyInteractiveResponse) -> Void

    @State private var rows: [[String]]
    @State private var responses: [String]
    @State private var annotations: String

    init(
        configuration: StudyGraphTableActivityConfiguration,
        initialResponse: StudyGraphTableResponse? = nil,
        onDraft: @escaping (StudyInteractiveResponse) -> Void,
        onComplete: @escaping (StudyInteractiveResponse) -> Void
    ) {
        self.configuration = configuration
        self.initialResponse = initialResponse
        self.onDraft = onDraft
        self.onComplete = onComplete
        let startingRows = initialResponse?.rows ?? configuration.initialRows
        _rows = State(initialValue: startingRows.isEmpty ? [Array(repeating: "", count: configuration.columns.count)] : startingRows)
        _responses = State(initialValue: initialResponse?.responses ?? Array(repeating: "", count: configuration.responsePrompts.count))
        _annotations = State(initialValue: initialResponse?.annotations.joined(separator: "\n") ?? "")
    }

    private var responseValue: StudyGraphTableResponse {
        .init(
            rows: rows,
            pointsBySeriesID: Dictionary(uniqueKeysWithValues: configuration.series.map { ($0.id, points(for: $0).map { .init(x: $0.x, y: $0.y) }) }),
            annotations: annotations.isEmpty ? [] : [annotations],
            responses: responses
        )
    }

    private var response: StudyInteractiveResponse { .graphTable(responseValue) }

    private var isComplete: Bool {
        rows.count >= (configuration.minimumRows ?? 1)
            && rows.allSatisfy { row in
                configuration.columns.enumerated().allSatisfy { index, column in
                    !column.isEditable || (index < row.count && !row[index].trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            && responses.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudyMarkdownDocument(markdown: configuration.promptMarkdown)
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        ForEach(configuration.columns) { column in
                            Text(column.unitID.map { "\(column.title) (\($0))" } ?? column.title)
                                .font(.caption.weight(.bold))
                                .frame(minWidth: 110, alignment: .leading)
                        }
                        Color.clear.frame(width: 32)
                    }
                    ForEach(rows.indices, id: \.self) { rowIndex in
                        GridRow {
                            ForEach(configuration.columns.indices, id: \.self) { columnIndex in
                                let column = configuration.columns[columnIndex]
                                TextField(
                                    column.title,
                                    text: cellBinding(row: rowIndex, column: columnIndex)
                                )
                                .keyboardType(.numbersAndPunctuation)
                                .textFieldStyle(.roundedBorder)
                                .disabled(!column.isEditable)
                                .frame(minWidth: 110)
                            }
                            Button(role: .destructive) {
                                rows.remove(at: rowIndex)
                                if rows.isEmpty { addRow() }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .accessibilityLabel("Remove row \(rowIndex + 1)")
                        }
                    }
                }
            }
            Button { addRow() } label: { Label("Add row", systemImage: "plus") }
                .buttonStyle(.bordered)

            ForEach(configuration.series) { series in
                VStack(alignment: .leading, spacing: 8) {
                    Text(series.title).font(.headline)
                    StudyScienceLineGraph(
                        points: points(for: series),
                        xLabel: columnTitle(series.xColumnID),
                        yLabel: columnTitle(series.yColumnID)
                    )
                    .frame(height: 220)
                    Text("Exact values remain available in the table above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .studyPaperSurface(cornerRadius: 14)
            }

            TextField("Graph annotations", text: $annotations, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)

            ForEach(configuration.responsePrompts.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    Text(configuration.responsePrompts[index]).font(.subheadline.weight(.semibold))
                    TextField("Response", text: responseBinding(index), axis: .vertical)
                        .lineLimit(2...6)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Button {
                onDraft(response)
                onComplete(response)
            } label: {
                Label("Save table and graph", systemImage: "chart.xyaxis.line")
                    .frame(maxWidth: .infinity)
            }
            .studyPrimaryActionStyle()
            .disabled(!isComplete)
        }
        .onChange(of: rows) { _, _ in onDraft(response) }
        .onChange(of: responses) { _, _ in onDraft(response) }
        .onChange(of: annotations) { _, _ in onDraft(response) }
    }

    private func cellBinding(row: Int, column: Int) -> Binding<String> {
        Binding(
            get: { rows.indices.contains(row) && rows[row].indices.contains(column) ? rows[row][column] : "" },
            set: { newValue in
                guard rows.indices.contains(row) else { return }
                while rows[row].count <= column { rows[row].append("") }
                rows[row][column] = newValue
            }
        )
    }

    private func responseBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { responses.indices.contains(index) ? responses[index] : "" },
            set: { value in
                while responses.count <= index { responses.append("") }
                responses[index] = value
            }
        )
    }

    private func addRow() {
        rows.append(Array(repeating: "", count: configuration.columns.count))
    }

    private func points(for series: StudyGraphSeriesSpecification) -> [StudyScienceGraphPointUI] {
        guard let xIndex = configuration.columns.firstIndex(where: { $0.id == series.xColumnID }),
              let yIndex = configuration.columns.firstIndex(where: { $0.id == series.yColumnID }) else { return [] }
        return rows.enumerated().compactMap { rowIndex, row in
            guard row.indices.contains(xIndex), row.indices.contains(yIndex),
                  let x = Double(row[xIndex].replacingOccurrences(of: ",", with: ".")),
                  let y = Double(row[yIndex].replacingOccurrences(of: ",", with: ".")) else { return nil }
            return .init(id: "\(series.id)-\(rowIndex)", x: x, y: y)
        }
    }

    private func columnTitle(_ id: String) -> String {
        guard let column = configuration.columns.first(where: { $0.id == id }) else { return id }
        return column.unitID.map { "\(column.title) (\($0))" } ?? column.title
    }
}

private struct StudyForceDraft: Identifiable, Equatable {
    var id = UUID().uuidString.lowercased()
    var sourceLabel = "Object"
    var forceLabel = "Force"
    var origin = StudyNormalizedPoint(x: 0.5, y: 0.5)
    var endpoint = StudyNormalizedPoint(x: 0.78, y: 0.5)
    var magnitudeText = ""
}

private struct StudyFreeBodyScenarioDraft: Identifiable, Equatable {
    let id: String
    var forces: [StudyForceDraft]
    var selectedForceID: String?
    var explanation: String
}

struct StudyFreeBodyDiagramActivityView: View {
    let configuration: StudyFreeBodyDiagramActivityConfiguration
    var initialResponse: [StudyFreeBodyDiagramResponse]?
    var onDraft: (StudyInteractiveResponse) -> Void
    var onComplete: (StudyInteractiveResponse) -> Void

    @State private var drafts: [StudyFreeBodyScenarioDraft]
    @State private var selfReviews: [Bool]

    init(
        configuration: StudyFreeBodyDiagramActivityConfiguration,
        initialResponse: [StudyFreeBodyDiagramResponse]? = nil,
        onDraft: @escaping (StudyInteractiveResponse) -> Void,
        onComplete: @escaping (StudyInteractiveResponse) -> Void
    ) {
        self.configuration = configuration
        self.initialResponse = initialResponse
        self.onDraft = onDraft
        self.onComplete = onComplete
        _drafts = State(initialValue: configuration.scenarios.map { scenario in
            let saved = initialResponse?.first { $0.scenarioID == scenario.id }
            let forces = (saved?.forces ?? []).map {
                StudyForceDraft(
                    id: $0.id,
                    sourceLabel: $0.sourceLabel,
                    forceLabel: $0.forceLabel,
                    origin: .init(x: $0.originX, y: $0.originY),
                    endpoint: .init(x: $0.endX, y: $0.endY),
                    magnitudeText: $0.magnitudeText ?? ""
                )
            }
            return .init(
                id: scenario.id,
                forces: forces,
                selectedForceID: forces.first?.id,
                explanation: saved?.explanation ?? ""
            )
        })
        _selfReviews = State(initialValue: Array(repeating: false, count: configuration.selfReviewPrompts.count))
    }

    private var response: StudyInteractiveResponse {
        .freeBodyDiagram(drafts.map { draft in
            StudyFreeBodyDiagramResponse(
                id: draft.id,
                scenarioID: draft.id,
                forces: draft.forces.map {
                    StudyForceVectorResponse(
                        id: $0.id,
                        sourceLabel: $0.sourceLabel,
                        forceLabel: $0.forceLabel,
                        originX: $0.origin.x,
                        originY: $0.origin.y,
                        endX: $0.endpoint.x,
                        endY: $0.endpoint.y,
                        magnitudeText: $0.magnitudeText.isEmpty ? nil : $0.magnitudeText
                    )
                },
                explanation: draft.explanation
            )
        })
    }

    private var isComplete: Bool {
        zip(configuration.scenarios, drafts).allSatisfy { scenario, draft in
            draft.forces.count >= scenario.minimumForceCount
                && draft.forces.allSatisfy { !$0.forceLabel.trimmingCharacters(in: .whitespaces).isEmpty }
                && !draft.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } && selfReviews.allSatisfy { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(configuration.scenarios.indices, id: \.self) { index in
                let scenario = configuration.scenarios[index]
                VStack(alignment: .leading, spacing: 12) {
                    Text(scenario.title).font(.headline)
                    StudyMarkdownDocument(markdown: scenario.situationMarkdown)
                    Label("System: \(scenario.namedSystem)", systemImage: "square.dashed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    StudyFreeBodyDiagramEditor(draft: $drafts[index])
                    TextField("Explain your force model", text: $drafts[index].explanation, axis: .vertical)
                        .lineLimit(2...6)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(14)
                .studyPaperSurface(cornerRadius: 15, emphasized: true)
            }

            if !configuration.selfReviewPrompts.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Self-review").font(.headline)
                    ForEach(configuration.selfReviewPrompts.indices, id: \.self) { index in
                        Toggle(configuration.selfReviewPrompts[index], isOn: $selfReviews[index])
                    }
                }
                .padding(14)
                .studyPaperSurface(cornerRadius: 14)
            }

            Button {
                onDraft(response)
                onComplete(response)
            } label: {
                Label("Save diagrams", systemImage: "arrow.up.right")
                    .frame(maxWidth: .infinity)
            }
            .studyPrimaryActionStyle()
            .disabled(!isComplete)
        }
        .onChange(of: drafts) { _, _ in onDraft(response) }
    }
}

private struct StudyFreeBodyDiagramEditor: View {
    @Binding var draft: StudyFreeBodyScenarioDraft

    private var selectedIndex: Int? {
        guard let id = draft.selectedForceID else { return nil }
        return draft.forces.firstIndex { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                ZStack {
                    Canvas { context, size in
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        var axes = Path()
                        axes.move(to: CGPoint(x: 12, y: center.y))
                        axes.addLine(to: CGPoint(x: size.width - 12, y: center.y))
                        axes.move(to: CGPoint(x: center.x, y: 12))
                        axes.addLine(to: CGPoint(x: center.x, y: size.height - 12))
                        context.stroke(axes, with: .color(Brand.separator), style: .init(lineWidth: 1, dash: [5]))

                        let bodyRect = CGRect(x: center.x - 28, y: center.y - 24, width: 56, height: 48)
                        context.fill(Path(roundedRect: bodyRect, cornerRadius: 8), with: .color(Brand.controlFill))
                        context.stroke(Path(roundedRect: bodyRect, cornerRadius: 8), with: .color(Brand.ink), lineWidth: 2)

                        for force in draft.forces {
                            draw(force: force, in: &context, size: size, selected: force.id == draft.selectedForceID)
                        }
                    }
                    ForEach(draft.forces) { force in
                        let endpoint = CGPoint(x: force.endpoint.x * proxy.size.width, y: force.endpoint.y * proxy.size.height)
                        Circle()
                            .fill(force.id == draft.selectedForceID ? Brand.red : Brand.surface)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(Brand.red, lineWidth: 2))
                            .position(endpoint)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard let index = draft.forces.firstIndex(where: { $0.id == force.id }) else { return }
                                        draft.selectedForceID = force.id
                                        draft.forces[index].endpoint = .init(
                                            x: value.location.x / max(proxy.size.width, 1),
                                            y: value.location.y / max(proxy.size.height, 1)
                                        )
                                    }
                            )
                            .accessibilityLabel("\(force.forceLabel) direction handle")
                            .accessibilityHint("Drag to set the force direction")
                    }
                }
                .contentShape(Rectangle())
            }
            .frame(height: 270)
            .background(Brand.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 13))
            .overlay { RoundedRectangle(cornerRadius: 13).stroke(Brand.separator) }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(draft.forces) { force in
                        Button(force.forceLabel) { draft.selectedForceID = force.id }
                            .buttonStyle(.bordered)
                            .tint(force.id == draft.selectedForceID ? Brand.red : nil)
                    }
                    Button { addForce() } label: { Label("Add force", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                        .tint(Brand.red)
                }
            }

            if let selectedIndex {
                HStack {
                    TextField("Force label", text: $draft.forces[selectedIndex].forceLabel)
                        .textFieldStyle(.roundedBorder)
                    TextField("Magnitude (optional)", text: $draft.forces[selectedIndex].magnitudeText)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    TextField("Agent / source", text: $draft.forces[selectedIndex].sourceLabel)
                        .textFieldStyle(.roundedBorder)
                    Button("Remove", role: .destructive) {
                        draft.forces.remove(at: selectedIndex)
                        draft.selectedForceID = draft.forces.first?.id
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func addForce() {
        let angle = Double(draft.forces.count) * .pi / 3
        let force = StudyForceDraft(
            endpoint: .init(x: 0.5 + 0.28 * cos(angle), y: 0.5 + 0.28 * sin(angle))
        )
        draft.forces.append(force)
        draft.selectedForceID = force.id
    }

    private func draw(
        force: StudyForceDraft,
        in context: inout GraphicsContext,
        size: CGSize,
        selected: Bool
    ) {
        let origin = CGPoint(x: force.origin.x * size.width, y: force.origin.y * size.height)
        let endpoint = CGPoint(x: force.endpoint.x * size.width, y: force.endpoint.y * size.height)
        var line = Path()
        line.move(to: origin)
        line.addLine(to: endpoint)
        context.stroke(line, with: .color(selected ? Brand.red : Brand.ink), lineWidth: selected ? 4 : 3)

        let angle = atan2(endpoint.y - origin.y, endpoint.x - origin.x)
        let length: CGFloat = 13
        var head = Path()
        head.move(to: endpoint)
        head.addLine(to: CGPoint(x: endpoint.x - length * cos(angle - .pi / 6), y: endpoint.y - length * sin(angle - .pi / 6)))
        head.move(to: endpoint)
        head.addLine(to: CGPoint(x: endpoint.x - length * cos(angle + .pi / 6), y: endpoint.y - length * sin(angle + .pi / 6)))
        context.stroke(head, with: .color(selected ? Brand.red : Brand.ink), lineWidth: selected ? 4 : 3)
        context.draw(
            Text(force.forceLabel).font(.caption.bold()).foregroundStyle(selected ? Brand.redSoft : Brand.ink),
            at: CGPoint(x: endpoint.x, y: endpoint.y - 20),
            anchor: .center
        )
    }
}

struct StudyAcknowledgementActivityView: View {
    let configuration: StudyAcknowledgementActivityConfiguration
    var initialValue: Bool
    var onDraft: (StudyInteractiveResponse) -> Void
    var onComplete: (StudyInteractiveResponse) -> Void

    @State private var isAcknowledged: Bool

    init(
        configuration: StudyAcknowledgementActivityConfiguration,
        initialValue: Bool = false,
        onDraft: @escaping (StudyInteractiveResponse) -> Void,
        onComplete: @escaping (StudyInteractiveResponse) -> Void
    ) {
        self.configuration = configuration
        self.initialValue = initialValue
        self.onDraft = onDraft
        self.onComplete = onComplete
        _isAcknowledged = State(initialValue: initialValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudyMarkdownDocument(markdown: configuration.statementMarkdown)
            Toggle(configuration.acknowledgementLabel, isOn: $isAcknowledged)
                .font(.subheadline.weight(.semibold))
            Button {
                let response = StudyInteractiveResponse.acknowledgement(true)
                onDraft(response)
                onComplete(response)
            } label: {
                Label("Continue", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .studyPrimaryActionStyle()
            .disabled(!isAcknowledged)
        }
        .onChange(of: isAcknowledged) { _, value in
            onDraft(.acknowledgement(value))
        }
    }
}

struct StudyConstructedResponseActivityView: View {
    let configuration: StudyConstructedResponseActivityConfiguration
    var initialResponse: StudyConstructedResponse?
    var onDraft: (StudyInteractiveResponse) -> Void
    var onComplete: (StudyInteractiveResponse) -> Void

    @State private var responses: [String]
    @State private var selfReviews: [Bool]

    init(
        configuration: StudyConstructedResponseActivityConfiguration,
        initialResponse: StudyConstructedResponse? = nil,
        onDraft: @escaping (StudyInteractiveResponse) -> Void,
        onComplete: @escaping (StudyInteractiveResponse) -> Void
    ) {
        self.configuration = configuration
        self.initialResponse = initialResponse
        self.onDraft = onDraft
        self.onComplete = onComplete
        var saved = initialResponse?.responses ?? []
        while saved.count < configuration.prompts.count { saved.append("") }
        _responses = State(initialValue: saved)
        var reviews = initialResponse?.completedSelfReview ?? []
        while reviews.count < configuration.selfReviewPrompts.count { reviews.append(false) }
        _selfReviews = State(initialValue: reviews)
    }

    private var value: StudyConstructedResponse {
        .init(responses: Array(responses.prefix(configuration.prompts.count)), completedSelfReview: selfReviews)
    }

    private var isComplete: Bool {
        responses.prefix(configuration.prompts.count).allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).count >= configuration.minimumResponseCharacters
        } && selfReviews.allSatisfy { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(configuration.prompts.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 7) {
                    StudyMarkdownDocument(markdown: configuration.prompts[index])
                    TextEditor(text: $responses[index])
                        .frame(minHeight: 120)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(Brand.controlFill, in: RoundedRectangle(cornerRadius: 11))
                        .overlay { RoundedRectangle(cornerRadius: 11).stroke(Brand.separator) }
                        .accessibilityLabel("Response \(index + 1)")
                }
            }
            if !configuration.selfReviewPrompts.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Self-review").font(.headline)
                    ForEach(configuration.selfReviewPrompts.indices, id: \.self) { index in
                        Toggle(configuration.selfReviewPrompts[index], isOn: $selfReviews[index])
                    }
                }
                .padding(14)
                .studyPaperSurface(cornerRadius: 14)
            }
            Button {
                let response = StudyInteractiveResponse.constructedResponse(value)
                onDraft(response)
                onComplete(response)
            } label: {
                Label("Save response", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .studyPrimaryActionStyle()
            .disabled(!isComplete)
        }
        .onChange(of: responses) { _, _ in onDraft(.constructedResponse(value)) }
        .onChange(of: selfReviews) { _, _ in onDraft(.constructedResponse(value)) }
    }
}

struct StudyWorkedExampleActivityView: View {
    let configuration: StudyWorkedExampleActivityConfiguration
    var initialResponse: StudyWorkedExampleResponse?
    var onDraft: (StudyInteractiveResponse) -> Void
    var onComplete: (StudyInteractiveResponse) -> Void

    @State private var attempt: String
    @State private var revealedSolution: Bool

    init(
        configuration: StudyWorkedExampleActivityConfiguration,
        initialResponse: StudyWorkedExampleResponse? = nil,
        onDraft: @escaping (StudyInteractiveResponse) -> Void,
        onComplete: @escaping (StudyInteractiveResponse) -> Void
    ) {
        self.configuration = configuration
        self.initialResponse = initialResponse
        self.onDraft = onDraft
        self.onComplete = onComplete
        _attempt = State(initialValue: initialResponse?.attemptMarkdown ?? "")
        _revealedSolution = State(initialValue: initialResponse?.revealedSolution ?? false)
    }

    private var value: StudyWorkedExampleResponse {
        .init(attemptMarkdown: attempt, revealedSolution: revealedSolution)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            StudyMarkdownDocument(markdown: configuration.problemMarkdown)
            VStack(alignment: .leading, spacing: 7) {
                Text("Your attempt").font(.headline)
                TextEditor(text: $attempt)
                    .frame(minHeight: 130)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(Brand.controlFill, in: RoundedRectangle(cornerRadius: 11))
                    .overlay { RoundedRectangle(cornerRadius: 11).stroke(Brand.separator) }
            }
            if revealedSolution {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Worked solution").font(.headline)
                    StudyMarkdownDocument(markdown: configuration.solutionMarkdown)
                    Divider()
                    StudyMarkdownDocument(markdown: configuration.resultMarkdown)
                    StudyMarkdownDocument(markdown: configuration.interpretationMarkdown)
                }
                .padding(15)
                .studyPaperSurface(cornerRadius: 15, emphasized: true)
                Button {
                    let response = StudyInteractiveResponse.workedExample(value)
                    onDraft(response)
                    onComplete(response)
                } label: {
                    Label("Finish worked example", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .studyPrimaryActionStyle()
            } else {
                Button {
                    revealedSolution = true
                    onDraft(.workedExample(value))
                } label: {
                    Label("Reveal worked solution", systemImage: "eye")
                        .frame(maxWidth: .infinity)
                }
                .studySecondaryActionStyle()
                .disabled(attempt.trimmingCharacters(in: .whitespacesAndNewlines).count < configuration.minimumAttemptCharacters)
            }
        }
        .onChange(of: attempt) { _, _ in onDraft(.workedExample(value)) }
    }
}

struct StudyErrorDiagnosisActivityView: View {
    let configuration: StudyErrorDiagnosisActivityConfiguration
    var initialResponse: StudyErrorDiagnosisResponse?
    var onDraft: (StudyInteractiveResponse) -> Void
    var onComplete: (StudyInteractiveResponse) -> Void

    @State private var responses: [String]
    @State private var didReview: Bool
    @State private var isReviewVisible = false

    init(
        configuration: StudyErrorDiagnosisActivityConfiguration,
        initialResponse: StudyErrorDiagnosisResponse? = nil,
        onDraft: @escaping (StudyInteractiveResponse) -> Void,
        onComplete: @escaping (StudyInteractiveResponse) -> Void
    ) {
        self.configuration = configuration
        self.initialResponse = initialResponse
        self.onDraft = onDraft
        self.onComplete = onComplete
        var saved = initialResponse?.responses ?? []
        while saved.count < configuration.requiredResponsePrompts.count { saved.append("") }
        _responses = State(initialValue: saved)
        _didReview = State(initialValue: initialResponse?.completedSelfReview ?? false)
    }

    private var value: StudyErrorDiagnosisResponse {
        .init(responses: responses, completedSelfReview: didReview)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Flawed solution", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(Brand.redSoft)
                StudyMarkdownDocument(markdown: configuration.flawedSolutionMarkdown)
            }
            .padding(14)
            .studyPaperSurface(cornerRadius: 14)

            ForEach(configuration.requiredResponsePrompts.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 7) {
                    StudyMarkdownDocument(markdown: configuration.requiredResponsePrompts[index])
                    TextField("Your diagnosis", text: $responses[index], axis: .vertical)
                        .lineLimit(2...7)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let review = configuration.selfReviewMarkdown {
                if isReviewVisible {
                    StudyMarkdownDocument(markdown: review)
                        .padding(14)
                        .studyPaperSurface(cornerRadius: 14, emphasized: true)
                    Toggle("I compared my diagnosis with the review.", isOn: $didReview)
                } else {
                    Button("Show review") { isReviewVisible = true }
                        .studySecondaryActionStyle()
                        .disabled(responses.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                }
            } else {
                Toggle("I checked the system, direction, law, and units.", isOn: $didReview)
            }

            Button {
                let response = StudyInteractiveResponse.errorDiagnosis(value)
                onDraft(response)
                onComplete(response)
            } label: {
                Label("Complete diagnosis", systemImage: "checkmark.seal")
                    .frame(maxWidth: .infinity)
            }
            .studyPrimaryActionStyle()
            .disabled(!didReview || responses.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        }
        .onChange(of: responses) { _, _ in onDraft(.errorDiagnosis(value)) }
        .onChange(of: didReview) { _, _ in onDraft(.errorDiagnosis(value)) }
    }
}

struct StudyAccelerationSampleUI: Equatable, Sendable {
    let time: Double
    let acceleration: Double
}

struct StudyNumericalKinematicsRowUI: Identifiable, Equatable, Sendable {
    var id: String { time.formatted(.number.precision(.fractionLength(12))) }
    let time: Double
    let acceleration: Double
    let velocity: Double
    let position: Double
}

enum StudyNumericalKinematicsEngine {
    static func integrate(
        acceleration: [StudyAccelerationSampleUI],
        timeStep: Double,
        initialPosition: Double,
        initialVelocity: Double
    ) -> [StudyNumericalKinematicsRowUI] {
        let sorted = acceleration.sorted { $0.time < $1.time }
        guard let first = sorted.first, let last = sorted.last,
              timeStep > 0, last.time >= first.time else { return [] }
        let step = min(max(timeStep, 0.0001), max(last.time - first.time, 0.0001))
        var time = first.time
        var position = initialPosition
        var velocity = initialVelocity
        var rows: [StudyNumericalKinematicsRowUI] = []
        while time <= last.time + step * 0.25, rows.count < 20_000 {
            let a = interpolatedAcceleration(at: time, samples: sorted)
            rows.append(.init(time: time, acceleration: a, velocity: velocity, position: position))
            position += velocity * step
            velocity += a * step
            time += step
        }
        return rows
    }

    private static func interpolatedAcceleration(
        at time: Double,
        samples: [StudyAccelerationSampleUI]
    ) -> Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        if time <= first.time { return first.acceleration }
        if time >= last.time { return last.acceleration }
        guard let upper = samples.firstIndex(where: { $0.time >= time }), upper > 0 else { return first.acceleration }
        let left = samples[upper - 1]
        let right = samples[upper]
        let fraction = (time - left.time) / max(right.time - left.time, 0.000_000_1)
        return left.acceleration + fraction * (right.acceleration - left.acceleration)
    }
}

struct StudyNumericalKinematicsActivityView: View {
    let configuration: StudyNumericalKinematicsActivityConfiguration
    let accelerationSamples: [StudyAccelerationSampleUI]
    var initialResponse: StudyNumericalKinematicsResponse?
    var onDraft: (StudyInteractiveResponse) -> Void
    var onComplete: (StudyInteractiveResponse) -> Void

    @State private var timeStepText: String
    @State private var rows: [StudyNumericalKinematicsRowUI] = []
    @State private var validationFields: [String: String]
    @State private var didRunSmallerStep = false

    init(
        configuration: StudyNumericalKinematicsActivityConfiguration,
        accelerationSamples: [StudyAccelerationSampleUI],
        initialResponse: StudyNumericalKinematicsResponse? = nil,
        onDraft: @escaping (StudyInteractiveResponse) -> Void,
        onComplete: @escaping (StudyInteractiveResponse) -> Void
    ) {
        self.configuration = configuration
        self.accelerationSamples = accelerationSamples
        self.initialResponse = initialResponse
        self.onDraft = onDraft
        self.onComplete = onComplete
        _timeStepText = State(initialValue: (initialResponse?.timeStep ?? configuration.defaultTimeStep).formatted(.number.grouping(.never)))
        _validationFields = State(initialValue: initialResponse?.validationFields ?? [:])
        if let initialResponse {
            _rows = State(initialValue: initialResponse.rows.compactMap { row in
                guard row.count >= 4 else { return nil }
                return .init(time: row[0], acceleration: row[1], velocity: row[2], position: row[3])
            })
        }
    }

    private var responseValue: StudyNumericalKinematicsResponse {
        .init(
            timeStep: Double(timeStepText) ?? configuration.defaultTimeStep,
            rows: rows.map { [$0.time, $0.acceleration, $0.velocity, $0.position] },
            validationFields: validationFields
        )
    }

    private var response: StudyInteractiveResponse { .numericalKinematics(responseValue) }

    private var isComplete: Bool {
        !rows.isEmpty
            && didRunSmallerStep
            && configuration.requiredValidationSteps.allSatisfy {
                !(validationFields[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            if accelerationSamples.isEmpty {
                ContentUnavailableView(
                    "Acceleration data unavailable",
                    systemImage: "tablecells.badge.ellipsis",
                    description: Text("The bundled dataset could not be read. Use the Python route or reinstall this course build.")
                )
            } else {
                HStack {
                    TextField("Time step", text: $timeStepText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    Text("seconds").foregroundStyle(.secondary)
                    Button("Run model") { run(step: Double(timeStepText) ?? configuration.defaultTimeStep) }
                        .buttonStyle(.borderedProminent)
                        .tint(Brand.red)
                }
                VStack(alignment: .leading, spacing: 5) {
                    StudyMarkdownDocument(markdown: configuration.velocityUpdateMarkdown)
                    StudyMarkdownDocument(markdown: configuration.positionUpdateMarkdown)
                }
                .font(.caption)
                .padding(12)
                .studyPaperSurface(cornerRadius: 12)

                if !rows.isEmpty {
                    StudyScienceLineGraph(
                        points: rows.map { .init(x: $0.time, y: $0.position) },
                        xLabel: "Time (s)",
                        yLabel: "Position (m)"
                    )
                    .frame(height: 230)

                    DisclosureGroup("Accessible numerical table") {
                        ScrollView(.horizontal) {
                            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
                                GridRow { Text("t"); Text("a"); Text("v"); Text("x") }
                                    .font(.caption.bold())
                                ForEach(rows.prefix(500)) { row in
                                    GridRow {
                                        number(row.time); number(row.acceleration); number(row.velocity); number(row.position)
                                    }
                                    .font(.caption.monospacedDigit())
                                }
                            }
                        }
                    }
                    .padding(12)
                    .studyPaperSurface(cornerRadius: 12)

                    Button {
                        let current = Double(timeStepText) ?? configuration.defaultTimeStep
                        let smaller = current / 2
                        timeStepText = smaller.formatted(.number.grouping(.never).precision(.significantDigits(1...8)))
                        run(step: smaller)
                        didRunSmallerStep = true
                    } label: {
                        Label("Rerun with half the time step", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                }

                ForEach(configuration.requiredValidationSteps, id: \.self) { prompt in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(prompt).font(.subheadline.weight(.semibold))
                        TextField("Record your check and conclusion", text: validationBinding(prompt), axis: .vertical)
                            .lineLimit(2...6)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Button {
                    onDraft(response)
                    onComplete(response)
                } label: {
                    Label("Complete numerical lab", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .studyPrimaryActionStyle()
                .disabled(!isComplete)
            }
        }
        .onChange(of: timeStepText) { _, _ in onDraft(response) }
        .onChange(of: validationFields) { _, _ in onDraft(response) }
    }

    private func run(step: Double) {
        rows = StudyNumericalKinematicsEngine.integrate(
            acceleration: accelerationSamples,
            timeStep: step,
            initialPosition: configuration.initialPosition,
            initialVelocity: configuration.initialVelocity
        )
        onDraft(response)
    }

    private func validationBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { validationFields[key] ?? "" },
            set: { validationFields[key] = $0 }
        )
    }

    private func number(_ value: Double) -> Text {
        Text(value.formatted(.number.precision(.significantDigits(1...5))))
    }
}

struct StudyPythonNotebookActivityView: View {
    let configuration: StudyPythonNotebookActivityConfiguration
    var initialResponse: StudyPythonNotebookResponse?
    var onDraft: (StudyInteractiveResponse) -> Void
    var onComplete: (StudyInteractiveResponse) -> Void

    @State private var source: String
    @State private var lastResult: StudyPythonRunResult?
    @State private var evidence: [String: String]

    init(
        configuration: StudyPythonNotebookActivityConfiguration,
        initialResponse: StudyPythonNotebookResponse? = nil,
        onDraft: @escaping (StudyInteractiveResponse) -> Void,
        onComplete: @escaping (StudyInteractiveResponse) -> Void
    ) {
        self.configuration = configuration
        self.initialResponse = initialResponse
        self.onDraft = onDraft
        self.onComplete = onComplete
        _source = State(initialValue: initialResponse?.source ?? configuration.templateSource)
        _evidence = State(initialValue: initialResponse?.evidenceFields ?? [:])
    }

    private var testResults: [String: Bool] {
        if let runtimeResults = lastResult?.visibleTestResults { return runtimeResults }
        return initialResponse?.visibleTestResults ?? [:]
    }

    private var responseValue: StudyPythonNotebookResponse {
        .init(
            source: source,
            stdout: lastResult?.stdout ?? initialResponse?.stdout ?? "",
            stderr: lastResult?.stderr ?? initialResponse?.stderr ?? "",
            visibleTestResults: testResults,
            evidenceFields: evidence
        )
    }

    private var response: StudyInteractiveResponse { .pythonNotebook(responseValue) }

    private var isComplete: Bool {
        !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !configuration.visibleTests.isEmpty
            && configuration.visibleTests.allSatisfy { testResults[$0.id] == true }
            && configuration.requiredEvidenceFields.allSatisfy {
                !(evidence[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            if configuration.runtimeManifestID != "PHY111.runtime.pyodide.v1" {
                ContentUnavailableView(
                    "Unknown Python runtime",
                    systemImage: "shippingbox",
                    description: Text("This build only permits the audited PHY111 offline runtime.")
                )
            } else {
                StudyPythonNotebookView(
                    configuration: .init(
                        title: "Python workspace",
                        instructions: "Edit the visible program. Runs are local, offline, temporary, and limited to five seconds.",
                        starterCode: configuration.templateSource,
                        validationCode: validationCode,
                        timeoutSeconds: Double(configuration.timeoutSeconds)
                    ),
                    initialSource: source,
                    onSourceChange: { value in
                        source = value
                        onDraft(response)
                    },
                    onSuccessfulRun: { result in
                        lastResult = result
                        onDraft(response)
                    }
                )

                VStack(alignment: .leading, spacing: 9) {
                    Text("Visible checks").font(.headline)
                    ForEach(configuration.visibleTests) { test in
                        Label(
                            "\(test.title): \(test.expectedDescription)",
                            systemImage: testResults[test.id] == true ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.subheadline)
                        .foregroundStyle(testResults[test.id] == true ? .green : .secondary)
                    }
                }
                .padding(14)
                .studyPaperSurface(cornerRadius: 14)

                ForEach(configuration.requiredEvidenceFields, id: \.self) { prompt in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(prompt).font(.subheadline.weight(.semibold))
                        TextField("Record your evidence", text: evidenceBinding(prompt), axis: .vertical)
                            .lineLimit(2...6)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Button {
                    onDraft(response)
                    onComplete(response)
                } label: {
                    Label("Complete Python lab", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .studyPrimaryActionStyle()
                .disabled(!isComplete)
            }
        }
        .onChange(of: evidence) { _, _ in onDraft(response) }
    }

    private var validationCode: String {
        let checks = configuration.visibleTests.map { test in
            let id = pythonString(test.id)
            return """
            try:
                _study_tests[\(id)] = bool(\(test.expression))
            except Exception:
                _study_tests[\(id)] = False
            """
        }.joined(separator: "\n")
        return """
        _study_tests = {}
        \(checks)
        {"passed": all(_study_tests.values()), "message": f"{sum(_study_tests.values())}/{len(_study_tests)} visible checks passed", "tests": _study_tests}
        """
    }

    private func pythonString(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    private func evidenceBinding(_ key: String) -> Binding<String> {
        Binding(get: { evidence[key] ?? "" }, set: { evidence[key] = $0 })
    }
}

enum StudyScienceDatasetLoader {
    static func accelerationSamples(
        dataset: StudyDataset?,
        bundle: Bundle = .main
    ) -> [StudyAccelerationSampleUI] {
        guard let dataset,
              let url = resourceURL(named: dataset.resourceName, bundle: bundle),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let rows = parseCSV(text)
        guard rows.count > 1 else { return [] }
        let headers = rows[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let timeIndex = headers.firstIndex { $0 == "time" || $0 == "t" || $0.contains("time") } ?? 0
        let accelerationIndex = headers.firstIndex { $0 == "acceleration" || $0 == "a" || $0.contains("acceleration") } ?? min(1, headers.count - 1)
        return rows.dropFirst().compactMap { row in
            guard row.indices.contains(timeIndex), row.indices.contains(accelerationIndex),
                  let time = Double(row[timeIndex]),
                  let acceleration = Double(row[accelerationIndex]) else { return nil }
            return .init(time: time, acceleration: acceleration)
        }
    }

    static func motionSamples(
        dataset: StudyDataset?,
        bundle: Bundle = .main
    ) -> [StudyMotionSampleUI] {
        guard let dataset,
              let url = resourceURL(named: dataset.resourceName, bundle: bundle),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let rows = parseCSV(text)
        guard rows.count > 1 else { return [] }
        let headers = rows[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let timeIndex = headers.firstIndex { $0 == "time" || $0 == "t" || $0.contains("time") } ?? 0
        let positionIndex = headers.firstIndex { $0 == "position" || $0 == "x" || $0.contains("position") } ?? min(1, headers.count - 1)
        return rows.dropFirst().enumerated().compactMap { rowIndex, row in
            guard row.indices.contains(timeIndex), row.indices.contains(positionIndex),
                  let time = Double(row[timeIndex]),
                  let position = Double(row[positionIndex]) else { return nil }
            return .init(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", rowIndex)) ?? UUID(), timeSeconds: time, positionMeters: position)
        }
    }

    private static func resourceURL(named name: String, bundle: Bundle) -> URL? {
        let resource = name as NSString
        return bundle.url(
            forResource: resource.deletingPathExtension,
            withExtension: resource.pathExtension.isEmpty ? nil : resource.pathExtension
        ) ?? bundle.url(forResource: name, withExtension: nil, subdirectory: "ScienceContent")
    }

    private static func parseCSV(_ source: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = source.makeIterator()
        while let character = iterator.next() {
            if character == "\"" {
                quoted.toggle()
            } else if character == ",", !quoted {
                row.append(field.trimmingCharacters(in: .whitespaces))
                field = ""
            } else if character == "\n", !quoted {
                row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
                field = ""
            } else if character != "\r" {
                field.append(character)
            }
        }
        row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }
}
