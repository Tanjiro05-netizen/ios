import Foundation
import Observation

enum StudyCourseType: String, Codable, CaseIterable, Identifiable, Sendable {
    case classicalReading
    case survey
    case seminar
    case examPreparation
    case videoSupported

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classicalReading: "Classical reading"
        case .survey: "Survey"
        case .seminar: "Seminar"
        case .examPreparation: "Exam preparation"
        case .videoSupported: "Video supported"
        }
    }
}

enum StudyInteractionIntensity: String, Codable, Sendable {
    case calm
    case balanced
    case intensive
}

enum StudyContentRequirement: String, Codable, Sendable {
    case required
    case recommended
    case optional
}

enum StudyPublicationStatus: String, Codable, Sendable {
    case preview
    case draftNeedsReview
    case published
    case archived
}

enum StudyCourseMode: String, Codable, Sendable {
    case selfPaced
    case cohort
}

enum StudyCourseDocumentKind: String, Hashable, Sendable {
    case overview
    case introduction
    case conclusion
    case bibliography
    case completeCourse
    case assignmentHandbook
    case formativeSolutions

    var title: String {
        switch self {
        case .overview: "Course Overview"
        case .introduction: "Course Introduction"
        case .conclusion: "Course Conclusion"
        case .bibliography: "Bibliography"
        case .completeCourse: "Complete Native Course Edition"
        case .assignmentHandbook: "Formal Assignments Handbook"
        case .formativeSolutions: "Formative Solutions and Commentary"
        }
    }
}

struct StudyContributor: Codable, Hashable, Sendable {
    let name: String
    let role: String
}

struct StudyCoursePackage: Codable, Identifiable, Sendable {
    let schemaVersion: Int
    let packageID: String
    let contentVersion: String
    let locale: String
    let minimumAppVersion: String
    let courses: [StudyCourse]
    let studyGuides: [StudyGuide]
    let readingGuides: [StudyReadingGuide]
    let primaryReadings: [StudyPrimaryReading]
    let readingLists: [StudyReadingList]
    let videos: [StudyEducationalVideo]
    let exerciseSets: [StudyExerciseSet]
    let assessments: [StudyCourseAssessmentBlueprint]
    let glossaryTerms: [StudyGlossaryTerm]
    let bibliographySources: [StudyBibliographicSource]
    var questions: [StudyQuestion]? = nil
    var assignments: [StudyAssignment]? = nil
    var learningPaths: [StudyLearningPath]? = nil
    var assets: [StudyCourseAsset]? = nil
    var restrictedResources: [StudyRestrictedCourseResource]? = nil

    var id: String { "\(packageID)@\(contentVersion)" }
}

struct StudyCourse: Codable, Identifiable, Sendable {
    let id: String
    let contentVersion: String
    let title: String
    let subtitle: String
    let summary: String
    let type: StudyCourseType
    let interactionIntensity: StudyInteractionIntensity
    let mode: StudyCourseMode
    let publicationStatus: StudyPublicationStatus
    let estimatedHours: Int
    let prerequisites: [String]
    let outcomes: [String]
    let contributors: [StudyContributor]
    let assessmentSummary: String
    let modules: [StudyCourseModule]
    var level: String? = nil
    var primarySubject: String? = nil
    var contentMode: String? = nil
    var programmePosition: String? = nil
    var estimatedWorkload: String? = nil
    var deliveryDescription: String? = nil
    var introductionMarkdown: String? = nil
    var conclusionMarkdown: String? = nil
    var overviewMarkdown: String? = nil
    var bibliographyMarkdown: String? = nil
    var studyGuideID: String? = nil
    var readingGuideID: String? = nil
    var assignmentIDs: [String]? = nil
    var finalAssessmentID: String? = nil
    var assetIDs: [String]? = nil
    var learningPathIDs: [String]? = nil
    var recommendedCourseIDs: [String]? = nil
    var academicReviewStatus: String? = nil
    var rightsStatus: String? = nil
    var sourceTextStatus: String? = nil
    var sourceMetadata: StudyCourseSourceMetadata? = nil
    var courseSourceMarkdown: String? = nil
    var assignmentHandbookMarkdown: String? = nil
    var formativeSolutionsMarkdown: String? = nil
}

struct StudyCourseModule: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let estimatedMinutes: Int
    let lessons: [StudyLesson]
    let moduleQuizID: String?
    var assignmentIDs: [String]? = nil
    var sourceVersion: String? = nil
    var sourceStatus: String? = nil
}

struct StudyLesson: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let estimatedMinutes: Int
    let blocks: [StudyLessonBlock]
}

enum StudyLessonBlockKind: String, Codable, Sendable {
    case lessonContent
    case primaryReading
    case studyGuide
    case readingGuide
    case video
    case exercise
    case lessonCheck
    case moduleQuiz
}

struct StudyLessonBlock: Codable, Identifiable, Sendable {
    let id: String
    let kind: StudyLessonBlockKind
    let title: String
    let summary: String
    let requirement: StudyContentRequirement
    let referencedContentID: String?
    let bodyMarkdown: String?
}

