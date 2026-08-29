import SwiftUI
import SwiftData

// MARK: - Shared assessment presentation

struct StudyAssessmentHeader: View {
    let eyebrow: String
    let title: String
    let message: String
    var systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Brand.onAccent)
                .frame(width: 48, height: 48)
                .background(Brand.red, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                Text(eyebrow)
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(Brand.redSoft)
                Text(title)
                    .font(.system(.title, design: .serif, weight: .semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassSurface(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }
}

struct StudyAssessmentSectionHeader: View {
    let title: String
    var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.title3, design: .serif, weight: .semibold))
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct StudyMetricTile: View {
    let value: String
    let label: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.redSoft)
            Text(value)
                .font(.title2.monospacedDigit().weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .padding(14)
        .glassSurface(cornerRadius: 15)
        .accessibilityElement(children: .combine)
    }
}

struct StudyActionCard: View {
    let eyebrow: String
    let title: String
    let message: String
    let metadata: String
    let systemImage: String
    var badge: String?
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Brand.redSoft)
                    .frame(width: 42, height: 42)
                    .background(Brand.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(eyebrow)
                            .font(.caption2.weight(.bold))
                            .tracking(0.65)
                            .foregroundStyle(Brand.redSoft)
                        Spacer(minLength: 4)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Brand.redSoft)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Brand.red.opacity(0.10), in: Capsule())
                        }
                    }
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(metadata)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .glassSurface(cornerRadius: 17, interactive: true)
        }
        .buttonStyle(PressableScaleButtonStyle(scale: 0.98))
        .disabled(isLoading || isDisabled)
        .accessibilityHint("Opens this study activity")
    }
}

struct StudyCatalogueNotice: View {
    let catalogue: StudyQuestionCatalogue

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "checkmark.seal")
                .foregroundStyle(Brand.redSoft)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Complete catalogue loaded")
                    .font(.subheadline.weight(.semibold))
                Text("All \(catalogue.counts.total) questions are preserved: \(catalogue.counts.singleChoice) single-choice and \(catalogue.counts.multipleChoice) multiple-choice. One flagged item remains visible in the catalogue but is excluded from scored draws.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Legacy doctrine bank · source citations still under editorial review")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Brand.redSoft)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Brand.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Brand.red.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StudyDomainProgressRow: View {
    let domain: StudyDomain
    let correct: Int
    let total: Int
    var diagnosticScale = false

    private var fraction: Double {
        total == 0 ? 0 : Double(correct) / Double(total)
    }

    private var trailingValue: String {
        if diagnosticScale {
            return String(format: "%.1f / 4", fraction * 4)
        }
        return "\(correct) / \(total)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(domain.diagnosticTitle)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(trailingValue)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: fraction)
                .tint(fraction >= StudyAssessmentEngine.masteryThreshold ? Brand.redSoft : Brand.red)
        }
        .accessibilityElement(children: .combine)
    }
}

extension StudyDomain {
    var diagnosticTitle: String {
        switch self {
        case .introduction: "Canon and chronology"
        case .formationOfCapitalism: "Political economy and capitalism"
        case .materialityAndDialectics, .epistemology, .historicalMaterialism: title
        }
    }

    var studySummary: String {
        switch self {
        case .introduction: "Founders, sources, scope, and the chronology of the canon."
        case .materialityAndDialectics: "Matter, motion, contradiction, development, and dialectical analysis."
        case .epistemology: "Practice, cognition, reflection, truth, error, and verification."
        case .historicalMaterialism: "Social being, productive forces, class, state, and historical agency."
        case .formationOfCapitalism: "Commodity, value, labour-power, surplus value, capital, and profit."
        }
    }
}

