import SwiftUI
import SwiftData

extension StudyAttemptItem {
    func displayLabel(forCanonicalOptionID optionID: String) -> String {
        guard let index = optionOrder.firstIndex(of: optionID), index < 26 else {
            return optionID
        }
        return String(Character(UnicodeScalar(65 + index)!))
    }

    func displayedAnswerSummary(forCanonicalOptionIDs optionIDs: Set<String>) -> String {
        let answers = optionOrder.compactMap { optionID -> String? in
            guard optionIDs.contains(optionID), let text = question.options[optionID] else { return nil }
            return "\(displayLabel(forCanonicalOptionID: optionID)). \(text)"
        }
        return answers.isEmpty ? "No answer" : answers.joined(separator: "; ")
    }

    func displayedMatchingSummary(_ pairs: [String: String]) -> String {
        let descriptions = Dictionary(uniqueKeysWithValues: (question.matchingDescriptions ?? []).map { ($0.id, $0.text) })
        return (question.matchingTerms ?? []).compactMap { term in
            guard let descriptionID = pairs[term.id], let description = descriptions[descriptionID] else { return nil }
            return "\(term.text) — \(description)"
        }.joined(separator: "; ")
    }
}

// MARK: - Quiz, diagnostic, review, and objective-exam player

struct StudyQuizScreen: View {
    let attemptID: UUID

