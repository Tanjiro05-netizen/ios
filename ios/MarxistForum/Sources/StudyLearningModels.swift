import Foundation
import SwiftData

@Model
final class StudyCourseProgressRecord {
    @Attribute(.unique) var recordID: String
    var subjectID: String
    var courseID: String
    var courseVersion: String
    var completedLessonIDs: [String]
    var completedRequiredBlockIDs: [String] = []
    var enrolledAt: Date
    var updatedAt: Date

    init(subjectID: String, courseID: String, courseVersion: String, enrolledAt: Date = .now) {
        self.recordID = "\(subjectID)::\(courseID)"
        self.subjectID = subjectID
        self.courseID = courseID
        self.courseVersion = courseVersion
        self.completedLessonIDs = []
        self.completedRequiredBlockIDs = []
        self.enrolledAt = enrolledAt
        self.updatedAt = enrolledAt
    }

    func setLesson(_ lessonID: String, completed: Bool, at date: Date = .now) {
        var values = Set(completedLessonIDs)
        if completed { values.insert(lessonID) } else { values.remove(lessonID) }
        completedLessonIDs = values.sorted()
        updatedAt = date
    }

    /// Records progress at the authored-section level while retaining the
    /// lesson IDs used by course packages and progress records created before
    /// section-level reading was introduced.
    func setSection(
        _ blockID: String,
        completed: Bool,
        lessonID: String,
        requiredBlockIDs: [String],
        at date: Date = .now
    ) {
        var blockValues = Set(completedRequiredBlockIDs)
        var lessonValues = Set(completedLessonIDs)
        let requiredValues = Set(requiredBlockIDs)

        // A legacy-completed lesson represents every required section in that
        // lesson. Materialise those IDs before allowing one section to change.
        if lessonValues.contains(lessonID) {
            blockValues.formUnion(requiredValues)
        }

        if completed {
            blockValues.insert(blockID)
        } else {
            blockValues.remove(blockID)
        }

        if !requiredValues.isEmpty, requiredValues.isSubset(of: blockValues) {
            lessonValues.insert(lessonID)
        } else {
            lessonValues.remove(lessonID)
        }

        completedRequiredBlockIDs = blockValues.sorted()
        completedLessonIDs = lessonValues.sorted()
        updatedAt = date
    }
}

@Model
final class StudyLearningEventRecord {
    @Attribute(.unique) var eventID: String
    var subjectID: String
    var kind: String
    var contentID: String
    var points: Int
    var occurredAt: Date

    init(eventID: String, subjectID: String, kind: String, contentID: String, points: Int, occurredAt: Date = .now) {
        self.eventID = eventID
        self.subjectID = subjectID
        self.kind = kind
        self.contentID = contentID
        self.points = points
        self.occurredAt = occurredAt
    }
}

@Model
final class StudySavedContentRecord {
    @Attribute(.unique) var recordID: String
    var subjectID: String
    var contentID: String
    var contentKind: String
    var savedAt: Date

    init(subjectID: String, contentID: String, contentKind: String, savedAt: Date = .now) {
        self.recordID = "\(subjectID)::\(contentKind)::\(contentID)"
        self.subjectID = subjectID
        self.contentID = contentID
        self.contentKind = contentKind
        self.savedAt = savedAt
    }
}

enum StudySubmissionStatus: String, Codable, Sendable {
    case draft
    case submitted
    case returned
    case graded

    var title: String {
        switch self {
        case .draft: "Draft"
        case .submitted: "Awaiting marking"
        case .returned: "Returned for revision"
        case .graded: "Marked"
        }
    }
}

@Model
final class StudyAssignmentSubmissionRecord {
    @Attribute(.unique) var recordID: String
    var subjectID: String
    var candidateDisplayName: String
    var courseID: String
    var assignmentID: String
    var draftMarkdown: String
    var status: String
    var updatedAt: Date
    var submittedAt: Date?
    var gradedAt: Date?
    var markedBySubjectID: String?
    var markedByDisplayName: String?
    var overallFeedback: String

