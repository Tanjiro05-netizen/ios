import SwiftUI

struct StudyScienceActivityCompletionUI: Sendable {
    let response: StudyInteractiveResponse
    let earnedPoints: Double?
    let possiblePoints: Double?
    let completionPath: String?
}

enum StudyScienceWorkspaceSaveState: Equatable {
    case saved
    case saving
    case waitingForConnection
    case failed(String)

    var title: String {
        switch self {
        case .saved: "Saved"
        case .saving: "Saving…"
        case .waitingForConnection: "Saved on this device"
        case .failed: "Could not save"
        }
    }

    var systemImage: String {
        switch self {
        case .saved: "checkmark.circle"
        case .saving: "arrow.triangle.2.circlepath"
        case .waitingForConnection: "wifi.slash"
        case .failed: "exclamationmark.triangle"
        }
    }
}

@MainActor
struct StudyScienceActivityScreen: View {
    let activity: StudyInteractiveActivity
    let datasets: [StudyDataset]
    let toolProfile: StudyToolProfile?
    let initialResponse: StudyInteractiveResponse?
    let initialStoredVideo: StudyMotionStoredVideoUI?
    let videoStorage: StudyMotionVideoStorageUI
    let saveDraft: (StudyInteractiveResponse) throws -> Void
    let submit: (StudyScienceActivityCompletionUI) throws -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTool: StudyScienceToolDestinationUI?
    @State private var saveState: StudyScienceWorkspaceSaveState = .saved
    @State private var draftSaveTask: Task<Void, Never>?
    @State private var latestResponse: StudyInteractiveResponse?
    @State private var completionMessage: String?
    @State private var submissionError: String?

