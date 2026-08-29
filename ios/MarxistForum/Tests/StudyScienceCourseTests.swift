import XCTest
@testable import MarxistForum

final class StudyScienceCourseTests: XCTestCase {
    func testNumericGraderConvertsUnitsAndEnforcesSignificantFigures() {
        let specification = StudyNumericAnswerSpecification(
            canonicalValue: 10,
            canonicalUnitID: "m/s",
            acceptedUnitIDs: ["km/h"],
            absoluteTolerance: 0.01,
            requiresUnit: true,
            minimumSignificantFigures: 3
        )

        XCTAssertTrue(StudyNumericResponseGrader.grade(
            rawValue: "36.0",
            unitID: "km/h",
            specification: specification
        ).isCorrect)
        XCTAssertFalse(StudyNumericResponseGrader.grade(
            rawValue: "36",
            unitID: "km/h",
            specification: specification
        ).isCorrect)
        XCTAssertFalse(StudyNumericResponseGrader.grade(
            rawValue: "36.0",
            unitID: "kg",
            specification: specification
        ).isCorrect)
    }

    func testRelativeToleranceUsesExactUnroundedBoundary() {
        let specification = StudyNumericAnswerSpecification(
            canonicalValue: 100,
            relativeTolerance: 0.01
        )

        XCTAssertTrue(StudyNumericResponseGrader.grade(
            rawValue: "101",
            unitID: nil,
            specification: specification
        ).isCorrect)
        XCTAssertFalse(StudyNumericResponseGrader.grade(
            rawValue: "101.0001",
            unitID: nil,
            specification: specification
        ).isCorrect)
    }

    func testMasteryAndLabUnlockSequence() throws {
        let course = try loadPHY111Course()
        let requiredBlockIDs = Set(
            StudyLearningProgress.sectionDestinations(for: course)
                .filter(\.isRequired)
                .map(\.blockID)
        )
        let video = StudyScienceProgressRecord(
            subjectID: "learner",
            courseID: course.id,
            courseVersion: course.contentVersion,
            itemID: StudyScienceCourseUnlockPolicy.videoCompletionID,
            itemKind: "video",
            isCompleted: true
        )

        XCTAssertNotNil(StudyScienceCourseUnlockPolicy.lockReason(
            for: StudyScienceCourseUnlockPolicy.masteryID,
            course: course,
            completedLessonIDs: [],
            completedRequiredBlockIDs: [],
            scienceProgress: [video],
            attempts: []
        ))
        XCTAssertNil(StudyScienceCourseUnlockPolicy.lockReason(
            for: StudyScienceCourseUnlockPolicy.masteryID,
            course: course,
            completedLessonIDs: [],
            completedRequiredBlockIDs: requiredBlockIDs,
            scienceProgress: [video],
            attempts: []
        ))
        XCTAssertNotNil(StudyScienceCourseUnlockPolicy.lockReason(
            for: StudyScienceCourseUnlockPolicy.pythonLabID,
            course: course,
            completedLessonIDs: [],
            completedRequiredBlockIDs: requiredBlockIDs,
            scienceProgress: [video],
            attempts: []
        ))

        let failedPracticeAttempt = StudyScienceActivityAttemptRecord(
            subjectID: "learner",
            courseID: course.id,
            courseVersion: course.contentVersion,
            activityID: StudyScienceCourseUnlockPolicy.masteryID,
            activityVersion: course.contentVersion,
            activityKind: "assessment",
            seed: 7,
            responseJSON: Data("{}".utf8),
            earnedPoints: 1,
            possiblePoints: 6
        )
        XCTAssertNil(StudyScienceCourseUnlockPolicy.lockReason(
            for: StudyScienceCourseUnlockPolicy.pythonLabID,
            course: course,
            completedLessonIDs: [],
            completedRequiredBlockIDs: requiredBlockIDs,
            scienceProgress: [video],
            attempts: [failedPracticeAttempt]
        ), "The lab unlocks after the first submitted practice attempt; that attempt need not pass.")
    }

    func testQuizRequiresMasteryAndEitherComputationPath() throws {
        let course = try loadPHY111Course()
        let mastery = progress(
            course: course,
            itemID: StudyScienceCourseUnlockPolicy.masteryID,
            score: 0.70,
            completionPath: "passed"
        )
        XCTAssertNotNil(StudyScienceCourseUnlockPolicy.lockReason(
            for: StudyScienceCourseUnlockPolicy.quizID,
            course: course,
            completedLessonIDs: [],
            completedRequiredBlockIDs: [],
            scienceProgress: [mastery],
            attempts: []
        ))

        let python = progress(
            course: course,
            itemID: StudyScienceCourseUnlockPolicy.pythonLabID,
            score: 0.70,
            completionPath: "python"
        )
        XCTAssertNil(StudyScienceCourseUnlockPolicy.lockReason(
            for: StudyScienceCourseUnlockPolicy.quizID,
            course: course,
            completedLessonIDs: [],
            completedRequiredBlockIDs: [],
            scienceProgress: [mastery, python],
            attempts: []
        ))
    }

