import Foundation
import SwiftUI

/// A native candidate-paper and examination setup screen.
///
/// The complete authored candidate paper remains available here as Markdown,
/// while the structured section list controls which written response fields are
/// included in the timed attempt. Examiner-only material is never exposed.
struct StudyCourseInteractiveExamScreen: View {
    let assessmentID: String

    @Environment(StudyCourseLibrary.self) private var library
    @Environment(StudyAssessmentStore.self) private var assessments
    @Environment(RouterPath.self) private var router

    @State private var selectedQuestionBySection: [String: String] = [:]
    @State private var isCandidatePaperExpanded = false
    @State private var confirmsCandidateDeclaration = false
    @State private var isStartingAttempt = false
    @State private var isReloadingCoursePackage = false
    @State private var presentedAlert: InteractiveExamAlert?

    private var exam: StudyCourseAssessmentBlueprint? {
        guard let assessment = library.assessment(id: assessmentID) else { return nil }
        switch assessment.kind {
        case .courseFinal, .mockExam, .fullScaleExam:
            return assessment
        case .lessonCheck, .moduleQuiz, .practiceTest:
            return nil
        }
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            if let exam {
                examContent(exam)
            } else {
                unavailableContent
            }
        }
        .navigationTitle("Final Examination")
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $presentedAlert) { alert in
            switch alert {
            case .confirmStart:
                Alert(
                    title: Text("Begin timed examination?"),
                    message: Text(confirmStartMessage),
                    primaryButton: .default(Text("Begin examination")) {
                        startAttempt()
                    },
                    secondaryButton: .cancel()
                )
            case .error(let message):
                Alert(
                    title: Text("Examination unavailable"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func examContent(_ exam: StudyCourseAssessmentBlueprint) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 17) {
                InteractiveExamHeader(
                    eyebrow: "COURSE FINAL · SUMMATIVE",
                    title: exam.title,
                    message: "Read the complete candidate paper, choose the permitted prompts, and write every response in the native timed examination.",
                    systemImage: "checkmark.seal"
                )

                examFacts(exam)
                candidateInstructions(exam)
                completeCandidatePaper(exam)

                ForEach(Array((exam.examSections ?? []).enumerated()), id: \.element.id) { index, section in
                    examSection(section, index: index)
                }

                selectionSummary(exam)
                candidateDeclaration(exam)
                assessmentReadiness(exam)
                startButton(exam)

                InteractiveExamNotice(
                    title: "Examiner materials are restricted",
                    message: "Examiner marking guides, answer keys, and restricted marking guidance are unavailable in the learner application. They are not included in this screen or released after submission.",
                    systemImage: "lock.shield",
                    tint: .secondary
                )
                .accessibilityLabel("Restricted examiner materials")
                .accessibilityValue("Examiner marking guides and answer keys are unavailable to learners")
            }
            .padding(16)
            .padding(.bottom, 36)
        }
    }

    private func examFacts(_ exam: StudyCourseAssessmentBlueprint) -> some View {
        InteractiveExamSectionCard(title: "Examination details") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 136), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                InteractiveExamFact(
                    title: "Time",
                    value: durationLabel(exam.durationSeconds),
                    systemImage: "timer"
                )
                InteractiveExamFact(
                    title: "Marks",
                    value: "\(exam.totalPoints)",
                    systemImage: "number"
                )
                InteractiveExamFact(
                    title: "Course weight",
                    value: exam.courseWeightPercent.map { "\($0)%" } ?? "Not specified",
                    systemImage: "percent"
                )
                InteractiveExamFact(
                    title: "Response mode",
                    value: "Written · human marked",
                    systemImage: "square.and.pencil"
                )
            }

            if let recommended = recommendedTimeLabel(exam) {
                Label(recommended, systemImage: "clock.badge.checkmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Recommended working time: \(recommended)")
            }
        }
    }

    private func candidateInstructions(_ exam: StudyCourseAssessmentBlueprint) -> some View {
        InteractiveExamSectionCard(title: "Before you begin") {
            if let materials = nonBlank(exam.permittedMaterials) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Permitted materials", systemImage: "books.vertical")
                        .font(.subheadline.weight(.semibold))
                    Text(materials)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }

            Label(
                "The timer begins when the native examination opens. Responses are saved locally as you proceed.",
                systemImage: "timer"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Label(
                "Written responses require human academic marking. The app does not calculate or claim an examination grade.",
                systemImage: "person.text.rectangle"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)

            if let instructions = nonBlank(exam.candidateInstructionsMarkdown) {
                Divider().padding(.vertical, 2)
                Text("Complete candidate instructions")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                StudyMarkdownDocument(markdown: instructions)
            } else {
                Label("Complete candidate instructions have not been extracted into the native examination record.", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
            }
        }
    }

    @ViewBuilder
    private func completeCandidatePaper(_ exam: StudyCourseAssessmentBlueprint) -> some View {
        if let sourceMarkdown = candidatePaper(exam) {
            VStack(alignment: .leading, spacing: 11) {
                DisclosureGroup(isExpanded: $isCandidatePaperExpanded) {
                    Divider().padding(.vertical, 4)
                    StudyMarkdownDocument(markdown: sourceMarkdown)
                        .padding(.top, 2)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Complete candidate paper", systemImage: "doc.text.fill")
                            .font(.system(.title3, design: .serif, weight: .semibold))
                        Text("Unabridged native text, including all candidate information and instructions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(Brand.redSoft)
                .accessibilityHint(isCandidatePaperExpanded ? "Collapses the complete candidate paper" : "Expands the complete candidate paper")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .studyPaperSurface(cornerRadius: 16, emphasized: true)
        } else {
            InteractiveExamNotice(
                title: "Complete candidate paper is missing",
                message: "The examination cannot begin because the unabridged source text has not been integrated into the native course package.",
                systemImage: "exclamationmark.triangle",
                tint: .orange
            )
        }
    }

    private func examSection(_ section: StudyCourseExamSection, index: Int) -> some View {
        let policy = InteractiveExamResponsePolicy(section.responsePolicy)
        let selectedQuestionID = selectedQuestionBySection[section.id]

        return InteractiveExamSectionCard(title: section.title) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("SECTION \(sectionLabel(section, fallbackIndex: index))")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(Brand.redSoft)
                Spacer()
                Text(policy.instruction(questionCount: section.questions.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(policy == .unsupported ? Color.orange : .secondary)
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)

            if let instructions = nonBlank(section.instructionsMarkdown) {
                StudyMarkdownDocument(markdown: instructions)
                    .foregroundStyle(.secondary)
            }

            ForEach(section.questions) { question in
                let isSelected = policy == .all || selectedQuestionID == question.id
                let canSelect = policy == .chooseOne && question.responseQuestionID != nil

                InteractiveExamQuestionCard(
                    question: question,
                    state: policy == .all ? .required : (isSelected ? .selected : .available),
                    isSelectable: canSelect
                ) {
                    selectedQuestionBySection[section.id] = question.id
                }
            }

            if policy == .chooseOne, selectedQuestionID == nil {
                Label("Choose exactly one prompt from this section before beginning.", systemImage: "circle.dotted")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if policy == .unsupported {
                Label("This response policy is not supported by the native examination player.", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
            }
        }
    }

    private func selectionSummary(_ exam: StudyCourseAssessmentBlueprint) -> some View {
        let questions = selectedQuestions(in: exam)
        let codes = questions.map(\.code).joined(separator: ", ")
        let marks = questions.reduce(0) { $0 + $1.points }
        let remaining = remainingChoiceCount(in: exam)

        return InteractiveExamSectionCard(title: "Your examination paper") {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: remaining == 0 ? "checkmark.circle.fill" : "circle.dotted")
                    .font(.title2)
                    .foregroundStyle(remaining == 0 ? Brand.redSoft : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(remaining == 0 ? "Selection complete" : selectionPrompt(remaining))
                        .font(.headline)
                    Text("\(questions.count) written response\(questions.count == 1 ? "" : "s") · \(marks) of \(exam.totalPoints) marks selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !codes.isEmpty {
                        Text(codes)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Examination selection summary")
            .accessibilityValue(remaining == 0
                ? "Complete. \(questions.count) responses worth \(marks) marks. \(codes)"
                : "\(remaining) section selections remaining")
        }
    }

    @ViewBuilder
    private func candidateDeclaration(_ exam: StudyCourseAssessmentBlueprint) -> some View {
        if let declaration = nonBlank(exam.candidateDeclarationMarkdown) {
            InteractiveExamSectionCard(title: "Candidate declaration") {
                StudyMarkdownDocument(markdown: declaration)

                Divider().padding(.vertical, 2)

                Toggle(isOn: $confirmsCandidateDeclaration) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("I confirm this declaration")
                            .font(.subheadline.weight(.semibold))
                        Text("This records only an in-app confirmation. It does not collect a signature or legal identity.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(Brand.red)
                .accessibilityLabel("Confirm candidate declaration")
                .accessibilityHint("Required before the timed examination can begin")
            }
        } else {
            InteractiveExamNotice(
                title: "Candidate declaration is missing",
                message: "The examination cannot begin until the complete declaration is available for native review and confirmation.",
                systemImage: "exclamationmark.triangle",
                tint: .orange
            )
        }
    }

    @ViewBuilder
    private func assessmentReadiness(_ exam: StudyCourseAssessmentBlueprint) -> some View {
        let issues = configurationIssues(for: exam)

        if !issues.isEmpty {
            InteractiveExamNotice(
                title: "Native examination setup is incomplete",
                message: issues.joined(separator: "\n"),
                systemImage: "exclamationmark.triangle",
                tint: .orange
            )
        }

        switch assessments.loadState {
        case .loading:
            HStack(spacing: 11) {
                ProgressView()
                Text("Preparing your local examination record…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .studyPaperSurface(cornerRadius: 15)
            .accessibilityElement(children: .combine)
        case .failed(let message):
            InteractiveExamNotice(
                title: "Study progress is unavailable",
                message: message,
                systemImage: "exclamationmark.icloud",
                tint: .orange
            )
        case .idle:
            InteractiveExamNotice(
                title: "Preparing your study profile",
                message: "The examination can begin after the local study profile has finished loading.",
                systemImage: "hourglass",
                tint: .secondary
            )
        case .ready:
            EmptyView()
        }
    }

    private func startButton(_ exam: StudyCourseAssessmentBlueprint) -> some View {
        Button {
            presentedAlert = .confirmStart
        } label: {
            HStack(spacing: 9) {
                if isStartingAttempt {
                    ProgressView()
                        .tint(Brand.onAccent)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "timer")
                        .accessibilityHidden(true)
                }
                Text(startButtonTitle(exam))
                    .font(.headline)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .studyPrimaryActionStyle()
        .disabled(!canStart(exam))
        .accessibilityLabel("Begin timed examination")
        .accessibilityHint(startAccessibilityHint(exam))
    }

    private var unavailableContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                ContentUnavailableView {
                    Label("Examination unavailable", systemImage: "doc.badge.ellipsis")
                } description: {
                    if let error = library.loadError {
                        Text(error)
                    } else {
                        Text("The native examination has not been loaded from its course package.")
                    }
                }

                Button {
                    reloadCoursePackage()
                } label: {
                    if isReloadingCoursePackage {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Reload course content", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                }
                .studySecondaryActionStyle()
                .disabled(isReloadingCoursePackage)
                .accessibilityHint("Reloads native course packages and examination response fields")
            }
            .padding(24)
        }
    }

    private var confirmStartMessage: String {
        guard let exam else { return "The examination is unavailable." }
        return "The \(durationLabel(exam.durationSeconds)) timer starts immediately. You selected \(selectedQuestions(in: exam).count) written responses worth \(selectedQuestions(in: exam).reduce(0) { $0 + $1.points }) marks. Written work requires human marking."
    }

    private func canStart(_ exam: StudyCourseAssessmentBlueprint) -> Bool {
        guard !isStartingAttempt,
              case .ready = assessments.loadState,
              remainingChoiceCount(in: exam) == 0,
              confirmsCandidateDeclaration,
              configurationIssues(for: exam).isEmpty else {
            return false
        }
        return !selectedResponseQuestionIDs(in: exam).isEmpty
    }

    private func startButtonTitle(_ exam: StudyCourseAssessmentBlueprint) -> String {
        if isStartingAttempt { return "Starting examination…" }
        let remaining = remainingChoiceCount(in: exam)
        if remaining > 0 { return selectionPrompt(remaining) }
        if case .loading = assessments.loadState { return "Preparing examination…" }
        if !confirmsCandidateDeclaration { return "Confirm declaration to begin" }
        return "Begin timed examination"
    }

    private func startAccessibilityHint(_ exam: StudyCourseAssessmentBlueprint) -> String {
        let remaining = remainingChoiceCount(in: exam)
        if remaining > 0 { return "Choose one prompt in each of the \(remaining) remaining sections first" }
        if !configurationIssues(for: exam).isEmpty { return "Unavailable until every native examination resource is integrated" }
        if !confirmsCandidateDeclaration { return "Review and confirm the candidate declaration first" }
        if case .ready = assessments.loadState {
            return "Starts the \(durationLabel(exam.durationSeconds)) timer immediately"
        }
        return "Unavailable until the local study profile finishes loading"
    }

    private func startAttempt() {
        guard let exam else {
            presentedAlert = .error("The examination is no longer available.")
            return
        }
        guard canStart(exam), let courseID = nonBlank(exam.courseID) else {
            presentedAlert = .error("Complete every required prompt selection and resolve the displayed course-package issues before beginning.")
            return
        }

        let questionIDs = selectedResponseQuestionIDs(in: exam)
        let plan = StudySessionPlan(
            id: exam.id,
            kind: .practiceExam,
            title: exam.title,
            requestedItemCount: questionIDs.count,
            domain: nil,
            requestedQuestionIDs: questionIDs,
            feedbackPolicy: .afterSubmission,
            durationSeconds: exam.durationSeconds,
            affectsItemMastery: false,
            context: StudyAssessmentContext(
                source: .exam,
                courseID: courseID,
                assessmentID: exam.id,
                gradeRole: .summative
            )
        )

        isStartingAttempt = true
        Task { @MainActor in
            defer { isStartingAttempt = false }
            do {
                let attemptID = try await assessments.startAttempt(plan: plan)
                router.navigate(to: .studyQuiz(attemptID: attemptID))
            } catch is CancellationError {
                return
            } catch {
                presentedAlert = .error(error.localizedDescription)
            }
        }
    }

    private func reloadCoursePackage() {
        guard !isReloadingCoursePackage else { return }
        isReloadingCoursePackage = true
        Task { @MainActor in
            await library.reload()
            assessments.setCourseQuestions(library.questions)
            isReloadingCoursePackage = false
            if exam == nil {
                presentedAlert = .error(library.loadError ?? "The requested examination is not present in the installed course package.")
            }
        }
    }

    /// Returns questions in source section order and source question order.
    private func selectedQuestions(in exam: StudyCourseAssessmentBlueprint) -> [StudyCourseExamQuestion] {
        (exam.examSections ?? []).flatMap { section in
            switch InteractiveExamResponsePolicy(section.responsePolicy) {
            case .all:
                return section.questions
            case .chooseOne:
                guard let selectedID = selectedQuestionBySection[section.id],
                      let question = section.questions.first(where: { $0.id == selectedID }) else {
                    return []
                }
                return [question]
            case .unsupported:
                return []
            }
        }
    }

    /// The assessment engine preserves this requested-ID order in the attempt.
    private func selectedResponseQuestionIDs(in exam: StudyCourseAssessmentBlueprint) -> [String] {
        selectedQuestions(in: exam).compactMap(\.responseQuestionID)
    }

    private func remainingChoiceCount(in exam: StudyCourseAssessmentBlueprint) -> Int {
        (exam.examSections ?? []).reduce(into: 0) { count, section in
            guard InteractiveExamResponsePolicy(section.responsePolicy) == .chooseOne else { return }
            guard let selectedID = selectedQuestionBySection[section.id],
                  section.questions.contains(where: { $0.id == selectedID && $0.responseQuestionID != nil }) else {
                count += 1
                return
            }
        }
    }

    private func configurationIssues(for exam: StudyCourseAssessmentBlueprint) -> [String] {
        var issues: [String] = []
        let sections = exam.examSections ?? []

        if candidatePaper(exam) == nil {
            issues.append("The complete candidate-paper text is missing.")
        }
        if nonBlank(exam.candidateInstructionsMarkdown) == nil {
            issues.append("The complete candidate instructions are missing from the native examination record.")
        }
        if nonBlank(exam.candidateDeclarationMarkdown) == nil {
            issues.append("The candidate declaration is missing from the native examination record.")
        }
        if nonBlank(exam.courseID) == nil {
            issues.append("The examination is not linked to its course.")
        }
        if sections.isEmpty {
            issues.append("No structured examination sections are available.")
        }
        if exam.durationSeconds == nil {
            issues.append("The examination duration is missing.")
        }

        let unsupportedPolicies = sections.filter {
            InteractiveExamResponsePolicy($0.responsePolicy) == .unsupported
        }
        if !unsupportedPolicies.isEmpty {
            issues.append("\(unsupportedPolicies.count) section response polic\(unsupportedPolicies.count == 1 ? "y is" : "ies are") unsupported.")
        }

        let examQuestions = sections.flatMap(\.questions)
        let missingMappings = examQuestions.filter { nonBlank($0.responseQuestionID) == nil }
        if !missingMappings.isEmpty {
            issues.append("\(missingMappings.count) examination prompt\(missingMappings.count == 1 ? " is" : "s are") not connected to a native written-response field.")
        }

        let mappedIDs = examQuestions.compactMap(\.responseQuestionID)
        let missingQuestions = mappedIDs.filter { assessments.question(id: $0) == nil }
        if !missingQuestions.isEmpty {
            issues.append("\(missingQuestions.count) native written-response field\(missingQuestions.count == 1 ? " has" : "s have") not loaded.")
        }
        if Set(mappedIDs).count != mappedIDs.count {
            issues.append("Two or more examination prompts refer to the same written-response field.")
        }

        return issues
    }

    private func candidatePaper(_ exam: StudyCourseAssessmentBlueprint) -> String? {
        guard let markdown = exam.sourceMarkdown, nonBlank(markdown) != nil else { return nil }
        return markdown
    }

    private func durationLabel(_ durationSeconds: Int?) -> String {
        guard let durationSeconds, durationSeconds > 0 else { return "Not specified" }
        let hours = durationSeconds / 3_600
        let minutes = (durationSeconds % 3_600) / 60
        if hours == 0 { return "\(minutes) minutes" }
        if minutes == 0 { return "\(hours) hour\(hours == 1 ? "" : "s")" }
        return "\(hours) hr \(minutes) min"
    }

    private func recommendedTimeLabel(_ exam: StudyCourseAssessmentBlueprint) -> String? {
        switch (exam.recommendedTimeMinimumMinutes, exam.recommendedTimeMaximumMinutes) {
        case let (minimum?, maximum?) where minimum == maximum:
            return "Recommended working time: \(minimum) minutes"
        case let (minimum?, maximum?):
            return "Recommended working time: \(minimum)–\(maximum) minutes"
        case let (minimum?, nil):
            return "Recommended working time: at least \(minimum) minutes"
        case let (nil, maximum?):
            return "Recommended working time: up to \(maximum) minutes"
        case (nil, nil):
            return nil
        }
    }

    private func sectionLabel(_ section: StudyCourseExamSection, fallbackIndex: Int) -> String {
        if let firstCode = section.questions.first?.code {
            let prefix = firstCode.prefix { !$0.isNumber }
            if !prefix.isEmpty { return String(prefix) }
        }
        return "\(fallbackIndex + 1)"
    }

    private func selectionPrompt(_ remaining: Int) -> String {
        "Choose \(remaining) more prompt\(remaining == 1 ? "" : "s")"
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}

private enum InteractiveExamResponsePolicy: Equatable {
    case all
    case chooseOne
    case unsupported

    init(_ sourceValue: String) {
        let normalized = sourceValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        switch normalized {
        case "all", "answer_all": self = .all
        case "choose_one", "one": self = .chooseOne
        default: self = .unsupported
        }
    }

    func instruction(questionCount: Int) -> String {
        switch self {
        case .all:
            "Answer all \(questionCount)"
        case .chooseOne:
            "Choose exactly one of \(questionCount)"
        case .unsupported:
            "Unsupported response policy"
        }
    }
}

private enum InteractiveExamAlert: Identifiable {
    case confirmStart
    case error(String)

    var id: String {
        switch self {
        case .confirmStart: "confirm-start"
        case .error(let message): "error-\(message)"
        }
    }
}

private enum InteractiveExamQuestionState {
    case required
    case selected
    case available

    var title: String {
        switch self {
        case .required: "Required"
        case .selected: "Selected"
        case .available: "Choose this prompt"
        }
    }

    var systemImage: String {
        switch self {
        case .required: "checkmark.circle.fill"
        case .selected: "largecircle.fill.circle"
        case .available: "circle"
        }
    }
}

private struct InteractiveExamHeader: View {
    let eyebrow: String
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Brand.redSoft)
                .accessibilityHidden(true)
            Text(eyebrow)
                .font(.caption2.weight(.bold))
                .tracking(0.9)
                .foregroundStyle(Brand.redSoft)
            Text(title)
                .font(.system(.title2, design: .serif, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.body)
                .lineSpacing(3)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studyPaperSurface(cornerRadius: 20, emphasized: true)
    }
}

private struct InteractiveExamSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studyPaperSurface(cornerRadius: 16)
    }
}

private struct InteractiveExamFact: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Brand.redSoft)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(Brand.subtleFill.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

private struct InteractiveExamQuestionCard: View {
    let question: StudyCourseExamQuestion
    let state: InteractiveExamQuestionState
    let isSelectable: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isSelectable {
                Button(action: action) {
                    questionContent
                }
                .buttonStyle(PressableScaleButtonStyle(scale: 0.988))
                .accessibilityValue(state == .selected ? "Selected" : "Not selected")
                .accessibilityHint(state == .selected ? "Currently selected for this section" : "Selects this prompt for the examination")
            } else {
                questionContent
                    .accessibilityElement(children: .contain)
            }
        }
    }

    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(question.code)
                    .font(.subheadline.monospaced().weight(.bold))
                    .foregroundStyle(Brand.redSoft)
                if !question.title.isEmpty {
                    Text(question.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 8)
                Text("\(question.points) marks")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            StudyMarkdownDocument(markdown: question.promptMarkdown)
                .foregroundStyle(.primary)

            HStack(spacing: 7) {
                Image(systemName: state.systemImage)
                    .accessibilityHidden(true)
                Text(state.title)
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(state == .available ? .secondary : Brand.redSoft)

            if question.responseQuestionID == nil {
                Label("Native response field unavailable", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            state == .selected ? Brand.red.opacity(0.10) : Brand.subtleFill.opacity(0.58),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(state == .selected ? Brand.red.opacity(0.45) : Brand.separator.opacity(0.48), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct InteractiveExamNotice: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.subtleFill.opacity(0.64), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
