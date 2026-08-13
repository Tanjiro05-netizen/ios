import XCTest

final class MarxistForumUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGuestCanBeginPHI111AndContinueOffline() throws {
        let app = launchGuest()
        openStudyCenter(in: app)
        openCourse(named: "Hegelian Dialectics I: Being, Essence, Concept", in: app)

        let begin = app.buttons["Begin course"]
        let resume = app.buttons["Continue learning"]
        scrollUntilExists(begin, or: resume, in: app)
        XCTAssertTrue(begin.exists || resume.exists)

        if begin.exists {
            begin.tap()
            XCTAssertTrue(app.navigationBars["Course Orientation"].waitForExistence(timeout: 15))
            XCTAssertTrue(
                identified("study.course.PHI111.orientation.overview", in: app)
                    .waitForExistence(timeout: 15)
            )
            let start = identified("study.course.PHI111.orientation.start", in: app)
            scrollUntilExists(start, in: app, maximumSwipes: 24)
            XCTAssertTrue(start.exists)
            start.tap()
        } else {
            resume.tap()
        }

        XCTAssertTrue(
            identified("study.course.section.PHI111-M01-S01.header", in: app)
                .waitForExistence(timeout: 15)
        )
        XCTAssertTrue(identified("study.course.section.PHI111-M01-S01.content", in: app).exists)

        let learningGoals = identified("study.course.section.PHI111-M01-S01.learning-goals", in: app)
        scrollUntilExists(learningGoals, in: app, maximumSwipes: 12)
        XCTAssertTrue(learningGoals.exists)

        let notes = identified("study.course.section.PHI111-M01-S01.workspace.notes", in: app)
        scrollUntilExists(notes, in: app, maximumSwipes: 28)
        XCTAssertTrue(notes.exists)
        XCTAssertTrue(identified("study.course.section.PHI111-M01-S01.workspace.reflection", in: app).exists)
        XCTAssertTrue(identified("study.course.section.PHI111-M01-S01.workspace.summary", in: app).exists)
        XCTAssertTrue(identified("study.course.section.PHI111-M01-S01.workspace.confidence", in: app).exists)

        notes.tap()
        notes.typeText("The category develops through its own contradiction.")
        app.navigationBars.buttons.firstMatch.tap()

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Study"].waitForExistence(timeout: 15))
        app.buttons["Study"].tap()
        XCTAssertTrue(app.navigationBars["Study Center"].waitForExistence(timeout: 15))

        openCourse(named: "Hegelian Dialectics I: Being, Essence, Concept", in: app)
        let continueLearning = app.buttons["Continue learning"]
        scrollUntilExists(continueLearning, in: app)
        XCTAssertTrue(continueLearning.exists)
        continueLearning.tap()
        XCTAssertTrue(
            identified("study.course.section.PHI111-M01-S01.header", in: app)
                .waitForExistence(timeout: 15)
        )

        let restoredNotes = identified("study.course.section.PHI111-M01-S01.workspace.notes", in: app)
        scrollUntilExists(restoredNotes, in: app, maximumSwipes: 28)
        XCTAssertTrue(restoredNotes.exists)
        XCTAssertTrue((restoredNotes.value as? String)?.contains("The category develops through its own contradiction.") == true)
    }

    @MainActor
    func testPHI111LearningPathOpensPHI211() throws {
        let app = launchGuest()
        openStudyCenter(in: app)
        openCourse(named: "Hegelian Dialectics I: Being, Essence, Concept", in: app)

        let sequel = app.staticTexts["2. Marx's Dialectical Method: From the Critique of Hegel to the Critique of Political Economy"]
        scrollUntilExists(sequel, in: app, maximumSwipes: 18)
        XCTAssertTrue(sequel.exists)
        sequel.tap()
        XCTAssertTrue(
            app.staticTexts["Marx's Dialectical Method: From the Critique of Hegel to the Critique of Political Economy"]
                .waitForExistence(timeout: 15)
        )
    }

    @MainActor
    func testQuestionCatalogueCanSearchStableID() throws {
        let app = launchGuest()
        openStudyCenter(in: app)

        let practice = app.buttons["Practice quizzes"]
        scrollUntilExists(practice, in: app, maximumSwipes: 18)
        XCTAssertTrue(practice.exists)
        practice.tap()

        let catalogue = identified("study.practice.question-catalogue", in: app)
        scrollUntilExists(catalogue, in: app, maximumSwipes: 24)
        XCTAssertTrue(catalogue.exists)
        catalogue.tap()
        XCTAssertTrue(app.navigationBars["Question Catalogue"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["529 questions"].waitForExistence(timeout: 15))

        let search = app.searchFields["Question, topic, or ID"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("B1-C04-MC-013")
        XCTAssertTrue(app.staticTexts["1 question"].waitForExistence(timeout: 10))
        XCTAssertTrue(identified("study.question.B1-C04-MC-013", in: app).exists)
    }

    @MainActor
    func testForumAndLegalBetaSurfacesRemainAvailable() throws {
        let app = launchGuest()
        XCTAssertTrue(app.buttons["Forum"].waitForExistence(timeout: 15))
        app.buttons["Forum"].tap()
        XCTAssertTrue(app.staticTexts["The Forum is Under Construction"].waitForExistence(timeout: 10))

        app.buttons["Profile"].tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))

        let privacy = app.buttons["Privacy Policy"]
        XCTAssertTrue(privacy.waitForExistence(timeout: 10))
        privacy.tap()
        XCTAssertTrue(app.navigationBars["Privacy Policy"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Read the public privacy policy"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func launchGuest() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-guest"]
        app.launch()
        XCTAssertTrue(app.buttons["Study"].waitForExistence(timeout: 20))
        return app
    }

    @MainActor
    private func openStudyCenter(in app: XCUIApplication) {
        app.buttons["Study"].tap()
        XCTAssertTrue(app.navigationBars["Study Center"].waitForExistence(timeout: 15))
        XCTAssertTrue(
            app.staticTexts["Hegelian Dialectics I: Being, Essence, Concept"]
                .waitForExistence(timeout: 20)
        )
    }

    @MainActor
    private func openCourse(named title: String, in app: XCUIApplication) {
        let course = app.staticTexts.matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(course.waitForExistence(timeout: 15))
        course.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 15))
    }

    @MainActor
    private func scrollUntilExists(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maximumSwipes: Int = 12
    ) {
        for _ in 0..<maximumSwipes where !element.exists {
            app.swipeUp()
        }
    }

    @MainActor
    private func scrollUntilExists(
        _ first: XCUIElement,
        or second: XCUIElement,
        in app: XCUIApplication,
        maximumSwipes: Int = 12
    ) {
        for _ in 0..<maximumSwipes where !first.exists && !second.exists {
            app.swipeUp()
        }
    }

    @MainActor
    private func identified(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