struct StudyAssessmentUnavailableView: View {
    @Environment(StudyAssessmentStore.self) private var store
    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: 14) {
            switch store.loadState {
            case .idle, .loading:
                ProgressView("Loading the question catalogue")
                    .padding(24)
                    .glassSurface()
            case .failed(let message):
                VStack(spacing: 12) {
                    EmptyPanel(
                        systemImage: "exclamationmark.triangle",
                        title: "Assessment Center unavailable",
                        message: message
                    )
                    if let subjectID = store.activeSubjectID {
                        Button {
                            guard !isRetrying else { return }
                            isRetrying = true
                            Task {
                                await store.activate(subjectID: subjectID)
                                isRetrying = false
                            }
                        } label: {
                            if isRetrying {
                                ProgressView()
                            } else {
                                Label("Retry local progress", systemImage: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRetrying)
                    }
                }
            case .ready:
                EmptyView()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Practice Center

struct StudyPracticeScreen: View {
    @Environment(StudyAssessmentStore.self) private var store
    @Environment(RouterPath.self) private var router
    @State private var launchingPlanID: String?
    @State private var presentedError: String?

    private let columns = [GridItem(.adaptive(minimum: 145), spacing: 10)]

    var body: some View {
        ZStack {
            ScreenBackground()
            if store.loadState == .ready, let catalogue = store.catalogue {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        StudyAssessmentHeader(
                            eyebrow: "ASSESSMENT CENTER",
                            title: "Practice with purpose",
                            message: "Use short retrieval, mixed practice, diagnostics, and scheduled review. Retakes are penalty-free and every draw is reshuffled.",
                            systemImage: "checkmark.circle.fill"
                        )

                        StudyCatalogueNotice(catalogue: catalogue)

                        LazyVGrid(columns: columns, spacing: 10) {
                            StudyMetricTile(
                                value: "\(store.progress.dueReviewCount)",
                                label: "due for review",
                                systemImage: "clock.arrow.circlepath"
                            )
                            StudyMetricTile(
                                value: "\(store.progress.answeredQuestions)",
                                label: "items practiced",
                                systemImage: "checkmark.circle"
                            )
                            StudyMetricTile(
                                value: "\(store.completedAttempts.count)",
                                label: "sessions completed",
                                systemImage: "checkmark.square.stack"
                            )
                        }

                        if !store.attempts.filter({ $0.state == .active }).isEmpty {
                            StudyAssessmentSectionHeader(
                                title: "Continue an attempt",
                                message: "Option order and elapsed exam time are preserved."
                            )
                            ForEach(store.attempts.filter { $0.state == .active }.suffix(3).reversed()) { attempt in
                                StudyActionCard(
                                    eyebrow: "IN PROGRESS",
                                    title: attempt.plan.title,
                                    message: "\(attempt.answeredCount) of \(attempt.items.count) answered",
                                    metadata: attempt.plan.durationSeconds == nil ? "Untimed" : "Timer uses original start time",
                                    systemImage: "arrow.right.circle",
                                    badge: "RESUME",
                                    isDisabled: launchingPlanID != nil
                                ) {
                                    router.navigate(to: .studyQuiz(attemptID: attempt.id))
                                }
                            }
                        }

                        if store.progress.dueReviewCount > 0 {
                            StudyActionCard(
                                eyebrow: "DUE REVIEW",
                                title: "Return to weak material",
                                message: "Review questions scheduled from errors before beginning another broad set.",
                                metadata: "\(store.progress.dueReviewCount) due now · 1d → 3d → 7d → 21d",
                                systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                                badge: "DUE",
                                isDisabled: launchingPlanID != nil
                            ) {
                                router.navigate(to: .studyReview)
                            }
                        }

                        StudyAssessmentSectionHeader(
                            title: "Core practice",
                            message: "Immediate feedback · scored for practice only · no timer"
                        )
                        StudyActionCard(
                            eyebrow: "RETRIEVAL",
                            title: "Basic Principles Drill",
                            message: "A quick mixed draw from the complete legacy doctrine bank.",
                            metadata: "10 questions · about 10 minutes",
                            systemImage: "bolt.fill",
                            isLoading: launchingPlanID == "legacy-drill-10",
                            isDisabled: launchingPlanID != nil
                        ) {
                            start(.legacyDrill(itemCount: 10))
                        }
                        StudyActionCard(
                            eyebrow: "INTERLEAVED",
                            title: "Mixed-domain practice",
                            message: "Discriminate between nearby concepts across all five domains.",
                            metadata: "20 questions · balanced by domain",
                            systemImage: "shuffle",
                            isLoading: launchingPlanID == "interleaved-20",
                            isDisabled: launchingPlanID != nil
                        ) {
                            start(.interleaved(itemCount: 20))
                        }

                        StudyAssessmentSectionHeader(
                            title: "Target a domain",
                            message: "Ten-question sets make it easier to isolate a weak area."
                        )
                        ForEach(StudyDomain.allCases) { domain in
                            let plan = StudySessionPlan.domain(domain, itemCount: 10)
                            StudyActionCard(
                                eyebrow: "DOMAIN PRACTICE",
                                title: domain.diagnosticTitle,
                                message: domain.studySummary,
                                metadata: "10 questions · immediate feedback",
                                systemImage: domain.systemImage,
                                isLoading: launchingPlanID == plan.id,
                                isDisabled: launchingPlanID != nil
                            ) {
                                start(plan)
                            }
                        }

                        StudyAssessmentSectionHeader(title: "Placement and reference")
                        StudyActionCard(
                            eyebrow: "NO FAILURE STATE",
                            title: "Take the foundations diagnostic",
                            message: "Build a five-domain profile and identify a sensible starting point.",
                            metadata: "25-question standard or 50-question extended",
                            systemImage: "scope",
                            isDisabled: launchingPlanID != nil
                        ) {
                            router.navigate(to: .studyDiagnostic)
                        }
                        StudyActionCard(
                            eyebrow: "ALL 529 ITEMS",
                            title: "Browse the question catalogue",
                            message: "Search and filter every imported question, including corrected and flagged records.",
                            metadata: "Answers remain hidden in browse mode",
                            systemImage: "list.bullet.rectangle",
                            isDisabled: launchingPlanID != nil
                        ) {
                            router.navigate(to: .studyQuestionCatalogue)
                        }
                        .accessibilityIdentifier("study.practice.question-catalogue")

                        Color.clear.frame(height: 32)
                    }
                    .padding(16)
                }
            } else {
                StudyAssessmentUnavailableView()
            }
        }
        .navigationTitle("Practice")
        .alert("Couldn’t start this session", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(presentedError ?? "Please try again.")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { presentedError != nil },
            set: { if !$0 { presentedError = nil } }
        )
    }

    private func start(_ plan: StudySessionPlan) {
        guard launchingPlanID == nil else { return }
        launchingPlanID = plan.id
        Task {
            defer { launchingPlanID = nil }
            do {
                let attemptID = try await store.startAttempt(plan: plan)
                router.navigate(to: .studyQuiz(attemptID: attemptID))
            } catch {
                presentedError = error.localizedDescription
            }
        }
    }
}

private extension StudyDomain {
    var systemImage: String {
        switch self {
        case .introduction: "person.3"
        case .materialityAndDialectics: "arrow.triangle.2.circlepath"
        case .epistemology: "eye"
        case .historicalMaterialism: "building.columns"
        case .formationOfCapitalism: "chart.line.uptrend.xyaxis"
        }
    }
}

// MARK: - Diagnostic

struct StudyDiagnosticScreen: View {
    @Environment(StudyAssessmentStore.self) private var store
    @Environment(RouterPath.self) private var router
    @State private var launchingPlanID: String?
    @State private var presentedError: String?

    var body: some View {
        ZStack {
            ScreenBackground()
            if store.loadState == .ready {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        StudyAssessmentHeader(
                            eyebrow: "PLACEMENT, NOT JUDGMENT",
                            title: "Foundations diagnostic",
                            message: "This is not an exam and it has no failure state. Feedback is delayed until submission so the result can reveal your present strengths without coaching the next answer.",
                            systemImage: "scope"
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            Label("Uses a balanced draw across all five domains", systemImage: "circle.lefthalf.filled")
                            Label("Includes at least five questions from each domain in the standard form", systemImage: "rectangle.split.3x1")
                            Label("Reports a domain profile on a 0–4 scale, not one reductive score", systemImage: "chart.bar.xaxis")
                            Label("Does not change item-mastery records", systemImage: "lock.shield")
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .glassSurface(cornerRadius: 16)

                        StudyAssessmentSectionHeader(
                            title: "What it covers",
                            message: "The current native diagnostic uses a balanced fixed form. Response-adaptive branching will follow after the bank’s citations and difficulty metadata complete editorial review."
                        )
                        ForEach(StudyDomain.allCases) { domain in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: domain.systemImage)
                                    .foregroundStyle(Brand.redSoft)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(domain.diagnosticTitle)
                                        .font(.subheadline.weight(.semibold))
                                    Text(domain.studySummary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(13)
                            .background(Brand.subtleFill.opacity(0.72), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }

                        StudyAssessmentSectionHeader(title: "Choose a form")
                        let standardPlan = StudySessionPlan.diagnostic(itemCount: 25)
                        StudyActionCard(
                            eyebrow: "RECOMMENDED",
                            title: "Standard diagnostic",
                            message: "A concise baseline with five questions drawn from each domain.",
                            metadata: "25 questions · untimed · delayed feedback",
                            systemImage: "25.circle",
                            badge: "STANDARD",
                            isLoading: launchingPlanID == standardPlan.id,
                            isDisabled: launchingPlanID != nil
                        ) {
                            start(standardPlan)
                        }

                        let extendedPlan = StudySessionPlan.diagnostic(itemCount: 50)
                        StudyActionCard(
                            eyebrow: "DEEPER PROFILE",
                            title: "Extended diagnostic",
                            message: "A larger balanced sample when you want more evidence in each domain.",
                            metadata: "50 questions · untimed · delayed feedback",
                            systemImage: "50.circle",
                            isLoading: launchingPlanID == extendedPlan.id,
                            isDisabled: launchingPlanID != nil
                        ) {
                            start(extendedPlan)
                        }

                        Color.clear.frame(height: 30)
                    }
                    .padding(16)
                }
            } else {
                StudyAssessmentUnavailableView()
            }
        }
        .navigationTitle("Diagnostic")
        .alert("Couldn’t start the diagnostic", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(presentedError ?? "Please try again.")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { presentedError != nil }, set: { if !$0 { presentedError = nil } })
    }

    private func start(_ plan: StudySessionPlan) {
        guard launchingPlanID == nil else { return }
        launchingPlanID = plan.id
        Task {
            defer { launchingPlanID = nil }
            do {
                let attemptID = try await store.startAttempt(plan: plan)
                router.navigate(to: .studyQuiz(attemptID: attemptID))
            } catch {
                presentedError = error.localizedDescription
            }
        }
    }
}

// MARK: - Complete question catalogue

struct StudyQuestionCatalogueScreen: View {
    @Environment(StudyAssessmentStore.self) private var store
    @State private var searchText = ""
    @State private var selectedBank: StudyQuestionBank?
    @State private var selectedDomain: StudyDomain?
    @State private var selectedType: StudyQuestionType?
    @State private var selectedQAStatus: StudyQuestionQAStatus?

    private var filteredQuestions: [StudyQuestion] {
        store.questions(
            bank: selectedBank,
            domain: selectedDomain,
            type: selectedType,
            qaStatus: selectedQAStatus,
            search: searchText
        )
    }

    private var hasFilters: Bool {
        selectedBank != nil || selectedDomain != nil || selectedType != nil || selectedQAStatus != nil
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            if store.loadState == .ready, let catalogue = store.catalogue {
                List {
                    Section {
                        StudyCatalogueNotice(catalogue: catalogue)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)

                        filterBar
                            .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 6, trailing: 0))
                            .listRowBackground(Color.clear)
                    }

                    Section(filteredQuestions.count == 1 ? "1 question" : "\(filteredQuestions.count) questions") {
                        ForEach(filteredQuestions) { question in
                            StudyQuestionCatalogueRow(question: question)
                                .listRowBackground(Brand.surface.opacity(0.72))
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .searchable(text: $searchText, prompt: "Question, topic, or ID")
                .overlay {
                    if filteredQuestions.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            } else {
                StudyAssessmentUnavailableView()
            }
        }
        .navigationTitle("Question Catalogue")
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Bank", selection: $selectedBank) {
                        Text("All banks").tag(StudyQuestionBank?.none)
                        ForEach(StudyQuestionBank.allCases) { bank in
                            Text(bank.title).tag(Optional(bank))
                        }
                    }
                } label: {
                    StudyFilterLabel(title: selectedBank?.title ?? "Bank", isActive: selectedBank != nil)
                }

                Menu {
                    Picker("Domain", selection: $selectedDomain) {
                        Text("All domains").tag(StudyDomain?.none)
                        ForEach(StudyDomain.allCases) { domain in
                            Text(domain.diagnosticTitle).tag(Optional(domain))
                        }
                    }
                } label: {
                    StudyFilterLabel(title: selectedDomain?.diagnosticTitle ?? "Domain", isActive: selectedDomain != nil)
                }

                Menu {
                    Picker("Type", selection: $selectedType) {
                        Text("All types").tag(StudyQuestionType?.none)
                        ForEach(StudyQuestionType.allCases) { type in
                            Text(type.title).tag(Optional(type))
                        }
                    }
                } label: {
                    StudyFilterLabel(title: selectedType?.title ?? "Type", isActive: selectedType != nil)
                }

                Menu {
                    Picker("Editorial status", selection: $selectedQAStatus) {
                        Text("All statuses").tag(StudyQuestionQAStatus?.none)
                        ForEach(StudyQuestionQAStatus.allCases) { status in
                            Text(status.title).tag(Optional(status))
                        }
                    }
                } label: {
                    StudyFilterLabel(title: selectedQAStatus?.shortTitle ?? "Status", isActive: selectedQAStatus != nil)
                }

                if hasFilters {
                    Button("Clear") {
                        selectedBank = nil
                        selectedDomain = nil
                        selectedType = nil
                        selectedQAStatus = nil
                    }
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 44)
                }
            }
        }
        .accessibilityLabel("Question filters")
    }
}