    init(
        subjectID: String,
        candidateDisplayName: String,
        courseID: String,
        assignmentID: String,
        draftMarkdown: String = "",
        status: StudySubmissionStatus = .draft,
        updatedAt: Date = .now
    ) {
        self.recordID = "\(subjectID)::\(assignmentID)"
        self.subjectID = subjectID
        self.candidateDisplayName = candidateDisplayName
        self.courseID = courseID
        self.assignmentID = assignmentID
        self.draftMarkdown = draftMarkdown
        self.status = status.rawValue
        self.updatedAt = updatedAt
        self.overallFeedback = ""
    }

    var submissionStatus: StudySubmissionStatus {
        get { StudySubmissionStatus(rawValue: status) ?? .draft }
        set { status = newValue.rawValue }
    }
}

@Model
final class StudyRubricMarkRecord {
    @Attribute(.unique) var recordID: String
    var submissionRecordID: String
    var subjectID: String
    var courseID: String
    var assignmentID: String
    var criterionID: String
    var criterionTitle: String
    var level: Int
    var feedback: String
    var markedBySubjectID: String
    var updatedAt: Date

    init(
        submissionRecordID: String,
        subjectID: String,
        courseID: String,
        assignmentID: String,
        criterionID: String,
        criterionTitle: String,
        markedBySubjectID: String,
        level: Int = 0,
        feedback: String = "",
        updatedAt: Date = .now
    ) {
        self.recordID = "\(submissionRecordID)::\(criterionID)"
        self.submissionRecordID = submissionRecordID
        self.subjectID = subjectID
        self.courseID = courseID
        self.assignmentID = assignmentID
        self.criterionID = criterionID
        self.criterionTitle = criterionTitle
        self.level = level
        self.feedback = feedback
        self.markedBySubjectID = markedBySubjectID
        self.updatedAt = updatedAt
    }
}

@Model
final class StudyExamSubmissionRecord {
    @Attribute(.unique) var recordID: String
    var attemptID: String
    var subjectID: String
    var candidateDisplayName: String
    var courseID: String
    var assessmentID: String
    var title: String
    var questionIDs: [String]
    var questionCodes: [String]
    var prompts: [String]
    var responses: [String]
    var pointValues: [Int]
    var submittedAt: Date
    var status: String
    var gradedAt: Date?
    var markedBySubjectID: String?
    var markedByDisplayName: String?
    var overallFeedback: String

    init(
        attemptID: UUID,
        subjectID: String,
        candidateDisplayName: String,
        courseID: String,
        assessmentID: String,
        title: String,
        questionIDs: [String],
        questionCodes: [String],
        prompts: [String],
        responses: [String],
        pointValues: [Int],
        submittedAt: Date = .now
    ) {
        self.recordID = attemptID.uuidString
        self.attemptID = attemptID.uuidString
        self.subjectID = subjectID
        self.candidateDisplayName = candidateDisplayName
        self.courseID = courseID
        self.assessmentID = assessmentID
        self.title = title
        self.questionIDs = questionIDs
        self.questionCodes = questionCodes
        self.prompts = prompts
        self.responses = responses
        self.pointValues = pointValues
        self.submittedAt = submittedAt
        self.status = StudySubmissionStatus.submitted.rawValue
        self.overallFeedback = ""
    }

    var submissionStatus: StudySubmissionStatus {
        get { StudySubmissionStatus(rawValue: status) ?? .submitted }
        set { status = newValue.rawValue }
    }
}

@Model
final class StudyExamQuestionMarkRecord {
    @Attribute(.unique) var recordID: String
    var examSubmissionID: String
    var questionID: String
    var questionCode: String
    var maxPoints: Int
    var awardedPoints: Double
    var feedback: String
    var markedBySubjectID: String
    var updatedAt: Date

    init(
        examSubmissionID: String,
        questionID: String,
        questionCode: String,
        maxPoints: Int,
        markedBySubjectID: String,
        awardedPoints: Double = 0,
        feedback: String = "",
        updatedAt: Date = .now
    ) {
        self.recordID = "\(examSubmissionID)::\(questionID)"
        self.examSubmissionID = examSubmissionID
        self.questionID = questionID
        self.questionCode = questionCode
        self.maxPoints = maxPoints
        self.awardedPoints = awardedPoints
        self.feedback = feedback
        self.markedBySubjectID = markedBySubjectID
        self.updatedAt = updatedAt
    }
}