struct StudyGuide: Codable, Identifiable, Sendable {
    let id: String
    let contentVersion: String
    let title: String
    let purpose: String
    let outcomes: [String]
    let essentialQuestions: [String]
    let sections: [StudyGuideSection]
    let glossaryTermIDs: [String]
    let bibliographySourceIDs: [String]
}

struct StudyGuideSection: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let bodyMarkdown: String
}

struct StudyReadingGuide: Codable, Identifiable, Sendable {
    let id: String
    let contentVersion: String
    let title: String
    let workTitle: String
    let author: String
    let editionNote: String
    let purpose: String
    let context: String
    let chunks: [StudyReadingChunk]
    let furtherReading: [String]
    var canonicalStudyGuideID: String? = nil
}

struct StudyReadingChunk: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let anchorLabel: String
    let estimatedMinutes: Int
    let terms: [String]
    let prompts: [String]
    let libraryBookID: String?
    var moduleID: String? = nil
    var bodyMarkdown: String? = nil
}

struct StudyPrimaryReading: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let author: String
    let editionNote: String
    let rightsNote: String
    let libraryBookID: String?
    let externalURL: URL?
}

struct StudyReadingList: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let requiredReadingIDs: [String]
    let recommendedReadingIDs: [String]
}

struct StudyEducationalVideo: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let durationSeconds: Int
    let language: String
    let captionLanguages: [String]
    let transcriptMarkdown: String?
    let mediaURL: URL?
}

enum StudyExerciseKind: String, Codable, Sendable {
    case guidedExercise
    case passageAnalysis
    case argumentReconstruction
    case matching
    case sequencing
    case conceptComparison
    case shortAnswer
    case sourceIdentification
    case misconceptionCorrection
    case contemporaryApplication
    case documentAnalysis
}

struct StudyExerciseSet: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let requirement: StudyContentRequirement
    let exercises: [StudyExercise]
}

struct StudyExercise: Codable, Identifiable, Sendable {
    let id: String
    let kind: StudyExerciseKind
    let promptMarkdown: String
    let sourceContentIDs: [String]
    let rubricMarkdown: String?
    let relatedLessonIDs: [String]
    var title: String? = nil
    var instructions: [String]? = nil
    var recommendedResponse: String? = nil
    var solutionMarkdown: String? = nil
    var isGraded: Bool? = nil
    var sourceStatus: String? = nil
}

enum StudyCourseAssessmentKind: String, Codable, Sendable {
    case lessonCheck
    case moduleQuiz
    case practiceTest
    case courseFinal
    case mockExam
    case fullScaleExam
}

struct StudyCourseAssessmentBlueprint: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let kind: StudyCourseAssessmentKind
    let questionIDs: [String]
    let requestedQuestionCount: Int
    let durationSeconds: Int?
    let gradeRole: StudyAssessmentGradeRole
    let writtenSections: [StudyWrittenAssessmentSection]
    let totalPoints: Int
    var courseID: String? = nil
    var moduleID: String? = nil
    var recommendedTimeMinimumMinutes: Int? = nil
    var recommendedTimeMaximumMinutes: Int? = nil
    var courseWeightPercent: Int? = nil
    var permittedMaterials: String? = nil
    var responsePolicy: [String: String]? = nil
    var examSections: [StudyCourseExamSection]? = nil
    var sourceAssetID: String? = nil
    var restrictedMarkingGuideID: String? = nil
    var sourceStatus: String? = nil
    var sourceMarkdown: String? = nil
    var candidateInstructionsMarkdown: String? = nil
    var candidateDeclarationMarkdown: String? = nil

    func sessionPlan(courseID: String, moduleID: String? = nil, lessonID: String? = nil) -> StudySessionPlan {
        let sessionKind: StudySessionKind = switch kind {
        case .courseFinal, .mockExam, .fullScaleExam: .practiceExam
        case .lessonCheck, .moduleQuiz, .practiceTest: .domainPractice
        }
        return StudySessionPlan(
            id: id,
            kind: sessionKind,
            title: title,
            requestedItemCount: questionIDs.isEmpty ? requestedQuestionCount : questionIDs.count,
            domain: nil,
            requestedQuestionIDs: questionIDs,
            feedbackPolicy: sessionKind == .practiceExam ? .afterSubmission : .immediate,
            durationSeconds: durationSeconds,
            affectsItemMastery: false,
            context: StudyAssessmentContext(
                source: kind == .fullScaleExam || kind == .courseFinal || kind == .mockExam ? .exam : .course,
                courseID: courseID,
                moduleID: moduleID,
                lessonID: lessonID,
                assessmentID: id,
                gradeRole: gradeRole
            )
        )
    }
}

struct StudyCourseExamSection: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let responsePolicy: String
    let questions: [StudyCourseExamQuestion]
    var instructionsMarkdown: String? = nil
}

struct StudyCourseExamQuestion: Codable, Identifiable, Sendable {
    let id: String
    let code: String
    let title: String
    let promptMarkdown: String
    let points: Int
    var responseQuestionID: String? = nil
}

