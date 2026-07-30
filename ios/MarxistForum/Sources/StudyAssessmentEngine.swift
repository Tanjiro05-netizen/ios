import Foundation

enum StudyQuestionCatalogueError: LocalizedError, Equatable {
    case resourceMissing(String)
    case countMismatch(expected: Int, actual: Int)
    case duplicateQuestionID(String)
    case invalidAnswer(questionID: String)
    case invalidDuplicateReference(clusterID: String, questionID: String)

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let name):
            "The bundled study catalogue \(name) is missing."
        case .countMismatch(let expected, let actual):
            "The study catalogue declares \(expected) questions but contains \(actual)."
        case .duplicateQuestionID(let id):
            "The study catalogue contains the duplicate question ID \(id)."
        case .invalidAnswer(let id):
            "Question \(id) has an answer that does not match its options."
        case .invalidDuplicateReference(let clusterID, let questionID):
            "Duplicate cluster \(clusterID) refers to unknown question \(questionID)."
        }
    }
}

enum StudyQuestionCatalogueDecoder {
    static func decode(_ data: Data) throws -> StudyQuestionCatalogue {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let catalogue = try decoder.decode(StudyQuestionCatalogue.self, from: data)
        try validate(catalogue)
        return catalogue
    }

    static func validate(_ catalogue: StudyQuestionCatalogue) throws {
        guard catalogue.counts.total == catalogue.items.count else {
            throw StudyQuestionCatalogueError.countMismatch(
                expected: catalogue.counts.total,
                actual: catalogue.items.count
            )
        }

        var questionIDs = Set<String>()
        for question in catalogue.items {
            guard questionIDs.insert(question.id).inserted else {
                throw StudyQuestionCatalogueError.duplicateQuestionID(question.id)
            }
            switch question.type {
            case .singleChoice, .multipleChoice:
                let correctIDs = question.correctOptionIDs
                guard !correctIDs.isEmpty,
                      correctIDs.isSubset(of: Set(question.options.keys)),
                      question.type != .singleChoice || correctIDs.count == 1 else {
                    throw StudyQuestionCatalogueError.invalidAnswer(questionID: question.id)
                }
            case .matching:
                let termIDs = Set(question.matchingTerms?.map(\.id) ?? [])
                let descriptionIDs = Set(question.matchingDescriptions?.map(\.id) ?? [])
                let pairs = question.matchingAnswerPairs ?? [:]
                guard !termIDs.isEmpty,
                      Set(pairs.keys) == termIDs,
                      Set(pairs.values).isSubset(of: descriptionIDs) else {
                    throw StudyQuestionCatalogueError.invalidAnswer(questionID: question.id)
                }
            case .shortResponse, .reconstruction:
                guard !(question.expectedResponse ?? question.answerNote)
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw StudyQuestionCatalogueError.invalidAnswer(questionID: question.id)
                }
            }
        }

        for (clusterID, clusterQuestionIDs) in catalogue.duplicateClusters {
            for questionID in clusterQuestionIDs where !questionIDs.contains(questionID) {
                throw StudyQuestionCatalogueError.invalidDuplicateReference(
                    clusterID: clusterID,
                    questionID: questionID
                )
            }
        }
    }
}

protocol StudyQuestionCatalogueLoading: Sendable {
    func loadCatalogue() async throws -> StudyQuestionCatalogue
}

struct BundledStudyQuestionCatalogueLoader: StudyQuestionCatalogueLoading, Sendable {
    let resourceURL: URL?
    let resourceName: String

    init(
        bundle: Bundle = .main,
        resourceName: String = "Marxist_Info_Full_Question_Catalogue",
        resourceExtension: String = "json"
    ) {
        self.resourceName = "\(resourceName).\(resourceExtension)"
        resourceURL = bundle.url(forResource: resourceName, withExtension: resourceExtension)
    }

    init(resourceURL: URL) {
        self.resourceURL = resourceURL
        resourceName = resourceURL.lastPathComponent
    }

    func loadCatalogue() async throws -> StudyQuestionCatalogue {
        guard let resourceURL else {
            throw StudyQuestionCatalogueError.resourceMissing(resourceName)
        }
        return try await Task.detached(priority: .userInitiated) {
            try StudyQuestionCatalogueDecoder.decode(Data(contentsOf: resourceURL))
        }.value
    }
}

struct DataStudyQuestionCatalogueLoader: StudyQuestionCatalogueLoading, Sendable {
    let data: Data

    func loadCatalogue() async throws -> StudyQuestionCatalogue {
        try StudyQuestionCatalogueDecoder.decode(data)
    }
}