@Model
final class StudyAchievementRecord {
    @Attribute(.unique) var recordID: String
    var subjectID: String
    var achievementID: String
    var title: String
    var detail: String
    var awardedAt: Date

    init(subjectID: String, achievementID: String, title: String, detail: String, awardedAt: Date = .now) {
        self.recordID = "\(subjectID)::\(achievementID)"
        self.subjectID = subjectID
        self.achievementID = achievementID
        self.title = title
        self.detail = detail
        self.awardedAt = awardedAt
    }
}

@MainActor
enum StudyLocalDataEraser {
    static func erase(subjectID: String, from modelContext: ModelContext) throws {
        let courseProgress = try modelContext.fetch(FetchDescriptor<StudyCourseProgressRecord>(
            predicate: #Predicate { $0.subjectID == subjectID }
        ))
        let learningEvents = try modelContext.fetch(FetchDescriptor<StudyLearningEventRecord>(
            predicate: #Predicate { $0.subjectID == subjectID }
        ))
        let savedContent = try modelContext.fetch(FetchDescriptor<StudySavedContentRecord>(
            predicate: #Predicate { $0.subjectID == subjectID }
        ))
        let assignmentSubmissions = try modelContext.fetch(FetchDescriptor<StudyAssignmentSubmissionRecord>(
            predicate: #Predicate { $0.subjectID == subjectID }
        ))
        let rubricMarks = try modelContext.fetch(FetchDescriptor<StudyRubricMarkRecord>(
            predicate: #Predicate { $0.subjectID == subjectID }
        ))
        let examSubmissions = try modelContext.fetch(FetchDescriptor<StudyExamSubmissionRecord>(
            predicate: #Predicate { $0.subjectID == subjectID }
        ))
        let examSubmissionIDs = Set(examSubmissions.map(\.recordID))
        let examMarks = try modelContext.fetch(FetchDescriptor<StudyExamQuestionMarkRecord>())
            .filter { examSubmissionIDs.contains($0.examSubmissionID) }
        let achievements = try modelContext.fetch(FetchDescriptor<StudyAchievementRecord>(
            predicate: #Predicate { $0.subjectID == subjectID }
        ))

        courseProgress.forEach(modelContext.delete)
        learningEvents.forEach(modelContext.delete)
        savedContent.forEach(modelContext.delete)
        assignmentSubmissions.forEach(modelContext.delete)
        rubricMarks.forEach(modelContext.delete)
        examMarks.forEach(modelContext.delete)
        examSubmissions.forEach(modelContext.delete)
        achievements.forEach(modelContext.delete)
        try modelContext.save()
    }
}

enum StudyLearningEventKind: String, Sendable {
    case lessonCompleted
    case moduleQuizSubmitted
    case exerciseCompleted
    case dailyQuizSubmitted
    case reviewCompleted
    case finalSubmitted
    case courseCompleted

    var points: Int {
        switch self {
        case .lessonCompleted: 10
        case .moduleQuizSubmitted: 15
        case .exerciseCompleted: 20
        case .dailyQuizSubmitted: 5
        case .reviewCompleted: 5
        case .finalSubmitted: 30
        case .courseCompleted: 100
        }
    }
}

enum StudyLearningProgress {
    struct LessonDestination: Equatable, Sendable {
        let moduleID: String
        let moduleNumber: Int
        let moduleTitle: String
        let lessonID: String
        let lessonTitle: String
    }

    struct SectionDestination: Equatable, Sendable, Identifiable {
        let moduleID: String
        let moduleNumber: Int
        let moduleTitle: String
        let lessonID: String
        let lessonTitle: String
        let blockID: String
        let blockTitle: String
        let sectionNumber: Int
        let sectionCount: Int
        let isRequired: Bool

        var id: String { blockID }
    }