struct StudyAssignment: Codable, Identifiable, Sendable {
    let id: String
    let courseID: String
    let contentVersion: String
    let code: String
    let title: String
    let afterModuleNumber: Int
    let weightPercent: Int
    let mode: String
    let expectedExtent: String
    let bodyMarkdown: String
    let sourceAssetID: String?
    let sourceStatus: String
    var rubricCriteria: [StudyAssignmentRubricCriterion] = []
}

struct StudyAssignmentRubricCriterion: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let excellent: String
    let competent: String
    let developing: String
    let insufficient: String
}

struct StudyLearningPath: Codable, Identifiable, Sendable {
    let id: String
    let contentVersion: String
    let title: String
    let language: String
    let sourceStatus: String
    let courses: [StudyLearningPathCourse]
    let recommendedNext: [StudyLearningPathRecommendation]
}

struct StudyLearningPathCourse: Codable, Identifiable, Sendable {
    var id: String { courseID }
    let courseID: String
    let order: Int
    let isRequired: Bool
}

struct StudyLearningPathRecommendation: Codable, Identifiable, Sendable {
    var id: String { courseID }
    let courseID: String
    let title: String
    let status: String
}

enum StudyCourseAssetKind: String, Codable, Sendable {
    case coursebook
    case assignmentHandbook
    case examinationPaper
}

enum StudyCourseAssetAvailability: String, Codable, Sendable {
    case immediate
    case afterCourseCompletion
}

struct StudyCourseAsset: Codable, Identifiable, Sendable {
    let id: String
    let courseID: String
    let title: String
    let kind: StudyCourseAssetKind
    let resourceName: String
    let isDownloadable: Bool
    let sourceStatus: String
    let mimeType: String
    let sha256: String
    let byteCount: Int
    let availability: StudyCourseAssetAvailability
    let containsAnswerMaterial: Bool
}

enum StudyRestrictedResourceKind: String, Codable, Sendable {
    case markingGuide
}

enum StudyRestrictedAccessPolicy: String, Codable, Sendable {
    case examinerOnly
}

struct StudyRestrictedCourseResource: Codable, Identifiable, Sendable {
    let id: String
    let courseID: String
    let title: String
    let kind: StudyRestrictedResourceKind
    let accessPolicy: StudyRestrictedAccessPolicy
    let sourceFilename: String
    let sourceStatus: String
    let sha256: String
    let byteCount: Int
    var companionSourceFilename: String? = nil
    var companionSHA256: String? = nil
    var companionByteCount: Int? = nil
}

struct StudyCourseSourceMetadata: Codable, Sendable {
    let canonicalEditorialSource: String
    let designedCoursebook: String
    let assignmentSource: String
    let examSource: String
    let markingSource: String
    let primaryTextCitationsEmbeddedInCourse: Bool
    let rightsReviewRequired: Bool
    let quotationVerificationRequired: Bool
    let notes: [String]
    var structuralValidationPassed: Bool? = nil
    var academicVerificationStatus: String? = nil
    var requiredHumanReview: [String]? = nil
}

struct StudyWrittenAssessmentSection: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let promptMarkdown: String
    let points: Int
    let rubricMarkdown: String
}

struct StudyGlossaryTerm: Codable, Identifiable, Sendable {
    let id: String
    let term: String
    let definitionMarkdown: String
    let sourceIDs: [String]
    let relatedTermIDs: [String]
    var displayTitle: String? = nil
    var legacySourceID: String? = nil
}

struct StudyBibliographicSource: Codable, Identifiable, Sendable {
    let id: String
    let citation: String
    let url: URL?
    let note: String?
}

struct StudyPackageValidationIssue: Equatable, Sendable {
    let path: String
    let message: String
}

enum StudyCoursePackageValidator {
    static func validate(_ package: StudyCoursePackage) -> [StudyPackageValidationIssue] {
        var issues: [StudyPackageValidationIssue] = []
        var identifiers = Set<String>()
        let questions = package.questions ?? []
        let assignments = package.assignments ?? []
        let learningPaths = package.learningPaths ?? []
        let assets = package.assets ?? []
        let restrictedResources = package.restrictedResources ?? []

        func register(_ id: String, path: String) {
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                issues.append(.init(path: path, message: "Identifier cannot be empty."))
                return
            }
            guard identifiers.insert(id).inserted else {
                issues.append(.init(path: path, message: "Duplicate canonical identifier: \(id)"))
                return
            }
        }

        register(package.packageID, path: "packageID")
        for course in package.courses {
            register(course.id, path: "courses.\(course.id)")
            for module in course.modules {
                register(module.id, path: "courses.\(course.id).modules.\(module.id)")
                for lesson in module.lessons {
                    register(lesson.id, path: "courses.\(course.id).modules.\(module.id).lessons.\(lesson.id)")
                    for block in lesson.blocks {
                        register(block.id, path: "lessons.\(lesson.id).blocks.\(block.id)")
                    }
                }
            }
        }
        for guide in package.studyGuides {
            register(guide.id, path: "studyGuides.\(guide.id)")
        }
        for guide in package.readingGuides {
            register(guide.id, path: "readingGuides.\(guide.id)")
            for chunk in guide.chunks {
                register(chunk.id, path: "readingGuides.\(guide.id).chunks.\(chunk.id)")
            }
        }