enum StudyAssessmentEngineError: LocalizedError, Equatable {
    case noEligibleQuestions
    case invalidItemCount
    case questionNotFound(String)
    case attemptNotFound
    case attemptIsNotActive
    case questionIndexOutOfRange
    case questionAlreadyAnswered
    case invalidSelection
    case attemptExpired
    case unansweredQuestions(Int)
    case reviewCardNotFound
    case reviewAlreadyRated

    var errorDescription: String? {
        switch self {
        case .noEligibleQuestions: "No eligible questions match this practice plan."
        case .invalidItemCount: "A practice session must contain at least one question."
        case .questionNotFound(let id): "Question \(id) could not be found in this catalogue."
        case .attemptNotFound: "That study attempt could not be found."
        case .attemptIsNotActive: "That study attempt is no longer active."
        case .questionIndexOutOfRange: "That question is outside this attempt."
        case .questionAlreadyAnswered: "This question has already been answered."
        case .invalidSelection: "Choose a valid answer before submitting."
        case .attemptExpired: "The time limit has ended. Submit the attempt to view your results."
        case .unansweredQuestions(let count): "Answer the remaining \(count) questions before submitting."
        case .reviewCardNotFound: "That review card could not be found."
        case .reviewAlreadyRated: "Recall for this review question has already been rated."
        }
    }
}

struct StudySeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

struct StudyReviewUpdate: Sendable {
    let card: StudyReviewCard
    let log: StudyReviewLog
}

enum StudyAssessmentEngine {
    static let masteryThreshold = 0.80
    static let honorsThreshold = 0.85
    static let reviewIntervalsInDays = [1, 3, 7, 21]

    static func isCorrect(question: StudyQuestion, selectedOptionIDs: some Sequence<String>) -> Bool {
        Set(selectedOptionIDs.map { $0.uppercased() }) == question.correctOptionIDs
    }

    static func score(
        question: StudyQuestion,
        selectedOptionIDs: some Sequence<String>,
        matchingPairs: [String: String]? = nil
    ) -> Bool? {
        switch question.type {
        case .singleChoice, .multipleChoice:
            return isCorrect(question: question, selectedOptionIDs: selectedOptionIDs)
        case .matching:
            guard let keyedPairs = question.matchingAnswerPairs, let matchingPairs else { return false }
            return matchingPairs == keyedPairs
        case .shortResponse, .reconstruction:
            return nil
        }
    }

    static func makeAttempt(
        catalogue: StudyQuestionCatalogue,
        plan: StudySessionPlan,
        seed: UInt64,
        attemptID: UUID = UUID(),
        now: Date = .now
    ) throws -> StudyAttempt {
        guard plan.requestedItemCount > 0 else {
            throw StudyAssessmentEngineError.invalidItemCount
        }

        var generator = StudySeededRandomNumberGenerator(seed: seed)
        let questions = selectQuestions(
            from: catalogue,
            plan: plan,
            generator: &generator
        )
        guard !questions.isEmpty else {
            throw StudyAssessmentEngineError.noEligibleQuestions
        }

        let items = questions.map { question in
            StudyAttemptItem(
                question: question,
                optionOrder: question.options.keys.sorted().shuffled(using: &generator),
                response: nil
            )
        }
        return StudyAttempt(
            id: attemptID,
            plan: plan,
            catalogueVersion: catalogue.catalogueVersion,
            randomSeed: seed,
            startedAt: now,
            items: items,
            currentIndex: 0,
            state: .active,
            submittedAt: nil
        )
    }

    static func feedback(for item: StudyAttemptItem) -> StudyAnswerFeedback? {
        guard let isCorrect = item.response?.isCorrect else { return nil }
        return StudyAnswerFeedback(
            isCorrect: isCorrect,
            correctOptionIDs: item.question.correctOptionIDs,
            explanation: item.question.answerNote,
            qaStatus: item.question.qaStatus,
            adjudicationNote: item.question.adjudicationNote
        )
    }

    static func finalizeScoring(_ attempt: StudyAttempt, at date: Date) -> StudyAttempt {
        var finalized = attempt
        for index in finalized.items.indices {
            guard var response = finalized.items[index].response else { continue }
            response.isCorrect = score(
                question: finalized.items[index].question,
                selectedOptionIDs: response.selectedOptionIDs,
                matchingPairs: response.matchingPairs
            )
            finalized.items[index].response = response
        }
        finalized.state = .completed
        finalized.submittedAt = date
        return finalized
    }

