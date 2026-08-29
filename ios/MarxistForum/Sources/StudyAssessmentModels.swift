import Foundation

// MARK: - Bundled catalogue

struct StudyQuestionCatalogue: Codable, Sendable {
    let catalogueVersion: String
    let generatedOn: String
    let sourceFile: String
    let counts: StudyQuestionCatalogueCounts
    let statusNotice: String
    let adjudicationRegister: [String: StudyQuestionAdjudication]
    let duplicateClusters: [String: [String]]
    let items: [StudyQuestion]

    var questionsByID: [String: StudyQuestion] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    var duplicateClusterByQuestionID: [String: String] {
        var result: [String: String] = [:]
        for (clusterID, questionIDs) in duplicateClusters {
            for questionID in questionIDs {
                result[questionID] = clusterID
            }
        }
        for item in items {
            if let clusterID = item.duplicateCluster {
                result[item.id] = clusterID
            }
        }
        return result
    }
}

struct StudyQuestionCatalogueCounts: Codable, Equatable, Sendable {
    let total: Int
    let singleChoice: Int
    let multipleChoice: Int
    let bank1: Int
    let bank2: Int
}

struct StudyQuestionAdjudication: Codable, Equatable, Sendable {
    let recommendedAnswer: String
    let status: StudyQuestionAdjudicationStatus
    let note: String
}

enum StudyQuestionAdjudicationStatus: String, Codable, Sendable {
    case corrected
    case flagged
}

enum StudyQuestionBank: String, Codable, CaseIterable, Identifiable, Sendable {
    case bank1
    case bank2
    case course

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bank1: "Bank 1"
        case .bank2: "Bank 2"
        case .course: "Course"
        }
    }

}

enum StudyQuestionType: String, Codable, CaseIterable, Identifiable, Sendable {
    case singleChoice = "single_choice"
    case multipleChoice = "multiple_choice"
    case matching
    case shortResponse = "short_response"
    case reconstruction

    var id: String { rawValue }

    var title: String {
        switch self {
        case .singleChoice: "Single choice"
        case .multipleChoice: "Multiple choice"
        case .matching: "Matching"
        case .shortResponse: "Short response"
        case .reconstruction: "Reconstruction"
        }
    }

    var isObjective: Bool {
        switch self {
        case .singleChoice, .multipleChoice, .matching: true
        case .shortResponse, .reconstruction: false
        }
    }
}

enum StudyQuestionQAStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case importedNeedsCitation = "imported_needs_citation"
    case draftNeedsAcademicReview = "draft_needs_academic_review"
    case corrected
    case reviewed
    case flagged

    var id: String { rawValue }

    var title: String {
        switch self {
        case .importedNeedsCitation: "Needs citation review"
        case .draftNeedsAcademicReview: "Needs academic review"
        case .corrected: "Corrected key"
        case .reviewed: "Reviewed and approved"
        case .flagged: "Flagged for adjudication"
        }
    }
}

enum StudyQuestionDifficulty: String, Codable, CaseIterable, Identifiable, Sendable {
    case easy
    case medium
    case hard

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum StudyQuestionBloomLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case remember
    case understand
    case apply
    case analyze
    case evaluate

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum StudyDomain: String, Codable, CaseIterable, Identifiable, Sendable {
    case introduction
    case materialityAndDialectics
    case epistemology
    case historicalMaterialism
    case formationOfCapitalism

    var id: String { rawValue }

    var title: String {
        switch self {
        case .introduction: "Introduction"
        case .materialityAndDialectics: "Materiality and Dialectics"
        case .epistemology: "Epistemology"
        case .historicalMaterialism: "Historical Materialism"
        case .formationOfCapitalism: "Formation of Capitalism"
        }
    }

    static func domain(forChapterSlug slug: String) -> StudyDomain? {
        switch slug.lowercased() {
        case "intro": .introduction
        case "ch1": .materialityAndDialectics
        case "ch2": .epistemology
        case "ch3": .historicalMaterialism
        case "ch4": .formationOfCapitalism
        default: nil
        }
    }
}

struct StudyAnswerOption: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let text: String
}