        for reading in package.primaryReadings { register(reading.id, path: "primaryReadings.\(reading.id)") }
        for list in package.readingLists { register(list.id, path: "readingLists.\(list.id)") }
        for video in package.videos { register(video.id, path: "videos.\(video.id)") }
        for set in package.exerciseSets {
            register(set.id, path: "exerciseSets.\(set.id)")
            for exercise in set.exercises { register(exercise.id, path: "exerciseSets.\(set.id).\(exercise.id)") }
        }
        for assessment in package.assessments {
            register(assessment.id, path: "assessments.\(assessment.id)")
            for section in assessment.examSections ?? [] {
                register(section.id, path: "assessments.\(assessment.id).examSections.\(section.id)")
                for question in section.questions {
                    register(question.id, path: "assessments.\(assessment.id).examSections.\(section.id).\(question.id)")
                }
            }
        }
        for term in package.glossaryTerms { register(term.id, path: "glossaryTerms.\(term.id)") }
        for source in package.bibliographySources { register(source.id, path: "bibliographySources.\(source.id)") }
        for question in questions { register(question.id, path: "questions.\(question.id)") }
        for assignment in assignments { register(assignment.id, path: "assignments.\(assignment.id)") }
        for path in learningPaths { register(path.id, path: "learningPaths.\(path.id)") }
        for asset in assets { register(asset.id, path: "assets.\(asset.id)") }
        for resource in restrictedResources {
            register(resource.id, path: "restrictedResources.\(resource.id)")
        }

        let studyGuideIDs = Set(package.studyGuides.map(\.id))
        let readingGuideIDs = Set(package.readingGuides.map(\.id))
        let guideIDs = studyGuideIDs.union(readingGuideIDs)
        let readingIDs = Set(package.primaryReadings.map(\.id))
        let videoIDs = Set(package.videos.map(\.id))
        let exerciseIDs = Set(package.exerciseSets.map(\.id))
        let assessmentIDs = Set(package.assessments.map(\.id))
        let questionIDs = Set(questions.map(\.id))
        let assignmentIDs = Set(assignments.map(\.id))
        let assetIDs = Set(assets.map(\.id))
        let restrictedResourceIDs = Set(restrictedResources.map(\.id))
        let courseIDs = Set(package.courses.map(\.id))
        let learningPathIDs = Set(learningPaths.map(\.id))
        let moduleIDs = Set(package.courses.flatMap(\.modules).map(\.id))
        let lessonIDs = Set(package.courses.flatMap(\.modules).flatMap(\.lessons).map(\.id))
        let blockIDs = Set(package.courses.flatMap(\.modules).flatMap(\.lessons).flatMap(\.blocks).map(\.id))
        let glossaryTermIDs = Set(package.glossaryTerms.map(\.id))
        let bibliographySourceIDs = Set(package.bibliographySources.map(\.id))