    static func summary(for attempt: StudyAttempt) -> StudyAttemptSummary {
        let correct = attempt.items.lazy.filter { $0.response?.isCorrect == true }.count
        let total = attempt.items.count
        let scoredTotal = attempt.items.lazy.filter { $0.response?.isCorrect != nil }.count
        let fraction = scoredTotal == 0 ? 0 : Double(correct) / Double(scoredTotal)
        let achievement: StudyAchievement
        if fraction >= honorsThreshold {
            achievement = .honors
        } else if fraction >= masteryThreshold {
            achievement = .mastered
        } else {
            achievement = .needsReview
        }

        let domainBreakdown = StudyDomain.allCases.compactMap { domain -> StudyDomainBreakdown? in
            let domainItems = attempt.items.filter { $0.question.domain == domain }
            guard !domainItems.isEmpty else { return nil }
            return StudyDomainBreakdown(
                domain: domain,
                correct: domainItems.lazy.filter { $0.response?.isCorrect == true }.count,
                total: domainItems.count
            )
        }
        let confidentWrong = attempt.items.compactMap { item in
            item.response?.isConfidentWrong == true ? item.question.id : nil
        }
        return StudyAttemptSummary(
            attemptID: attempt.id,
            correct: correct,
            total: total,
            achievement: achievement,
            domainBreakdown: domainBreakdown,
            confidentWrongQuestionIDs: confidentWrong,
            scoredTotal: scoredTotal
        )
    }

    static func applyingMastery(
        questionID: String,
        response: StudyQuestionResponse,
        attemptID: UUID,
        existing: StudyItemMastery?,
        at date: Date
    ) -> StudyItemMastery {
        var mastery = existing ?? StudyItemMastery(
            questionID: questionID,
            successfulSessionIDs: [],
            consecutiveCorrectSessions: 0,
            lifetimeCorrectSessions: 0,
            lastResult: false,
            lastConfidence: response.confidence,
            confidentWrongCount: 0,
            state: .learning,
            updatedAt: date
        )
        let isCorrect = response.isCorrect == true
        mastery.lastResult = isCorrect
        mastery.lastConfidence = response.confidence
        mastery.updatedAt = date

        if isCorrect {
            if !mastery.successfulSessionIDs.contains(attemptID) {
                mastery.successfulSessionIDs.append(attemptID)
                mastery.consecutiveCorrectSessions += 1
                mastery.lifetimeCorrectSessions += 1
            }
            mastery.state = mastery.successfulSessionIDs.count >= 3 ? .mastered : .learning
        } else {
            mastery.successfulSessionIDs = []
            mastery.consecutiveCorrectSessions = 0
            mastery.state = .reopened
            if response.isConfidentWrong {
                mastery.confidentWrongCount += 1
            }
        }
        return mastery
    }

    static func reviewCard(
        for questionID: String,
        existing: StudyReviewCard?,
        at date: Date,
        cardID: UUID = UUID()
    ) -> StudyReviewCard {
        let firstDue = date.addingTimeInterval(days: 1)
        guard var existing else {
            return StudyReviewCard(
                id: cardID,
                questionID: questionID,
                createdAt: date,
                dueAt: firstDue,
                intervalIndex: 0,
                state: .scheduled,
                lastRating: nil,
                updatedAt: date
            )
        }
        existing.intervalIndex = 0
        existing.state = .scheduled
        existing.dueAt = min(existing.dueAt, firstDue)
        existing.lastRating = nil
        existing.updatedAt = date
        return existing
    }

    static func scheduleReview(
        card: StudyReviewCard,
        rating: StudyReviewRating,
        at date: Date,
        logID: UUID = UUID()
    ) -> StudyReviewUpdate {
        let priorIndex = min(max(card.intervalIndex, 0), reviewIntervalsInDays.count - 1)
        let newIndex: Int
        switch rating {
        case .again: newIndex = 0
        case .hard: newIndex = 1
        case .good: newIndex = 2
        case .easy: newIndex = 3
        }

        var updated = card
        updated.intervalIndex = newIndex
        updated.dueAt = date.addingTimeInterval(days: reviewIntervalsInDays[newIndex])
        updated.lastRating = rating
        updated.updatedAt = date
        let log = StudyReviewLog(
            id: logID,
            cardID: card.id,
            questionID: card.questionID,
            rating: rating,
            reviewedAt: date,
            priorIntervalIndex: priorIndex,
            newIntervalIndex: newIndex,
            newDueAt: updated.dueAt
        )
        return StudyReviewUpdate(card: updated, log: log)
    }