struct StudyQuestion: Codable, Identifiable, Sendable {
    let bank: StudyQuestionBank
    let chapterSlug: String
    let chapterTitle: String
    let type: StudyQuestionType
    let options: [String: String]
    let stem: String
    let printedAnswer: String
    let id: String
    let adjudicatedAnswer: String
    let qaStatus: StudyQuestionQAStatus
    let adjudicationNote: String?
    let topic: String
    let difficulty: StudyQuestionDifficulty
    let bloom: StudyQuestionBloomLevel
    let dok: Int
    let courses: [String]
    let answerNote: String
    let source: StudyQuestionSource
    let duplicateCluster: String?
    var matchingTerms: [StudyAnswerOption]? = nil
    var matchingDescriptions: [StudyAnswerOption]? = nil
    var matchingAnswerPairs: [String: String]? = nil
    var expectedResponse: String? = nil
    var legacySourceID: String? = nil
    var examCode: String? = nil
    var examSection: String? = nil
    var pointValue: Int? = nil

    var orderedOptions: [StudyAnswerOption] {
        options.keys.sorted().compactMap { key in
            options[key].map { StudyAnswerOption(id: key, text: $0) }
        }
    }

    var correctOptionIDs: Set<String> {
        Set(adjudicatedAnswer.compactMap { character in
            let value = String(character).uppercased()
            return value.range(of: #"^[A-Z]$"#, options: .regularExpression) == nil ? nil : value
        })
    }

    var domain: StudyDomain? {
        StudyDomain.domain(forChapterSlug: chapterSlug)
    }

    var answerNoteWithoutCanonicalKey: String {
        guard answerNote.hasPrefix("Keyed answer: "),
              let separator = answerNote.range(of: ". ") else {
            return answerNote
        }
        return String(answerNote[separator.upperBound...])
    }

    var isFlagged: Bool { qaStatus == .flagged }
    var isApprovedForScoring: Bool {
        qaStatus == .reviewed
            || (AppFeatureFlags.unreviewedAssessmentContentEnabled && qaStatus != .flagged)
    }
    var requiresWrittenResponse: Bool { type == .shortResponse || type == .reconstruction }
}

struct StudyQuestionSource: Codable, Equatable, Sendable {
    let file: String
    let line: Int
    let bank: StudyQuestionBank
    let printedNumber: StudySourcePrintedNumber
}

enum StudySourcePrintedNumber: Codable, Equatable, Sendable, CustomStringConvertible {
    case number(Int)
    case note(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            self = .number(number)
        } else {
            self = .note(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let number): try container.encode(number)
        case .note(let note): try container.encode(note)
        }
    }

    var description: String {
        switch self {
        case .number(let number): String(number)
        case .note(let note): note
        }
    }
}

// MARK: - Session plans and attempts

enum StudySessionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case legacyDrill
    case domainPractice
    case interleavedPractice
    case diagnostic
    case review
    case practiceExam

    var id: String { rawValue }
}

enum StudyFeedbackPolicy: String, Codable, Sendable {
    case immediate
    case afterSubmission
}

enum StudyAssessmentSource: String, Codable, Sendable {
    case standalone
    case course
    case daily
    case review
    case exam
}

enum StudyAssessmentGradeRole: String, Codable, Sendable {
    case ungraded
    case completion
    case formative
    case summative
}

struct StudyAssessmentContext: Codable, Hashable, Sendable {
    let source: StudyAssessmentSource
    let learningPathID: String?
    let courseID: String?
    let moduleID: String?
    let lessonID: String?
    let assessmentID: String?
    let gradeRole: StudyAssessmentGradeRole

    init(
        source: StudyAssessmentSource,
        learningPathID: String? = nil,
        courseID: String? = nil,
        moduleID: String? = nil,
        lessonID: String? = nil,
        assessmentID: String? = nil,
        gradeRole: StudyAssessmentGradeRole = .ungraded
    ) {
        self.source = source
        self.learningPathID = learningPathID
        self.courseID = courseID
        self.moduleID = moduleID
        self.lessonID = lessonID
        self.assessmentID = assessmentID
        self.gradeRole = gradeRole
    }
}