        for guide in package.readingGuides {
            if let canonicalID = guide.canonicalStudyGuideID,
               !studyGuideIDs.contains(canonicalID) {
                issues.append(.init(path: "readingGuides.\(guide.id).canonicalStudyGuideID", message: "Canonical guide reference does not resolve."))
            }
            for chunk in guide.chunks {
                if let moduleID = chunk.moduleID, !moduleIDs.contains(moduleID) {
                    issues.append(.init(path: "readingGuides.\(guide.id).chunks.\(chunk.id).moduleID", message: "Module reference \(moduleID) does not resolve."))
                }
                if chunk.bodyMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                    issues.append(.init(path: "readingGuides.\(guide.id).chunks.\(chunk.id).bodyMarkdown", message: "Native reading-guide content cannot be blank."))
                }
            }
        }
        for guide in package.studyGuides {
            for termID in guide.glossaryTermIDs where !glossaryTermIDs.contains(termID) {
                issues.append(.init(path: "studyGuides.\(guide.id).glossaryTermIDs", message: "Glossary reference \(termID) does not resolve."))
            }
            for sourceID in guide.bibliographySourceIDs where !bibliographySourceIDs.contains(sourceID) {
                issues.append(.init(path: "studyGuides.\(guide.id).bibliographySourceIDs", message: "Bibliography reference \(sourceID) does not resolve."))
            }
        }
        for list in package.readingLists {
            for readingID in list.requiredReadingIDs + list.recommendedReadingIDs where !readingIDs.contains(readingID) {
                issues.append(.init(path: "readingLists.\(list.id)", message: "Primary-reading reference \(readingID) does not resolve."))
            }
        }
        for set in package.exerciseSets {
            for exercise in set.exercises {
                for contentID in exercise.sourceContentIDs where !blockIDs.contains(contentID) {
                    issues.append(.init(path: "exerciseSets.\(set.id).\(exercise.id).sourceContentIDs", message: "Lesson-content reference \(contentID) does not resolve."))
                }
                for lessonID in exercise.relatedLessonIDs where !lessonIDs.contains(lessonID) {
                    issues.append(.init(path: "exerciseSets.\(set.id).\(exercise.id).relatedLessonIDs", message: "Lesson reference \(lessonID) does not resolve."))
                }
            }
        }

        for assessment in package.assessments {
            if let courseID = assessment.courseID, !courseIDs.contains(courseID) {
                issues.append(.init(path: "assessments.\(assessment.id).courseID", message: "Course reference \(courseID) does not resolve."))
            }
            if let moduleID = assessment.moduleID, !moduleIDs.contains(moduleID) {
                issues.append(.init(path: "assessments.\(assessment.id).moduleID", message: "Module reference \(moduleID) does not resolve."))
            }
            for questionID in assessment.questionIDs where !questionIDs.contains(questionID) {
                issues.append(.init(path: "assessments.\(assessment.id).questionIDs", message: "Question reference \(questionID) does not resolve."))
            }
            if let assetID = assessment.sourceAssetID, !assetIDs.contains(assetID) {
                issues.append(.init(path: "assessments.\(assessment.id).sourceAssetID", message: "Asset reference does not resolve."))
            }
            if let resourceID = assessment.restrictedMarkingGuideID,
               !restrictedResourceIDs.contains(resourceID) {
                issues.append(.init(path: "assessments.\(assessment.id).restrictedMarkingGuideID", message: "Restricted-resource reference does not resolve."))
            }
            for section in assessment.examSections ?? [] {
                if package.schemaVersion >= 3,
                   assessment.kind == .courseFinal,
                   section.instructionsMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    issues.append(.init(
                        path: "assessments.\(assessment.id).examSections.\(section.id).instructionsMarkdown",
                        message: "Course-final section instructions cannot be blank."
                    ))
                }
                for question in section.questions {
                    if let responseID = question.responseQuestionID,
                       !questionIDs.contains(responseID) {
                        issues.append(.init(
                            path: "assessments.\(assessment.id).examSections.\(section.id).\(question.id).responseQuestionID",
                            message: "Written-response question reference \(responseID) does not resolve."
                        ))
                    }
                }
            }
            if package.schemaVersion >= 3, assessment.kind == .courseFinal {
                if assessment.sourceMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    issues.append(.init(path: "assessments.\(assessment.id).sourceMarkdown", message: "The complete native candidate paper is required."))
                }
                if assessment.candidateInstructionsMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    issues.append(.init(path: "assessments.\(assessment.id).candidateInstructionsMarkdown", message: "Candidate instructions are required."))
                }
                if assessment.candidateDeclarationMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    issues.append(.init(path: "assessments.\(assessment.id).candidateDeclarationMarkdown", message: "The candidate declaration is required."))
                }
            }
        }

        for assignment in assignments {
            if !courseIDs.contains(assignment.courseID) {
                issues.append(.init(path: "assignments.\(assignment.id).courseID", message: "Course reference does not resolve."))
            }
            if let assetID = assignment.sourceAssetID, !assetIDs.contains(assetID) {
                issues.append(.init(path: "assignments.\(assignment.id).sourceAssetID", message: "Asset reference does not resolve."))
            }
        }

        for path in learningPaths {
            for entry in path.courses where !courseIDs.contains(entry.courseID) {
                issues.append(.init(path: "learningPaths.\(path.id).courses", message: "Course reference \(entry.courseID) does not resolve."))
            }
            for recommendation in path.recommendedNext
                where recommendation.status != "planned" && !courseIDs.contains(recommendation.courseID) {
                issues.append(.init(path: "learningPaths.\(path.id).recommendedNext", message: "Course reference \(recommendation.courseID) does not resolve."))
            }
        }
        for asset in assets where !courseIDs.contains(asset.courseID) {
            issues.append(.init(path: "assets.\(asset.id).courseID", message: "Course reference \(asset.courseID) does not resolve."))
        }
        for resource in restrictedResources where !courseIDs.contains(resource.courseID) {
            issues.append(.init(path: "restrictedResources.\(resource.id).courseID", message: "Course reference \(resource.courseID) does not resolve."))
        }
        for term in package.glossaryTerms {
            for sourceID in term.sourceIDs
                where !courseIDs.contains(sourceID)
                    && !guideIDs.contains(sourceID)
                    && !bibliographySourceIDs.contains(sourceID) {
                issues.append(.init(path: "glossaryTerms.\(term.id).sourceIDs", message: "Source reference \(sourceID) does not resolve."))
            }
            for relatedID in term.relatedTermIDs where !glossaryTermIDs.contains(relatedID) {
                issues.append(.init(path: "glossaryTerms.\(term.id).relatedTermIDs", message: "Related-term reference \(relatedID) does not resolve."))
            }
        }
        for question in questions where question.source.bank == .course {
            for courseID in question.courses where !courseIDs.contains(courseID) {
                issues.append(.init(path: "questions.\(question.id).courses", message: "Course reference \(courseID) does not resolve."))
            }
        }
        for course in package.courses {
            if let guideID = course.studyGuideID, !studyGuideIDs.contains(guideID) {
                issues.append(.init(path: "courses.\(course.id).studyGuideID", message: "Study-guide reference does not resolve."))
            }
            if let guideID = course.readingGuideID, !readingGuideIDs.contains(guideID) {
                issues.append(.init(path: "courses.\(course.id).readingGuideID", message: "Reading-guide reference does not resolve."))
            }
            for assignmentID in course.assignmentIDs ?? [] where !assignmentIDs.contains(assignmentID) {
                issues.append(.init(path: "courses.\(course.id).assignmentIDs", message: "Assignment reference \(assignmentID) does not resolve."))
            }
            for assetID in course.assetIDs ?? [] where !assetIDs.contains(assetID) {
                issues.append(.init(path: "courses.\(course.id).assetIDs", message: "Asset reference \(assetID) does not resolve."))
            }
            for pathID in course.learningPathIDs ?? [] where !learningPathIDs.contains(pathID) {
                issues.append(.init(path: "courses.\(course.id).learningPathIDs", message: "Learning-path reference \(pathID) does not resolve."))
            }
            for recommendedID in course.recommendedCourseIDs ?? [] where !courseIDs.contains(recommendedID) {
                issues.append(.init(path: "courses.\(course.id).recommendedCourseIDs", message: "Recommended-course reference \(recommendedID) does not resolve."))
            }
            if let finalID = course.finalAssessmentID, !assessmentIDs.contains(finalID) {
                issues.append(.init(path: "courses.\(course.id).finalAssessmentID", message: "Final-assessment reference does not resolve."))
            }
            for module in course.modules {
                if let quizID = module.moduleQuizID, !assessmentIDs.contains(quizID) {
                    issues.append(.init(path: "modules.\(module.id).moduleQuizID", message: "Assessment reference does not resolve."))
                }
                for assignmentID in module.assignmentIDs ?? [] where !assignmentIDs.contains(assignmentID) {
                    issues.append(.init(path: "modules.\(module.id).assignmentIDs", message: "Assignment reference \(assignmentID) does not resolve."))
                }
                for lesson in module.lessons {
                    for block in lesson.blocks {
                        let expectedIDs: Set<String>? = switch block.kind {
                        case .studyGuide, .readingGuide: guideIDs
                        case .primaryReading: readingIDs
                        case .video: videoIDs
                        case .exercise: exerciseIDs
                        case .lessonCheck, .moduleQuiz: assessmentIDs
                        case .lessonContent: nil
                        }
                        if let expectedIDs,
                           !(block.referencedContentID.map(expectedIDs.contains) ?? false) {
                            issues.append(.init(path: "lessons.\(lesson.id).blocks.\(block.id)", message: "Canonical content reference does not resolve."))
                        }
                    }
                }
            }
        }
        return issues
    }
}