private struct StudyFilterLabel: View {
    let title: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(isActive ? Brand.onAccent : .primary)
        .padding(.horizontal, 11)
        .frame(minHeight: 44)
        .background(isActive ? Brand.red : Brand.controlFill, in: Capsule())
    }
}

private struct StudyQuestionCatalogueRow: View {
    let question: StudyQuestion
    @State private var isExpanded = false

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(question.id)
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(Brand.redSoft)
                    Spacer()
                    StudyQAStatusBadge(status: question.qaStatus)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                Text(question.stem)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 7) {
                    Text(question.domain?.diagnosticTitle ?? question.chapterTitle)
                    Text("•")
                    Text(question.type.title)
                    Text("•")
                    Text(question.difficulty.title)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if isExpanded {
                    Divider()
                    Text(question.topic)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(question.orderedOptions) { option in
                        HStack(alignment: .top, spacing: 8) {
                            Text(option.id)
                                .font(.caption.monospaced().weight(.bold))
                                .foregroundStyle(Brand.redSoft)
                                .frame(width: 20, alignment: .leading)
                            Text(option.text)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Text("Answer keys are deliberately hidden in browse mode.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("study.question.\(question.id)")
        .accessibilityHint(isExpanded ? "Collapses answer choices" : "Shows answer choices without the key")
    }
}

struct StudyQAStatusBadge: View {
    let status: StudyQuestionQAStatus

    var body: some View {
        Text(status.shortTitle.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(status == .flagged ? Color.orange : Brand.redSoft)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background((status == .flagged ? Color.orange : Brand.red).opacity(0.10), in: Capsule())
    }
}

extension StudyQuestionQAStatus {
    var shortTitle: String {
        switch self {
        case .importedNeedsCitation: "Citation review"
        case .draftNeedsAcademicReview: "Academic review"
        case .corrected: "Corrected"
        case .reviewed: "Reviewed"
        case .flagged: "Flagged"
        }
    }
}

// MARK: - Review queue

struct StudyReviewScreen: View {
    @Environment(StudyAssessmentStore.self) private var store
    @Environment(RouterPath.self) private var router
    @State private var launchingPlanID: String?
    @State private var presentedError: String?

    private var now: Date { Date() }
    private var dueCards: [StudyReviewCard] { store.dueReviewCards(at: now) }
    private var overdueCount: Int {
        let startOfToday = Calendar.current.startOfDay(for: now)
        return dueCards.filter { $0.dueAt < startOfToday }.count
    }
    private var newCount: Int {
        store.reviewCards.values.filter { $0.lastRating == nil }.count
    }
    private var sevenDayForecast: Int {
        let limit = now.addingTimeInterval(7 * 86_400)
        return store.reviewCards.values.filter {
            $0.state == .scheduled && $0.dueAt > now && $0.dueAt <= limit
        }.count
    }
    private var rescueQuestionIDs: [String] {
        var result: [String] = []
        var seen = Set<String>()
        func append(_ questionID: String) {
            if seen.insert(questionID).inserted {
                result.append(questionID)
            }
        }

        for card in store.reviewCards.values
            .filter({ $0.state == .scheduled })
            .sorted(by: { $0.dueAt < $1.dueAt }) {
            append(card.questionID)
        }
        var questionsWithLatestResponse = Set<String>()
        for attempt in store.completedAttempts.reversed() {
            for item in attempt.items where item.response != nil {
                if questionsWithLatestResponse.insert(item.question.id).inserted,
                   item.response?.isCorrect == false {
                    append(item.question.id)
                }
            }
        }
        for mastery in store.itemMastery.values
            .filter({ $0.state == .reopened || $0.confidentWrongCount > 0 })
            .sorted(by: { $0.updatedAt > $1.updatedAt }) {
            append(mastery.questionID)
        }
        return result
    }

    private let columns = [GridItem(.adaptive(minimum: 132), spacing: 10)]

    var body: some View {
        ZStack {
            ScreenBackground()
            if store.loadState == .ready {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 21) {
                        StudyAssessmentHeader(
                            eyebrow: "SPACED RETRIEVAL",
                            title: "Review queue",
                            message: "Errors and manually saved questions return on a simple 1, 3, 7, and 21-day schedule. Rate the quality of recall after attempting each answer.",
                            systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
                        )

                        LazyVGrid(columns: columns, spacing: 10) {
                            StudyMetricTile(value: "\(dueCards.count)", label: "due now", systemImage: "clock")
                            StudyMetricTile(value: "\(overdueCount)", label: "overdue", systemImage: "exclamationmark.circle")
                            StudyMetricTile(value: "\(newCount)", label: "new cards", systemImage: "sparkles.rectangle.stack")
                            StudyMetricTile(value: "\(store.progress.confidentWrongCount)", label: "confident but wrong", systemImage: "exclamationmark.bubble")
                            StudyMetricTile(value: "\(sevenDayForecast)", label: "next seven days", systemImage: "calendar")
                        }

                        StudyAssessmentSectionHeader(
                            title: "Session setup",
                            message: "The answer is shown only after you commit to a response."
                        )

                        if dueCards.isEmpty {
                            EmptyPanel(
                                systemImage: "checkmark.circle",
                                title: "Nothing is due right now",
                                message: newCount > 0
                                    ? "Your newest cards are scheduled for a later day."
                                    : "Incorrect answers and questions you save will appear here."
                            )
                        } else {
                            let normalPlan = store.reviewPlan(maxCount: 20, at: now)
                            StudyActionCard(
                                eyebrow: "NORMAL SESSION",
                                title: "Review what is due",
                                message: "Work through the oldest due cards first.",
                                metadata: "Up to 20 questions · immediate feedback",
                                systemImage: "rectangle.stack",
                                badge: "\(dueCards.count) DUE",
                                isLoading: launchingPlanID == normalPlan.id,
                                isDisabled: launchingPlanID != nil
                            ) {
                                start(normalPlan)
                            }

                            let quickPlan = store.reviewPlan(maxCount: 10, at: now)
                            StudyActionCard(
                                eyebrow: "10-MINUTE SESSION",
                                title: "Quick review",
                                message: "A smaller queue for a short focused return.",
                                metadata: "Up to 10 questions",
                                systemImage: "timer",
                                isLoading: launchingPlanID == "review-quick",
                                isDisabled: launchingPlanID != nil
                            ) {
                                start(quickPlan, launchID: "review-quick")
                            }
                        }

                        if !rescueQuestionIDs.isEmpty {
                            let rescuePlan = StudySessionPlan(
                                id: "review-rescue",
                                kind: .review,
                                title: "Weak-concept rescue",
                                requestedItemCount: min(20, rescueQuestionIDs.count),
                                domain: nil,
                                requestedQuestionIDs: Array(rescueQuestionIDs.prefix(20)),
                                feedbackPolicy: .immediate,
                                durationSeconds: nil,
                                affectsItemMastery: false
                            )
                            StudyActionCard(
                                eyebrow: "WEAK-CONCEPT RESCUE",
                                title: "Return to weak items",
                                message: "Prioritise questions that were answered incorrectly or with misplaced confidence.",
                                metadata: "\(min(20, rescueQuestionIDs.count)) questions available",
                                systemImage: "lifepreserver",
                                isLoading: launchingPlanID == rescuePlan.id,
                                isDisabled: launchingPlanID != nil
                            ) {
                                start(rescuePlan)
                            }
                        }

                        if !dueCards.isEmpty {
                            StudyAssessmentSectionHeader(title: "Due cards")
                            ForEach(dueCards.prefix(10)) { card in
                                HStack(alignment: .top, spacing: 11) {
                                    Image(systemName: "clock.badge.exclamationmark")
                                        .foregroundStyle(Brand.redSoft)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(store.question(id: card.questionID)?.stem ?? card.questionID)
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(3)
                                        HStack {
                                            Text(store.question(id: card.questionID)?.topic ?? "Question review")
                                            Text("·")
                                            Text(card.dueAt, style: .relative)
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .glassSurface(cornerRadius: 14)
                            }
                        }

                        Color.clear.frame(height: 30)
                    }
                    .padding(16)
                }
            } else {
                StudyAssessmentUnavailableView()
            }
        }
        .navigationTitle("Review")
        .alert("Couldn’t start review", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(presentedError ?? "Please try again.")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { presentedError != nil }, set: { if !$0 { presentedError = nil } })
    }

    private func start(_ plan: StudySessionPlan, launchID: String? = nil) {
        guard launchingPlanID == nil else { return }
        launchingPlanID = launchID ?? plan.id
        Task {
            defer { launchingPlanID = nil }
            do {
                let attemptID = try await store.startAttempt(plan: plan)
                router.navigate(to: .studyQuiz(attemptID: attemptID))
            } catch {
                presentedError = error.localizedDescription
            }
        }
    }
}

// MARK: - Practice exams

enum StudyPracticeExamDefinition: String, CaseIterable, Identifiable {
    case foundations
    case politicalEconomy
    case extendedPrinciples

    var id: String { rawValue }

    var title: String {
        switch self {
        case .foundations: "Foundations Objective Practice"
        case .politicalEconomy: "Political Economy Objective Practice"
        case .extendedPrinciples: "Extended Basic Principles Form"
        }
    }

    var purpose: String {
        switch self {
        case .foundations:
            "A balanced rehearsal across the five foundations domains."
        case .politicalEconomy:
            "A focused rehearsal covering commodity, value, labour-power, surplus value, capital, and profit."
        case .extendedPrinciples:
            "A longer mixed form for sustained retrieval and pacing practice."
        }
    }

    var itemCount: Int {
        switch self {
        case .foundations: 40
        case .politicalEconomy: 40
        case .extendedPrinciples: 60
        }
    }

    var durationSeconds: Int {
        switch self {
        case .foundations, .politicalEconomy: 60 * 60
        case .extendedPrinciples: 90 * 60
        }
    }

    var durationLabel: String {
        "\(durationSeconds / 60) minutes"
    }

    var domain: StudyDomain? {
        switch self {
        case .politicalEconomy: .formationOfCapitalism
        case .foundations, .extendedPrinciples: nil
        }
    }

    var plan: StudySessionPlan {
        StudySessionPlan(
            id: "practice-exam-\(rawValue)",
            kind: .practiceExam,
            title: title,
            requestedItemCount: itemCount,
            domain: domain,
            requestedQuestionIDs: [],
            feedbackPolicy: .afterSubmission,
            durationSeconds: durationSeconds,
            affectsItemMastery: false
        )
    }

    var blueprint: [String] {
        [
            "One objective section worth \(itemCount) raw points",
            "Single-choice and exact-set multiple-choice items",
            "Answer feedback released after final submission",
            domain == nil ? "Balanced draw across five domains" : "Focused draw from \(domain?.diagnosticTitle ?? "one domain")",
            "No partial credit and no penalty for a retake"
        ]
    }
}

struct StudyExamsScreen: View {
    @Environment(RouterPath.self) private var router
    @Environment(StudyCourseLibrary.self) private var library

    private var courseFinals: [StudyCourseAssessmentBlueprint] {
        library.assessments
            .filter { $0.kind == .courseFinal }
            .sorted { ($0.courseID ?? "") < ($1.courseID ?? "") }
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 21) {
                    StudyAssessmentHeader(
                        eyebrow: "TIMED ASSESSMENT",
                        title: "Exam catalog",
                        message: "Rehearse pacing with objective practice forms now. Full text finals, written sections, document analysis, and authentic university simulations remain separate roadmap formats.",
                        systemImage: "timer"
                    )

                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: "shield.slash")
                            .foregroundStyle(Color.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Practice only")
                                .font(.subheadline.weight(.semibold))
                            Text("These forms are scored locally from bundled answer keys. They are not secure, server-scored, certified, or evidence of reading a particular primary text.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(Color.orange.opacity(0.20), lineWidth: 1)
                    }

                    if !courseFinals.isEmpty {
                        StudyAssessmentSectionHeader(
                            title: "Course final examinations",
                            message: "Authored cumulative papers remain separate from course lessons and from learning XP."
                        )
                        ForEach(courseFinals) { exam in
                            let course = exam.courseID.flatMap { library.course(id: $0) }
                            StudyActionCard(
                                eyebrow: course?.id ?? "COURSE FINAL",
                                title: exam.title,
                                message: course?.title ?? "Cumulative course examination",
                                metadata: "\((exam.durationSeconds ?? 0) / 60) min · \(exam.totalPoints) marks",
                                systemImage: "checkmark.seal",
                                badge: exam.sourceStatus == "draft_needs_academic_review" ? "REVIEW PENDING" : "COURSE FINAL"
                            ) {
                                router.navigate(to: .studyCourseExam(id: exam.id))
                            }
                        }
                    }

                    StudyAssessmentSectionHeader(
                        title: "Objective practice forms",
                        message: "Opening instructions does not start the timer."
                    )
                    ForEach(StudyPracticeExamDefinition.allCases) { definition in
                        StudyActionCard(
                            eyebrow: "PRACTICE ONLY",
                            title: definition.title,
                            message: definition.purpose,
                            metadata: "\(definition.durationLabel) · \(definition.itemCount) objective questions",
                            systemImage: "doc.text.magnifyingglass",
                            badge: "LOCAL"
                        ) {
                            router.navigate(to: .studyExamInstructions(examID: definition.id))
                        }
                    }

                    StudyAssessmentSectionHeader(
                        title: "Other roadmap exam formats",
                        message: "The interface reserves distinct categories without inventing unauthored prompts, model answers, or accreditation claims."
                    )
                    VStack(spacing: 0) {
                        StudyExamCapabilityRow(
                            title: "Platform Standard",
                            detail: "75–90 minutes · objective, short answer, and essay or document analysis",
                            status: "AUTHORING REQUIRED"
                        )
                        Divider()
                        StudyExamCapabilityRow(
                            title: "Authentic University Simulation",
                            detail: "Documented paper structure only; 180 minutes where the source model warrants it",
                            status: "SOURCE REQUIRED"
                        )
                        Divider()
                        StudyExamCapabilityRow(
                            title: "Document Analysis Lab",
                            detail: "Identification 10% · context 20% · reconstruction 40% · evaluation 30%",
                            status: "PASSAGES REQUIRED"
                        )
                    }
                    .padding(.horizontal, 15)
                    .glassSurface(cornerRadius: 16)

                    Color.clear.frame(height: 30)
                }
                .padding(16)
            }
        }
        .navigationTitle("Exams")
    }
}

private struct StudyExamCapabilityRow: View {
    let title: String
    let detail: String
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(status)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}

struct StudyExamInstructionsScreen: View {
    let examID: String

    @Environment(StudyAssessmentStore.self) private var store
    @Environment(RouterPath.self) private var router
    @State private var hasAcknowledgedPracticeStatus = false
    @State private var isStarting = false
    @State private var presentedError: String?

    private var definition: StudyPracticeExamDefinition? {
        StudyPracticeExamDefinition(rawValue: examID)
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            if let definition {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        StudyAssessmentHeader(
                            eyebrow: "PRACTICE EXAM INSTRUCTIONS",
                            title: definition.title,
                            message: definition.purpose,
                            systemImage: "doc.text"
                        )

                        HStack(spacing: 10) {
                            Label(definition.durationLabel, systemImage: "timer")
                            Spacer()
                            Label("\(definition.itemCount) points", systemImage: "number")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(15)
                        .glassSurface(cornerRadius: 15)

                        StudyAssessmentSectionHeader(title: "Local practice blueprint")
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(definition.blueprint, id: \.self) { line in
                                Label {
                                    Text(line)
                                        .fixedSize(horizontal: false, vertical: true)
                                } icon: {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundStyle(Brand.redSoft)
                                }
                            }
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .glassSurface(cornerRadius: 16)

                        StudyAssessmentSectionHeader(title: "Attempt rules")
                        VStack(alignment: .leading, spacing: 11) {
                            Label("Permitted materials: choose your own open- or closed-book rehearsal", systemImage: "books.vertical")
                            Label("Each submitted answer is saved locally to this study profile", systemImage: "externaldrive")
                            Label("Leaving the player preserves the attempt; the wall-clock timer continues", systemImage: "arrow.clockwise")
                            Label("MarxBot and contextual hints do not appear in the exam player", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                            Label("Opening this page has not started the timer", systemImage: "pause.circle")
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .glassSurface(cornerRadius: 16)

                        Toggle(isOn: $hasAcknowledgedPracticeStatus) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("I understand this is practice only")
                                    .font(.subheadline.weight(.semibold))
                                Text("It is locally scored and does not issue a certificate.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(Brand.red)
                        .padding(16)
                        .glassSurface(cornerRadius: 16)

                        Button {
                            start(definition.plan)
                        } label: {
                            HStack {
                                if isStarting {
                                    ProgressView()
                                        .tint(Brand.onAccent)
                                }
                                Text(isStarting ? "Starting…" : "Start exam and timer")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 12))
                        .tint(Brand.red)
                        .disabled(!hasAcknowledgedPracticeStatus || isStarting || store.loadState != .ready)
                        .accessibilityHint("Starts the persisted wall-clock timer")

                        Color.clear.frame(height: 30)
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView(
                    "Exam unavailable",
                    systemImage: "doc.questionmark",
                    description: Text("This practice blueprint could not be found.")
                )
            }
        }
        .navigationTitle("Instructions")
        .alert("Couldn’t start this exam", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(presentedError ?? "Please try again.")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { presentedError != nil }, set: { if !$0 { presentedError = nil } })
    }

    private func start(_ plan: StudySessionPlan) {
        guard !isStarting else { return }
        isStarting = true
        Task {
            defer { isStarting = false }
            do {
                let attemptID = try await store.startAttempt(plan: plan)
                router.navigate(to: .studyQuiz(attemptID: attemptID))
            } catch {
                presentedError = error.localizedDescription
            }
        }
    }
}

// MARK: - Progress

struct StudyProgressScreen: View {
    @Environment(StudyAssessmentStore.self) private var store
    @Environment(StudyCourseLibrary.self) private var library
    @Environment(RouterPath.self) private var router
    @Environment(AuthStore.self) private var auth
    @Query private var courseProgressRecords: [StudyCourseProgressRecord]
    @Query private var learningEvents: [StudyLearningEventRecord]
    @Query private var achievements: [StudyAchievementRecord]
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 10)]

    private var subjectID: String { auth.studySubjectID ?? "guest.local" }
    private var learning: StudyLearningProgressSnapshot {
        StudyLearningProgressSnapshot.make(events: learningEvents, subjectID: subjectID)
    }
    private var enrolledCourses: [StudyEnrolledCourseProgress] {
        courseProgressRecords
            .filter { $0.subjectID == subjectID }
            .sorted { $0.updatedAt > $1.updatedAt }
            .compactMap { record in
                guard let course = library.course(id: record.courseID) else { return nil }
                return StudyEnrolledCourseProgress(
                    course: course,
                    summary: StudyCourseProgressSummary(course: course, progress: record)
                )
            }
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            if store.loadState == .ready {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 21) {
                        StudyAssessmentHeader(
                            eyebrow: "LEARNING RECORD",
                            title: "Progress and practice record",
                            message: "Academic grades, course reading, practice evidence, and optional learning rewards are recorded separately so one measure never impersonates another.",
                            systemImage: "chart.bar.xaxis"
                        )

                        StudyAssessmentSectionHeader(
                            title: "Course progress",
                            message: "Resume an enrolled course at its next unfinished section. Reading progress remains separate from practice results and grades."
                        )
                        if enrolledCourses.isEmpty {
                            EmptyPanel(
                                systemImage: "rectangle.stack",
                                title: "No courses in progress",
                                message: "Open a course from Study Center to begin and track its required sections here."
                            )
                            .accessibilityIdentifier("study.course-progress.empty")
                        } else {
                            VStack(spacing: 10) {
                                ForEach(enrolledCourses) { item in
                                    StudyCourseProgressRow(item: item) {
                                        openCourse(item)
                                    }
                                }
                            }
                            .accessibilityIdentifier("study.course-progress.list")
                        }

                        StudyAssessmentSectionHeader(
                            title: "Learning activity — not an academic grade",
                            message: "XP is earned only from meaningful learning tasks. Streaks are optional and neither measure changes an assignment or examination result."
                        )
                        LazyVGrid(columns: columns, spacing: 10) {
                            StudyMetricTile(value: "\(learning.totalXP)", label: "learning XP", systemImage: "sparkles")
                            StudyMetricTile(value: "\(learning.currentStreak)", label: "current study streak", systemImage: "calendar.badge.checkmark")
                            StudyMetricTile(value: "\(learning.longestStreak)", label: "longest study streak", systemImage: "chart.line.uptrend.xyaxis")
                            StudyMetricTile(value: "\(achievements.filter { $0.subjectID == subjectID }.count)", label: "achievements earned", systemImage: "medal")
                        }

                        let myAchievements = achievements.filter { $0.subjectID == subjectID }.sorted { $0.awardedAt > $1.awardedAt }
                        if !myAchievements.isEmpty {
                            StudyAssessmentSectionHeader(title: "Achievements")
                            VStack(spacing: 10) {
                                ForEach(myAchievements) { achievement in
                                    HStack(alignment: .top, spacing: 11) {
                                        Image(systemName: "medal.fill").foregroundStyle(Brand.redSoft).frame(width: 28)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(achievement.title).font(.subheadline.weight(.semibold))
                                            Text(achievement.detail).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(13)
                                }
                            }
                            .glassSurface(cornerRadius: 16)
                        }

                        LazyVGrid(columns: columns, spacing: 10) {
                            StudyMetricTile(value: "\(store.progress.completedAttempts)", label: "completed attempts", systemImage: "checkmark.square.stack")
                            StudyMetricTile(value: "\(store.progress.answeredQuestions)", label: "distinct items answered", systemImage: "questionmark.square")
                            StudyMetricTile(
                                value: store.itemMastery.isEmpty ? "—" : "\(store.progress.masteredItems)",
                                label: "reviewed-item mastery",
                                systemImage: "seal"
                            )
                            StudyMetricTile(value: "\(store.progress.dueReviewCount)", label: "reviews due", systemImage: "clock.arrow.circlepath")
                            StudyMetricTile(value: "\(store.progress.confidentWrongCount)", label: "latest confident errors", systemImage: "exclamationmark.bubble")
                        }

                        StudyAssessmentSectionHeader(
                            title: "Current domain evidence",
                            message: "Based on the latest completed response for each distinct question."
                        )
                        if store.progress.domainBreakdown.isEmpty {
                            EmptyPanel(
                                systemImage: "chart.bar",
                                title: "No completed practice yet",
                                message: "Finish a drill or diagnostic to begin your domain profile."
                            )
                        } else {
                            VStack(spacing: 15) {
                                ForEach(store.progress.domainBreakdown) { breakdown in
                                    StudyDomainProgressRow(
                                        domain: breakdown.domain,
                                        correct: breakdown.correct,
                                        total: breakdown.total
                                    )
                                }
                            }
                            .padding(16)
                            .glassSurface(cornerRadius: 16)
                        }

                        StudyAssessmentSectionHeader(title: "Recent results")
                        if store.completedAttempts.isEmpty {
                            Text("Completed attempts will appear here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .glassSurface(cornerRadius: 15)
                        } else {
                            ForEach(Array(store.completedAttempts.suffix(10).reversed())) { attempt in
                                let summary = StudyAssessmentEngine.summary(for: attempt)
                                let isDiagnostic = attempt.plan.kind == .diagnostic
                                let scoredTotal = summary.scoredTotal ?? summary.total
                                let guidedResponses = max(0, summary.total - scoredTotal)
                                let isWrittenExam = attempt.plan.context?.source == .exam
                                Button {
                                    router.navigate(to: .studyResults(attemptID: attempt.id))
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: isDiagnostic ? "chart.bar.xaxis" : (isWrittenExam ? "person.text.rectangle" : (summary.achievement == .needsReview ? "book.closed" : "checkmark.seal")))
                                            .foregroundStyle(isDiagnostic || isWrittenExam || summary.achievement != .needsReview ? Brand.redSoft : .secondary)
                                            .frame(width: 30)
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(alignment: .firstTextBaseline) {
                                                Text(attempt.plan.title)
                                                    .font(.subheadline.weight(.semibold))
                                                Spacer()
                                                Text(isWrittenExam ? "\(attempt.answeredCount) of \(summary.total) responses" : (isDiagnostic ? "\(summary.total) items" : "\(summary.correct)/\(scoredTotal)"))
                                                    .font(.caption.monospacedDigit().weight(.bold))
                                            }
                                            Text("\(isWrittenExam ? "Human assessment pending" : (isDiagnostic ? "Domain profile" : summary.achievement.practiceTitle))\(!isWrittenExam && guidedResponses > 0 ? " · \(guidedResponses) written" : "") · \((attempt.submittedAt ?? attempt.startedAt).formatted(date: .abbreviated, time: .shortened))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .glassSurface(cornerRadius: 14, interactive: true)
                                }
                                .buttonStyle(PressableScaleButtonStyle(scale: 0.985))
                                .accessibilityLabel(attempt.plan.title)
                                .accessibilityValue(isWrittenExam ? "\(attempt.answeredCount) of \(summary.total) written responses, awaiting human assessment" : (isDiagnostic ? "\(summary.total) diagnostic items" : "\(summary.correct) of \(scoredTotal) correct"))
                                .accessibilityHint("Opens the saved attempt and responses")
                            }
                        }

                        Color.clear.frame(height: 30)
                    }
                    .padding(16)
                }
            } else {
                StudyAssessmentUnavailableView()
            }
        }
        .navigationTitle("Progress")
    }

    private func openCourse(_ item: StudyEnrolledCourseProgress) {
        if let nextSection = item.summary.nextSection {
            router.navigate(to: .studyCourseSection(
                courseID: item.course.id,
                moduleID: nextSection.moduleID,
                lessonID: nextSection.lessonID,
                blockID: nextSection.blockID
            ))
        } else {
            router.navigate(to: .studyCourse(id: item.course.id))
        }
    }
}

private struct StudyEnrolledCourseProgress: Identifiable {
    let course: StudyCourse
    let summary: StudyCourseProgressSummary

    var id: String { course.id }
}

private struct StudyCourseProgressRow: View {
    let item: StudyEnrolledCourseProgress
    let action: () -> Void

    private var actionTitle: String {
        item.summary.nextSection == nil ? "Open course" : "Resume"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.summary.nextSection == nil ? "checkmark.seal.fill" : "book.closed.fill")
                        .font(.headline)
                        .foregroundStyle(Brand.redSoft)
                        .frame(width: 34, height: 34)
                        .background(Brand.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.course.title)
                            .font(.system(.headline, design: .serif, weight: .semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let nextSection = item.summary.nextSection {
                            Text("Module \(nextSection.moduleNumber) · \(nextSection.moduleTitle)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(nextSection.blockTitle)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("All course sections complete")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Brand.redSoft)
                        }
                    }
                    Spacer(minLength: 4)
                }

                ProgressView(value: item.summary.fraction)
                    .tint(Brand.red)
                    .accessibilityHidden(true)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(item.summary.completedRequiredSections) of \(item.summary.totalRequiredSections) required sections")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(item.summary.percentage)%")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Brand.redSoft)
                    Spacer(minLength: 8)
                    Label(actionTitle, systemImage: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Brand.redSoft)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .glassSurface(cornerRadius: 15, interactive: true)
        }
        .buttonStyle(PressableScaleButtonStyle(scale: 0.985))
        .accessibilityLabel("\(actionTitle) \(item.course.title)")
        .accessibilityValue("\(item.summary.completedRequiredSections) of \(item.summary.totalRequiredSections) required sections complete, \(item.summary.percentage) percent")
        .accessibilityHint(item.summary.nextSection.map { "Opens \($0.blockTitle) in module \($0.moduleNumber)" } ?? "Opens the completed course")
        .accessibilityIdentifier("study.course-progress.course.\(item.course.id)")
    }
}