struct StudySessionPlan: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let kind: StudySessionKind
    let title: String
    let requestedItemCount: Int
    let domain: StudyDomain?
    let requestedQuestionIDs: [String]
    let feedbackPolicy: StudyFeedbackPolicy
    let durationSeconds: Int?
    let affectsItemMastery: Bool
    let context: StudyAssessmentContext?

    init(
        id: String,
        kind: StudySessionKind,
        title: String,
        requestedItemCount: Int,
        domain: StudyDomain?,
        requestedQuestionIDs: [String],
        feedbackPolicy: StudyFeedbackPolicy,
        durationSeconds: Int?,
        affectsItemMastery: Bool,
        context: StudyAssessmentContext? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.requestedItemCount = requestedItemCount
        self.domain = domain
        self.requestedQuestionIDs = requestedQuestionIDs
        self.feedbackPolicy = feedbackPolicy
        self.durationSeconds = durationSeconds
        self.affectsItemMastery = affectsItemMastery
        self.context = context
    }

    static func legacyDrill(itemCount: Int = 10) -> StudySessionPlan {
        StudySessionPlan(
            id: "legacy-drill-\(itemCount)", kind: .legacyDrill,
            title: "Basic Principles Drill", requestedItemCount: itemCount,
            domain: nil, requestedQuestionIDs: [], feedbackPolicy: .immediate,
            durationSeconds: nil, affectsItemMastery: false
        )
    }

    static func domain(_ domain: StudyDomain, itemCount: Int = 10) -> StudySessionPlan {
        StudySessionPlan(
            id: "domain-\(domain.rawValue)-\(itemCount)", kind: .domainPractice,
            title: domain.title, requestedItemCount: itemCount,
            domain: domain, requestedQuestionIDs: [], feedbackPolicy: .immediate,
            durationSeconds: nil, affectsItemMastery: false
        )
    }

    static func interleaved(itemCount: Int = 20) -> StudySessionPlan {
        StudySessionPlan(
            id: "interleaved-\(itemCount)", kind: .interleavedPractice,
            title: "Interleaved Practice", requestedItemCount: itemCount,
            domain: nil, requestedQuestionIDs: [], feedbackPolicy: .immediate,
            durationSeconds: nil, affectsItemMastery: false
        )
    }

    static func diagnostic(itemCount: Int = 25) -> StudySessionPlan {
        StudySessionPlan(
            id: "diagnostic-\(itemCount)", kind: .diagnostic,
            title: "Foundations Diagnostic", requestedItemCount: itemCount,
            domain: nil, requestedQuestionIDs: [], feedbackPolicy: .afterSubmission,
            durationSeconds: nil, affectsItemMastery: false
        )
    }

    static func review(questionIDs: [String]) -> StudySessionPlan {
        StudySessionPlan(
            id: "review", kind: .review, title: "Review Queue",
            requestedItemCount: questionIDs.count, domain: nil,
            requestedQuestionIDs: questionIDs, feedbackPolicy: .immediate,
            durationSeconds: nil, affectsItemMastery: false
        )
    }

    static func practiceExam(itemCount: Int = 40, durationSeconds: Int = 60 * 60) -> StudySessionPlan {
        StudySessionPlan(
            id: "practice-exam-\(itemCount)-\(durationSeconds)", kind: .practiceExam,
            title: "Foundations Practice Exam", requestedItemCount: itemCount,
            domain: nil, requestedQuestionIDs: [], feedbackPolicy: .afterSubmission,
            durationSeconds: durationSeconds, affectsItemMastery: false
        )
    }
}

enum StudyConfidence: String, Codable, CaseIterable, Identifiable, Sendable {
    case guess
    case fairlySure
    case certain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .guess: "Guess"
        case .fairlySure: "Fairly sure"
        case .certain: "Certain"
        }
    }
}

enum StudyAttemptState: String, Codable, Sendable {
    case active
    case completed
    case abandoned
}

struct StudyQuestionResponse: Codable, Sendable {
    let selectedOptionIDs: [String]
    let confidence: StudyConfidence
    let submittedAt: Date
    let responseDuration: TimeInterval
    var isCorrect: Bool?
    var wasAppliedToMastery: Bool
    var reviewRating: StudyReviewRating? = nil
    var textResponse: String? = nil
    var matchingPairs: [String: String]? = nil

    var isConfidentWrong: Bool {
        confidence == .certain && isCorrect == false
    }
}

struct StudyAttemptItem: Codable, Identifiable, Sendable {
    var id: String { question.id }
    let question: StudyQuestion
    let optionOrder: [String]
    var response: StudyQuestionResponse?

    var displayedOptions: [StudyAnswerOption] {
        optionOrder.compactMap { id in
            question.options[id].map { StudyAnswerOption(id: id, text: $0) }
        }
    }
}

struct StudyAttempt: Codable, Identifiable, Sendable {
    let id: UUID
    let plan: StudySessionPlan
    let catalogueVersion: String
    let randomSeed: UInt64
    let startedAt: Date
    var items: [StudyAttemptItem]
    var currentIndex: Int
    var state: StudyAttemptState
    var submittedAt: Date?