    init(
        activity: StudyInteractiveActivity,
        datasets: [StudyDataset] = [],
        toolProfile: StudyToolProfile? = nil,
        initialResponse: StudyInteractiveResponse? = nil,
        initialStoredVideo: StudyMotionStoredVideoUI? = nil,
        videoStorage: StudyMotionVideoStorageUI,
        saveDraft: @escaping (StudyInteractiveResponse) throws -> Void,
        submit: @escaping (StudyScienceActivityCompletionUI) throws -> Void
    ) {
        self.activity = activity
        self.datasets = datasets
        self.toolProfile = toolProfile
        self.initialResponse = initialResponse
        self.initialStoredVideo = initialStoredVideo
        self.videoStorage = videoStorage
        self.saveDraft = saveDraft
        self.submit = submit
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    activityHeader
                    if let instructions = activity.instructionsMarkdown,
                       !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        StudyMarkdownDocument(markdown: instructions)
                            .padding(16)
                            .studyPaperSurface(cornerRadius: 16)
                    }
                    StudyInteractiveActivityBody(
                        activity: activity,
                        datasets: datasets,
                        initialResponse: initialResponse,
                        initialStoredVideo: initialStoredVideo,
                        videoStorage: videoStorage,
                        onDraft: queueDraftSave,
                        onComplete: complete
                    )
                    evidenceChecklist
                }
                .padding(16)
                .padding(.bottom, 36)
            }
            .frame(maxWidth: .infinity)

            if horizontalSizeClass == .regular, let selectedTool {
                Divider()
                StudyScienceToolPanelUI(destination: selectedTool, profile: toolProfile)
                    .frame(width: 390)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .navigationTitle(activity.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !availableTools.isEmpty {
                    Menu {
                        ForEach(availableTools) { tool in
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { selectedTool = tool }
                            } label: {
                                Label(tool.title, systemImage: tool.systemImage)
                            }
                        }
                    } label: {
                        Label("Tools", systemImage: "wrench.and.screwdriver")
                    }
                    .accessibilityIdentifier("study.science.activity.tools")
                }
                if horizontalSizeClass == .regular, selectedTool != nil {
                    Button { withAnimation { selectedTool = nil } } label: {
                        Image(systemName: "sidebar.trailing")
                    }
                    .accessibilityLabel("Close science tool panel")
                }
            }
        }
        .sheet(item: compactToolBinding) { tool in
            NavigationStack {
                StudyScienceToolPanelUI(destination: tool, profile: toolProfile)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { selectedTool = nil }
                        }
                    }
            }
            .presentationDetents(tool == .calculator ? [.large] : [.medium, .large])
        }
        .alert("Activity saved", isPresented: Binding(
            get: { completionMessage != nil },
            set: { if !$0 { completionMessage = nil } }
        )) {
            Button("Continue", role: .cancel) {}
        } message: {
            Text(completionMessage ?? "Your evidence was recorded.")
        }
        .alert("Unable to submit", isPresented: Binding(
            get: { submissionError != nil },
            set: { if !$0 { submissionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(submissionError ?? "Your draft remains on this device.")
        }
        .onDisappear { draftSaveTask?.cancel() }
    }

    private var activityHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(activity.kind.scienceTitle, systemImage: activity.kind.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.redSoft)
                Spacer()
                Label("\(activity.estimatedMinutes) min", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(activity.title)
                .font(.system(.title, design: .serif, weight: .semibold))
            Text(activity.summary)
                .font(.body)
                .foregroundStyle(.secondary)
            HStack {
                Label(saveState.title, systemImage: saveState.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(saveState.isFailure ? Brand.redSoft : .secondary)
                Spacer()
                if let page = activity.sourcePageRange {
                    Text(page.firstPage == page.lastPage ? "Source p. \(page.firstPage)" : "Source pp. \(page.firstPage)–\(page.lastPage)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .studyPaperSurface(cornerRadius: 20, emphasized: true)
    }

    private var evidenceChecklist: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Evidence saved with this activity", systemImage: "checklist")
                .font(.headline)
            if activity.evidenceRequirements.isEmpty {
                Text("Your submitted response and completion fact are retained. Raw experiment video remains on this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activity.evidenceRequirements) { requirement in
                    Label {
                        Text(requirement.minimumCount.map { "\(requirement.title) · at least \($0)" } ?? requirement.title)
                    } icon: {
                        Image(systemName: "circle")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(15)
        .studyPaperSurface(cornerRadius: 15)
    }

    private var availableTools: [StudyScienceToolDestinationUI] {
        guard let toolProfile else { return [] }
        var tools: [StudyScienceToolDestinationUI] = []
        if toolProfile.capabilities.contains(.scientificCalculator) { tools.append(.calculator) }
        if toolProfile.capabilities.contains(.formulaCard), toolProfile.formulaCardMarkdown != nil { tools.append(.formulaCard) }
        if toolProfile.capabilities.contains(.unitHelper) { tools.append(.unitHelper) }
        return tools
    }

    private var compactToolBinding: Binding<StudyScienceToolDestinationUI?> {
        Binding(
            get: { horizontalSizeClass == .compact ? selectedTool : nil },
            set: { selectedTool = $0 }
        )
    }

    private func queueDraftSave(_ response: StudyInteractiveResponse) {
        latestResponse = response
        saveState = .saving
        draftSaveTask?.cancel()
        draftSaveTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                try saveDraft(response)
                saveState = .saved
            } catch is CancellationError {
                return
            } catch {
                saveState = .failed(error.localizedDescription)
            }
        }
    }

    private func complete(_ response: StudyInteractiveResponse) {
        draftSaveTask?.cancel()
        do {
            try saveDraft(response)
            let score = StudyScienceActivityScoring.score(activity: activity, response: response)
            try submit(.init(
                response: response,
                earnedPoints: score.earned,
                possiblePoints: score.possible,
                completionPath: score.path
            ))
            saveState = .saved
            completionMessage = score.message
        } catch {
            latestResponse = response
            saveState = .failed(error.localizedDescription)
            submissionError = error.localizedDescription
        }
    }
}

private extension StudyScienceWorkspaceSaveState {
    var isFailure: Bool {
        if case .failed = self { true } else { false }
    }
}

private extension StudyInteractiveActivityKind {
    var scienceTitle: String {
        switch self {
        case .acknowledgement: "Orientation"
        case .numericQuantity: "Numerical exercise"
        case .mathExpression: "Mathematical response"
        case .graphTable: "Data and graph"
        case .freeBodyDiagram: "Diagram studio"
        case .motionTrackingLab: "Investigation"
        case .numericalKinematics: "Computational lab"
        case .pythonNotebook: "Python lab"
        case .constructedResponse: "Constructed response"
        case .workedExample: "Worked studio"
        case .errorDiagnosis: "Error diagnosis"
        }
    }

    var systemImage: String {
        switch self {
        case .acknowledgement: "checkmark.shield"
        case .numericQuantity: "number"
        case .mathExpression: "function"
        case .graphTable: "chart.xyaxis.line"
        case .freeBodyDiagram: "arrow.up.right"
        case .motionTrackingLab: "video.badge.waveform"
        case .numericalKinematics: "tablecells"
        case .pythonNotebook: "chevron.left.forwardslash.chevron.right"
        case .constructedResponse: "text.alignleft"
        case .workedExample: "list.number"
        case .errorDiagnosis: "exclamationmark.triangle"
        }
    }
}

enum StudyScienceActivityScoring {
    struct Score {
        let earned: Double?
        let possible: Double?
        let path: String?
        let message: String
    }

    static func score(activity: StudyInteractiveActivity, response: StudyInteractiveResponse) -> Score {
        switch (activity.configuration, response) {
        case (.numericQuantity(let configuration), .numericQuantity(let value)):
            let submitted = Dictionary(uniqueKeysWithValues: value.values.map { ($0.partID, $0) })
            let earned = configuration.parts.reduce(0) { total, part in
                guard let answer = submitted[part.id] else { return total }
                return total + (StudyNumericResponseGrader.grade(
                    rawValue: answer.rawValue,
                    unitID: answer.unitID,
                    specification: part.answer
                ).isCorrect ? 1 : 0)
            }
            return .init(
                earned: Double(earned),
                possible: Double(configuration.parts.count),
                path: nil,
                message: "Numerical evidence saved: \(earned) of \(configuration.parts.count) correct."
            )
        case (.numericalKinematics, .numericalKinematics):
            return .init(earned: 1, possible: 1, path: "guided", message: "Guided computational evidence saved.")
        case (.pythonNotebook, .pythonNotebook):
            return .init(earned: 1, possible: 1, path: "python", message: "Python computational evidence saved.")
        default:
            return .init(earned: nil, possible: nil, path: nil, message: "Activity evidence saved.")
        }
    }
}

private struct StudyInteractiveActivityBody: View {
    let activity: StudyInteractiveActivity
    let datasets: [StudyDataset]
    let initialResponse: StudyInteractiveResponse?
    let initialStoredVideo: StudyMotionStoredVideoUI?
    let videoStorage: StudyMotionVideoStorageUI
    let onDraft: (StudyInteractiveResponse) -> Void
    let onComplete: (StudyInteractiveResponse) -> Void

    @ViewBuilder
    var body: some View {
        switch activity.configuration {
        case .acknowledgement(let configuration):
            StudyAcknowledgementActivityView(
                configuration: configuration,
                initialValue: initialAcknowledgement,
                onDraft: onDraft,
                onComplete: onComplete
            )
        case .numericQuantity(let configuration):
            StudyNumericQuantityActivityView(
                configuration: configuration,
                initialResponse: initialNumeric,
                onDraft: onDraft,
                onComplete: onComplete
            )
        case .mathExpression(let configuration):
            StudyMathExpressionActivityView(
                configuration: configuration,
                initialResponse: initialMath,
                onDraft: onDraft,
                onComplete: onComplete
            )
        case .graphTable(let configuration):
            StudyGraphTableActivityView(
                configuration: configuration,
                initialResponse: initialGraph,
                onDraft: onDraft,
                onComplete: onComplete
            )
        case .freeBodyDiagram(let configuration):
            StudyFreeBodyDiagramActivityView(
                configuration: configuration,
                initialResponse: initialDiagrams,
                onDraft: onDraft,
                onComplete: onComplete
            )
        case .motionTrackingLab(let configuration):
            StudyMotionTrackingActivityAdapter(
                configuration: configuration,
                dataset: datasets.first { $0.id == configuration.fallbackDatasetID },
                initialResponse: initialMotion,
                initialStoredVideo: initialStoredVideo,
                videoStorage: videoStorage,
                onDraft: onDraft,
                onComplete: onComplete
            )
        case .numericalKinematics(let configuration):
            StudyNumericalKinematicsActivityView(
                configuration: configuration,
                accelerationSamples: StudyScienceDatasetLoader.accelerationSamples(
                    dataset: datasets.first { $0.id == configuration.accelerationDatasetID }
                ),
                initialResponse: initialNumerical,
                onDraft: onDraft,
                onComplete: onComplete
            )
        case .pythonNotebook(let configuration):
            StudyPythonNotebookActivityView(
                configuration: configuration,
                initialResponse: initialPython,
                onDraft: onDraft,
                onComplete: onComplete
            )
        case .constructedResponse(let configuration):
            StudyConstructedResponseActivityView(
                configuration: configuration,
                initialResponse: initialConstructed,
                onDraft: onDraft,
                onComplete: onComplete
            )
        case .workedExample(let configuration):
            StudyWorkedExampleActivityView(
                configuration: configuration,
                initialResponse: initialWorked,
                onDraft: onDraft,
                onComplete: onComplete
            )
        case .errorDiagnosis(let configuration):
            StudyErrorDiagnosisActivityView(
                configuration: configuration,
                initialResponse: initialErrorDiagnosis,
                onDraft: onDraft,
                onComplete: onComplete
            )
        }
    }

    private var initialAcknowledgement: Bool {
        if case .acknowledgement(let value)? = initialResponse { value } else { false }
    }
    private var initialNumeric: StudyNumericQuantityResponse? {
        if case .numericQuantity(let value)? = initialResponse { value } else { nil }
    }
    private var initialMath: StudyMathExpressionResponse? {
        if case .mathExpression(let value)? = initialResponse { value } else { nil }
    }
    private var initialGraph: StudyGraphTableResponse? {
        if case .graphTable(let value)? = initialResponse { value } else { nil }
    }
    private var initialDiagrams: [StudyFreeBodyDiagramResponse]? {
        if case .freeBodyDiagram(let value)? = initialResponse { value } else { nil }
    }
    private var initialMotion: StudyMotionTrackingResponse? {
        if case .motionTrackingLab(let value)? = initialResponse { value } else { nil }
    }
    private var initialNumerical: StudyNumericalKinematicsResponse? {
        if case .numericalKinematics(let value)? = initialResponse { value } else { nil }
    }
    private var initialPython: StudyPythonNotebookResponse? {
        if case .pythonNotebook(let value)? = initialResponse { value } else { nil }
    }
    private var initialConstructed: StudyConstructedResponse? {
        if case .constructedResponse(let value)? = initialResponse { value } else { nil }
    }
    private var initialWorked: StudyWorkedExampleResponse? {
        if case .workedExample(let value)? = initialResponse { value } else { nil }
    }
    private var initialErrorDiagnosis: StudyErrorDiagnosisResponse? {
        if case .errorDiagnosis(let value)? = initialResponse { value } else { nil }
    }
}

private struct StudyMotionTrackingActivityAdapter: View {
    let configuration: StudyMotionTrackingActivityConfiguration
    let dataset: StudyDataset?
    let videoStorage: StudyMotionVideoStorageUI
    let onDraft: (StudyInteractiveResponse) -> Void
    let onComplete: (StudyInteractiveResponse) -> Void

    @State private var draft: StudyMotionTrackingDraftUI

    init(
        configuration: StudyMotionTrackingActivityConfiguration,
        dataset: StudyDataset?,
        initialResponse: StudyMotionTrackingResponse?,
        initialStoredVideo: StudyMotionStoredVideoUI?,
        videoStorage: StudyMotionVideoStorageUI,
        onDraft: @escaping (StudyInteractiveResponse) -> Void,
        onComplete: @escaping (StudyInteractiveResponse) -> Void
    ) {
        self.configuration = configuration
        self.dataset = dataset
        self.videoStorage = videoStorage
        self.onDraft = onDraft
        self.onComplete = onComplete
        let priorSamples = initialResponse?.samples.map {
            StudyMotionSampleUI(timeSeconds: $0.timeSeconds, positionMeters: $0.positionMetres)
        } ?? []
        let priorCalibration = initialResponse?.calibrationPoints.map {
            StudyNormalizedPoint(x: $0.x, y: $0.y)
        } ?? []
        let priorMarks = initialResponse?.frameMarks.map {
            StudyMotionFrameMarkUI(
                timeSeconds: $0.timeSeconds,
                point: .init(x: $0.normalizedX, y: $0.normalizedY)
            )
        } ?? []
        let reportValues = configuration.requiredReportFields.map { initialResponse?.reportFields[$0] ?? "" }
        _draft = State(initialValue: .init(
            localVideoURL: initialStoredVideo?.localURL,
            storedVideoArtifactID: initialStoredVideo?.artifactID,
            storedVideoRelativePath: initialStoredVideo?.relativePath,
            calibrationPixelSpan: initialResponse?.calibrationPixels ?? 0,
            calibrationPoints: priorCalibration,
            calibrationDistanceText: initialResponse.map { $0.calibrationDistanceMetres.formatted(.number.grouping(.never)) } ?? "",
            frameMarks: priorMarks,
            fallbackSamples: initialResponse?.usedFallbackDataset == true ? priorSamples : [],
            uncertainty: reportValues.indices.contains(0) ? reportValues[0] : "",
            modelComparison: reportValues.indices.contains(1) ? reportValues[1] : "",
            limitations: reportValues.indices.contains(2) ? reportValues[2] : ""
        ))
    }

    var body: some View {
        StudyMotionTrackingActivityView(
            configuration: .init(
                instructions: configuration.safetyMarkdown,
                minimumSamples: configuration.minimumSampleCount,
                maximumSamples: configuration.maximumSampleCount,
                fallbackSamples: StudyScienceDatasetLoader.motionSamples(dataset: dataset)
            ),
            draft: $draft,
            videoStorage: videoStorage,
            onComplete: { derived in
                let response = makeResponse(derived: derived)
                onDraft(response)
                onComplete(response)
            }
        )
        .onChange(of: draft) { _, _ in
            let derived = StudyMotionAnalysis.derive(activeSamples)
            onDraft(makeResponse(derived: derived))
        }
    }

    private var activeSamples: [StudyMotionSampleUI] {
        if !draft.fallbackSamples.isEmpty { return draft.fallbackSamples }
        guard let distance = Double(draft.calibrationDistanceText) else { return [] }
        return StudyMotionAnalysis.samples(
            from: draft.frameMarks,
            calibrationPoints: draft.calibrationPoints,
            knownDistanceMeters: draft.calibrationUnit.meters(from: distance)
        )
    }

    private func makeResponse(derived: [StudyMotionDerivedSampleUI]) -> StudyInteractiveResponse {
        let reportValues = [draft.uncertainty, draft.modelComparison, draft.limitations]
        let reports = Dictionary(uniqueKeysWithValues: configuration.requiredReportFields.enumerated().map { index, key in
            (key, reportValues.indices.contains(index) ? reportValues[index] : "")
        })
        return .motionTrackingLab(.init(
            calibrationDistanceMetres: Double(draft.calibrationDistanceText).map(draft.calibrationUnit.meters(from:)) ?? 0,
            calibrationPixels: draft.calibrationPixelSpan,
            samples: activeSamples.enumerated().map { index, sample in
                .init(frameIndex: index, timeSeconds: sample.timeSeconds, positionMetres: sample.positionMeters)
            },
            velocityPoints: derived.compactMap { sample in
                sample.velocityMetersPerSecond.map { .init(x: sample.timeSeconds, y: $0) }
            },
            accelerationPoints: derived.compactMap { sample in
                sample.accelerationMetersPerSecondSquared.map { .init(x: sample.timeSeconds, y: $0) }
            },
            calibrationPoints: draft.calibrationPoints.map { .init(x: $0.x, y: $0.y) },
            frameMarks: draft.frameMarks.map {
                .init(
                    timeSeconds: $0.timeSeconds,
                    normalizedX: $0.point.x,
                    normalizedY: $0.point.y
                )
            },
            reportFields: reports,
            usedFallbackDataset: !draft.fallbackSamples.isEmpty
        ))
    }
}

private enum StudyScienceToolDestinationUI: String, Identifiable, Equatable {
    case calculator
    case formulaCard
    case unitHelper

    var id: String { rawValue }
    var title: String {
        switch self {
        case .calculator: "Calculator"
        case .formulaCard: "Formula card"
        case .unitHelper: "Unit helper"
        }
    }
    var systemImage: String {
        switch self {
        case .calculator: "function"
        case .formulaCard: "list.bullet.rectangle"
        case .unitHelper: "ruler"
        }
    }
}

private struct StudyScienceToolPanelUI: View {
    let destination: StudyScienceToolDestinationUI
    let profile: StudyToolProfile?

    var body: some View {
        switch destination {
        case .calculator:
            StudyScientificCalculatorView(profile: calculatorProfile)
        case .formulaCard:
            ScrollView {
                StudyMarkdownDocument(markdown: profile?.formulaCardMarkdown ?? "No formula card is available.")
                    .padding()
            }
            .navigationTitle("Formula card")
            .background(ScreenBackground())
        case .unitHelper:
            StudyScienceUnitHelperView()
        }
    }

    private var calculatorProfile: StudyScientificCalculatorProfileUI {
        let formulae = (profile?.formulaCardMarkdown ?? "")
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "- *")) }
            .filter { !$0.isEmpty }
        return .init(
            title: profile?.title ?? "Scientific calculator",
            formulaCard: formulae,
            allowsHistory: profile?.calculator?.historyPolicy != .disabled
        )
    }
}

private struct StudyScienceUnitHelperView: View {
    private let units = ["m", "cm", "mm", "km", "s", "ms", "min", "h", "kg", "g", "m/s", "km/h", "m/s²", "cm/s²", "N", "kN", "rad", "deg"]
    @State private var value = "1"
    @State private var source = "m"
    @State private var target = "cm"

    private var result: String {
        guard let number = Double(value.replacingOccurrences(of: ",", with: ".")),
              let converted = StudyUnitNormalizer.convert(number, from: source, to: target) else {
            return "Choose compatible units."
        }
        return "\(converted.formatted(.number.precision(.significantDigits(1...10)))) \(target)"
    }

    var body: some View {
        Form {
            Section("Convert") {
                TextField("Value", text: $value)
                    .keyboardType(.numbersAndPunctuation)
                Picker("From", selection: $source) { ForEach(units, id: \.self) { Text($0).tag($0) } }
                Picker("To", selection: $target) { ForEach(units, id: \.self) { Text($0).tag($0) } }
            }
            Section("Result") {
                Text(result).font(.title3.monospacedDigit())
                Text("This helper converts units; it does not choose the correct physical model for you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Unit helper")
    }
}

// MARK: - Science assessments

enum StudyScienceAssessmentAnswerUI: Codable, Equatable, Sendable {
    case optionIDs([String])
    case numeric(rawValue: String, unitID: String?)
    case constructed(String)
}

struct StudyScienceAssessmentDraftUI: Codable, Equatable, Sendable {
    var attemptID: UUID
    var seed: UInt64
    var startedAt: Date
    var answers: [String: StudyScienceAssessmentAnswerUI]
}

struct StudyScienceAssessmentSubmissionUI: Sendable {
    let draft: StudyScienceAssessmentDraftUI
    let earnedPoints: Double
    let possiblePoints: Double
    let correctScorableItems: Int
    let requiredScorableItems: Int
    let didPass: Bool
}

@MainActor
struct StudyScienceAssessmentScreen: View {
    let blueprint: StudyCourseAssessmentBlueprint
    let items: [StudyScienceAssessmentItem]
    let toolProfile: StudyToolProfile?
    let initialDraft: StudyScienceAssessmentDraftUI?
    let saveDraft: (StudyScienceAssessmentDraftUI) throws -> Void
    let submit: (StudyScienceAssessmentSubmissionUI) throws -> Void

    @State private var draft: StudyScienceAssessmentDraftUI
    @State private var currentIndex = 0
    @State private var submittedResult: StudyScienceAssessmentSubmissionUI?
    @State private var selectedTool: StudyScienceToolDestinationUI?
    @State private var saveTask: Task<Void, Never>?
    @State private var saveState: StudyScienceWorkspaceSaveState = .saved
    @State private var submissionError: String?
    @State private var now = Date.now

    init(
        blueprint: StudyCourseAssessmentBlueprint,
        items: [StudyScienceAssessmentItem],
        toolProfile: StudyToolProfile?,
        initialDraft: StudyScienceAssessmentDraftUI? = nil,
        seed: UInt64 = UInt64.random(in: 1...UInt64.max),
        saveDraft: @escaping (StudyScienceAssessmentDraftUI) throws -> Void,
        submit: @escaping (StudyScienceAssessmentSubmissionUI) throws -> Void
    ) {
        self.blueprint = blueprint
        self.items = items
        self.toolProfile = toolProfile
        self.initialDraft = initialDraft
        self.saveDraft = saveDraft
        self.submit = submit
        _draft = State(initialValue: initialDraft ?? .init(
            attemptID: UUID(),
            seed: seed,
            startedAt: .now,
            answers: [:]
        ))
    }

    private var orderedItems: [StudyScienceAssessmentItem] {
        let requested = blueprint.scienceAssessmentItemIDs ?? items.map(\.id)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return requested.compactMap { byID[$0] }
    }

    private var passPolicy: StudyScienceAssessmentPassPolicy {
        let scorableCount = orderedItems.filter { $0.kind != .constructedResponse }.count
        return blueprint.sciencePassPolicy ?? .init(
            scorableItemCount: scorableCount,
            minimumCorrectCount: Int(ceil(Double(scorableCount) * 0.7)),
            requiredConstructedResponseCount: orderedItems.filter { $0.kind == .constructedResponse }.count,
            displayThreshold: "70%"
        )
    }

    private var remainingSeconds: Int? {
        guard let duration = blueprint.durationSeconds else { return nil }
        return max(0, duration - Int(now.timeIntervalSince(draft.startedAt)))
    }

    var body: some View {
        Group {
            if let submittedResult {
                assessmentReview(submittedResult)
            } else if orderedItems.isEmpty {
                ContentUnavailableView("Assessment unavailable", systemImage: "doc.questionmark")
            } else {
                assessmentPlayer
            }
        }
        .navigationTitle(blueprint.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
        .toolbar {
            if toolProfile?.capabilities.contains(.scientificCalculator) == true {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { selectedTool = .calculator } label: {
                        Label("Calculator", systemImage: "function")
                    }
                }
            }
        }
        .sheet(item: $selectedTool) { tool in
            NavigationStack {
                StudyScienceToolPanelUI(destination: tool, profile: toolProfile)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { selectedTool = nil }
                        }
                    }
            }
        }
        .task(id: draft.attemptID) {
            while !Task.isCancelled, submittedResult == nil {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                now = .now
                if remainingSeconds == 0 {
                    submitAssessment()
                    return
                }
            }
        }
        .onChange(of: draft) { _, _ in queueSave() }
        .alert("Unable to submit", isPresented: Binding(
            get: { submissionError != nil },
            set: { if !$0 { submissionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(submissionError ?? "Your assessment draft remains saved.")
        }
        .onDisappear { saveTask?.cancel() }
    }

    private var assessmentPlayer: some View {
        let item = orderedItems[min(currentIndex, orderedItems.count - 1)]
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                assessmentHeader
                ProgressView(value: Double(currentIndex + 1), total: Double(orderedItems.count)) {
                    Text("Question \(currentIndex + 1) of \(orderedItems.count)")
                }
                .tint(Brand.red)
                StudyScienceAssessmentItemEditor(
                    item: item,
                    seed: draft.seed,
                    answer: answerBinding(for: item.id)
                )
                .id(item.id)
                HStack {
                    Button("Previous") { currentIndex = max(currentIndex - 1, 0) }
                        .studySecondaryActionStyle()
                        .disabled(currentIndex == 0)
                    Spacer()
                    if currentIndex < orderedItems.count - 1 {
                        Button("Next") { currentIndex += 1 }
                            .studyPrimaryActionStyle()
                    } else {
                        Button("Submit assessment") { submitAssessment() }
                            .studyPrimaryActionStyle()
                            .disabled(!allRequiredAnswersPresent)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 36)
        }
    }

    private var assessmentHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(blueprint.kind == .masteryTest ? "MASTERY TEST" : "MODULE QUIZ", systemImage: "checkmark.seal")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.redSoft)
                Spacer()
                if let remainingSeconds {
                    Text(duration(remainingSeconds))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(remainingSeconds <= 60 ? Brand.redSoft : .primary)
                        .accessibilityLabel("\(remainingSeconds) seconds remaining")
                }
            }
            Text("Pass with \(passPolicy.minimumCorrectCount) of \(passPolicy.scorableItemCount) objective questions correct and all \(passPolicy.requiredConstructedResponseCount) written responses completed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label(saveState.title, systemImage: saveState.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .studyPaperSurface(cornerRadius: 17, emphasized: true)
    }

    private var allRequiredAnswersPresent: Bool {
        orderedItems.allSatisfy { item in
            guard let answer = draft.answers[item.id] else { return false }
            switch answer {
            case .optionIDs(let ids): return !ids.isEmpty
            case .numeric(let raw, let unit):
                return !raw.trimmingCharacters(in: .whitespaces).isEmpty
                    && (!(item.numericAnswer?.requiresUnit ?? false) || unit?.isEmpty == false)
            case .constructed(let value):
                return value.trimmingCharacters(in: .whitespacesAndNewlines).count >= (item.minimumResponseCharacters ?? 1)
            }
        }
    }

    private func answerBinding(for itemID: String) -> Binding<StudyScienceAssessmentAnswerUI?> {
        Binding(get: { draft.answers[itemID] }, set: { answer in draft.answers[itemID] = answer })
    }

    private func queueSave() {
        saveState = .saving
        saveTask?.cancel()
        let snapshot = draft
        saveTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                try saveDraft(snapshot)
                saveState = .saved
            } catch is CancellationError {
                return
            } catch {
                saveState = .failed(error.localizedDescription)
            }
        }
    }

    private func submitAssessment() {
        saveTask?.cancel()
        let result = grade()
        do {
            try saveDraft(draft)
            try submit(result)
            submittedResult = result
            saveState = .saved
        } catch {
            submissionError = error.localizedDescription
            saveState = .failed(error.localizedDescription)
        }
    }

    private func grade() -> StudyScienceAssessmentSubmissionUI {
        var correct = 0
        var scorable = 0
        var constructedCount = 0
        for item in orderedItems {
            switch item.kind {
            case .objectiveChoice:
                scorable += 1
                if case .optionIDs(let selected) = draft.answers[item.id],
                   Set(selected) == Set(item.correctOptionIDs) { correct += 1 }
            case .numericQuantity:
                scorable += 1
                if case .numeric(let raw, let unit) = draft.answers[item.id],
                   let specification = item.numericAnswer,
                   StudyNumericResponseGrader.grade(rawValue: raw, unitID: unit, specification: specification).isCorrect {
                    correct += 1
                }
            case .constructedResponse:
                if case .constructed(let response) = draft.answers[item.id],
                   response.trimmingCharacters(in: .whitespacesAndNewlines).count >= (item.minimumResponseCharacters ?? 1) {
                    constructedCount += 1
                }
            }
        }
        let requiredScorable = passPolicy.scorableItemCount
        return .init(
            draft: draft,
            earnedPoints: Double(correct),
            possiblePoints: Double(max(requiredScorable, scorable)),
            correctScorableItems: correct,
            requiredScorableItems: requiredScorable,
            didPass: correct >= passPolicy.minimumCorrectCount
                && constructedCount >= passPolicy.requiredConstructedResponseCount
        )
    }

    private func assessmentReview(_ result: StudyScienceAssessmentSubmissionUI) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        result.didPass ? "Mastery target reached" : "Review and retry",
                        systemImage: result.didPass ? "checkmark.seal.fill" : "arrow.counterclockwise.circle"
                    )
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(result.didPass ? .green : Brand.redSoft)
                    Text("\(result.correctScorableItems) of \(result.requiredScorableItems) objective questions correct. Written responses were recorded but are not assigned an invented score.")
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .studyPaperSurface(cornerRadius: 18, emphasized: true)

                ForEach(orderedItems) { item in
                    StudyScienceAssessmentFeedbackCard(item: item, answer: draft.answers[item.id])
                }

                if blueprint.unlimitedRetries == true {
                    Button {
                        draft = .init(
                            attemptID: UUID(),
                            seed: draft.seed &+ 1,
                            startedAt: .now,
                            answers: [:]
                        )
                        currentIndex = 0
                        submittedResult = nil
                        now = .now
                    } label: {
                        Label("Try another attempt", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .studyPrimaryActionStyle()
                }
            }
            .padding(16)
            .padding(.bottom, 36)
        }
    }

    private func duration(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct StudyScienceAssessmentItemEditor: View {
    let item: StudyScienceAssessmentItem
    let seed: UInt64
    @Binding var answer: StudyScienceAssessmentAnswerUI?

    private var orderedOptions: [StudyScienceAssessmentOption] {
        item.options.sorted {
            stableOrder(itemID: item.id, optionID: $0.id) < stableOrder(itemID: item.id, optionID: $1.id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            StudyMarkdownDocument(markdown: item.promptMarkdown)
            switch item.kind {
            case .objectiveChoice:
                ForEach(orderedOptions) { option in
                    Button {
                        select(option.id)
                    } label: {
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: selectedOptionIDs.contains(option.id)
                                  ? (item.correctOptionIDs.count > 1 ? "checkmark.square.fill" : "largecircle.fill.circle")
                                  : (item.correctOptionIDs.count > 1 ? "square" : "circle"))
                                .foregroundStyle(selectedOptionIDs.contains(option.id) ? Brand.red : .secondary)
                            Text(option.label)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(13)
                        .contentShape(Rectangle())
                        .studyPaperSurface(cornerRadius: 13)
                    }
                    .buttonStyle(.plain)
                }
            case .numericQuantity:
                let numeric = numericAnswer
                HStack {
                    TextField("Value", text: Binding(
                        get: { numeric.rawValue },
                        set: { answer = .numeric(rawValue: $0, unitID: numeric.unitID) }
                    ))
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)
                    TextField(item.numericAnswer?.canonicalUnitID ?? "Unit", text: Binding(
                        get: { numeric.unitID ?? "" },
                        set: { answer = .numeric(rawValue: numeric.rawValue, unitID: $0) }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 110)
                }
            case .constructedResponse:
                TextEditor(text: Binding(
                    get: { constructedAnswer },
                    set: { answer = .constructed($0) }
                ))
                .frame(minHeight: 180)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Brand.controlFill, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(Brand.separator) }
                Text("Required response; retained for self-comparison and future teacher review, not automatically scored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .studyPaperSurface(cornerRadius: 17, emphasized: true)
    }

    private var selectedOptionIDs: Set<String> {
        if case .optionIDs(let ids) = answer { Set(ids) } else { [] }
    }
    private var numericAnswer: (rawValue: String, unitID: String?) {
        if case .numeric(let raw, let unit) = answer { (raw, unit) } else { ("", nil) }
    }
    private var constructedAnswer: String {
        if case .constructed(let value) = answer { value } else { "" }
    }

    private func select(_ id: String) {
        if item.correctOptionIDs.count <= 1 {
            answer = .optionIDs([id])
        } else {
            var selected = selectedOptionIDs
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
            answer = .optionIDs(selected.sorted())
        }
    }

    private func stableOrder(itemID: String, optionID: String) -> UInt64 {
        var value = seed ^ 14_695_981_039_346_656_037
        for byte in "\(itemID)::\(optionID)".utf8 {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
        return value
    }
}

private struct StudyScienceAssessmentFeedbackCard: View {
    let item: StudyScienceAssessmentItem
    let answer: StudyScienceAssessmentAnswerUI?

    private var isCorrect: Bool? {
        switch item.kind {
        case .objectiveChoice:
            guard case .optionIDs(let selected) = answer else { return false }
            return Set(selected) == Set(item.correctOptionIDs)
        case .numericQuantity:
            guard case .numeric(let raw, let unit) = answer,
                  let specification = item.numericAnswer else { return false }
            return StudyNumericResponseGrader.grade(rawValue: raw, unitID: unit, specification: specification).isCorrect
        case .constructedResponse:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(item.id).font(.caption.monospaced())
                Spacer()
                if let isCorrect {
                    Label(isCorrect ? "Correct" : "Review", systemImage: isCorrect ? "checkmark.circle.fill" : "arrow.counterclockwise.circle")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isCorrect ? .green : Brand.redSoft)
                } else {
                    Label("Recorded · unscored", systemImage: "text.badge.checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            StudyMarkdownDocument(markdown: item.promptMarkdown)
            if item.kind == .objectiveChoice {
                let correctLabels = item.options.filter { item.correctOptionIDs.contains($0.id) }.map(\.label)
                Text("Expected: \(correctLabels.joined(separator: ", "))")
                    .font(.subheadline.weight(.semibold))
            }
            if let rubric = item.rubricMarkdown {
                DisclosureGroup("Compare with the response guide") {
                    StudyMarkdownDocument(markdown: rubric).padding(.top, 7)
                }
            }
        }
        .padding(15)
        .studyPaperSurface(cornerRadius: 15)
    }
}