    static func progressSnapshot(
        attempts: [StudyAttempt],
        mastery: [String: StudyItemMastery],
        reviewCards: [StudyReviewCard],
        at date: Date
    ) -> StudyProgressSnapshot {
        let completed = attempts.filter { $0.state == .completed }
        var latestByQuestion: [String: (Date, StudyAttemptItem)] = [:]
        for attempt in completed {
            let attemptDate = attempt.submittedAt ?? attempt.startedAt
            for item in attempt.items where item.response?.isCorrect != nil {
                if latestByQuestion[item.question.id]?.0 ?? .distantPast <= attemptDate {
                    latestByQuestion[item.question.id] = (attemptDate, item)
                }
            }
        }

        let latestItems = latestByQuestion.values.map(\.1)
        let domains = StudyDomain.allCases.compactMap { domain -> StudyDomainBreakdown? in
            let items = latestItems.filter { $0.question.domain == domain }
            guard !items.isEmpty else { return nil }
            return StudyDomainBreakdown(
                domain: domain,
                correct: items.lazy.filter { $0.response?.isCorrect == true }.count,
                total: items.count
            )
        }
        return StudyProgressSnapshot(
            completedAttempts: completed.count,
            answeredQuestions: latestItems.count,
            masteredItems: mastery.values.lazy.filter { $0.state == .mastered }.count,
            dueReviewCount: reviewCards.lazy.filter { $0.isDue(at: date) }.count,
            confidentWrongCount: latestItems.lazy.filter { $0.response?.isConfidentWrong == true }.count,
            domainBreakdown: domains
        )
    }

    private static func selectQuestions(
        from catalogue: StudyQuestionCatalogue,
        plan: StudySessionPlan,
        generator: inout StudySeededRandomNumberGenerator
    ) -> [StudyQuestion] {
        let byID = catalogue.questionsByID
        if !plan.requestedQuestionIDs.isEmpty, plan.kind != .review {
            return plan.requestedQuestionIDs.compactMap { byID[$0] }.filter(\.isApprovedForScoring)
        }
        let eligible = catalogue.items.filter(\.isApprovedForScoring)
        let candidates: [StudyQuestion]

        switch plan.kind {
        case .domainPractice:
            candidates = eligible.filter { $0.domain == plan.domain }
        case .practiceExam:
            if let domain = plan.domain {
                candidates = eligible.filter { $0.domain == domain }
            } else {
                candidates = eligible
            }
        case .review:
            candidates = plan.requestedQuestionIDs.compactMap { byID[$0] }.filter(\.isApprovedForScoring)
        case .legacyDrill, .interleavedPractice, .diagnostic:
            candidates = eligible
        }

        let clusterByID = catalogue.duplicateClusterByQuestionID
        if plan.kind == .review {
            return uniqueQuestions(
                candidates,
                limit: plan.requestedItemCount,
                clusterByID: clusterByID
            )
        }
        if plan.kind == .interleavedPractice || plan.kind == .diagnostic || plan.kind == .practiceExam {
            return balancedQuestions(
                candidates,
                limit: plan.requestedItemCount,
                clusterByID: clusterByID,
                generator: &generator
            )
        }
        return uniqueQuestions(
            candidates.shuffled(using: &generator),
            limit: plan.requestedItemCount,
            clusterByID: clusterByID
        )
    }

    private static func balancedQuestions(
        _ candidates: [StudyQuestion],
        limit: Int,
        clusterByID: [String: String],
        generator: inout StudySeededRandomNumberGenerator
    ) -> [StudyQuestion] {
        var buckets: [StudyDomain: [StudyQuestion]] = [:]
        for domain in StudyDomain.allCases {
            buckets[domain] = candidates.filter { $0.domain == domain }.shuffled(using: &generator)
        }
        var offsets = Dictionary(uniqueKeysWithValues: StudyDomain.allCases.map { ($0, 0) })
        var selected: [StudyQuestion] = []
        var usedTokens = Set<String>()
        var madeProgress = true

        while selected.count < limit && madeProgress {
            madeProgress = false
            for domain in StudyDomain.allCases where selected.count < limit {
                guard let bucket = buckets[domain] else { continue }
                var offset = offsets[domain, default: 0]
                while offset < bucket.count {
                    let question = bucket[offset]
                    offset += 1
                    offsets[domain] = offset
                    let token = clusterByID[question.id] ?? "question:\(question.id)"
                    if usedTokens.insert(token).inserted {
                        selected.append(question)
                        madeProgress = true
                        break
                    }
                }
            }
        }
        return selected
    }

    private static func uniqueQuestions(
        _ candidates: [StudyQuestion],
        limit: Int,
        clusterByID: [String: String]
    ) -> [StudyQuestion] {
        var selected: [StudyQuestion] = []
        var usedTokens = Set<String>()
        for question in candidates where selected.count < limit {
            let token = clusterByID[question.id] ?? "question:\(question.id)"
            guard usedTokens.insert(token).inserted else { continue }
            selected.append(question)
        }
        return selected
    }
}

private extension Date {
    func addingTimeInterval(days: Int) -> Date {
        addingTimeInterval(TimeInterval(days) * 86_400)
    }
}