    static func fraction(for course: StudyCourse, completedLessonIDs: Set<String>) -> Double {
        let requiredLessons = course.modules.flatMap(\.lessons).filter { lesson in
            !lesson.blocks.isEmpty || course.publicationStatus == .published
        }
        guard !requiredLessons.isEmpty else { return 0 }
        let completed = requiredLessons.lazy.filter { completedLessonIDs.contains($0.id) }.count
        return Double(completed) / Double(requiredLessons.count)
    }

    /// Section-aware course completion. A lesson completed by an earlier app
    /// version counts all of its authored sections as complete.
    static func fraction(
        for course: StudyCourse,
        completedLessonIDs: Set<String>,
        completedRequiredBlockIDs: Set<String>
    ) -> Double {
        let requiredSections = sectionDestinations(for: course).filter(\.isRequired)
        guard !requiredSections.isEmpty else {
            return fraction(for: course, completedLessonIDs: completedLessonIDs)
        }
        let completed = requiredSections.lazy.filter {
            isSectionCompleted(
                $0,
                completedLessonIDs: completedLessonIDs,
                completedRequiredBlockIDs: completedRequiredBlockIDs
            )
        }.count
        return Double(completed) / Double(requiredSections.count)
    }

    static func sectionDestinations(for course: StudyCourse) -> [SectionDestination] {
        var destinations: [SectionDestination] = []

        for (moduleIndex, module) in course.modules.enumerated() {
            let sectionCount = module.lessons.reduce(into: 0) { count, lesson in
                count += lesson.blocks.lazy.filter { $0.kind == .lessonContent }.count
            }
            var sectionIndex = 0

            for lesson in module.lessons {
                for block in lesson.blocks where block.kind == .lessonContent {
                    sectionIndex += 1
                    destinations.append(SectionDestination(
                        moduleID: module.id,
                        moduleNumber: moduleIndex + 1,
                        moduleTitle: module.title,
                        lessonID: lesson.id,
                        lessonTitle: lesson.title,
                        blockID: block.id,
                        blockTitle: block.title,
                        sectionNumber: sectionIndex,
                        sectionCount: sectionCount,
                        isRequired: block.requirement == .required
                    ))
                }
            }
        }

        return destinations
    }

    static func firstSection(for course: StudyCourse) -> SectionDestination? {
        sectionDestinations(for: course).first
    }

    static func section(
        in course: StudyCourse,
        blockID: String
    ) -> SectionDestination? {
        sectionDestinations(for: course).first { $0.blockID == blockID }
    }

    static func nextSection(
        for course: StudyCourse,
        completedLessonIDs: Set<String>,
        completedRequiredBlockIDs: Set<String>
    ) -> SectionDestination? {
        sectionDestinations(for: course).first {
            !isSectionCompleted(
                $0,
                completedLessonIDs: completedLessonIDs,
                completedRequiredBlockIDs: completedRequiredBlockIDs
            )
        }
    }

    static func previousSection(
        in course: StudyCourse,
        before blockID: String
    ) -> SectionDestination? {
        let destinations = sectionDestinations(for: course)
        guard let index = destinations.firstIndex(where: { $0.blockID == blockID }), index > 0 else {
            return nil
        }
        return destinations[index - 1]
    }

    static func nextSection(
        in course: StudyCourse,
        after blockID: String
    ) -> SectionDestination? {
        let destinations = sectionDestinations(for: course)
        guard let index = destinations.firstIndex(where: { $0.blockID == blockID }),
              destinations.indices.contains(index + 1) else {
            return nil
        }
        return destinations[index + 1]
    }

    static func isSectionCompleted(
        _ destination: SectionDestination,
        completedLessonIDs: Set<String>,
        completedRequiredBlockIDs: Set<String>
    ) -> Bool {
        completedLessonIDs.contains(destination.lessonID)
            || completedRequiredBlockIDs.contains(destination.blockID)
    }

    static func requiredSectionBlockIDs(in lesson: StudyLesson) -> [String] {
        lesson.blocks.compactMap { block in
            guard block.kind == .lessonContent, block.requirement == .required else { return nil }
            return block.id
        }
    }