@MainActor
@Observable
final class StudyCourseLibrary {
    private(set) var packages: [StudyCoursePackage] = []
    private(set) var loadError: String?
    private(set) var courses: [StudyCourse] = []
    private(set) var studyGuides: [StudyGuide] = []
    private(set) var readingGuides: [StudyReadingGuide] = []
    private(set) var primaryReadings: [StudyPrimaryReading] = []
    private(set) var questions: [StudyQuestion] = []
    private(set) var assignments: [StudyAssignment] = []
    private(set) var learningPaths: [StudyLearningPath] = []
    private(set) var assets: [StudyCourseAsset] = []
    private(set) var assessments: [StudyCourseAssessmentBlueprint] = []
    private(set) var exerciseSets: [StudyExerciseSet] = []
    private(set) var glossaryTerms: [StudyGlossaryTerm] = []

    @ObservationIgnored private var courseIndex: [String: StudyCourse] = [:]
    @ObservationIgnored private var studyGuideIndex: [String: StudyGuide] = [:]
    @ObservationIgnored private var readingGuideIndex: [String: StudyReadingGuide] = [:]
    @ObservationIgnored private var primaryReadingIndex: [String: StudyPrimaryReading] = [:]
    @ObservationIgnored private var assignmentIndex: [String: StudyAssignment] = [:]
    @ObservationIgnored private var learningPathIndex: [String: StudyLearningPath] = [:]
    @ObservationIgnored private var assetIndex: [String: StudyCourseAsset] = [:]
    @ObservationIgnored private var assessmentIndex: [String: StudyCourseAssessmentBlueprint] = [:]
    @ObservationIgnored private var exerciseSetIndex: [String: StudyExerciseSet] = [:]
    @ObservationIgnored private var sectionIndex: [String: [StudyLearningProgress.SectionDestination]] = [:]

    func course(id: String) -> StudyCourse? { courseIndex[id] }
    func studyGuide(id: String) -> StudyGuide? { studyGuideIndex[id] }
    func readingGuide(id: String) -> StudyReadingGuide? { readingGuideIndex[id] }
    func primaryReading(id: String) -> StudyPrimaryReading? { primaryReadingIndex[id] }
    func assignment(id: String) -> StudyAssignment? { assignmentIndex[id] }
    func learningPath(id: String) -> StudyLearningPath? { learningPathIndex[id] }
    func asset(id: String) -> StudyCourseAsset? { assetIndex[id] }
    func assessment(id: String) -> StudyCourseAssessmentBlueprint? { assessmentIndex[id] }
    func exerciseSet(id: String) -> StudyExerciseSet? { exerciseSetIndex[id] }
    func sectionDestinations(courseID: String) -> [StudyLearningProgress.SectionDestination] {
        sectionIndex[courseID] ?? []
    }

