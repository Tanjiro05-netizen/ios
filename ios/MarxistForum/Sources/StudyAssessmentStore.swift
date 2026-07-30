import Foundation
import Observation

// MARK: - Durable local persistence

protocol StudyAssessmentPersisting: Sendable {
    func loadState(for subjectID: String) async throws -> StudyAssessmentPersistentState?
    func saveState(_ state: StudyAssessmentPersistentState, for subjectID: String) async throws
    func deleteState(for subjectID: String) async throws
}

enum StudyAssessmentPersistenceError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case subjectMismatch

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "Study progress uses unsupported storage schema \(version)."
        case .subjectMismatch:
            "Stored study progress belongs to a different local account."
        }
    }
}

actor StudyAssessmentJSONPersistence: StudyAssessmentPersisting {
    private let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            self.directory = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "StudyAssessment", directoryHint: .isDirectory)
        }
    }

    func loadState(for subjectID: String) throws -> StudyAssessmentPersistentState? {
        let url = fileURL(for: subjectID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let state = try Self.decoder.decode(
            StudyAssessmentPersistentState.self,
            from: Data(contentsOf: url)
        )
        guard state.schemaVersion == StudyAssessmentPersistentState.currentSchemaVersion else {
            throw StudyAssessmentPersistenceError.unsupportedSchema(state.schemaVersion)
        }
        return state
    }

    func saveState(_ state: StudyAssessmentPersistentState, for subjectID: String) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(state)
        try data.write(to: fileURL(for: subjectID), options: .atomic)
    }

    func deleteState(for subjectID: String) throws {
        let url = fileURL(for: subjectID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func fileURL(for subjectID: String) -> URL {
        let hexadecimalID = subjectID.utf8.map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(hexadecimalID).json")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

actor InMemoryStudyAssessmentPersistence: StudyAssessmentPersisting {
    private var states: [String: StudyAssessmentPersistentState]

    init(initialStates: [String: StudyAssessmentPersistentState] = [:]) {
        states = initialStates
    }

    func loadState(for subjectID: String) -> StudyAssessmentPersistentState? {
        states[subjectID]
    }

    func saveState(_ state: StudyAssessmentPersistentState, for subjectID: String) {
        states[subjectID] = state
    }

    func deleteState(for subjectID: String) {
        states[subjectID] = nil
    }

    func snapshot(for subjectID: String) -> StudyAssessmentPersistentState? {
        states[subjectID]
    }
}

// MARK: - Root-owned feature store

enum StudyAssessmentLoadState: Equatable, Sendable {
    case idle
    case loading
    case ready
    case failed(String)
}

enum StudyAssessmentStoreError: LocalizedError, Equatable {
    case noActiveSubject
    case storeNotReady
    case attemptCreationInProgress
    case catalogueUnavailable

    var errorDescription: String? {
        switch self {
        case .noActiveSubject: "Study progress needs an active local account."
        case .storeNotReady: "Study progress could not be loaded safely. Retry before starting or changing an activity."
        case .attemptCreationInProgress: "Another study activity is already being prepared."
        case .catalogueUnavailable: "The study question catalogue is not loaded."
        }
    }
}

@MainActor
@Observable
final class StudyAssessmentStore {
    private(set) var loadState: StudyAssessmentLoadState = .idle
    private(set) var activeSubjectID: String?
    private(set) var catalogue: StudyQuestionCatalogue?
    private(set) var attempts: [StudyAttempt] = []
    private(set) var itemMastery: [String: StudyItemMastery] = [:]
    private(set) var reviewCards: [UUID: StudyReviewCard] = [:]
    private(set) var reviewLogs: [StudyReviewLog] = []
    private(set) var courseQuestions: [StudyQuestion] = []
    var errorMessage: String?

    @ObservationIgnored private let loader: any StudyQuestionCatalogueLoading
    @ObservationIgnored private let persistence: any StudyAssessmentPersisting
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let seedProvider: @Sendable () -> UInt64
    @ObservationIgnored private let idProvider: @Sendable () -> UUID
    @ObservationIgnored private var attemptCreationInFlight = false

    init(
        loader: any StudyQuestionCatalogueLoading = BundledStudyQuestionCatalogueLoader(),
        persistence: any StudyAssessmentPersisting = StudyAssessmentJSONPersistence(),
        now: @escaping @Sendable () -> Date = { Date() },
        seedProvider: @escaping @Sendable () -> UInt64 = { UInt64.random(in: UInt64.min...UInt64.max) },
        idProvider: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.loader = loader
        self.persistence = persistence
        self.now = now
        self.seedProvider = seedProvider
        self.idProvider = idProvider
    }

    var allQuestions: [StudyQuestion] { catalogue?.items ?? [] }
    var flaggedQuestions: [StudyQuestion] { allQuestions.filter(\.isFlagged) }
    var completedAttempts: [StudyAttempt] { attempts.filter { $0.state == .completed } }

    var progress: StudyProgressSnapshot {
        StudyAssessmentEngine.progressSnapshot(
            attempts: attempts,
            mastery: itemMastery,
            reviewCards: Array(reviewCards.values),
            at: now()
        )
    }

    func activate(subjectID: String) async {
        let normalizedID = subjectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else {
            clearActiveSubject()
            loadState = .failed(StudyAssessmentStoreError.noActiveSubject.localizedDescription)
            return
        }
        if activeSubjectID == normalizedID, loadState == .ready { return }

        activeSubjectID = normalizedID
        attempts = []
        itemMastery = [:]
        reviewCards = [:]
        reviewLogs = []
        loadState = .loading
        errorMessage = nil

        do {
            let loadedCatalogue: StudyQuestionCatalogue
            if let catalogue {
                loadedCatalogue = catalogue
            } else {
                loadedCatalogue = try await loader.loadCatalogue()
            }
            let state = try await persistence.loadState(for: normalizedID)
            guard activeSubjectID == normalizedID else { return }
            if let state, state.subjectID != normalizedID {
                throw StudyAssessmentPersistenceError.subjectMismatch
            }

            catalogue = loadedCatalogue
            if let state {
                attempts = state.attempts
                itemMastery = state.itemMastery
                reviewCards = state.reviewCards
                reviewLogs = state.reviewLogs
            }
            loadState = .ready
        } catch is CancellationError {
            return
        } catch {
            guard activeSubjectID == normalizedID else { return }
            let message = error.localizedDescription
            errorMessage = message
            loadState = .failed(message)
        }
    }

    func clearActiveSubject() {
        activeSubjectID = nil
        attempts = []
        itemMastery = [:]
        reviewCards = [:]
        reviewLogs = []
        errorMessage = nil
        loadState = .idle
    }

    func deleteLocalData(for subjectID: String) async throws {
        try await persistence.deleteState(for: subjectID)
        if activeSubjectID == subjectID {
            clearActiveSubject()
        }
    }

    func questions(
        bank: StudyQuestionBank? = nil,
        domain: StudyDomain? = nil,
        type: StudyQuestionType? = nil,
        qaStatus: StudyQuestionQAStatus? = nil,
        search: String = ""
    ) -> [StudyQuestion] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return allQuestions.filter { question in
            (bank == nil || question.bank == bank)
                && (domain == nil || question.domain == domain)
                && (type == nil || question.type == type)
                && (qaStatus == nil || question.qaStatus == qaStatus)
                && (query.isEmpty
                    || question.stem.localizedCaseInsensitiveContains(query)
                    || question.topic.localizedCaseInsensitiveContains(query)
                    || question.id.localizedCaseInsensitiveContains(query))
        }
    }

    func question(id: String) -> StudyQuestion? {
        catalogue?.questionsByID[id] ?? courseQuestions.first { $0.id == id }
    }

    func setCourseQuestions(_ questions: [StudyQuestion]) {
        courseQuestions = Dictionary(grouping: questions, by: \.id)
            .compactMap { _, versions in versions.first }
            .sorted { $0.id < $1.id }
    }

    func attempt(id: UUID) -> StudyAttempt? {
        attempts.first { $0.id == id }
    }

    func currentItem(for attemptID: UUID) -> StudyAttemptItem? {
        guard let attempt = attempt(id: attemptID), attempt.items.indices.contains(attempt.currentIndex) else {
            return nil
        }
        return attempt.items[attempt.currentIndex]
    }

    func startAttempt(plan: StudySessionPlan) async throws -> UUID {
        try requireReadySubject()
        guard let startingSubjectID = activeSubjectID else {
            throw StudyAssessmentStoreError.noActiveSubject
        }
        guard let catalogue else { throw StudyAssessmentStoreError.catalogueUnavailable }
        guard !attemptCreationInFlight else {
            throw StudyAssessmentStoreError.attemptCreationInProgress
        }
        attemptCreationInFlight = true
        defer { attemptCreationInFlight = false }

        let attemptID = idProvider()
        let attemptCatalogue = catalogueForPlan(plan, base: catalogue)
        let attempt = try StudyAssessmentEngine.makeAttempt(
            catalogue: attemptCatalogue,
            plan: plan,
            seed: seedProvider(),
            attemptID: attemptID,
            now: now()
        )
        attempts.append(attempt)
        try await persist()
        guard activeSubjectID == startingSubjectID, loadState == .ready else {
            throw StudyAssessmentStoreError.storeNotReady
        }
        return attemptID
    }

    private func catalogueForPlan(
        _ plan: StudySessionPlan,
        base: StudyQuestionCatalogue
    ) -> StudyQuestionCatalogue {
        let courseIDs = Set(courseQuestions.map(\.id))
        guard plan.requestedQuestionIDs.contains(where: courseIDs.contains) else { return base }
        let legacyIDs = Set(base.items.map(\.id))
        let supplemental = courseQuestions.filter { !legacyIDs.contains($0.id) }
        let items = base.items + supplemental
        return StudyQuestionCatalogue(
            catalogueVersion: "\(base.catalogueVersion)+courses",
            generatedOn: base.generatedOn,
            sourceFile: base.sourceFile,
            counts: StudyQuestionCatalogueCounts(
                total: items.count,
                singleChoice: base.counts.singleChoice,
                multipleChoice: base.counts.multipleChoice,
                bank1: base.counts.bank1,
                bank2: base.counts.bank2
            ),
            statusNotice: base.statusNotice,
            adjudicationRegister: base.adjudicationRegister,
            duplicateClusters: base.duplicateClusters,
            items: items
        )
    }

    @discardableResult
    func submitResponse(
        attemptID: UUID,
        selectedOptionIDs: Set<String>,
        textResponse: String? = nil,
        matchingPairs: [String: String]? = nil,
        confidence: StudyConfidence,
        responseDuration: TimeInterval,
        allowExpiredDraft: Bool = false
    ) async throws -> StudyAnswerFeedback? {
        try requireReadySubject()
        guard let attemptIndex = attempts.firstIndex(where: { $0.id == attemptID }) else {
            throw StudyAssessmentEngineError.attemptNotFound
        }
        try requireMutableAttempt(at: attemptIndex, allowExpiredDraft: allowExpiredDraft)
        let itemIndex = attempts[attemptIndex].currentIndex
        guard attempts[attemptIndex].items.indices.contains(itemIndex) else {
            throw StudyAssessmentEngineError.questionIndexOutOfRange
        }
        let immediate = attempts[attemptIndex].plan.feedbackPolicy == .immediate
        if attempts[attemptIndex].items[itemIndex].response != nil, immediate {
            throw StudyAssessmentEngineError.questionAlreadyAnswered
        }

        let question = attempts[attemptIndex].items[itemIndex].question
        let normalizedSelection = Set(selectedOptionIDs.map { $0.uppercased() })
        let normalizedText = textResponse?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch question.type {
        case .singleChoice, .multipleChoice:
            guard !normalizedSelection.isEmpty,
                  normalizedSelection.isSubset(of: Set(question.options.keys)),
                  question.type != .singleChoice || normalizedSelection.count == 1 else {
                throw StudyAssessmentEngineError.invalidSelection
            }
        case .matching:
            let termIDs = Set(question.matchingTerms?.map(\.id) ?? [])
            let descriptionIDs = Set(question.matchingDescriptions?.map(\.id) ?? [])
            guard let matchingPairs,
                  Set(matchingPairs.keys) == termIDs,
                  Set(matchingPairs.values).isSubset(of: descriptionIDs) else {
                throw StudyAssessmentEngineError.invalidSelection
            }
        case .shortResponse, .reconstruction:
            guard let normalizedText, !normalizedText.isEmpty else {
                throw StudyAssessmentEngineError.invalidSelection
            }
        }

        let submittedAt = now()
        var response = StudyQuestionResponse(
            selectedOptionIDs: normalizedSelection.sorted(),
            confidence: confidence,
            submittedAt: submittedAt,
            responseDuration: max(0, responseDuration),
            isCorrect: immediate
                ? StudyAssessmentEngine.score(
                    question: question,
                    selectedOptionIDs: normalizedSelection,
                    matchingPairs: matchingPairs
                )
                : nil,
            wasAppliedToMastery: false,
            textResponse: normalizedText,
            matchingPairs: matchingPairs
        )

        if immediate, response.isCorrect != nil, attempts[attemptIndex].plan.affectsItemMastery {
            applyMastery(
                questionID: question.id,
                response: response,
                attemptID: attemptID,
                at: submittedAt
            )
            response.wasAppliedToMastery = true
        }
        if response.isCorrect == false {
            scheduleCorrection(for: question.id, at: submittedAt)
        }

        attempts[attemptIndex].items[itemIndex].response = response
        let feedback = immediate
            ? StudyAssessmentEngine.feedback(for: attempts[attemptIndex].items[itemIndex])
            : nil
        try await persist()
        return feedback
    }

    func move(to questionIndex: Int, in attemptID: UUID) async throws {
        try requireReadySubject()
        guard let attemptIndex = attempts.firstIndex(where: { $0.id == attemptID }) else {
            throw StudyAssessmentEngineError.attemptNotFound
        }
        try requireMutableAttempt(at: attemptIndex)
        guard attempts[attemptIndex].items.indices.contains(questionIndex) else {
            throw StudyAssessmentEngineError.questionIndexOutOfRange
        }
        attempts[attemptIndex].currentIndex = questionIndex
        try await persist()
    }

    @discardableResult
    func advance(in attemptID: UUID) async throws -> Bool {
        guard let attempt = attempt(id: attemptID) else {
            throw StudyAssessmentEngineError.attemptNotFound
        }
        let nextIndex = attempt.currentIndex + 1
        guard attempt.items.indices.contains(nextIndex) else { return false }
        try await move(to: nextIndex, in: attemptID)
        return true
    }

    func finalizeAttempt(id attemptID: UUID, allowIncomplete: Bool = false) async throws -> StudyAttemptSummary {
        try requireReadySubject()
        guard let attemptIndex = attempts.firstIndex(where: { $0.id == attemptID }) else {
            throw StudyAssessmentEngineError.attemptNotFound
        }
        guard attempts[attemptIndex].state == .active else {
            throw StudyAssessmentEngineError.attemptIsNotActive
        }
        let unanswered = attempts[attemptIndex].items.lazy.filter { $0.response == nil }.count
        if unanswered > 0, !allowIncomplete {
            throw StudyAssessmentEngineError.unansweredQuestions(unanswered)
        }

        let completedAt = now()
        var finalized = StudyAssessmentEngine.finalizeScoring(attempts[attemptIndex], at: completedAt)
        for itemIndex in finalized.items.indices {
            guard var response = finalized.items[itemIndex].response else { continue }
            let needsCorrectionCard = response.isCorrect == false
                && finalized.plan.feedbackPolicy == .afterSubmission
            if finalized.plan.affectsItemMastery,
               response.isCorrect != nil,
               !response.wasAppliedToMastery {
                applyMastery(
                    questionID: finalized.items[itemIndex].question.id,
                    response: response,
                    attemptID: finalized.id,
                    at: completedAt
                )
                response.wasAppliedToMastery = true
                finalized.items[itemIndex].response = response
            }
            if needsCorrectionCard {
                scheduleCorrection(for: finalized.items[itemIndex].question.id, at: completedAt)
            }
        }
        attempts[attemptIndex] = finalized
        let result = StudyAssessmentEngine.summary(for: finalized)
        try await persist()
        return result
    }

    func abandonAttempt(id attemptID: UUID) async throws {
        try requireReadySubject()
        guard let attemptIndex = attempts.firstIndex(where: { $0.id == attemptID }) else {
            throw StudyAssessmentEngineError.attemptNotFound
        }
        guard attempts[attemptIndex].state == .active else {
            throw StudyAssessmentEngineError.attemptIsNotActive
        }
        attempts[attemptIndex].state = .abandoned
        try await persist()
    }

    func summary(for attemptID: UUID) -> StudyAttemptSummary? {
        attempt(id: attemptID).map(StudyAssessmentEngine.summary(for:))
    }

    func dueReviewCards(at date: Date? = nil) -> [StudyReviewCard] {
        let referenceDate = date ?? now()
        return reviewCards.values
            .filter { $0.isDue(at: referenceDate) }
            .sorted { $0.dueAt < $1.dueAt }
    }

    func reviewPlan(maxCount: Int = 20, at date: Date? = nil) -> StudySessionPlan {
        let questionIDs = dueReviewCards(at: date).prefix(max(0, maxCount)).map(\.questionID)
        return .review(questionIDs: Array(questionIDs))
    }

    func rateReviewCard(
        id cardID: UUID,
        rating: StudyReviewRating,
        attemptID: UUID,
        questionID: String
    ) async throws {
        try requireReadySubject()
        guard let card = reviewCards[cardID] else {
            throw StudyAssessmentEngineError.reviewCardNotFound
        }
        guard let attemptIndex = attempts.firstIndex(where: { $0.id == attemptID }) else {
            throw StudyAssessmentEngineError.attemptNotFound
        }
        guard attempts[attemptIndex].state == .active else {
            throw StudyAssessmentEngineError.attemptIsNotActive
        }
        guard let itemIndex = attempts[attemptIndex].items.firstIndex(where: { $0.question.id == questionID }) else {
            throw StudyAssessmentEngineError.questionIndexOutOfRange
        }
        guard var response = attempts[attemptIndex].items[itemIndex].response else {
            throw StudyAssessmentEngineError.invalidSelection
        }
        guard response.reviewRating == nil else {
            throw StudyAssessmentEngineError.reviewAlreadyRated
        }
        let update = StudyAssessmentEngine.scheduleReview(
            card: card,
            rating: rating,
            at: now(),
            logID: idProvider()
        )
        response.reviewRating = rating
        attempts[attemptIndex].items[itemIndex].response = response
        reviewCards[cardID] = update.card
        reviewLogs.append(update.log)
        try await persist()
    }

    func addToReview(questionID: String) async throws {
        try requireReadySubject()
        guard question(id: questionID) != nil else {
            throw StudyAssessmentEngineError.questionNotFound(questionID)
        }
        guard !reviewCards.values.contains(where: { $0.questionID == questionID }) else {
            return
        }
        scheduleCorrection(for: questionID, at: now())
        try await persist()
    }

    func deleteActiveSubjectData() async throws {
        guard let activeSubjectID else { throw StudyAssessmentStoreError.noActiveSubject }
        try await persistence.deleteState(for: activeSubjectID)
        guard self.activeSubjectID == activeSubjectID else { return }
        attempts = []
        itemMastery = [:]
        reviewCards = [:]
        reviewLogs = []
    }

    private func applyMastery(
        questionID: String,
        response: StudyQuestionResponse,
        attemptID: UUID,
        at date: Date
    ) {
        itemMastery[questionID] = StudyAssessmentEngine.applyingMastery(
            questionID: questionID,
            response: response,
            attemptID: attemptID,
            existing: itemMastery[questionID],
            at: date
        )
    }

    private func scheduleCorrection(for questionID: String, at date: Date) {
        let existing = reviewCards.values.first { $0.questionID == questionID }
        let card = StudyAssessmentEngine.reviewCard(
            for: questionID,
            existing: existing,
            at: date,
            cardID: idProvider()
        )
        reviewCards[card.id] = card
    }

    private func requireReadySubject() throws {
        guard activeSubjectID != nil else {
            throw StudyAssessmentStoreError.noActiveSubject
        }
        guard loadState == .ready else {
            throw StudyAssessmentStoreError.storeNotReady
        }
    }

    private func requireMutableAttempt(at index: Int, allowExpiredDraft: Bool = false) throws {
        guard attempts[index].state == .active else {
            throw StudyAssessmentEngineError.attemptIsNotActive
        }
        if !allowExpiredDraft,
           let remaining = attempts[index].remainingTime(at: now()), remaining <= 0 {
            throw StudyAssessmentEngineError.attemptExpired
        }
    }

    private func persist() async throws {
        try requireReadySubject()
        guard let activeSubjectID else { throw StudyAssessmentStoreError.noActiveSubject }
        let state = StudyAssessmentPersistentState(
            subjectID: activeSubjectID,
            attempts: attempts,
            itemMastery: itemMastery,
            reviewCards: reviewCards,
            reviewLogs: reviewLogs,
            savedAt: now()
        )
        try await persistence.saveState(state, for: activeSubjectID)
    }
}