    @Environment(StudyAssessmentStore.self) private var store
    @Environment(RouterPath.self) private var router
    @Environment(AuthStore.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var learningEvents: [StudyLearningEventRecord]
    @Query private var examSubmissions: [StudyExamSubmissionRecord]
    @State private var selectedOptionIDs = Set<String>()
    @State private var textResponse = ""
    @State private var matchingPairs: [String: String] = [:]
    @State private var confidence: StudyConfidence = .fairlySure
    @State private var feedback: StudyAnswerFeedback?
    @State private var responseStartedAt = Date()
    @State private var clock = Date()
    @State private var isWorking = false
    @State private var showSubmitConfirmation = false
    @State private var presentedError: String?
    @State private var addedToReview = false
    @State private var reviewRating: StudyReviewRating?
    @State private var didFinalizeForTimeout = false

    private var attempt: StudyAttempt? { store.attempt(id: attemptID) }
    private var currentItem: StudyAttemptItem? { store.currentItem(for: attemptID) }
    private var isDelayedFeedback: Bool { attempt?.plan.feedbackPolicy == .afterSubmission }
    private var unansweredCount: Int {
        attempt?.items.lazy.filter { $0.response == nil }.count ?? 0
    }
    private var hasUnsavedChanges: Bool {
        guard isDelayedFeedback else { return false }
        guard let response = currentItem?.response else {
            return hasValidResponse
        }
        return Set(response.selectedOptionIDs) != selectedOptionIDs
            || response.textResponse != textResponse.nilIfBlank
            || (response.matchingPairs ?? [:]) != matchingPairs
            || response.confidence != confidence
    }
    private var hasValidResponse: Bool {
        guard let question = currentItem?.question else { return false }
        switch question.type {
        case .singleChoice, .multipleChoice:
            return !selectedOptionIDs.isEmpty
        case .matching:
            return !matchingPairs.isEmpty
                && Set(matchingPairs.keys) == Set(question.matchingTerms?.map(\.id) ?? [])
        case .shortResponse, .reconstruction:
            return textResponse.nilIfBlank != nil
        }
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            if let attempt, let item = currentItem {
                if attempt.state == .completed {
                    completedAttemptView
                } else {
                    VStack(spacing: 0) {
                        playerHeader(attempt)
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 20) {
                                questionContext(item.question, attempt: attempt)
                                questionCard(item, attempt: attempt)

                                if isDelayedFeedback {
                                    questionNavigator(attempt)
                                }

                                responseControls(item, attempt: attempt)
                                Color.clear.frame(height: 20)
                            }
                            .padding(16)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Attempt unavailable",
                    systemImage: "questionmark.folder",
                    description: Text("This assessment attempt could not be loaded for the active study profile.")
                )
            }
        }
        .navigationTitle(attempt?.plan.kind == .practiceExam ? "Practice Exam" : "Question")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let attempt, attempt.state == .active, isDelayedFeedback {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Submit") {
                        showSubmitConfirmation = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(isWorking || hasUnsavedChanges)
                }
            }
        }
        .task(id: attempt?.currentIndex) {
            restoreCurrentResponse()
        }
        .task(id: attempt?.state) {
            await runTimerIfNeeded()
        }
        .task(id: examDraftAutosaveKey) {
            await autosaveExamDraft()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            Task { await saveExamDraftIfNeeded(allowExpiredDraft: false) }
        }
        .alert("Assessment error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(presentedError ?? "Please try again.")
        }
        .alert("Submit this attempt?", isPresented: $showSubmitConfirmation) {
            Button("Keep working", role: .cancel) {}
            Button(unansweredCount == 0 ? "Submit" : "Submit with \(unansweredCount) unanswered", role: .destructive) {
                finalizeAndOpenResults(allowIncomplete: true)
            }
        } message: {
            if unansweredCount == 0 {
                Text("Answers cannot be changed after final submission.")
            } else {
                Text("Unanswered questions receive no credit. You can return to the navigator before submitting.")
            }
        }
    }

    private func playerHeader(_ attempt: StudyAttempt) -> some View {
        VStack(spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(attempt.plan.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("Question \(attempt.currentIndex + 1) of \(attempt.items.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let remaining = attempt.remainingTime(at: clock) {
                    Label(Self.durationString(remaining), systemImage: "timer")
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(remaining <= 300 ? Color.orange : .primary)
                        .accessibilityLabel("Time remaining \(Self.durationString(remaining))")
                } else {
                    Text("Untimed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: Double(attempt.currentIndex + 1), total: Double(attempt.items.count))
                .tint(Brand.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func questionContext(_ question: StudyQuestion, attempt: StudyAttempt) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(question.examSection.map { "SECTION \($0)" } ?? question.domain?.diagnosticTitle ?? question.chapterTitle)
                .font(.caption.weight(.bold))
                .foregroundStyle(Brand.redSoft)
            Text("•")
                .foregroundStyle(.tertiary)
            Text(question.type.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let code = question.examCode {
                Text(code)
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(.secondary)
            } else {
                StudyQAStatusBadge(status: question.qaStatus)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func questionCard(_ item: StudyAttemptItem, attempt: StudyAttempt) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let code = item.question.examCode {
                HStack(alignment: .firstTextBaseline) {
                    Text(code)
                        .font(.system(.title3, design: .serif, weight: .bold))
                        .foregroundStyle(Brand.redSoft)
                    Spacer()
                    if let points = item.question.pointValue {
                        Text("\(points) marks")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                StudyMarkdownDocument(markdown: item.question.stem)
            } else {
                Text(item.question.stem)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if item.question.type == .multipleChoice {
                Label("Select every correct answer. Exact-set scoring applies.", systemImage: "checklist")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if item.question.type == .singleChoice {
                Text("Choose one answer.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if item.question.type == .matching {
                Label("Choose one description for every term.", systemImage: "arrow.left.arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if item.question.examCode != nil {
                Label("Write and save your examination response. It requires human marking and is not auto-scored.", systemImage: "square.and.pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Label("Write your response, then compare it with the supplied model guidance.", systemImage: "square.and.pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            switch item.question.type {
            case .singleChoice, .multipleChoice:
                VStack(spacing: 10) {
                    ForEach(item.displayedOptions) { option in
                        optionButton(option, item: item)
                    }
                }
            case .matching:
                matchingEditor(item)
            case .shortResponse, .reconstruction:
                TextEditor(text: $textResponse)
                    .font(.body)
                    .frame(minHeight: item.question.examCode != nil ? 360 : (item.question.type == .reconstruction ? 220 : 150))
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(Brand.subtleFill.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Brand.separator.opacity(0.45), lineWidth: 1)
                    }
                    .disabled((item.response != nil && !isDelayedFeedback) || isWorking)
                    .accessibilityLabel(item.question.examCode.map { "Written examination response for \($0)" } ?? "Written response")
            }
        }
        .padding(17)
        .glassSurface(cornerRadius: 18)
    }

    private func matchingEditor(_ item: StudyAttemptItem) -> some View {
        VStack(spacing: 12) {
            ForEach(item.question.matchingTerms ?? []) { term in
                VStack(alignment: .leading, spacing: 7) {
                    Text(term.text)
                        .font(.subheadline.weight(.semibold))
                    Picker(
                        "Match for \(term.text)",
                        selection: Binding(
                            get: { matchingPairs[term.id] ?? "" },
                            set: { value in
                                if value.isEmpty { matchingPairs[term.id] = nil }
                                else { matchingPairs[term.id] = value }
                            }
                        )
                    ) {
                        Text("Choose a description").tag("")
                        ForEach(item.question.matchingDescriptions ?? []) { description in
                            Text(description.text)
                                .tag(description.id)
                                .disabled(
                                    matchingPairs[term.id] != description.id
                                        && matchingPairs.values.contains(description.id)
                                )
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Brand.redSoft)
                    .disabled((item.response != nil && !isDelayedFeedback) || isWorking)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Brand.subtleFill.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func optionButton(_ option: StudyAnswerOption, item: StudyAttemptItem) -> some View {
        let isSelected = selectedOptionIDs.contains(option.id)
        let isLocked = (item.response != nil && !isDelayedFeedback) || isWorking
        let label = displayLabel(for: option.id, in: item)

        return Button {
            guard !isLocked else { return }
            if item.question.type == .singleChoice {
                selectedOptionIDs = [option.id]
            } else if isSelected {
                selectedOptionIDs.remove(option.id)
            } else {
                selectedOptionIDs.insert(option.id)
            }
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: selectionSymbol(isSelected: isSelected, type: item.question.type))
                    .font(.title3)
                    .foregroundStyle(isSelected ? Brand.redSoft : .secondary)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.subheadline.monospaced().weight(.bold))
                    .foregroundStyle(isSelected ? Brand.redSoft : .secondary)
                    .frame(width: 20, alignment: .leading)
                Text(option.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                isSelected ? Brand.red.opacity(0.11) : Brand.subtleFill.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isSelected ? Brand.red.opacity(0.45) : Brand.separator.opacity(0.4), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(PressableScaleButtonStyle(scale: 0.985))
        .disabled(isLocked)
        .accessibilityLabel("Option \(label): \(option.text)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private func responseControls(_ item: StudyAttemptItem, attempt: StudyAttempt) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 9) {
                Text("How certain are you?")
                    .font(.subheadline.weight(.semibold))
                Picker("Confidence", selection: $confidence) {
                    ForEach(StudyConfidence.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .disabled((item.response != nil && !isDelayedFeedback) || isWorking)
            }
            .padding(15)
            .glassSurface(cornerRadius: 15)

            if let feedback {
                StudyAnswerFeedbackPanel(
                    feedback: feedback,
                    item: item,
                    confidence: confidence,
                    wasAddedToReview: addedToReview,
                    reviewRating: reviewRating,
                    showReviewRating: attempt.plan.kind == .review,
                    addToReview: addCurrentQuestionToReview,
                    rateReview: rateCurrentReview,
                    continueAction: continueAfterFeedback,
                    isWorking: isWorking
                )
            } else if item.response != nil,
                      item.question.requiresWrittenResponse,
                      !isDelayedFeedback {
                StudyGuidedResponsePanel(
                    guidance: item.question.expectedResponse ?? item.question.answerNote,
                    continueAction: continueAfterFeedback,
                    isWorking: isWorking
                )
            } else if item.response == nil {
                Button {
                    submitCurrentResponse()
                } label: {
                    HStack {
                        if isWorking {
                            ProgressView().tint(Brand.onAccent)
                        }
                        Text(submitButtonTitle(attempt))
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .tint(Brand.red)
                .disabled(!hasValidResponse || isWorking)
            } else if isDelayedFeedback {
                submittedAnswerControls(attempt, item: item)
            }
        }
    }

    private func questionNavigator(_ attempt: StudyAttempt) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Question navigator")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(attempt.answeredCount) answered · \(unansweredCount) open")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 5), spacing: 7) {
                ForEach(attempt.items.indices, id: \.self) { index in
                    let isCurrent = index == attempt.currentIndex
                    let isAnswered = attempt.items[index].response != nil
                    Button("\(index + 1)") {
                        move(to: index)
                    }
                    .font(.caption.monospacedDigit().weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(isCurrent ? Brand.onAccent : (isAnswered ? Brand.redSoft : .primary))
                    .background(
                        isCurrent ? Brand.red : (isAnswered ? Brand.red.opacity(0.10) : Brand.controlFill),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .buttonStyle(PressableScaleButtonStyle(scale: 0.95))
                    .disabled(isWorking || hasUnsavedChanges)
                    .accessibilityLabel("Question \(index + 1), \(isCurrent ? "current, " : "")\(isAnswered ? "answered" : "unanswered")")
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                }
            }
        }
        .padding(15)
        .glassSurface(cornerRadius: 15)
    }

    private func submittedAnswerControls(_ attempt: StudyAttempt, item: StudyAttemptItem) -> some View {
        VStack(spacing: 12) {
            Label(
                hasUnsavedChanges
                    ? "This answer has unsaved changes."
                    : "Answer saved. You can revise it until final submission.",
                systemImage: hasUnsavedChanges ? "exclamationmark.circle" : "checkmark.circle"
            )
                .font(.subheadline)
                .foregroundStyle(hasUnsavedChanges ? Color.orange : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hasUnsavedChanges {
                Button("Update saved answer") {
                    submitCurrentResponse(advanceAfterSave: false)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.red)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .disabled(!hasValidResponse || isWorking)
            }

            HStack(spacing: 10) {
                Button("Previous") {
                    move(to: max(0, attempt.currentIndex - 1))
                }
                .buttonStyle(.bordered)
                .disabled(attempt.currentIndex == 0 || isWorking || hasUnsavedChanges)

                if attempt.currentIndex < attempt.items.count - 1 {
                    Button("Next question") {
                        move(to: attempt.currentIndex + 1)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.red)
                    .disabled(isWorking || hasUnsavedChanges)
                } else {
                    Button("Review and submit") {
                        showSubmitConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.red)
                    .disabled(isWorking || hasUnsavedChanges)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(15)
        .glassSurface(cornerRadius: 15)
    }

    private var completedAttemptView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal")
                .font(.largeTitle)
                .foregroundStyle(Brand.redSoft)
            Text("This attempt is complete")
                .font(.title3.weight(.semibold))
            Button("Open results") {
                router.navigate(to: .studyResults(attemptID: attemptID))
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.red)
        }
        .padding(24)
        .glassSurface(cornerRadius: 18)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { presentedError != nil }, set: { if !$0 { presentedError = nil } })
    }

    private func selectionSymbol(isSelected: Bool, type: StudyQuestionType) -> String {
        switch (type, isSelected) {
        case (.singleChoice, true): "largecircle.fill.circle"
        case (.singleChoice, false): "circle"
        case (.multipleChoice, true): "checkmark.square.fill"
        case (.multipleChoice, false): "square"
        case (.matching, _), (.shortResponse, _), (.reconstruction, _): "circle"
        }
    }

    private func displayLabel(for canonicalOptionID: String, in item: StudyAttemptItem) -> String {
        item.displayLabel(forCanonicalOptionID: canonicalOptionID)
    }

    private func submitButtonTitle(_ attempt: StudyAttempt) -> String {
        if attempt.plan.feedbackPolicy == .immediate { return "Submit answer" }
        return attempt.currentIndex == attempt.items.count - 1 ? "Save answer" : "Save and continue"
    }

    private func restoreCurrentResponse() {
        guard let item = currentItem else { return }
        selectedOptionIDs = Set(item.response?.selectedOptionIDs ?? [])
        textResponse = item.response?.textResponse ?? ""
        matchingPairs = item.response?.matchingPairs ?? [:]
        confidence = item.response?.confidence ?? .fairlySure
        feedback = attempt?.plan.feedbackPolicy == .immediate
            ? StudyAssessmentEngine.feedback(for: item)
            : nil
        responseStartedAt = Date()
        let card = store.reviewCards.values.first { $0.questionID == item.question.id }
        addedToReview = item.response?.isCorrect == false || card != nil
        reviewRating = item.response?.reviewRating
    }

    private func submitCurrentResponse(advanceAfterSave: Bool = true) {
        guard hasValidResponse else { return }
        isWorking = true
        let responseDuration = Date().timeIntervalSince(responseStartedAt)
        Task {
            defer { isWorking = false }
            do {
                let returnedFeedback = try await store.submitResponse(
                    attemptID: attemptID,
                    selectedOptionIDs: selectedOptionIDs,
                    textResponse: textResponse,
                    matchingPairs: matchingPairs,
                    confidence: confidence,
                    responseDuration: responseDuration
                )
                if let returnedFeedback {
                    feedback = returnedFeedback
                    if !returnedFeedback.isCorrect {
                        addedToReview = true
                    }
                } else if currentItem?.question.requiresWrittenResponse == true,
                          attempt?.plan.feedbackPolicy == .immediate {
                    responseStartedAt = Date()
                } else if !advanceAfterSave {
                    responseStartedAt = Date()
                } else if let attempt = store.attempt(id: attemptID),
                          attempt.currentIndex < attempt.items.count - 1 {
                    _ = try await store.advance(in: attemptID)
                } else {
                    showSubmitConfirmation = true
                }
            } catch {
                presentedError = error.localizedDescription
            }
        }
    }

    private func continueAfterFeedback() {
        if attempt?.plan.kind == .review,
           currentReviewCard != nil,
           reviewRating == nil {
            presentedError = "Rate your recall as Again, Hard, Good, or Easy before continuing."
            return
        }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                if try await store.advance(in: attemptID) {
                    return
                }
                _ = try await store.finalizeAttempt(id: attemptID)
                recordCompletedAttempt()
                router.navigate(to: .studyResults(attemptID: attemptID))
            } catch {
                presentedError = error.localizedDescription
            }
        }
    }

    private func move(to index: Int) {
        guard attempt?.currentIndex != index else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await store.move(to: index, in: attemptID)
            } catch {
                presentedError = error.localizedDescription
            }
        }
    }

    private func finalizeAndOpenResults(allowIncomplete: Bool) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                _ = try await store.finalizeAttempt(id: attemptID, allowIncomplete: allowIncomplete)
                recordCompletedAttempt()
                router.navigate(to: .studyResults(attemptID: attemptID))
            } catch {
                presentedError = error.localizedDescription
            }
        }
    }

    private func addCurrentQuestionToReview() {
        guard let questionID = currentItem?.question.id else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await store.addToReview(questionID: questionID)
                addedToReview = true
            } catch {
                presentedError = error.localizedDescription
            }
        }
    }

    private var currentReviewCard: StudyReviewCard? {
        guard let questionID = currentItem?.question.id else { return nil }
        return store.reviewCards.values.first { $0.questionID == questionID }
    }

    private func rateCurrentReview(_ rating: StudyReviewRating) {
        guard let card = currentReviewCard else {
            presentedError = "This question does not have a review card yet."
            return
        }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                guard let questionID = currentItem?.question.id else {
                    throw StudyAssessmentEngineError.questionIndexOutOfRange
                }
                try await store.rateReviewCard(
                    id: card.id,
                    rating: rating,
                    attemptID: attemptID,
                    questionID: questionID
                )
                reviewRating = rating
            } catch {
                presentedError = error.localizedDescription
            }
        }
    }

    private func runTimerIfNeeded() async {
        guard let initialAttempt = attempt,
              initialAttempt.plan.durationSeconds != nil,
              initialAttempt.state == .active else { return }
        while !Task.isCancelled {
            clock = Date()
            guard let activeAttempt = store.attempt(id: attemptID),
                  activeAttempt.state == .active else { return }
            let remaining = activeAttempt.remainingTime(at: clock) ?? 0
            if remaining > 0, remaining <= 1 {
                await saveExamDraftIfNeeded(allowExpiredDraft: false)
            }
            if remaining == 0,
               !didFinalizeForTimeout {
                if isWorking {
                    try? await Task.sleep(for: .milliseconds(100))
                    continue
                }
                didFinalizeForTimeout = true
                do {
                    await saveExamDraftIfNeeded(allowExpiredDraft: true)
                    _ = try await store.finalizeAttempt(id: attemptID, allowIncomplete: true)
                    recordCompletedAttempt()
                    router.navigate(to: .studyResults(attemptID: attemptID))
                } catch {
                    presentedError = error.localizedDescription
                }
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private static func durationString(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.down)))
        if seconds >= 3_600 {
            return String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func recordCompletedAttempt() {
        guard let attempt = store.attempt(id: attemptID), attempt.state == .completed,
              let subjectID = auth.studySubjectID else { return }
        let context = attempt.plan.context
        let eventKind: StudyLearningEventKind? = switch context?.source {
        case .course: .moduleQuizSubmitted
        case .daily: .dailyQuizSubmitted
        case .review: .reviewCompleted
        case .exam: .finalSubmitted
        case .standalone, .none: nil
        }
        if let eventKind {
            let contentID = context?.assessmentID ?? attempt.plan.id
            let eventID = StudyLearningProgress.eventID(
                subjectID: subjectID,
                kind: eventKind,
                contentID: contentID,
                version: attempt.catalogueVersion,
                day: eventKind == .dailyQuizSubmitted ? attempt.submittedAt : nil
            )
            if !learningEvents.contains(where: { $0.eventID == eventID }) {
                modelContext.insert(StudyLearningEventRecord(
                    eventID: eventID,
                    subjectID: subjectID,
                    kind: eventKind.rawValue,
                    contentID: contentID,
                    points: eventKind.points,
                    occurredAt: attempt.submittedAt ?? .now
                ))
            }
        }

        if context?.source == .exam,
           let courseID = context?.courseID,
           let assessmentID = context?.assessmentID,
           !examSubmissions.contains(where: { $0.attemptID == attempt.id.uuidString }) {
            modelContext.insert(StudyExamSubmissionRecord(
                attemptID: attempt.id,
                subjectID: subjectID,
                candidateDisplayName: auth.displayName,
                courseID: courseID,
                assessmentID: assessmentID,
                title: attempt.plan.title,
                questionIDs: attempt.items.map(\.question.id),
                questionCodes: attempt.items.map { $0.question.examCode ?? $0.question.source.printedNumber.description },
                prompts: attempt.items.map(\.question.stem),
                responses: attempt.items.map { $0.response?.textResponse ?? "" },
                pointValues: attempt.items.map { $0.question.pointValue ?? 0 },
                submittedAt: attempt.submittedAt ?? .now
            ))
        }
        try? modelContext.save()
    }

    private var examDraftAutosaveKey: StudyExamDraftAutosaveKey {
        StudyExamDraftAutosaveKey(
            questionID: currentItem?.question.id,
            text: textResponse
        )
    }

    private func autosaveExamDraft() async {
        guard isNativeWrittenExamResponse else { return }
        try? await Task.sleep(for: .milliseconds(750))
        guard !Task.isCancelled else { return }
        await saveExamDraftIfNeeded(allowExpiredDraft: false)
    }

    private var isNativeWrittenExamResponse: Bool {
        attempt?.plan.context?.source == .exam && currentItem?.question.examCode != nil
    }

    private func saveExamDraftIfNeeded(allowExpiredDraft: Bool) async {
        guard isNativeWrittenExamResponse,
              hasUnsavedChanges,
              hasValidResponse,
              !isWorking else { return }
        do {
            _ = try await store.submitResponse(
                attemptID: attemptID,
                selectedOptionIDs: selectedOptionIDs,
                textResponse: textResponse,
                matchingPairs: matchingPairs,
                confidence: confidence,
                responseDuration: Date().timeIntervalSince(responseStartedAt),
                allowExpiredDraft: allowExpiredDraft
            )
        } catch StudyAssessmentEngineError.attemptExpired {
            // The timeout path immediately retries once with explicit draft
            // preservation before it finalizes the otherwise immutable attempt.
        } catch StudyAssessmentEngineError.attemptIsNotActive {
            // Another finalization path completed while the draft was saving.
        } catch {
            presentedError = error.localizedDescription
        }
    }
}

private struct StudyExamDraftAutosaveKey: Hashable {
    let questionID: String?
    let text: String
}

private struct StudyGuidedResponsePanel: View {
    let guidance: String
    let continueAction: () -> Void
    let isWorking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Response recorded", systemImage: "checkmark.circle")
                .font(.headline)
                .foregroundStyle(Brand.redSoft)
            Text("This response is not auto-graded. Compare it with the model guidance before continuing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Divider()
            Text("Model guidance")
                .font(.caption.weight(.bold))
                .foregroundStyle(Brand.redSoft)
            Text(guidance)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Button("Continue") { continueAction() }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .tint(Brand.red)
                .disabled(isWorking)
        }
        .padding(16)
        .background(Brand.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Brand.red.opacity(0.2), lineWidth: 1)
        }
    }
}

private struct StudyAnswerFeedbackPanel: View {
    let feedback: StudyAnswerFeedback
    let item: StudyAttemptItem
    let confidence: StudyConfidence
    let wasAddedToReview: Bool
    let reviewRating: StudyReviewRating?
    let showReviewRating: Bool
    let addToReview: () -> Void
    let rateReview: (StudyReviewRating) -> Void
    let continueAction: () -> Void
    let isWorking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: feedback.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(feedback.isCorrect ? Brand.redSoft : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(feedback.isCorrect ? "Correct" : "Not yet")
                        .font(.headline)
                    Text("Keyed answer: \(keyedAnswerSummary)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(explanationHeading)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.redSoft)
                Text(explanationText)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = feedback.adjudicationNote, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Label(calibrationMessage, systemImage: "gauge.with.dots.needle.33percent")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !feedback.isCorrect {
                Label("A correction card is in your review queue.", systemImage: "calendar.badge.plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.redSoft)
            }

            if showReviewRating {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How well did you recall it?")
                        .font(.subheadline.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 7)], spacing: 7) {
                        ForEach(StudyReviewRating.allCases) { rating in
                            Button {
                                rateReview(rating)
                            } label: {
                                VStack(spacing: 2) {
                                    Text(rating.title)
                                        .font(.caption.weight(.semibold))
                                    Text(rating.intervalLabel)
                                        .font(.caption2)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .tint(reviewRating == rating ? Brand.red : .secondary)
                            .disabled(isWorking || reviewRating != nil)
                            .accessibilityAddTraits(reviewRating == rating ? .isSelected : [])
                        }
                    }
                    if let reviewRating {
                        Text("Scheduled as \(reviewRating.title.lowercased()) for \(reviewRating.intervalLabel).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 10) {
                if wasAddedToReview {
                    Label("In review queue", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        addToReview()
                    } label: {
                        Label("Add to review", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking)
                }

                Spacer()

                Button("Continue") {
                    continueAction()
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.red)
                .disabled(isWorking)
            }
        }
        .padding(16)
        .background(
            (feedback.isCorrect ? Brand.red : Color.orange).opacity(0.07),
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke((feedback.isCorrect ? Brand.red : Color.orange).opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var explanationHeading: String {
        if item.question.examCode != nil { return "Examination response" }
        return item.question.source.bank == .course ? "Course answer guidance" : "Imported key note — not a source citation"
    }

    private var explanationText: String {
        if item.question.examCode != nil {
            return "This response is saved for human assessment. The learner app does not contain or reveal the restricted examiner marking guide."
        }
        guard item.question.source.bank == .course else {
            return item.question.answerNoteWithoutCanonicalKey
        }
        let expected = item.question.expectedResponse?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let commentary = item.question.answerNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if expected.isEmpty { return commentary }
        if commentary.isEmpty || expected == commentary { return expected }
        return "\(expected)\n\nCommentary: \(commentary)"
    }

    private var calibrationMessage: String {
        switch (feedback.isCorrect, confidence) {
        case (false, .certain): "High-confidence error: prioritise the distinction in review."
        case (false, .fairlySure): "The answer felt plausible; compare the nearby concepts before retrying."
        case (false, .guess): "A guess gives useful baseline evidence without counting against you."
        case (true, .guess): "Correct guess: recall it again later before treating it as stable knowledge."
        case (true, .fairlySure): "Correct with moderate confidence: another separate recall can strengthen retention."
        case (true, .certain): "Correct with high confidence; spaced recall will test whether it remains stable."
        }
    }

    private var keyedAnswerSummary: String {
        if item.question.type == .matching {
            return item.displayedMatchingSummary(item.question.matchingAnswerPairs ?? [:])
        }
        return item.displayedAnswerSummary(forCanonicalOptionIDs: feedback.correctOptionIDs)
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension StudyReviewRating {
    var intervalLabel: String {
        switch self {
        case .again: "1 day"
        case .hard: "3 days"
        case .good: "7 days"
        case .easy: "21 days"
        }
    }
}

// MARK: - Results and recommendations

struct StudyResultsScreen: View {
    let attemptID: UUID

    @Environment(StudyAssessmentStore.self) private var store
    @Environment(RouterPath.self) private var router
    @State private var isStartingRetake = false
    @State private var presentedError: String?

    private var attempt: StudyAttempt? { store.attempt(id: attemptID) }
    private var summary: StudyAttemptSummary? { store.summary(for: attemptID) }
    private var isDiagnostic: Bool { attempt?.plan.kind == .diagnostic }
    private var isPracticeExam: Bool { attempt?.plan.kind == .practiceExam }
    private var isWrittenCourseExam: Bool { attempt?.plan.context?.source == .exam }
    private var isCourseLinked: Bool {
        attempt?.plan.context?.courseID != nil
    }

    private var weakestDomain: StudyDomainBreakdown? {
        summary?.domainBreakdown
            .filter { $0.total > 0 }
            .min { $0.fractionCorrect < $1.fractionCorrect }
    }

    private var incorrectItems: [StudyAttemptItem] {
        attempt?.items.filter { $0.response?.isCorrect == false } ?? []
    }
    private var unansweredItems: [StudyAttemptItem] {
        attempt?.items.filter { $0.response == nil } ?? []
    }
    private var guidedResponseCount: Int {
        attempt?.items.lazy.filter { $0.response != nil && $0.response?.isCorrect == nil }.count ?? 0
    }

    private var weakTopics: [(topic: String, count: Int)] {
        Dictionary(grouping: incorrectItems, by: { $0.question.topic })
            .map { (topic: $0.key, count: $0.value.count) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.topic < $1.topic
            }
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            if let attempt, let summary {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 21) {
                        StudyAssessmentHeader(
                            eyebrow: resultEyebrow(summary),
                            title: resultTitle(summary),
                            message: resultMessage(summary),
                            systemImage: resultSystemImage(summary)
                        )

                        if isPracticeExam {
                            Label(
                                isWrittenCourseExam
                                    ? "Locally saved written examination · requires human marking"
                                    : "Practice only · locally scored · no certificate",
                                systemImage: isWrittenCourseExam ? "person.crop.circle.badge.questionmark" : "shield.slash"
                            )
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        if !isDiagnostic {
                            scoreOverview(summary)
                        }

                        if !isCourseLinked {
                            StudyAssessmentSectionHeader(
                                title: isDiagnostic ? "Domain profile" : "Performance by domain",
                                message: isDiagnostic
                                    ? "Each bar is shown on a 0–4 placement scale; no single pass/fail score is used."
                                    : "Use the weakest domain to choose the next practice set."
                            )
                            VStack(spacing: 15) {
                                ForEach(summary.domainBreakdown) { breakdown in
                                    StudyDomainProgressRow(
                                        domain: breakdown.domain,
                                        correct: breakdown.correct,
                                        total: breakdown.total,
                                        diagnosticScale: isDiagnostic
                                    )
                                }
                            }
                            .padding(16)
                            .glassSurface(cornerRadius: 16)

                            recommendationCard(attempt: attempt, summary: summary)
                        }

                        if !summary.confidentWrongQuestionIDs.isEmpty {
                            StudyAssessmentSectionHeader(
                                title: "Confident but wrong",
                                message: "These errors are especially useful because they reveal a misconception rather than uncertainty."
                            )
                            ForEach(summary.confidentWrongQuestionIDs, id: \.self) { questionID in
                                if let question = store.question(id: questionID) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(question.stem)
                                            .font(.subheadline.weight(.semibold))
                                        Text(question.topic)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .glassSurface(cornerRadius: 14)
                                }
                            }
                        }

                        if !weakTopics.isEmpty {
                            StudyAssessmentSectionHeader(title: "Areas to revisit")
                            VStack(spacing: 0) {
                                ForEach(Array(weakTopics.prefix(6)), id: \.topic) { topic in
                                    HStack {
                                        Text(topic.topic)
                                            .font(.subheadline)
                                        Spacer()
                                        Text("\(topic.count) missed")
                                            .font(.caption.monospacedDigit().weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 11)
                                    if topic.topic != weakTopics.prefix(6).last?.topic {
                                        Divider()
                                    }
                                }
                            }
                            .padding(.horizontal, 15)
                            .glassSurface(cornerRadius: 15)
                        }

                        StudyAssessmentSectionHeader(
                            title: "Question history",
                            message: isWrittenCourseExam
                                ? "Every submitted response is retained locally. No mark is inferred without an authorised human examiner."
                                : isCourseLinked
                                ? "The supplied course guidance and model responses appear with each recorded answer."
                                : "The imported notes below explain the keyed answer only; they are not primary-text citations."
                        )
                        ForEach(Array(attempt.items.enumerated()), id: \.element.id) { index, item in
                            StudyResultQuestionRow(index: index, item: item)
                        }

                        VStack(spacing: 10) {
                            if let weakestDomain {
                                Button {
                                    startDomainPractice(weakestDomain.domain)
                                } label: {
                                    Label("Practice \(weakestDomain.domain.diagnosticTitle)", systemImage: "target")
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                }
                                .buttonStyle(.borderedProminent)
                                .buttonBorderShape(.roundedRectangle(radius: 11))
                                .tint(Brand.red)
                                .disabled(isStartingRetake)
                            }

                            Button {
                                startRetake(attempt.plan)
                            } label: {
                                Label(isStartingRetake ? "Preparing…" : retakeButtonTitle(for: attempt.plan), systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.roundedRectangle(radius: 11))
                            .disabled(isStartingRetake)

                            Button(isCourseLinked ? "Return to Course" : "Return to Practice Center") {
                                if isCourseLinked, let courseID = attempt.plan.context?.courseID {
                                    router.replacePath(with: [.studyCourse(id: courseID)])
                                } else {
                                    router.replacePath(with: [.studyPractice])
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }

                        Color.clear.frame(height: 30)
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView(
                    "Results unavailable",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("Finish the attempt before opening its results.")
                )
            }
        }
        .navigationTitle("Results")
        .navigationBarBackButtonHidden(false)
        .alert("Couldn’t start practice", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(presentedError ?? "Please try again.")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { presentedError != nil }, set: { if !$0 { presentedError = nil } })
    }

    private func scoreOverview(_ summary: StudyAttemptSummary) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if isWrittenCourseExam, summary.scoredTotal == 0 {
                    Text("\(guidedResponseCount)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("written examination responses submitted")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(Int((summary.fractionCorrect * 100).rounded()))%")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("\(summary.correct) of \(summary.scoredTotal ?? summary.total) auto-scored items correct")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if guidedResponseCount > 0 {
                    Text(
                        isWrittenCourseExam
                            ? "No automatic grade has been assigned"
                            : "\(guidedResponseCount) guided written response\(guidedResponseCount == 1 ? "" : "s") recorded separately"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(isWrittenCourseExam ? "Awaiting human assessment" : summary.achievement.practiceTitle)
                    .font(.headline)
                    .foregroundStyle(isWrittenCourseExam || summary.achievement == .needsReview ? .secondary : Brand.redSoft)
                Text(isWrittenCourseExam ? "Academic grade remains separate from learning XP" : (isCourseLinked ? "Course-linked check · learning XP remains separate" : "Practice target 80% · Honors band 85%"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(17)
        .glassSurface(cornerRadius: 17)
        .accessibilityElement(children: .combine)
    }

    private func recommendationCard(attempt: StudyAttempt, summary: StudyAttemptSummary) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(isDiagnostic ? "Recommended starting point" : "Next step", systemImage: "signpost.right")
                .font(.headline)
                .foregroundStyle(Brand.redSoft)
            if let weakestDomain {
                Text(recommendationText(for: weakestDomain, isDiagnostic: isDiagnostic))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Manual override is always available: choose any path or domain in the Study Center.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Complete another mixed set to build enough domain evidence for a targeted recommendation.")
                    .font(.subheadline)
            }
            if !incorrectItems.isEmpty {
                Label("\(incorrectItems.count) correction cards scheduled", systemImage: "calendar.badge.plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.redSoft)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Brand.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Brand.red.opacity(0.18), lineWidth: 1)
        }
    }

    private func resultEyebrow(_ summary: StudyAttemptSummary) -> String {
        if isDiagnostic { return "DOMAIN PROFILE READY" }
        if isWrittenCourseExam { return "WRITTEN EXAMINATION SUBMITTED" }
        if isCourseLinked { return "COURSE CHECK COMPLETE" }
        if isPracticeExam { return "OBJECTIVE PRACTICE COMPLETE" }
        return summary.achievement == .needsReview ? "KEEP BUILDING" : "SESSION COMPLETE"
    }

    private func resultTitle(_ summary: StudyAttemptSummary) -> String {
        if isDiagnostic { return "Your present baseline" }
        if isWrittenCourseExam { return "Your responses are saved" }
        if isCourseLinked { return "Your module result" }
        return summary.achievement.practiceTitle
    }

    private func resultMessage(_ summary: StudyAttemptSummary) -> String {
        if isDiagnostic {
            return "Use this profile as placement evidence, not a verdict. It does not affect item mastery and has no failure state."
        }
        if isWrittenCourseExam {
            return "The app has recorded the complete written attempt and timing. It does not expose the restricted marking guide or manufacture an automatic academic grade."
        }
        if isCourseLinked {
            return "This result records the supplied module quiz separately from course reading progress. Open any answer to review its course guidance."
        }
        return switch summary.achievement {
        case .needsReview where !incorrectItems.isEmpty:
            "Incorrect responses have seeded corrective review. Revisit the weakest distinctions before another draw."
        case .needsReview where !unansweredItems.isEmpty:
            "Some questions were left unanswered. Review the domain breakdown before beginning another attempt."
        case .needsReview:
            "Use the domain breakdown to choose a focused practice set before another draw."
        case .mastered:
            "You reached the 80% practice target. The legacy bank remains practice evidence, not published unit mastery."
        case .honors:
            "You reached the 85% honors score band. The legacy bank remains practice evidence, not published unit mastery."
        }
    }

    private func resultSystemImage(_ summary: StudyAttemptSummary) -> String {
        if isDiagnostic { return "chart.bar.xaxis" }
        if isWrittenCourseExam { return "doc.text.fill" }
        return summary.achievement == .needsReview ? "book.closed.fill" : "seal.fill"
    }

    private func recommendationText(for breakdown: StudyDomainBreakdown, isDiagnostic: Bool) -> String {
        let percentage = Int((breakdown.fractionCorrect * 100).rounded())
        if isDiagnostic {
            if breakdown.fractionCorrect < 0.5 {
                return "Begin with an introductory guide and ten-question practice in \(breakdown.domain.diagnosticTitle). This was the least resolved domain at \(String(format: "%.1f", breakdown.fractionCorrect * 4)) / 4."
            }
            return "Use \(breakdown.domain.diagnosticTitle) as your first refresher, then continue into an interleaved set."
        }
        return "Revisit \(breakdown.domain.diagnosticTitle), where this attempt scored \(percentage)%, then use a new draw to check transfer."
    }

    private func startDomainPractice(_ domain: StudyDomain) {
        startNewAttempt(.domain(domain, itemCount: 10))
    }

    private func startRetake(_ plan: StudySessionPlan) {
        if plan.context?.source == .exam,
           let assessmentID = plan.context?.assessmentID {
            router.replacePath(with: [.studyCourseExam(id: assessmentID)])
            return
        }
        if plan.kind == .practiceExam,
           let definition = StudyPracticeExamDefinition.allCases.first(where: { $0.plan.id == plan.id }) {
            router.replacePath(with: [.studyExams, .studyExamInstructions(examID: definition.id)])
            return
        }
        startNewAttempt(plan)
    }

    private func retakeButtonTitle(for plan: StudySessionPlan) -> String {
        switch plan.kind {
        case .practiceExam: "Review instructions for another attempt"
        case .review: "Repeat this review set"
        case .legacyDrill, .domainPractice, .interleavedPractice, .diagnostic: "Retake with a new draw"
        }
    }

    private func startNewAttempt(_ plan: StudySessionPlan) {
        guard !isStartingRetake else { return }
        isStartingRetake = true
        Task {
            defer { isStartingRetake = false }
            do {
                let newAttemptID = try await store.startAttempt(plan: plan)
                if let courseID = plan.context?.courseID {
                    var routes: [Route] = [.studyCourse(id: courseID)]
                    if let moduleID = plan.context?.moduleID,
                       let lessonID = plan.context?.lessonID {
                        routes.append(.studyLesson(courseID: courseID, moduleID: moduleID, lessonID: lessonID))
                    }
                    routes.append(.studyQuiz(attemptID: newAttemptID))
                    router.replacePath(with: routes)
                    return
                }
                let sourceRoute: Route = switch plan.kind {
                case .review: .studyReview
                case .diagnostic: .studyDiagnostic
                case .legacyDrill, .domainPractice, .interleavedPractice: .studyPractice
                case .practiceExam: .studyExams
                }
                router.replacePath(with: [sourceRoute, .studyQuiz(attemptID: newAttemptID)])
            } catch {
                presentedError = error.localizedDescription
            }
        }
    }
}

private struct StudyResultQuestionRow: View {
    let index: Int
    let item: StudyAttemptItem
    @State private var isExpanded = false

    private var resultTitle: String {
        guard let response = item.response else { return "Unanswered" }
        guard let isCorrect = response.isCorrect else { return "Response recorded" }
        return isCorrect ? "Correct" : "Incorrect"
    }

    private var resultSymbol: String {
        guard let response = item.response else { return "minus.circle.fill" }
        guard let isCorrect = response.isCorrect else { return "doc.text.fill" }
        return isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var resultColor: Color {
        guard let response = item.response else { return .secondary }
        guard let isCorrect = response.isCorrect else { return Brand.redSoft }
        return isCorrect ? Brand.redSoft : .orange
    }

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: resultSymbol)
                        .foregroundStyle(resultColor)
                        .accessibilityLabel(resultTitle)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(index + 1). \(item.question.stem)")
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        responseSummary
                    }
                    Spacer(minLength: 2)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }

                if isExpanded {
                    Divider()
                    Text(explanationHeading)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Brand.redSoft)
                    Text(explanationText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    HStack {
                        Text(item.question.topic)
                        Spacer()
                        Text(item.response?.confidence.title ?? "No confidence")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .glassSurface(cornerRadius: 14, interactive: true)
        }
        .buttonStyle(PressableScaleButtonStyle(scale: 0.985))
        .accessibilityValue(resultTitle)
        .accessibilityHint(
            item.question.examCode != nil
                ? (isExpanded ? "Hides examination response status" : "Shows examination response status")
                : (isExpanded ? "Hides keyed answer note" : "Shows keyed answer note")
        )
    }

    private var explanationHeading: String {
        if item.question.examCode != nil { return "Examination response" }
        return item.question.source.bank == .course ? "Course answer guidance" : "Imported key note — not a source citation"
    }

    private var explanationText: String {
        if item.question.examCode != nil {
            return "This response is saved for human assessment. The learner app does not contain or reveal the restricted examiner marking guide."
        }
        guard item.question.source.bank == .course else {
            return item.question.answerNoteWithoutCanonicalKey
        }
        let expected = item.question.expectedResponse?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let commentary = item.question.answerNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if expected.isEmpty { return commentary }
        if commentary.isEmpty || commentary == expected { return expected }
        return "\(expected)\n\nCommentary: \(commentary)"
    }

    @ViewBuilder
    private var responseSummary: some View {
        switch item.question.type {
        case .singleChoice, .multipleChoice:
            Text("Selected: \(item.displayedAnswerSummary(forCanonicalOptionIDs: Set(item.response?.selectedOptionIDs ?? [])))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Key: \(item.displayedAnswerSummary(forCanonicalOptionIDs: item.question.correctOptionIDs))")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .matching:
            Text("Selected: \(item.displayedMatchingSummary(item.response?.matchingPairs ?? [:]))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Key: \(item.displayedMatchingSummary(item.question.matchingAnswerPairs ?? [:]))")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .shortResponse, .reconstruction:
            Text(item.response?.textResponse ?? "No response")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : 4)
        }
    }
}