    func testTimedOutIncompleteAssessmentDoesNotBecomeMastery() throws {
        let course = try loadPHY111Course()
        let timedOut = progress(
            course: course,
            itemID: StudyScienceCourseUnlockPolicy.masteryID,
            score: 5.0 / 6.0,
            completionPath: "attempted"
        )
        let computation = progress(
            course: course,
            itemID: StudyScienceCourseUnlockPolicy.guidedLabID,
            score: 1,
            completionPath: "guided"
        )

        XCTAssertNotNil(StudyScienceCourseUnlockPolicy.lockReason(
            for: StudyScienceCourseUnlockPolicy.quizID,
            course: course,
            completedLessonIDs: [],
            completedRequiredBlockIDs: [],
            scienceProgress: [timedOut, computation],
            attempts: []
        ))

        timedOut.recordCompletion(score: 5.0 / 6.0, path: "passed")
        timedOut.recordCompletion(score: 1.0 / 6.0, path: "attempted")
        XCTAssertEqual(timedOut.completionPath, "passed", "A later retry must not erase a valid prior pass.")
        XCTAssertNil(StudyScienceCourseUnlockPolicy.lockReason(
            for: StudyScienceCourseUnlockPolicy.quizID,
            course: course,
            completedLessonIDs: [],
            completedRequiredBlockIDs: [],
            scienceProgress: [timedOut, computation],
            attempts: []
        ))
    }

    func testComputationActivitiesSubmitPassingScore() throws {
        let package = try loadPHY111Package()
        let activities = Dictionary(uniqueKeysWithValues: try XCTUnwrap(package.interactiveActivities).map { ($0.id, $0) })
        let guided = try XCTUnwrap(activities[StudyScienceCourseUnlockPolicy.guidedLabID])
        let python = try XCTUnwrap(activities[StudyScienceCourseUnlockPolicy.pythonLabID])

        let guidedScore = StudyScienceActivityScoring.score(
            activity: guided,
            response: .numericalKinematics(.init(timeStep: 0.1, rows: [], validationFields: [:]))
        )
        let pythonScore = StudyScienceActivityScoring.score(
            activity: python,
            response: .pythonNotebook(.init(
                source: "print('ok')",
                stdout: "ok",
                stderr: "",
                visibleTestResults: [:],
                evidenceFields: [:]
            ))
        )

        XCTAssertEqual(guidedScore.earned, 1)
        XCTAssertEqual(guidedScore.possible, 1)
        XCTAssertEqual(guidedScore.path, "guided")
        XCTAssertEqual(pythonScore.earned, 1)
        XCTAssertEqual(pythonScore.possible, 1)
        XCTAssertEqual(pythonScore.path, "python")
    }

    func testBundledComputeEngineRecognizesEquivalentAndRejectsDifferentExpression() async {
        let equivalent = await StudyComputeEngineEvaluator.shared.evaluate(
            submittedLaTeX: "x+x",
            acceptedLaTeX: ["2x"]
        )
        let different = await StudyComputeEngineEvaluator.shared.evaluate(
            submittedLaTeX: "x+x",
            acceptedLaTeX: ["3x"]
        )

        XCTAssertTrue(equivalent.isEquivalent, equivalent.message)
        XCTAssertNotNil(equivalent.mathJSON)
        XCTAssertFalse(different.isEquivalent)
    }

    func testEntitlementStaysAvailableOfflineUntilSuccessfulRevocationCheck() {
        let entitlement = StudyScienceEntitlementRecord(
            subjectID: "learner",
            courseID: "PHY111",
            verifiedAt: Date(timeIntervalSince1970: 0),
            offlineExpiresAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertTrue(entitlement.permitsOfflineAccess(at: Date(timeIntervalSince1970: 10_000)))
        entitlement.renew(status: .revoked, at: Date(timeIntervalSince1970: 10_001))
        XCTAssertFalse(entitlement.permitsOfflineAccess(at: Date(timeIntervalSince1970: 10_002)))
    }

    private func progress(
        course: StudyCourse,
        itemID: String,
        score: Double,
        completionPath: String? = nil
    ) -> StudyScienceProgressRecord {
        StudyScienceProgressRecord(
            subjectID: "learner",
            courseID: course.id,
            courseVersion: course.contentVersion,
            itemID: itemID,
            itemKind: "activity",
            isCompleted: true,
            bestScore: score,
            completionPath: completionPath
        )
    }

    private func loadPHY111Course() throws -> StudyCourse {
        try XCTUnwrap(loadPHY111Package().courses.first { $0.id == "PHY111" })
    }

    private func loadPHY111Package() throws -> StudyCoursePackage {
        let url = try XCTUnwrap(Bundle.main.url(
            forResource: "PHY111_Module1_Public_Beta.study-course",
            withExtension: "json"
        ))
        return try JSONDecoder().decode(StudyCoursePackage.self, from: Data(contentsOf: url))
    }
}