    static func firstLesson(for course: StudyCourse) -> LessonDestination? {
        for (moduleIndex, module) in course.modules.enumerated() {
            guard let lesson = module.lessons.first else { continue }
            return LessonDestination(
                moduleID: module.id,
                moduleNumber: moduleIndex + 1,
                moduleTitle: module.title,
                lessonID: lesson.id,
                lessonTitle: lesson.title
            )
        }
        return nil
    }

    static func nextLesson(
        for course: StudyCourse,
        completedLessonIDs: Set<String>
    ) -> LessonDestination? {
        for (moduleIndex, module) in course.modules.enumerated() {
            guard let lesson = module.lessons.first(where: { !completedLessonIDs.contains($0.id) }) else {
                continue
            }
            return LessonDestination(
                moduleID: module.id,
                moduleNumber: moduleIndex + 1,
                moduleTitle: module.title,
                lessonID: lesson.id,
                lessonTitle: lesson.title
            )
        }
        return nil
    }

    static func eventID(
        subjectID: String,
        kind: StudyLearningEventKind,
        contentID: String,
        version: String? = nil,
        day: Date? = nil,
        calendar: Calendar = .current
    ) -> String {
        var parts = [subjectID, kind.rawValue, contentID, version ?? "-"]
        if let day {
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            parts.append("\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)")
        }
        return parts.joined(separator: "::")
    }
}

enum StudyAcademicRolePolicy {
    static func canGrade(profile: Profile?) -> Bool {
        if profile?.isAdmin == true { return true }
        let role = profile?.role?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["admin", "examiner", "teacher", "instructor"].contains(role)
    }
}

struct StudyLearningProgressSnapshot: Sendable {
    struct Award: Identifiable, Sendable {
        let id: String
        let title: String
        let detail: String
    }

    let totalXP: Int
    let currentStreak: Int
    let longestStreak: Int
    let achievements: [Award]