    var answeredCount: Int { items.lazy.filter { $0.response != nil }.count }
    var isComplete: Bool { state == .completed }

    func remainingTime(at date: Date) -> TimeInterval? {
        guard let durationSeconds = plan.durationSeconds else { return nil }
        return max(0, TimeInterval(durationSeconds) - date.timeIntervalSince(startedAt))
    }
}

struct StudyAnswerFeedback: Equatable, Sendable {
    let isCorrect: Bool
    let correctOptionIDs: Set<String>
    let explanation: String
    let qaStatus: StudyQuestionQAStatus
    let adjudicationNote: String?
}

enum StudyAchievement: String, Codable, Sendable {
    case needsReview
    case mastered
    case honors

    var title: String {
        switch self {
        case .needsReview: "Needs Review"
        case .mastered: "Mastered"
        case .honors: "Honors"
        }
    }

    var practiceTitle: String {
        switch self {
        case .needsReview: "Review Recommended"
        case .mastered: "80% Target Reached"
        case .honors: "Honors Score Band"
        }
    }
}

struct StudyDomainBreakdown: Codable, Equatable, Identifiable, Sendable {
    var id: StudyDomain { domain }
    let domain: StudyDomain
    let correct: Int
    let total: Int
    var fractionCorrect: Double { total == 0 ? 0 : Double(correct) / Double(total) }
}

struct StudyAttemptSummary: Codable, Sendable {
    let attemptID: UUID
    let correct: Int
    let total: Int
    let achievement: StudyAchievement
    let domainBreakdown: [StudyDomainBreakdown]
    let confidentWrongQuestionIDs: [String]
    var scoredTotal: Int? = nil

    var fractionCorrect: Double {
        let denominator = scoredTotal ?? total
        return denominator == 0 ? 0 : Double(correct) / Double(denominator)
    }
}

// MARK: - Mastery and review

enum StudyItemMasteryState: String, Codable, Sendable {
    case learning
    case mastered
    case reopened
}

struct StudyItemMastery: Codable, Sendable {
    let questionID: String
    var successfulSessionIDs: [UUID]
    var consecutiveCorrectSessions: Int
    var lifetimeCorrectSessions: Int
    var lastResult: Bool
    var lastConfidence: StudyConfidence
    var confidentWrongCount: Int
    var state: StudyItemMasteryState
    var updatedAt: Date
}

enum StudyReviewRating: String, Codable, CaseIterable, Identifiable, Sendable {
    case again
    case hard
    case good
    case easy

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum StudyReviewCardState: String, Codable, Sendable {
    case scheduled
    case suspended
}

struct StudyReviewCard: Codable, Identifiable, Sendable {
    let id: UUID
    let questionID: String
    let createdAt: Date
    var dueAt: Date
    var intervalIndex: Int
    var state: StudyReviewCardState
    var lastRating: StudyReviewRating?
    var updatedAt: Date

    func isDue(at date: Date) -> Bool {
        state == .scheduled && dueAt <= date
    }
}

struct StudyReviewLog: Codable, Identifiable, Sendable {
    let id: UUID
    let cardID: UUID
    let questionID: String
    let rating: StudyReviewRating
    let reviewedAt: Date
    let priorIntervalIndex: Int
    let newIntervalIndex: Int
    let newDueAt: Date
}

struct StudyProgressSnapshot: Sendable {
    let completedAttempts: Int
    let answeredQuestions: Int
    let masteredItems: Int
    let dueReviewCount: Int
    let confidentWrongCount: Int
    let domainBreakdown: [StudyDomainBreakdown]
}

struct StudyAssessmentPersistentState: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let subjectID: String
    var attempts: [StudyAttempt]
    var itemMastery: [String: StudyItemMastery]
    var reviewCards: [UUID: StudyReviewCard]
    var reviewLogs: [StudyReviewLog]
    var savedAt: Date

    init(
        subjectID: String,
        attempts: [StudyAttempt] = [],
        itemMastery: [String: StudyItemMastery] = [:],
        reviewCards: [UUID: StudyReviewCard] = [:],
        reviewLogs: [StudyReviewLog] = [],
        savedAt: Date = .now
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.subjectID = subjectID
        self.attempts = attempts
        self.itemMastery = itemMastery
        self.reviewCards = reviewCards
        self.reviewLogs = reviewLogs
        self.savedAt = savedAt
    }
}