// MARK: - Canonical glossary and question-topic index

struct StudyGlossaryScreen: View {
    @Environment(StudyAssessmentStore.self) private var store
    @Environment(StudyCourseLibrary.self) private var library
    @Environment(RouterPath.self) private var router
    @State private var searchText = ""

    private var terms: [StudyGlossaryTerm] {
        library.glossaryTerms.filter { term in
            searchText.isEmpty
                || term.term.localizedCaseInsensitiveContains(searchText)
                || (term.displayTitle?.localizedCaseInsensitiveContains(searchText) ?? false)
                || term.definitionMarkdown.localizedCaseInsensitiveContains(searchText)
                || term.sourceIDs.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var topics: [(name: String, questions: [StudyQuestion])] {
        let groups = Dictionary(grouping: store.allQuestions, by: \.topic)
        return groups
            .map { (name: $0.key, questions: $0.value) }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Course glossary")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                        Text("Canonical definitions supplied with PHI111 and PHI211 appear here. Question-bank topic labels remain available below as a separate practice index.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Label("Course definitions are included with their source course and remain pending the archive's stated academic review.", systemImage: "checkmark.seal")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.redSoft)
                            .padding(.top, 3)
                    }
                    .padding(16)
                    .glassSurface(cornerRadius: 17)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if !terms.isEmpty {
                    Section("Course terms · \(terms.count)") {
                        ForEach(terms) { term in
                            VStack(alignment: .leading, spacing: 7) {
                                inlineMarkdown(term.displayTitle ?? term.term)
                                    .font(.subheadline.weight(.semibold))
                                inlineMarkdown(term.definitionMarkdown)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(term.sourceIDs.joined(separator: " · "))
                                    .font(.caption2.weight(.bold))
                                    .tracking(0.5)
                                    .foregroundStyle(Brand.redSoft)
                            }
                            .padding(.vertical, 4)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                if store.loadState == .ready, !topics.isEmpty {
                    Section("Question-bank topics") {
                        ForEach(topics, id: \.name) { topic in
                            let masteredCount = topic.questions.lazy.filter {
                                store.itemMastery[$0.id]?.state == .mastered
                            }.count
                            let dueCount = topic.questions.lazy.filter { question in
                                store.reviewCards.values.contains {
                                    $0.questionID == question.id && $0.isDue(at: Date())
                                }
                            }.count
                            VStack(alignment: .leading, spacing: 7) {
                                Text(topic.name)
                                    .font(.subheadline.weight(.semibold))
                                HStack(spacing: 8) {
                                    Text("\(topic.questions.count) questions")
                                    if masteredCount > 0 {
                                        Text("·")
                                        Text("\(masteredCount) mastered")
                                    }
                                    if dueCount > 0 {
                                        Text("·")
                                        Text("\(dueCount) due")
                                            .foregroundStyle(Brand.redSoft)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                Section {
                    Button {
                        router.navigate(to: .studyPractice)
                    } label: {
                        Label("Open Practice Center", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .listRowBackground(Brand.surface.opacity(0.72))
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .searchable(text: $searchText, prompt: "Search terms and topics")
        }
        .navigationTitle("Glossary")
    }

    private func inlineMarkdown(_ value: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return Text((try? AttributedString(markdown: value, options: options)) ?? AttributedString(value))
    }
}