    func assetURL(id: String, bundle: Bundle = .main) -> URL? {
        guard let asset = asset(id: id) else { return nil }
        let resource = asset.resourceName as NSString
        return bundle.url(
            forResource: resource.deletingPathExtension,
            withExtension: resource.pathExtension.isEmpty ? nil : resource.pathExtension
        )
    }

    func reload(bundle: Bundle = .main, fileManager: FileManager = .default) async {
        var packageURLs = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil)?
            .filter { $0.lastPathComponent.hasSuffix(".study-course.json") } ?? []
        var directoryError: String?
        do {
            let support = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = support.appending(path: "StudyPackages", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            packageURLs += try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasSuffix(".study-course.json") }
        } catch {
            directoryError = "Installed course directory: \(error.localizedDescription)"
        }

        let result = await Task.detached(priority: .userInitiated) {
            Self.decodePackages(at: packageURLs)
        }.value
        var errors = result.errors
        if let directoryError { errors.append(directoryError) }

        // Preview packages are retained as test fixtures, but never compete with
        // real installed academic courses in the learner catalogue.
        packages = Self.latestPackages(from: result.packages.isEmpty ? StudyCoursePreview.packages : result.packages)
        rebuildIndexes()
        loadError = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    nonisolated private static func decodePackages(at urls: [URL]) -> (packages: [StudyCoursePackage], errors: [String]) {
        var packages: [StudyCoursePackage] = []
        var errors: [String] = []
        let decoder = JSONDecoder()
        for url in urls {
            do {
                let package = try decoder.decode(StudyCoursePackage.self, from: Data(contentsOf: url))
                let issues = StudyCoursePackageValidator.validate(package)
                if issues.isEmpty { packages.append(package) }
                else { errors.append("\(url.lastPathComponent): \(issues.count) validation issue(s)") }
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (packages, errors)
    }

    private func rebuildIndexes() {
        courses = Dictionary(grouping: packages.flatMap(\.courses), by: \.id)
            .compactMap { _, values in values.max(by: Self.isLowerPriority) }
            .filter { $0.publicationStatus != .archived }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        studyGuides = latestByVersion(packages.flatMap(\.studyGuides), id: \.id, version: \.contentVersion)
        readingGuides = latestByVersion(packages.flatMap(\.readingGuides), id: \.id, version: \.contentVersion)
        primaryReadings = firstByID(packages.flatMap(\.primaryReadings), id: \.id)
        questions = firstByID(packages.flatMap { $0.questions ?? [] }, id: \.id)
        assignments = firstByID(packages.flatMap { $0.assignments ?? [] }, id: \.id)
        learningPaths = firstByID(packages.flatMap { $0.learningPaths ?? [] }, id: \.id)
        assets = firstByID(packages.flatMap { $0.assets ?? [] }, id: \.id)
        assessments = firstByID(packages.flatMap(\.assessments), id: \.id)
        exerciseSets = firstByID(packages.flatMap(\.exerciseSets), id: \.id)
        glossaryTerms = firstByID(packages.flatMap(\.glossaryTerms), id: \.id)
            .sorted { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }

        courseIndex = Dictionary(uniqueKeysWithValues: courses.map { ($0.id, $0) })
        studyGuideIndex = Dictionary(uniqueKeysWithValues: studyGuides.map { ($0.id, $0) })
        readingGuideIndex = Dictionary(uniqueKeysWithValues: readingGuides.map { ($0.id, $0) })
        primaryReadingIndex = Dictionary(uniqueKeysWithValues: primaryReadings.map { ($0.id, $0) })
        assignmentIndex = Dictionary(uniqueKeysWithValues: assignments.map { ($0.id, $0) })
        learningPathIndex = Dictionary(uniqueKeysWithValues: learningPaths.map { ($0.id, $0) })
        assetIndex = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        assessmentIndex = Dictionary(uniqueKeysWithValues: assessments.map { ($0.id, $0) })
        exerciseSetIndex = Dictionary(uniqueKeysWithValues: exerciseSets.map { ($0.id, $0) })
        sectionIndex = Dictionary(uniqueKeysWithValues: courses.map {
            ($0.id, StudyLearningProgress.sectionDestinations(for: $0))
        })
    }

    private func firstByID<Value>(_ values: [Value], id: KeyPath<Value, String>) -> [Value] {
        Dictionary(grouping: values, by: { $0[keyPath: id] }).compactMap { $0.value.first }
    }

    private func latestByVersion<Value>(
        _ values: [Value],
        id: KeyPath<Value, String>,
        version: KeyPath<Value, String>
    ) -> [Value] {
        Dictionary(grouping: values, by: { $0[keyPath: id] }).compactMap { _, candidates in
            candidates.max {
                $0[keyPath: version].compare($1[keyPath: version], options: .numeric) == .orderedAscending
            }
        }
    }

    nonisolated private static func latestPackages(from packages: [StudyCoursePackage]) -> [StudyCoursePackage] {
        Dictionary(grouping: packages, by: \.packageID).compactMap { _, candidates in
            candidates.max { $0.contentVersion.compare($1.contentVersion, options: .numeric) == .orderedAscending }
        }
    }

    nonisolated private static func isLowerPriority(_ lhs: StudyCourse, _ rhs: StudyCourse) -> Bool {
        let rank: (StudyPublicationStatus) -> Int = { status in
            switch status {
            case .archived: 0
            case .preview: 1
            case .draftNeedsReview: 2
            case .published: 3
            }
        }
        let lhsRank = rank(lhs.publicationStatus)
        let rhsRank = rank(rhs.publicationStatus)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        return lhs.contentVersion.compare(rhs.contentVersion, options: .numeric) == .orderedAscending
    }
}

enum StudyCoursePreview {
    static let packages: [StudyCoursePackage] = [
        StudyCoursePackage(
            schemaVersion: 1,
            packageID: "preview.hybrid-study-center",
            contentVersion: "1.0.0",
            locale: "en",
            minimumAppVersion: "1.0",
            courses: [manifesto, basicPrinciples],
            studyGuides: [],
            readingGuides: [],
            primaryReadings: [],
            readingLists: [],
            videos: [],
            exerciseSets: [],
            assessments: [],
            glossaryTerms: [],
            bibliographySources: []
        )
    ]

    private static let manifesto = StudyCourse(
        id: "course.communist-manifesto",
        contentVersion: "preview-1",
        title: "The Communist Manifesto",
        subtitle: "A calm, reading-centred course framework",
        summary: "The full course structure is ready for authored lessons, assigned readings, guides, and a cumulative examination.",
        type: .classicalReading,
        interactionIntensity: .calm,
        mode: .selfPaced,
        publicationStatus: .preview,
        estimatedHours: 15,
        prerequisites: ["No formal prerequisites"],
        outcomes: [
            "Reconstruct the Manifesto’s central argument.",
            "Explain its account of class, production, and political struggle.",
            "Interpret key passages in historical and textual context."
        ],
        contributors: [],
        assessmentSummary: "Short module quizzes and a cumulative written final",
        modules: outlineModules([
            ("orientation", "Orientation and historical context", "Europe before 1848, the Communist League, and how to read a political manifesto."),
            ("bourgeois-proletarians", "Bourgeois and Proletarians", "The world market, transformations of production, class conflict, and the proletariat."),
            ("proletarians-communists", "Proletarians and Communists", "Communist politics, property, labour, nation, family, and political power."),
            ("socialist-literature", "Socialist and Communist Literature", "Reactionary, conservative, and critical-utopian socialist traditions."),
            ("opposition-parties", "Position toward opposition parties", "Strategy, political alliances, national contexts, and longer-term aims."),
            ("synthesis", "Synthesis, reception, and debate", "The complete argument, later prefaces, reception, and interpretive debates.")
        ], courseID: "course.communist-manifesto")
    )

    private static let basicPrinciples = StudyCourse(
        id: "course.basic-principles.exam-prep",
        contentVersion: "preview-1",
        title: "Basic Principles of Marxism Examination Preparation",
        subtitle: "An interactive course framework around the canonical question bank",
        summary: "Connect diagnostics, topic drills, wrong-answer review, timed practice, and a future 150-point simulation exam.",
        type: .examPreparation,
        interactionIntensity: .intensive,
        mode: .selfPaced,
        publicationStatus: .preview,
        estimatedHours: 36,
        prerequisites: ["A foundation course or equivalent independent study"],
        outcomes: [
            "Identify strengths and weak domains through diagnostic testing.",
            "Use the canonical question bank without duplicating questions.",
            "Prepare for objective, written, passage, and document-analysis sections."
        ],
        contributors: [],
        assessmentSummary: "Diagnostics, topic drills, mock exams, and a future 150-point full simulation",
        modules: outlineModules([
            ("diagnostic", "Diagnostic and study plan", "Begin with an existing 25- or 50-question diagnostic and confidence analysis."),
            ("introduction", "Introduction and basic outlook", "Review the foundations before focused drills."),
            ("dialectics", "Materiality and dialectics", "Concept comparisons, guided practice, and topic-specific questions."),
            ("epistemology", "Epistemology", "Argument reconstruction, knowledge, practice, and confident-but-wrong review."),
            ("historical-materialism", "Historical materialism", "Conceptual relationships, passage interpretation, and mixed practice."),
            ("political-economy", "Capitalism and political economy", "Political-economy review, weak-topic practice, and timed drills."),
            ("simulation", "Mixed review and examination technique", "Interleaved practice, review scheduling, mock exams, and full simulation preparation.")
        ], courseID: "course.basic-principles.exam-prep")
    )

    private static func outlineModules(
        _ values: [(id: String, title: String, summary: String)],
        courseID: String
    ) -> [StudyCourseModule] {
        values.map { value in
            StudyCourseModule(
                id: "\(courseID).module.\(value.id)",
                title: value.title,
                summary: value.summary,
                estimatedMinutes: 90,
                lessons: [
                    StudyLesson(
                        id: "\(courseID).module.\(value.id).lesson.preview",
                        title: "Course material pending",
                        summary: "This lesson slot will be replaced by the supplied, versioned course material.",
                        estimatedMinutes: 0,
                        blocks: []
                    )
                ],
                moduleQuizID: nil
            )
        }
    }
}