    static func make(
        events: [StudyLearningEventRecord],
        subjectID: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> StudyLearningProgressSnapshot {
        let mine = events.filter { $0.subjectID == subjectID }
        let totalXP = mine.reduce(0) { $0 + $1.points }
        let days = Set(mine.map { calendar.startOfDay(for: $0.occurredAt) })
        let today = calendar.startOfDay(for: now)
        let start = days.contains(today) ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        var current = 0
        var cursor = start
        while days.contains(cursor) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        var longest = 0
        var run = 0
        var prior: Date?
        for day in days.sorted() {
            if let prior, calendar.dateComponents([.day], from: prior, to: day).day == 1 {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            prior = day
        }

        var awards: [Award] = []
        if mine.contains(where: { $0.kind == StudyLearningEventKind.lessonCompleted.rawValue }) {
            awards.append(Award(id: "first-section", title: "First section", detail: "Completed a required course section."))
        }
        if mine.contains(where: { $0.kind == StudyLearningEventKind.moduleQuizSubmitted.rawValue }) {
            awards.append(Award(id: "first-quiz", title: "First module quiz", detail: "Submitted a course-linked module quiz."))
        }
        if mine.contains(where: { $0.kind == StudyLearningEventKind.courseCompleted.rawValue }) {
            awards.append(Award(id: "course-complete", title: "Course reader", detail: "Completed all required course reading."))
        }
        if longest >= 7 {
            awards.append(Award(id: "seven-day-streak", title: "Seven-day rhythm", detail: "Learned on seven consecutive days."))
        }
        for threshold in [100, 500, 1_000] where totalXP >= threshold {
            awards.append(Award(id: "xp-\(threshold)", title: "\(threshold) learning XP", detail: "Earned through meaningful learning tasks."))
        }
        return StudyLearningProgressSnapshot(totalXP: totalXP, currentStreak: current, longestStreak: longest, achievements: awards)
    }
}

struct StudyCourseGradeSnapshot: Sendable {
    struct Component: Identifiable, Sendable {
        let id: String
        let title: String
        let weightPercent: Int
        let scorePercent: Double?
        let status: String
        var weightedPoints: Double { (scorePercent ?? 0) * Double(weightPercent) / 100 }
    }

    let components: [Component]
    let currentAveragePercent: Double?
    let overallPercent: Double?
    let gradedWeightPercent: Int
    let submittedWeightPercent: Int
    let readingCompletion: Double
    let passThresholdPercent: Double

    var allAssessmentMarked: Bool { gradedWeightPercent == components.reduce(0) { $0 + $1.weightPercent } }
    var academicResult: String {
        guard let overallPercent else { return "Result pending" }
        return overallPercent >= passThresholdPercent ? "Pass" : "Not passed"
    }
}

enum StudyCourseGradebook {
    static let passThresholdPercent = 60.0

    static func assignmentPercent(
        submission: StudyAssignmentSubmissionRecord?,
        criteria: [StudyAssignmentRubricCriterion],
        marks: [StudyRubricMarkRecord]
    ) -> Double? {
        guard submission?.submissionStatus == .graded, !criteria.isEmpty else { return nil }
        let values = criteria.compactMap { criterion in
            marks.first { $0.submissionRecordID == submission?.recordID && $0.criterionID == criterion.id }?.level
        }
        guard values.count == criteria.count, values.allSatisfy({ (1...4).contains($0) }) else { return nil }
        return Double(values.reduce(0, +)) / Double(criteria.count * 4) * 100
    }

    static func examPercent(
        submission: StudyExamSubmissionRecord?,
        marks: [StudyExamQuestionMarkRecord]
    ) -> Double? {
        guard submission?.submissionStatus == .graded, let submission else { return nil }
        let relevant = marks.filter { $0.examSubmissionID == submission.recordID }
        let possible = relevant.reduce(0) { $0 + $1.maxPoints }
        guard possible > 0 else { return nil }
        return relevant.reduce(0) { $0 + $1.awardedPoints } / Double(possible) * 100
    }

    static func make(
        course: StudyCourse,
        assignments: [StudyAssignment],
        assignmentSubmissions: [StudyAssignmentSubmissionRecord],
        rubricMarks: [StudyRubricMarkRecord],
        finalAssessment: StudyCourseAssessmentBlueprint?,
        examSubmissions: [StudyExamSubmissionRecord],
        examMarks: [StudyExamQuestionMarkRecord],
        subjectID: String,
        readingCompletion: Double
    ) -> StudyCourseGradeSnapshot {
        var components = assignments.map { assignment -> StudyCourseGradeSnapshot.Component in
            let submission = assignmentSubmissions.first { $0.subjectID == subjectID && $0.assignmentID == assignment.id }
            return .init(
                id: assignment.id,
                title: "\(assignment.code) · \(assignment.title)",
                weightPercent: assignment.weightPercent,
                scorePercent: assignmentPercent(submission: submission, criteria: assignment.rubricCriteria, marks: rubricMarks),
                status: submission?.submissionStatus.title ?? "Not started"
            )
        }
        if let finalAssessment {
            let submission = examSubmissions
                .filter { $0.subjectID == subjectID && $0.assessmentID == finalAssessment.id }
                .max { $0.submittedAt < $1.submittedAt }
            components.append(.init(
                id: finalAssessment.id,
                title: finalAssessment.title,
                weightPercent: finalAssessment.courseWeightPercent ?? 0,
                scorePercent: examPercent(submission: submission, marks: examMarks),
                status: submission?.submissionStatus.title ?? "Not attempted"
            ))
        }
        let graded = components.filter { $0.scorePercent != nil }
        let gradedWeight = graded.reduce(0) { $0 + $1.weightPercent }
        let submittedWeight = components.filter { $0.status != "Not started" && $0.status != "Not attempted" }.reduce(0) { $0 + $1.weightPercent }
        let weighted = graded.reduce(0) { $0 + $1.weightedPoints }
        let current = gradedWeight > 0 ? weighted / Double(gradedWeight) * 100 : nil
        let totalWeight = components.reduce(0) { $0 + $1.weightPercent }
        let overall = gradedWeight == totalWeight && totalWeight > 0 ? weighted / Double(totalWeight) * 100 : nil
        return StudyCourseGradeSnapshot(
            components: components,
            currentAveragePercent: current,
            overallPercent: overall,
            gradedWeightPercent: gradedWeight,
            submittedWeightPercent: submittedWeight,
            readingCompletion: readingCompletion,
            passThresholdPercent: passThresholdPercent
        )
    }
}
