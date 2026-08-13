import Foundation
import SwiftData
import SwiftUI

struct StudyCoursesScreen: View {
    @Environment(StudyCourseLibrary.self) private var library
    @Environment(RouterPath.self) private var router

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                StudyAcademicHeader(
                    eyebrow: "ACADEMIC CORE",
                    title: "Courses",
                    message: "Serious, structured study built around complete written lessons, assigned readings, guides, and examinations. Practice remains available without interrupting the reading path.",
                    systemImage: "rectangle.stack.fill"
                )

                if let error = library.loadError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .studyPaperSurface(cornerRadius: 14)
                }

                ForEach(library.courses) { course in
                    Button {
                        router.navigate(to: .studyCourse(id: course.id))
                    } label: {
                        StudyCourseRow(course: course)
                    }
                    .buttonStyle(PressableScaleButtonStyle(scale: 0.98))
                }

                Text("Course packages use stable canonical IDs and versioned JSON. Your prepared course can be imported without replacing the existing quiz, review, or examination systems.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .studyPaperSurface(cornerRadius: 14)
            }
            .padding(16)
            .padding(.bottom, 36)
        }
        .navigationTitle("Courses")
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
    }
}

struct StudyCourseDetailScreen: View {
    let courseID: String

    @Environment(StudyCourseLibrary.self) private var library
    @Environment(RouterPath.self) private var router
    @Environment(AuthStore.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Query private var progressRecords: [StudyCourseProgressRecord]
    @Query private var assignmentSubmissions: [StudyAssignmentSubmissionRecord]
    @Query private var rubricMarks: [StudyRubricMarkRecord]
    @Query private var examSubmissions: [StudyExamSubmissionRecord]
    @Query private var examMarks: [StudyExamQuestionMarkRecord]
    @Query private var learningEvents: [StudyLearningEventRecord]
    @State private var enrollmentError: String?
    @State private var selectedSection: CourseHomeSection = .home
    @State private var expandedModuleIDs: Set<String> = []

    private var course: StudyCourse? { library.course(id: courseID) }
    private var subjectID: String { auth.studySubjectID ?? "guest.local" }
    private var progress: StudyCourseProgressRecord? {
        progressRecords.first { $0.subjectID == subjectID && $0.courseID == courseID }
    }
    private var activeModuleID: String? {
        guard let course else { return nil }
        return StudyLearningProgress.nextSection(
            for: course,
            completedLessonIDs: Set(progress?.completedLessonIDs ?? []),
            completedRequiredBlockIDs: Set(progress?.completedRequiredBlockIDs ?? [])
        )?.moduleID ?? StudyLearningProgress.firstSection(for: course)?.moduleID
    }

    private enum CourseHomeSection: String, CaseIterable, Identifiable {
        case home = "Home"
        case content = "Content"
        case assignments = "Assignments"
        case grades = "Grades"
        case resources = "Resources"

        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .home: "house"
            case .content: "list.bullet.rectangle"
            case .assignments: "square.and.pencil"
            case .grades: "chart.bar.doc.horizontal"
            case .resources: "books.vertical"
            }
        }
    }

    private var visibleCourseHomeSections: [CourseHomeSection] {
        CourseHomeSection.allCases.filter {
            $0 != .grades || AppFeatureFlags.writtenCourseSubmissionsEnabled
        }
    }

    var body: some View {
        Group {
            if let course {
                courseContent(course)
            } else {
                ContentUnavailableView("Course unavailable", systemImage: "rectangle.stack.badge.exclamationmark")
            }
        }
        .navigationTitle(course?.title ?? "Course")
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
        .task(id: activeModuleID) {
            if let activeModuleID {
                expandedModuleIDs.insert(activeModuleID)
            }
        }
        .task(id: learningEvents.count) { syncAchievements() }
        .alert("Unable to begin course", isPresented: Binding(
            get: { enrollmentError != nil },
            set: { if !$0 { enrollmentError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(enrollmentError ?? "Please try again.")
        }
    }

    private func courseContent(_ course: StudyCourse) -> some View {
        let completedLessons = Set(progress?.completedLessonIDs ?? [])
        let completedBlocks = Set(progress?.completedRequiredBlockIDs ?? [])
        let fraction = StudyLearningProgress.fraction(
            for: course,
            completedLessonIDs: completedLessons,
            completedRequiredBlockIDs: completedBlocks
        )
        let courseAssignments = (course.assignmentIDs ?? []).compactMap(library.assignment(id:))
        let learningPaths = (course.learningPathIDs ?? []).compactMap(library.learningPath(id:))
        let finalAssessment = course.finalAssessmentID.flatMap(library.assessment(id:))
        let nextSection = StudyLearningProgress.nextSection(
            for: course,
            completedLessonIDs: completedLessons,
            completedRequiredBlockIDs: completedBlocks
        )
        let launchDestination = nextSection ?? StudyLearningProgress.firstSection(for: course)
        let requiredSections = StudyLearningProgress.sectionDestinations(for: course).filter(\.isRequired)
        let completedRequiredSectionCount = requiredSections.lazy.filter {
            StudyLearningProgress.isSectionCompleted(
                $0,
                completedLessonIDs: completedLessons,
                completedRequiredBlockIDs: completedBlocks
            )
        }.count
        let remainingRequiredSectionCount = max(requiredSections.count - completedRequiredSectionCount, 0)
        let gradebook = StudyCourseGradebook.make(
            course: course,
            assignments: courseAssignments,
            assignmentSubmissions: assignmentSubmissions,
            rubricMarks: rubricMarks,
            finalAssessment: finalAssessment,
            examSubmissions: examSubmissions,
            examMarks: examMarks,
            subjectID: subjectID,
            readingCompletion: fraction
        )
        let learning = StudyLearningProgressSnapshot.make(events: learningEvents, subjectID: subjectID)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(course.type.title, systemImage: course.type == .examPreparation ? "timer" : "book.closed")
                        Spacer()
                        Text(courseStatusTitle(course.publicationStatus))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(course.publicationStatus == .published ? Brand.redSoft : .secondary)
                    }
                    .font(.caption.weight(.semibold))

                    Text(course.title)
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    Text(course.subtitle)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(course.summary)
                        .font(.body)
                        .lineSpacing(3)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        StudyCoursePill(text: "\(course.estimatedHours) hours", systemImage: "clock")
                        StudyCoursePill(text: course.mode == .selfPaced ? "Self-paced" : "Cohort", systemImage: "person.2")
                        StudyCoursePill(text: course.interactionIntensity.rawValue.capitalized, systemImage: "slider.horizontal.3")
                    }

                    if course.publicationStatus != .preview {
                        ProgressView(value: fraction) {
                            Text("Course completion")
                        } currentValueLabel: {
                            Text(fraction, format: .percent.precision(.fractionLength(0)))
                        }
                        .tint(Brand.red)

                        Text("\(completedRequiredSectionCount) of \(requiredSections.count) required sections complete")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("study.course.\(course.id).required-section-count")
                    }
                }
                .padding(18)
                .studyPaperSurface(cornerRadius: 20, emphasized: true)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(visibleCourseHomeSections) { section in
                            Button {
                                withAnimation(.snappy(duration: 0.22)) { selectedSection = section }
                                if section == .content, let activeModuleID {
                                    expandedModuleIDs.insert(activeModuleID)
                                }
                            } label: {
                                Label(section.rawValue, systemImage: section.systemImage)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 38)
                                    .background(selectedSection == section ? Brand.red : Brand.controlFill, in: Capsule())
                                    .foregroundStyle(selectedSection == section ? Brand.onAccent : .primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("study.course.\(course.id).tab.\(section.rawValue.lowercased())")
                        }
                    }
                }

                if course.publicationStatus == .draftNeedsReview {
                    Label {
                        Text("This complete course is marked \(course.academicReviewStatus ?? "not reviewed") and its rights status is \(course.rightsStatus ?? "not recorded"). The source wording is preserved; this integration does not convert a structural validation into academic approval.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .studyPaperSurface(cornerRadius: 16)
                }

                switch selectedSection {
                case .home:
                    courseHome(
                        course,
                        launchDestination: launchDestination,
                        nextSection: nextSection,
                        fraction: fraction,
                        gradebook: gradebook,
                        learning: learning,
                        learningPaths: learningPaths,
                        completedRequiredSectionCount: completedRequiredSectionCount,
                        requiredSectionCount: requiredSections.count,
                        remainingRequiredSectionCount: remainingRequiredSectionCount
                    )
                case .content:
                    courseContentList(
                        course,
                        completedLessons: completedLessons,
                        completedBlocks: completedBlocks,
                        launchDestination: launchDestination,
                        nextSection: nextSection,
                        fraction: fraction,
                        remainingRequiredSectionCount: remainingRequiredSectionCount
                    )
                case .assignments:
                    courseAssignmentsView(course, assignments: courseAssignments, finalAssessment: finalAssessment)
                case .grades:
                    courseGrades(course, gradebook: gradebook, learning: learning)
                case .resources:
                    courseResources(course, fraction: fraction)
                }
            }
            .padding(16)
            .padding(.bottom, 36)
        }
    }

    @ViewBuilder
    private func courseHome(
        _ course: StudyCourse,
        launchDestination: StudyLearningProgress.SectionDestination?,
        nextSection: StudyLearningProgress.SectionDestination?,
        fraction: Double,
        gradebook: StudyCourseGradeSnapshot,
        learning: StudyLearningProgressSnapshot,
        learningPaths: [StudyLearningPath],
        completedRequiredSectionCount: Int,
        requiredSectionCount: Int,
        remainingRequiredSectionCount: Int
    ) -> some View {
        if let launchDestination {
                    StudyCourseLaunchCard(
                        isEnrolled: progress != nil,
                        isComplete: nextSection == nil && fraction >= 1,
                        destination: launchDestination,
                        remainingRequiredSectionCount: remainingRequiredSectionCount
                    ) {
                        beginOrContinue(course, destination: launchDestination)
                    }
        }
        HStack(spacing: 10) {
            StudyCourseMetricTile(
                title: "Reading",
                value: fraction.formatted(.percent.precision(.fractionLength(0))),
                detail: "\(completedRequiredSectionCount)/\(requiredSectionCount) required sections"
            )
            if AppFeatureFlags.writtenCourseSubmissionsEnabled {
                StudyCourseMetricTile(title: "Academic", value: gradebook.overallPercent.map { $0.formatted(.number.precision(.fractionLength(0))) + "%" } ?? "Pending", detail: gradebook.academicResult)
            } else {
                StudyCourseMetricTile(title: "Assessment", value: "Study only", detail: "submissions unavailable in beta")
            }
        }
        HStack(spacing: 10) {
            StudyCourseMetricTile(title: "Learning XP", value: "\(learning.totalXP)", detail: "separate from grades")
            StudyCourseMetricTile(title: "Study rhythm", value: "\(learning.currentStreak) days", detail: "optional streak")
        }
        StudyCourseSection(title: "Course overview") {
            Text(course.summary).font(.subheadline).foregroundStyle(.secondary)
        }
        StudyCourseSection(title: "Learning outcomes") {
            ForEach(course.outcomes, id: \.self) { outcome in
                Label(outcome, systemImage: "checkmark.circle").font(.subheadline)
            }
        }
        ForEach(learningPaths) { path in
            StudyCourseSection(title: path.title) {
                ForEach(path.courses.sorted { $0.order < $1.order }) { entry in
                    if let pathCourse = library.course(id: entry.courseID) {
                        StudyCourseNavigationButton(
                            title: "\(entry.order). \(pathCourse.title)",
                            detail: entry.courseID == course.id ? "Current course" : "Recommended learning-path course",
                            systemImage: entry.courseID == course.id ? "checkmark.circle" : "arrow.right.circle"
                        ) { router.navigate(to: .studyCourse(id: pathCourse.id)) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func courseContentList(
        _ course: StudyCourse,
        completedLessons: Set<String>,
        completedBlocks: Set<String>,
        launchDestination: StudyLearningProgress.SectionDestination?,
        nextSection: StudyLearningProgress.SectionDestination?,
        fraction: Double,
        remainingRequiredSectionCount: Int
    ) -> some View {
        if let launchDestination {
            StudyCourseLaunchCard(
                isEnrolled: progress != nil,
                isComplete: nextSection == nil && fraction >= 1,
                destination: launchDestination,
                remainingRequiredSectionCount: remainingRequiredSectionCount
            ) {
                beginOrContinue(course, destination: launchDestination)
            }
        }
        Text("Syllabus").font(.system(.title3, design: .serif, weight: .semibold)).padding(.horizontal, 4)
        ForEach(Array(course.modules.enumerated()), id: \.element.id) { index, module in
            StudyCollapsibleModuleCard(
                course: course,
                module: module,
                moduleNumber: index + 1,
                completedLessonIDs: completedLessons,
                completedRequiredBlockIDs: completedBlocks,
                isExpanded: expandedModuleIDs.contains(module.id),
                toggle: {
                    withAnimation(.snappy(duration: 0.22)) {
                        if expandedModuleIDs.contains(module.id) { expandedModuleIDs.remove(module.id) }
                        else { expandedModuleIDs.insert(module.id) }
                    }
                }
            )
        }
        if course.conclusionMarkdown != nil {
            StudyCourseNavigationButton(title: StudyCourseDocumentKind.conclusion.title, detail: "Read after the final module", systemImage: "flag.checkered") {
                router.navigate(to: .studyCourseDocument(courseID: course.id, kind: .conclusion))
            }.padding(16).studyPaperSurface(cornerRadius: 16)
        }
    }

    @ViewBuilder
    private func courseAssignmentsView(_ course: StudyCourse, assignments: [StudyAssignment], finalAssessment: StudyCourseAssessmentBlueprint?) -> some View {
        StudyCourseSection(title: "Formal coursework") {
            Text(course.assessmentSummary).font(.subheadline).foregroundStyle(.secondary)
            ForEach(assignments) { assignment in
                StudyCourseNavigationButton(
                    title: "\(assignment.code) · \(assignment.title)",
                    detail: AppFeatureFlags.writtenCourseSubmissionsEnabled
                        ? "\(assignment.weightPercent)% · \(assignmentSubmissions.first { $0.subjectID == subjectID && $0.assignmentID == assignment.id }?.submissionStatus.title ?? "Not started")"
                        : "\(assignment.weightPercent)% · candidate paper and public rubric",
                    systemImage: "doc.text"
                ) { router.navigate(to: .studyAssignment(id: assignment.id)) }
            }
        }
        if let finalAssessment {
            StudyCourseSection(title: "Final examination") {
                StudyCourseNavigationButton(
                    title: finalAssessment.title,
                    detail: AppFeatureFlags.writtenCourseSubmissionsEnabled
                        ? "\((finalAssessment.durationSeconds ?? 0) / 60) min · \(finalAssessment.totalPoints) marks · \(finalAssessment.courseWeightPercent ?? 0)%"
                        : "Complete candidate paper · read-only in beta",
                    systemImage: "doc.text.magnifyingglass"
                ) { router.navigate(to: .studyCourseExam(id: finalAssessment.id)) }
            }
        }
    }

    @ViewBuilder
    private func courseGrades(_ course: StudyCourse, gradebook: StudyCourseGradeSnapshot, learning: StudyLearningProgressSnapshot) -> some View {
        StudyCourseSection(title: "Academic gradebook") {
            Text("Academic results use the authored 60% coursework / 40% final weighting. A formal result appears only after every weighted component is marked.")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(gradebook.components) { component in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(component.title).font(.subheadline.weight(.semibold))
                        Text("\(component.weightPercent)% · \(component.status)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(component.scorePercent.map { $0.formatted(.number.precision(.fractionLength(0))) + "%" } ?? "—")
                        .font(.headline.monospacedDigit())
                }
                .padding(.vertical, 4)
            }
            Divider()
            LabeledContent("Current marked average", value: gradebook.currentAveragePercent.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "Not yet available")
            LabeledContent("Formal course result", value: gradebook.overallPercent.map { $0.formatted(.number.precision(.fractionLength(1))) + "% · " + gradebook.academicResult } ?? "Pending")
            LabeledContent("Marked weighting", value: "\(gradebook.gradedWeightPercent)%")
            LabeledContent("Reading completion", value: gradebook.readingCompletion.formatted(.percent.precision(.fractionLength(0))))
        }
        StudyCourseSection(title: "Learning progress — not a grade") {
            LabeledContent("Learning XP", value: "\(learning.totalXP)")
            LabeledContent("Current streak", value: "\(learning.currentStreak) days")
            LabeledContent("Longest streak", value: "\(learning.longestStreak) days")
            Text("XP and streaks reward completed learning tasks. They cannot change an examination mark, course grade, or pass result.")
                .font(.caption).foregroundStyle(.secondary)
        }
        if AppFeatureFlags.examinerGradingEnabled, StudyAcademicRolePolicy.canGrade(profile: auth.profile) {
            Button {
                router.navigate(to: .studyCourseMarking(courseID: course.id))
            } label: {
                Label("Open examiner marking desk", systemImage: "lock.shield")
                    .frame(maxWidth: .infinity)
            }
            .studyPrimaryActionStyle()
        }
    }

    @ViewBuilder
    private func courseResources(_ course: StudyCourse, fraction: Double) -> some View {
        StudyCourseSection(title: "Course documents") {
            if course.overviewMarkdown != nil { documentButton(course, .overview) }
            if course.introductionMarkdown != nil { documentButton(course, .introduction) }
            if let guideID = course.studyGuideID {
                StudyCourseNavigationButton(title: "Study and Reading Guide", systemImage: "book.pages") { router.navigate(to: .studyGuide(id: guideID)) }
            }
            if let guideID = course.readingGuideID {
                StudyCourseNavigationButton(title: "Module Reading Guide", systemImage: "text.book.closed") { router.navigate(to: .studyReadingGuide(id: guideID)) }
            }
            if course.courseSourceMarkdown != nil { documentButton(course, .completeCourse) }
            if course.assignmentHandbookMarkdown != nil { documentButton(course, .assignmentHandbook) }
            if course.bibliographyMarkdown != nil { documentButton(course, .bibliography) }
            if course.formativeSolutionsMarkdown != nil {
                if fraction >= 1 { documentButton(course, .formativeSolutions) }
                else { Label("Formative solutions unlock after required reading is complete", systemImage: "lock").font(.subheadline).foregroundStyle(.secondary) }
            }
        }
    }

    private func documentButton(_ course: StudyCourse, _ kind: StudyCourseDocumentKind) -> some View {
        StudyCourseNavigationButton(title: kind.title, systemImage: kind == .bibliography ? "books.vertical" : "doc.text") {
            router.navigate(to: .studyCourseDocument(courseID: course.id, kind: kind))
        }
    }

    private func courseStatusTitle(_ status: StudyPublicationStatus) -> String {
        switch status {
        case .preview: "STRUCTURE PREVIEW"
        case .draftNeedsReview: "DRAFT · REVIEW PENDING"
        case .published: "PUBLISHED"
        case .archived: "ARCHIVED"
        }
    }

    private func beginOrContinue(
        _ course: StudyCourse,
        destination: StudyLearningProgress.SectionDestination
    ) {
        let isNewEnrollment = progress == nil
        if isNewEnrollment {
            modelContext.insert(StudyCourseProgressRecord(
                subjectID: subjectID,
                courseID: course.id,
                courseVersion: course.contentVersion
            ))
            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                enrollmentError = error.localizedDescription
                return
            }
        }

        if isNewEnrollment {
            router.navigate(to: .studyCourseOrientation(courseID: course.id))
        } else {
            router.navigate(to: .studyCourseSection(
                courseID: course.id,
                moduleID: destination.moduleID,
                lessonID: destination.lessonID,
                blockID: destination.blockID
            ))
        }
    }

    private func syncAchievements() {
        let snapshot = StudyLearningProgressSnapshot.make(events: learningEvents, subjectID: subjectID)
        let descriptor = FetchDescriptor<StudyAchievementRecord>()
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        for award in snapshot.achievements where !existing.contains(where: { $0.subjectID == subjectID && $0.achievementID == award.id }) {
            modelContext.insert(StudyAchievementRecord(
                subjectID: subjectID,
                achievementID: award.id,
                title: award.title,
                detail: award.detail
            ))
        }
        try? modelContext.save()
    }
}

struct StudyCourseOrientationScreen: View {
    let courseID: String

    @Environment(StudyCourseLibrary.self) private var library
    @Environment(RouterPath.self) private var router

    private var course: StudyCourse? { library.course(id: courseID) }

    var body: some View {
        Group {
            if let course {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        StudyAcademicHeader(
                            eyebrow: "COURSE ORIENTATION",
                            title: course.title,
                            message: course.subtitle,
                            systemImage: "signpost.right.and.left"
                        )

                        if let overview = course.overviewMarkdown, !overview.isEmpty {
                            StudyMarkdownSection(title: StudyCourseDocumentKind.overview.title, markdown: overview)
                                .accessibilityIdentifier("study.course.\(course.id).orientation.overview")
                        }
                        if let introduction = course.introductionMarkdown, !introduction.isEmpty {
                            StudyMarkdownSection(title: StudyCourseDocumentKind.introduction.title, markdown: introduction)
                                .accessibilityIdentifier("study.course.\(course.id).orientation.introduction")
                        }

                        if let first = StudyLearningProgress.firstSection(for: course) {
                            Button {
                                open(first, courseID: course.id)
                            } label: {
                                HStack {
                                    Label("Start first authored section", systemImage: "book.pages")
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                }
                                .frame(maxWidth: .infinity, minHeight: 34)
                            }
                            .studyPrimaryActionStyle()
                            .accessibilityLabel("Start course with \(first.blockTitle)")
                            .accessibilityIdentifier("study.course.\(course.id).orientation.start")
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 36)
                }
            } else {
                ContentUnavailableView("Course unavailable", systemImage: "rectangle.stack.badge.exclamationmark")
            }
        }
        .navigationTitle("Course Orientation")
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
    }

    private func open(_ destination: StudyLearningProgress.SectionDestination, courseID: String) {
        router.navigate(to: .studyCourseSection(
            courseID: courseID,
            moduleID: destination.moduleID,
            lessonID: destination.lessonID,
            blockID: destination.blockID
        ))
    }
}

/// The legacy lesson route is retained as the native module contents screen so
/// existing deep links remain valid while authored sections receive their own
/// focused reader destination.
struct StudyLessonScreen: View {
    let courseID: String
    let moduleID: String
    let lessonID: String

    @Environment(StudyCourseLibrary.self) private var library
    @Environment(RouterPath.self) private var router
    @Environment(AuthStore.self) private var auth
    @Query private var progressRecords: [StudyCourseProgressRecord]

    private var course: StudyCourse? { library.course(id: courseID) }
    private var module: StudyCourseModule? { course?.modules.first { $0.id == moduleID } }
    private var subjectID: String { auth.studySubjectID ?? "guest.local" }
    private var progress: StudyCourseProgressRecord? {
        progressRecords.first { $0.subjectID == subjectID && $0.courseID == courseID }
    }
    private var completedLessons: Set<String> { Set(progress?.completedLessonIDs ?? []) }
    private var completedBlocks: Set<String> { Set(progress?.completedRequiredBlockIDs ?? []) }
    private var moduleSections: [StudyLearningProgress.SectionDestination] {
        library.sectionDestinations(courseID: courseID).filter { $0.moduleID == moduleID }
    }

    var body: some View {
        Group {
            if let course, let module {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        StudyAcademicHeader(
                            eyebrow: "MODULE \(moduleNumber(in: course)) OF \(course.modules.count)",
                            title: module.title,
                            message: "\(moduleSections.count) authored sections · \(module.estimatedMinutes) minutes",
                            systemImage: "list.bullet.rectangle"
                        )

                        if let next = nextIncompleteSection ?? moduleSections.first {
                            Button {
                                open(next)
                            } label: {
                                HStack {
                                    Label(nextIncompleteSection == nil ? "Review module" : "Continue module", systemImage: "book.pages")
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                }
                                .frame(maxWidth: .infinity, minHeight: 34)
                            }
                            .studyPrimaryActionStyle()
                            .accessibilityLabel("\(nextIncompleteSection == nil ? "Review" : "Continue") module at \(next.blockTitle)")
                            .accessibilityIdentifier("study.course.\(courseID).module.\(moduleID).continue")
                        }

                        StudyCourseSection(title: "Authored sections") {
                            ForEach(moduleSections) { destination in
                                StudyCourseNavigationButton(
                                    title: destination.blockTitle,
                                    detail: "Section \(destination.sectionNumber) of \(destination.sectionCount)",
                                    systemImage: isCompleted(destination) ? "checkmark.circle.fill" : "doc.text"
                                ) {
                                    open(destination)
                                }
                                .id(destination.blockID)
                                .accessibilityLabel("Section \(destination.sectionNumber) of \(destination.sectionCount), \(destination.blockTitle)\(isCompleted(destination) ? ", completed" : "")")
                                .accessibilityIdentifier("study.course.section-row.\(destination.blockID)")
                            }
                        }

                        StudyModuleResources(
                            course: course,
                            module: module,
                            moduleSections: moduleSections
                        )
                    }
                    .padding(16)
                    .padding(.bottom, 36)
                }
            } else {
                ContentUnavailableView("Module unavailable", systemImage: "doc.badge.ellipsis")
            }
        }
        .navigationTitle(module?.title ?? "Module Contents")
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
    }

    private var nextIncompleteSection: StudyLearningProgress.SectionDestination? {
        moduleSections.first { !isCompleted($0) }
    }

    private func isCompleted(_ destination: StudyLearningProgress.SectionDestination) -> Bool {
        StudyLearningProgress.isSectionCompleted(
            destination,
            completedLessonIDs: completedLessons,
            completedRequiredBlockIDs: completedBlocks
        )
    }

    private func moduleNumber(in course: StudyCourse) -> Int {
        (course.modules.firstIndex { $0.id == moduleID } ?? 0) + 1
    }

    private func open(_ destination: StudyLearningProgress.SectionDestination) {
        router.navigate(to: .studyCourseSection(
            courseID: courseID,
            moduleID: destination.moduleID,
            lessonID: destination.lessonID,
            blockID: destination.blockID
        ))
    }
}

struct StudyCourseSectionScreen: View {
    let courseID: String
    let moduleID: String
    let lessonID: String
    let blockID: String

    @Environment(StudyCourseLibrary.self) private var library
    @Environment(StudyAssessmentStore.self) private var assessments
    @Environment(RouterPath.self) private var router
    @Environment(AuthStore.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var progressRecords: [StudyCourseProgressRecord]
    @Query private var learningEvents: [StudyLearningEventRecord]
    @Query private var sectionWorkRecords: [StudySectionWorkRecord]
    @State private var launchingAssessmentID: String?
    @State private var presentedError: String?
    @State private var notesMarkdown = ""
    @State private var reflectionMarkdown = ""
    @State private var summaryMarkdown = ""
    @State private var confidence: Int?
    @State private var workspaceDidLoad = false
    @State private var workspaceRecord: StudySectionWorkRecord?

    private struct SectionWorkspaceDraft: Hashable {
        let notesMarkdown: String
        let reflectionMarkdown: String
        let summaryMarkdown: String
        let confidence: Int?
    }

    private var course: StudyCourse? { library.course(id: courseID) }
    private var module: StudyCourseModule? { course?.modules.first { $0.id == moduleID } }
    private var lesson: StudyLesson? { module?.lessons.first { $0.id == lessonID } }
    private var sectionBlock: StudyLessonBlock? {
        lesson?.blocks.first { $0.id == blockID && $0.kind == .lessonContent }
    }
    private var destination: StudyLearningProgress.SectionDestination? {
        guard let course else { return nil }
        return StudyLearningProgress.section(in: course, blockID: blockID)
    }
    private var subjectID: String { auth.studySubjectID ?? "guest.local" }
    private var progress: StudyCourseProgressRecord? {
        progressRecords.first { $0.subjectID == subjectID && $0.courseID == courseID }
    }
    private var completedLessons: Set<String> { Set(progress?.completedLessonIDs ?? []) }
    private var completedBlocks: Set<String> { Set(progress?.completedRequiredBlockIDs ?? []) }
    private var workspaceRecordID: String? {
        guard let course else { return nil }
        return StudySectionWorkRecord.makeRecordID(
            subjectID: subjectID,
            courseID: course.id,
            courseVersion: course.contentVersion,
            lessonID: lessonID,
            blockID: blockID
        )
    }
    private var workspaceDraft: SectionWorkspaceDraft {
        SectionWorkspaceDraft(
            notesMarkdown: notesMarkdown,
            reflectionMarkdown: reflectionMarkdown,
            summaryMarkdown: summaryMarkdown,
            confidence: confidence
        )
    }

    var body: some View {
        Group {
            if let course, let module, let lesson, let sectionBlock, let destination {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        StudyAcademicHeader(
                            eyebrow: "MODULE \(destination.moduleNumber) · SECTION \(destination.sectionNumber) OF \(destination.sectionCount)",
                            title: sectionBlock.title,
                            message: module.title,
                            systemImage: "doc.text"
                        )
                        .accessibilityIdentifier("study.course.section.\(sectionBlock.id).header")

                        if !(lesson.objectives ?? []).isEmpty || !(lesson.essentialQuestions ?? []).isEmpty {
                            StudySectionLearningGoals(
                                objectives: lesson.objectives ?? [],
                                essentialQuestions: lesson.essentialQuestions ?? []
                            )
                            .accessibilityIdentifier("study.course.section.\(sectionBlock.id).learning-goals")
                        }

                        if let markdown = sectionBlock.bodyMarkdown, !markdown.isEmpty {
                            StudyMarkdownSection(title: sectionBlock.title, markdown: markdown)
                                .id(sectionBlock.id)
                                .accessibilityIdentifier("study.course.section.\(sectionBlock.id).content")
                        }

                        ForEach(attachedBlocks) { block in
                            StudyLessonBlockView(
                                block: block,
                                exerciseSet: block.referencedContentID.flatMap(library.exerciseSet(id:)),
                                isWorking: launchingAssessmentID == block.referencedContentID,
                                open: open
                            )
                            .id(block.id)
                            .accessibilityIdentifier("study.course.block.\(block.id)")
                        }

                        StudySectionWorkspace(
                            notesMarkdown: $notesMarkdown,
                            reflectionMarkdown: $reflectionMarkdown,
                            summaryMarkdown: $summaryMarkdown,
                            confidence: $confidence,
                            reflectionPrompts: lesson.reflectionPrompts ?? [],
                            accessibilityPrefix: "study.course.section.\(sectionBlock.id).workspace"
                        )

                        if isCompleted(destination) {
                            Button("Mark section as not completed") {
                                _ = saveWorkspace(course: course)
                                setCompleted(false, course: course, lesson: lesson, destination: destination)
                            }
                            .frame(maxWidth: .infinity)
                            .studySecondaryActionStyle()
                            .accessibilityIdentifier("study.course.section.\(sectionBlock.id).completion")
                        } else {
                            Button {
                                completeAndContinue(course: course, lesson: lesson, destination: destination)
                            } label: {
                                HStack {
                                    Label("Complete and continue", systemImage: "checkmark.circle")
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                }
                                .frame(maxWidth: .infinity, minHeight: 34)
                            }
                            .studyPrimaryActionStyle()
                            .accessibilityIdentifier("study.course.section.\(sectionBlock.id).completion")
                        }

                        StudySectionNavigation(
                            previous: StudyLearningProgress.previousSection(in: course, before: blockID),
                            next: StudyLearningProgress.nextSection(in: course, after: blockID),
                            conclusionAvailable: course.conclusionMarkdown != nil,
                            finalAssessmentAvailable: course.finalAssessmentID != nil,
                            openSection: open,
                            openConclusion: {
                                router.navigate(to: .studyCourseDocument(courseID: course.id, kind: .conclusion))
                            },
                            openFinalAssessment: {
                                if let assessmentID = course.finalAssessmentID {
                                    router.navigate(to: .studyCourseExam(id: assessmentID))
                                }
                            }
                        )
                    }
                    .padding(16)
                    .padding(.bottom, 36)
                }
            } else {
                ContentUnavailableView("Section unavailable", systemImage: "doc.badge.ellipsis")
            }
        }
        .navigationTitle(sectionBlock?.title ?? "Course Section")
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
        .task(id: workspaceRecordID) {
            loadWorkspace()
        }
        .task(id: workspaceDraft) {
            guard workspaceDidLoad else { return }
            do {
                try await Task.sleep(for: .milliseconds(600))
                try Task.checkCancellation()
            } catch {
                return
            }
            _ = saveWorkspace()
        }
        .onDisappear {
            _ = saveWorkspace()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.navigate(to: .studyLesson(courseID: courseID, moduleID: moduleID, lessonID: lessonID))
                } label: {
                    Label("Module contents", systemImage: "list.bullet")
                }
                .accessibilityIdentifier("study.course.section.\(blockID).module-contents")
            }
        }
        .alert("Course activity unavailable", isPresented: Binding(
            get: { presentedError != nil },
            set: { if !$0 { presentedError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(presentedError ?? "Please try again.")
        }
    }

    private var attachedBlocks: [StudyLessonBlock] {
        guard let lesson,
              let sectionIndex = lesson.blocks.firstIndex(where: { $0.id == blockID }) else { return [] }
        let following = lesson.blocks.index(after: sectionIndex)..<lesson.blocks.endIndex
        guard let nextSectionIndex = following.first(where: { lesson.blocks[$0].kind == .lessonContent }) else {
            return Array(lesson.blocks[following])
        }
        return Array(lesson.blocks[lesson.blocks.index(after: sectionIndex)..<nextSectionIndex])
    }

    private func loadWorkspace() {
        guard let workspaceRecordID else { return }
        workspaceDidLoad = false
        if let record = sectionWorkRecords.first(where: { $0.recordID == workspaceRecordID }) {
            workspaceRecord = record
            notesMarkdown = record.notesMarkdown
            reflectionMarkdown = record.reflectionMarkdown
            summaryMarkdown = record.summaryMarkdown
            confidence = record.confidence
        } else {
            workspaceRecord = nil
            notesMarkdown = ""
            reflectionMarkdown = ""
            summaryMarkdown = ""
            confidence = nil
        }
        workspaceDidLoad = true
    }

    @discardableResult
    private func saveWorkspace(course explicitCourse: StudyCourse? = nil) -> Bool {
        guard workspaceDidLoad, let resolvedCourse = explicitCourse ?? course else { return true }
        let recordID = StudySectionWorkRecord.makeRecordID(
            subjectID: subjectID,
            courseID: resolvedCourse.id,
            courseVersion: resolvedCourse.contentVersion,
            lessonID: lessonID,
            blockID: blockID
        )
        let existing = workspaceRecord ?? sectionWorkRecords.first { $0.recordID == recordID }
        let isNewRecord = existing == nil
        let hasContent = !notesMarkdown.isEmpty
            || !reflectionMarkdown.isEmpty
            || !summaryMarkdown.isEmpty
            || confidence != nil

        if let existing {
            guard existing.notesMarkdown != notesMarkdown
                    || existing.reflectionMarkdown != reflectionMarkdown
                    || existing.summaryMarkdown != summaryMarkdown
                    || existing.confidence != confidence else { return true }
            existing.update(
                notesMarkdown: notesMarkdown,
                reflectionMarkdown: reflectionMarkdown,
                summaryMarkdown: summaryMarkdown,
                confidence: confidence
            )
        } else {
            guard hasContent else { return true }
            let record = StudySectionWorkRecord(
                subjectID: subjectID,
                courseID: resolvedCourse.id,
                courseVersion: resolvedCourse.contentVersion,
                lessonID: lessonID,
                blockID: blockID,
                notesMarkdown: notesMarkdown,
                reflectionMarkdown: reflectionMarkdown,
                summaryMarkdown: summaryMarkdown,
                confidence: confidence
            )
            modelContext.insert(record)
            workspaceRecord = record
        }

        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            if isNewRecord { workspaceRecord = nil }
            presentedError = "Your private notes could not be saved. \(error.localizedDescription)"
            return false
        }
    }

    private func isCompleted(_ destination: StudyLearningProgress.SectionDestination) -> Bool {
        StudyLearningProgress.isSectionCompleted(
            destination,
            completedLessonIDs: completedLessons,
            completedRequiredBlockIDs: completedBlocks
        )
    }

    private func open(_ destination: StudyLearningProgress.SectionDestination) {
        _ = saveWorkspace()
        router.navigate(to: .studyCourseSection(
            courseID: courseID,
            moduleID: destination.moduleID,
            lessonID: destination.lessonID,
            blockID: destination.blockID
        ))
    }

    private func open(_ block: StudyLessonBlock) {
        _ = saveWorkspace()
        switch block.kind {
        case .studyGuide:
            if let id = block.referencedContentID { router.navigate(to: .studyGuide(id: id)) }
        case .readingGuide:
            if let id = block.referencedContentID { router.navigate(to: .studyReadingGuide(id: id)) }
        case .video:
            router.navigate(to: .studyCollection(kind: .videos))
        case .exercise, .lessonContent:
            break
        case .lessonCheck, .moduleQuiz:
            guard let id = block.referencedContentID,
                  let blueprint = library.assessment(id: id) else { return }
            launchingAssessmentID = id
            Task {
                defer { launchingAssessmentID = nil }
                do {
                    let attemptID = try await assessments.startAttempt(
                        plan: blueprint.sessionPlan(
                            courseID: courseID,
                            moduleID: moduleID,
                            lessonID: lessonID
                        )
                    )
                    router.navigate(to: .studyQuiz(attemptID: attemptID))
                } catch {
                    presentedError = error.localizedDescription
                }
            }
        case .primaryReading:
            guard let id = block.referencedContentID,
                  let reading = library.primaryReading(id: id) else { return }
            if let bookID = reading.libraryBookID {
                router.navigate(to: .bookReader(id: bookID))
            } else if let url = reading.externalURL {
                openURL(url)
            }
        }
    }

    private func completeAndContinue(
        course: StudyCourse,
        lesson: StudyLesson,
        destination: StudyLearningProgress.SectionDestination
    ) {
        guard saveWorkspace(course: course),
              setCompleted(true, course: course, lesson: lesson, destination: destination) else { return }

        if let next = StudyLearningProgress.nextSection(in: course, after: destination.blockID) {
            router.navigate(to: .studyCourseSection(
                courseID: course.id,
                moduleID: next.moduleID,
                lessonID: next.lessonID,
                blockID: next.blockID
            ))
        } else if course.conclusionMarkdown != nil {
            router.navigate(to: .studyCourseDocument(courseID: course.id, kind: .conclusion))
        } else if let assessmentID = course.finalAssessmentID {
            router.navigate(to: .studyCourseExam(id: assessmentID))
        }
    }

    @discardableResult
    private func setCompleted(
        _ completed: Bool,
        course: StudyCourse,
        lesson: StudyLesson,
        destination: StudyLearningProgress.SectionDestination
    ) -> Bool {
        let record: StudyCourseProgressRecord
        if let progress {
            record = progress
        } else {
            record = StudyCourseProgressRecord(subjectID: subjectID, courseID: course.id, courseVersion: course.contentVersion)
            modelContext.insert(record)
        }

        let lessonWasCompleted = record.completedLessonIDs.contains(lesson.id)
        record.setSection(
            destination.blockID,
            completed: completed,
            lessonID: lesson.id,
            requiredBlockIDs: StudyLearningProgress.requiredSectionBlockIDs(in: lesson)
        )

        if !lessonWasCompleted, record.completedLessonIDs.contains(lesson.id) {
            insertEvent(kind: .lessonCompleted, contentID: lesson.id, course: course)
        }

        let newFraction = StudyLearningProgress.fraction(
            for: course,
            completedLessonIDs: Set(record.completedLessonIDs),
            completedRequiredBlockIDs: Set(record.completedRequiredBlockIDs)
        )
        if completed, newFraction >= 1 {
            insertEvent(kind: .courseCompleted, contentID: course.id, course: course)
        }

        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            presentedError = error.localizedDescription
            return false
        }
    }

    private func insertEvent(kind: StudyLearningEventKind, contentID: String, course: StudyCourse) {
        let eventID = StudyLearningProgress.eventID(
            subjectID: subjectID,
            kind: kind,
            contentID: contentID,
            version: course.contentVersion
        )
        guard !learningEvents.contains(where: { $0.eventID == eventID }) else { return }
        modelContext.insert(StudyLearningEventRecord(
            eventID: eventID,
            subjectID: subjectID,
            kind: kind.rawValue,
            contentID: contentID,
            points: kind.points
        ))
    }
}

struct StudyGuideDetailScreen: View {
    let guideID: String
    @Environment(StudyCourseLibrary.self) private var library

    var body: some View {
        Group {
            if let guide = library.studyGuide(id: guideID) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        StudyAcademicHeader(eyebrow: "STUDY GUIDE", title: guide.title, message: guide.purpose, systemImage: "doc.text")
                        StudyCourseSection(title: "Outcomes") {
                            ForEach(guide.outcomes, id: \.self) { Label($0, systemImage: "checkmark.circle") }
                        }
                        ForEach(guide.sections) { section in
                            StudyMarkdownSection(title: section.title, markdown: section.bodyMarkdown)
                        }
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView("Guide unavailable", systemImage: "doc.badge.ellipsis")
            }
        }
        .navigationTitle("Study Guide")
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
    }
}

struct StudyReadingGuideDetailScreen: View {
    let guideID: String
    @Environment(StudyCourseLibrary.self) private var library
    @Environment(RouterPath.self) private var router

    var body: some View {
        Group {
            if let guide = library.readingGuide(id: guideID),
               let canonicalID = guide.canonicalStudyGuideID,
               let canonical = library.studyGuide(id: canonicalID) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        StudyAcademicHeader(eyebrow: "STUDY & READING GUIDE", title: canonical.title, message: canonical.purpose, systemImage: "book.pages")
                        if !guide.chunks.isEmpty {
                            StudyCourseSection(title: "Module reading guides") {
                                ForEach(guide.chunks) { chunk in
                                    StudyCourseNavigationButton(
                                        title: chunk.title,
                                        detail: chunk.anchorLabel,
                                        systemImage: "book.pages"
                                    ) {
                                        router.navigate(to: .studyReadingGuideChunk(guideID: guide.id, chunkID: chunk.id))
                                    }
                                    .accessibilityIdentifier("study.reading-guide.chunk.\(chunk.id)")
                                }
                            }
                        }
                        ForEach(canonical.sections) { section in
                            StudyMarkdownSection(title: section.title, markdown: section.bodyMarkdown)
                        }
                    }
                    .padding(16)
                }
            } else if let guide = library.readingGuide(id: guideID) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        StudyAcademicHeader(eyebrow: "READING GUIDE", title: guide.title, message: guide.purpose, systemImage: "book.pages")
                        StudyCourseSection(title: "Context") {
                            Text(guide.context).font(.body).foregroundStyle(.secondary)
                            Text(guide.editionNote).font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(guide.chunks) { chunk in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(chunk.title).font(.system(.headline, design: .serif, weight: .semibold))
                                Text("\(chunk.anchorLabel) · \(chunk.estimatedMinutes) min").font(.caption).foregroundStyle(.secondary)
                                if let markdown = chunk.bodyMarkdown, !markdown.isEmpty {
                                    StudyMarkdownDocument(markdown: markdown)
                                }
                                ForEach(chunk.prompts, id: \.self) { Label($0, systemImage: "questionmark.circle") }
                                if let bookID = chunk.libraryBookID {
                                    Button("Open assigned text") { router.navigate(to: .bookReader(id: bookID)) }
                                        .studySecondaryActionStyle()
                                }
                            }
                            .padding(16)
                            .studyPaperSurface(cornerRadius: 16)
                        }
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView("Reading guide unavailable", systemImage: "book.pages")
            }
        }
        .navigationTitle("Reading Guide")
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
    }
}

struct StudyReadingGuideChunkScreen: View {
    let guideID: String
    let chunkID: String

    @Environment(StudyCourseLibrary.self) private var library
    @Environment(RouterPath.self) private var router

    private var guide: StudyReadingGuide? { library.readingGuide(id: guideID) }
    private var chunk: StudyReadingChunk? { guide?.chunks.first { $0.id == chunkID } }

    var body: some View {
        Group {
            if let chunk {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        StudyAcademicHeader(
                            eyebrow: "MODULE READING GUIDE",
                            title: chunk.title,
                            message: chunk.anchorLabel,
                            systemImage: "book.pages"
                        )

                        if let markdown = chunk.bodyMarkdown, !markdown.isEmpty {
                            StudyMarkdownSection(title: chunk.title, markdown: markdown)
                                .accessibilityIdentifier("study.reading-guide.chunk.\(chunk.id).content")
                        } else {
                            StudyCourseSection(title: "Reading guidance") {
                                ForEach(chunk.prompts, id: \.self) { prompt in
                                    Label(prompt, systemImage: "questionmark.circle")
                                        .font(.subheadline)
                                }
                                if !chunk.terms.isEmpty {
                                    Text("Key terms: \(chunk.terms.joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if let bookID = chunk.libraryBookID {
                            Button {
                                router.navigate(to: .bookReader(id: bookID))
                            } label: {
                                Label("Open assigned text", systemImage: "book")
                                    .frame(maxWidth: .infinity)
                            }
                            .studySecondaryActionStyle()
                            .accessibilityIdentifier("study.reading-guide.chunk.\(chunk.id).assigned-text")
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 36)
                }
            } else {
                ContentUnavailableView("Reading guide section unavailable", systemImage: "book.pages")
            }
        }
        .navigationTitle(chunk?.title ?? guide?.title ?? "Reading Guide")
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
    }
}

struct StudyGuideCollectionScreen: View {
    let kind: StudyContentKind
    @Environment(StudyCourseLibrary.self) private var library
    @Environment(RouterPath.self) private var router

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                StudyAcademicHeader(
                    eyebrow: kind == .studyGuides ? "STUDY GUIDES" : "READING GUIDES",
                    title: kind.title,
                    message: kind.collectionIntroduction,
                    systemImage: kind.systemImage
                )
                if kind == .studyGuides {
                    ForEach(library.studyGuides) { guide in
                        Button { router.navigate(to: .studyGuide(id: guide.id)) } label: {
                            StudyCanonicalGuideRow(title: guide.title, purpose: guide.purpose, sectionCount: guide.sections.count)
                        }
                        .buttonStyle(PressableScaleButtonStyle(scale: 0.98))
                    }
                } else {
                    ForEach(library.readingGuides) { guide in
                        let sectionCount = guide.canonicalStudyGuideID
                            .flatMap { library.studyGuide(id: $0)?.sections.count }
                            ?? guide.chunks.count
                        Button { router.navigate(to: .studyReadingGuide(id: guide.id)) } label: {
                            StudyCanonicalGuideRow(title: guide.title, purpose: guide.purpose, sectionCount: sectionCount)
                        }
                        .buttonStyle(PressableScaleButtonStyle(scale: 0.98))
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 36)
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
    }
}

struct StudyCourseDocumentScreen: View {
    let courseID: String
    let kind: StudyCourseDocumentKind
    @Environment(StudyCourseLibrary.self) private var library
    @Environment(RouterPath.self) private var router
    @Environment(AuthStore.self) private var auth
    @Query private var progressRecords: [StudyCourseProgressRecord]

    private var course: StudyCourse? { library.course(id: courseID) }
    private var progress: StudyCourseProgressRecord? {
        let subjectID = auth.studySubjectID ?? "guest.local"
        return progressRecords.first { $0.subjectID == subjectID && $0.courseID == courseID }
    }
    private var isSolutionsLocked: Bool {
        guard kind == .formativeSolutions, let course else { return false }
        return StudyLearningProgress.fraction(
            for: course,
            completedLessonIDs: Set(progress?.completedLessonIDs ?? []),
            completedRequiredBlockIDs: Set(progress?.completedRequiredBlockIDs ?? [])
        ) < 1
    }
    private var markdown: String? {
        guard let course else { return nil }
        return switch kind {
        case .overview: course.overviewMarkdown
        case .introduction: course.introductionMarkdown
        case .conclusion: course.conclusionMarkdown
        case .bibliography: course.bibliographyMarkdown
        case .completeCourse: course.courseSourceMarkdown
        case .assignmentHandbook: course.assignmentHandbookMarkdown
        case .formativeSolutions: course.formativeSolutionsMarkdown
        }
    }

    var body: some View {
        Group {
            if isSolutionsLocked {
                ContentUnavailableView {
                    Label("Solutions locked", systemImage: "lock")
                } description: {
                    Text("Complete the required authored sections before opening the collected formative solutions.")
                }
            } else if let course, let markdown {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        StudyAcademicHeader(
                            eyebrow: course.id,
                            title: kind.title,
                            message: course.title,
                            systemImage: kind == .bibliography ? "books.vertical" : "doc.text"
                        )
                        StudyMarkdownSection(title: kind.title, markdown: markdown)
                        if kind == .conclusion,
                           let assessmentID = course.finalAssessmentID,
                           library.assessment(id: assessmentID) != nil {
                            Button {
                                router.navigate(to: .studyCourseExam(id: assessmentID))
                            } label: {
                                HStack {
                                    Label("Continue to final examination", systemImage: "checkmark.seal")
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                }
                                .frame(maxWidth: .infinity, minHeight: 34)
                            }
                            .studyPrimaryActionStyle()
                            .accessibilityIdentifier("study.course.\(course.id).conclusion.final-exam")
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 36)
                }
            } else {
                ContentUnavailableView("Document unavailable", systemImage: "doc.badge.ellipsis")
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
    }
}

struct StudyAssignmentDetailScreen: View {
    let assignmentID: String
    @Environment(StudyCourseLibrary.self) private var library
    @Environment(RouterPath.self) private var router
    @Environment(AuthStore.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Query private var submissions: [StudyAssignmentSubmissionRecord]
    @Query private var rubricMarks: [StudyRubricMarkRecord]
    @State private var draft = ""
    @State private var isConfirmingSubmission = false
    @State private var message: String?

    private var subjectID: String { auth.studySubjectID ?? "guest.local" }
    private var submission: StudyAssignmentSubmissionRecord? {
        submissions.first { $0.subjectID == subjectID && $0.assignmentID == assignmentID }
    }

    var body: some View {
        Group {
            if let assignment = library.assignment(id: assignmentID) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        StudyAcademicHeader(
                            eyebrow: "\(assignment.code) · AFTER MODULE \(assignment.afterModuleNumber)",
                            title: assignment.title,
                            message: "\(assignment.mode) · \(assignment.expectedExtent)",
                            systemImage: "doc.text"
                        )
                        HStack(spacing: 8) {
                            StudyCoursePill(text: "\(assignment.weightPercent)%", systemImage: "percent")
                            StudyCoursePill(text: assignment.mode, systemImage: "square.and.pencil")
                            if AppFeatureFlags.writtenCourseSubmissionsEnabled {
                                StudyCoursePill(text: submission?.submissionStatus.title ?? "Not started", systemImage: "clock")
                            } else {
                                StudyCoursePill(text: "Study paper", systemImage: "doc.text")
                            }
                        }
                        StudyMarkdownSection(title: "Assignment instructions and rubric", markdown: assignment.bodyMarkdown)
                        if AppFeatureFlags.writtenCourseSubmissionsEnabled {
                            StudyCourseSection(title: "Your submission") {
                            if submission?.submissionStatus == .graded {
                                markedSubmission(assignment)
                            } else {
                                Text("Write or paste your response below. Drafts stay on this device until you submit them for marking.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                TextEditor(text: $draft)
                                    .font(.body)
                                    .frame(minHeight: 280)
                                    .padding(8)
                                    .background(Brand.controlFill, in: RoundedRectangle(cornerRadius: 12))
                                    .disabled(submission?.submissionStatus == .submitted)
                                    .accessibilityIdentifier("study.assignment.\(assignment.id).draft")
                                if submission?.submissionStatus == .submitted {
                                    Label("Submitted for marking. The draft is locked while it is with an examiner.", systemImage: "clock.badge.checkmark")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    HStack {
                                        Button("Save draft") { saveDraft(assignment) }
                                            .studySecondaryActionStyle()
                                        Button("Submit for marking") {
                                            saveDraft(assignment)
                                            isConfirmingSubmission = true
                                        }
                                        .studyPrimaryActionStyle()
                                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    }
                                }
                            }
                            }
                        } else {
                            StudyCourseSection(title: "Beta availability") {
                                Label("This complete candidate paper and its public rubric are available for study. Draft fields, submission, examiner marking, and formal grades are disabled in this external beta.", systemImage: "doc.text.magnifyingglass")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let course = library.course(id: assignment.courseID),
                           course.assignmentHandbookMarkdown != nil {
                            Button {
                                router.navigate(to: .studyCourseDocument(courseID: course.id, kind: .assignmentHandbook))
                            } label: {
                                Label("Open complete native assignment handbook", systemImage: "doc.text")
                                    .frame(maxWidth: .infinity)
                            }
                            .studySecondaryActionStyle()
                            .accessibilityIdentifier("study.assignment.\(assignment.id).handbook")
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 36)
                }
            } else {
                ContentUnavailableView("Assignment unavailable", systemImage: "doc.badge.ellipsis")
            }
        }
        .navigationTitle("Assignment")
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
        .task(id: submission?.updatedAt) {
            draft = submission?.draftMarkdown ?? ""
        }
        .confirmationDialog("Submit this assignment?", isPresented: $isConfirmingSubmission, titleVisibility: .visible) {
            Button("Submit for marking") {
                guard let assignment = library.assignment(id: assignmentID) else { return }
                submit(assignment)
            }
        } message: {
            Text("Your response will be locked until an examiner marks or returns it.")
        }
        .alert("Assignment", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    @ViewBuilder
    private func markedSubmission(_ assignment: StudyAssignment) -> some View {
        if let submission {
            Text(submission.draftMarkdown).font(.body).textSelection(.enabled)
            Divider()
            ForEach(assignment.rubricCriteria) { criterion in
                let mark = rubricMarks.first { $0.submissionRecordID == submission.recordID && $0.criterionID == criterion.id }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(criterion.title).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(rubricLevelTitle(mark?.level ?? 0)).font(.caption.weight(.bold)).foregroundStyle(Brand.redSoft)
                    }
                    if let feedback = mark?.feedback, !feedback.isEmpty {
                        Text(feedback).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !submission.overallFeedback.isEmpty {
                Divider()
                Text("Examiner feedback").font(.headline)
                Text(submission.overallFeedback).font(.subheadline)
            }
        }
    }

    private func record(for assignment: StudyAssignment) -> StudyAssignmentSubmissionRecord {
        if let submission { return submission }
        let record = StudyAssignmentSubmissionRecord(
            subjectID: subjectID,
            candidateDisplayName: auth.displayName,
            courseID: assignment.courseID,
            assignmentID: assignment.id
        )
        modelContext.insert(record)
        return record
    }

    private func saveDraft(_ assignment: StudyAssignment) {
        let record = record(for: assignment)
        record.draftMarkdown = draft
        record.updatedAt = .now
        if record.submissionStatus == .returned { record.submissionStatus = .draft }
        persist(success: "Draft saved")
    }

    private func submit(_ assignment: StudyAssignment) {
        let record = record(for: assignment)
        record.draftMarkdown = draft
        record.candidateDisplayName = auth.displayName
        record.submissionStatus = .submitted
        record.submittedAt = .now
        record.updatedAt = .now
        persist(success: "Assignment submitted for marking")
    }

    private func persist(success: String) {
        do { try modelContext.save(); message = success }
        catch { modelContext.rollback(); message = error.localizedDescription }
    }

    private func rubricLevelTitle(_ level: Int) -> String {
        switch level {
        case 4: "Excellent"
        case 3: "Competent"
        case 2: "Developing"
        case 1: "Insufficient"
        default: "Not marked"
        }
    }
}

struct StudyCourseExamScreen: View {
    let assessmentID: String
    @Environment(StudyCourseLibrary.self) private var library

    var body: some View {
        Group {
            if let exam = library.assessment(id: assessmentID), exam.kind == .courseFinal {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        StudyAcademicHeader(
                            eyebrow: "COURSE FINAL · CANDIDATE PAPER",
                            title: exam.title,
                            message: "Complete, read-only examination material for study during the external beta",
                            systemImage: "checkmark.seal"
                        )
                        Label("Timed response fields, submission, examiner marking, and formal grades are disabled in this beta.", systemImage: "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .studyPaperSurface(cornerRadius: 14)
                        if let sourceMarkdown = exam.sourceMarkdown,
                           !sourceMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            StudyMarkdownSection(title: "Complete candidate paper", markdown: sourceMarkdown)
                        }
                        StudyCourseSection(title: "Candidate instructions") {
                            if let materials = exam.permittedMaterials {
                                Label(materials, systemImage: "books.vertical")
                                    .font(.subheadline)
                            }
                            Text("Answer every required question according to each section's response policy. The examination is separate from ordinary lessons and learning XP.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(exam.examSections ?? []) { section in
                            StudyCourseSection(title: "Section \(section.id.suffix(1)) · \(section.title)") {
                                Text(section.responsePolicy == "all" ? "Answer all questions" : "Choose one question")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Brand.redSoft)
                                ForEach(section.questions) { question in
                                    VStack(alignment: .leading, spacing: 7) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(question.code).font(.subheadline.weight(.bold)).foregroundStyle(Brand.redSoft)
                                            if !question.title.isEmpty {
                                                Text(question.title).font(.subheadline.weight(.semibold))
                                            }
                                            Spacer()
                                            Text("\(question.points) marks").font(.caption).foregroundStyle(.secondary)
                                        }
                                        StudyMarkdownDocument(markdown: question.promptMarkdown)
                                    }
                                    .padding(13)
                                    .background(Brand.subtleFill.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                        Label("Examiner marking guidance is stored as a restricted resource and is not included in the learner application bundle.", systemImage: "lock.shield")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .padding(.bottom, 36)
                }
            } else {
                ContentUnavailableView("Examination unavailable", systemImage: "doc.badge.ellipsis")
            }
        }
        .navigationTitle("Final Examination")
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
    }
}

struct StudyCourseMarkingScreen: View {
    let courseID: String
    @Environment(StudyCourseLibrary.self) private var library
    @Environment(RouterPath.self) private var router
    @Environment(AuthStore.self) private var auth
    @Query private var assignments: [StudyAssignmentSubmissionRecord]
    @Query private var exams: [StudyExamSubmissionRecord]

    var body: some View {
        Group {
            if AppFeatureFlags.examinerGradingEnabled, StudyAcademicRolePolicy.canGrade(profile: auth.profile) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        StudyAcademicHeader(
                            eyebrow: "EXAMINER ONLY",
                            title: "Marking desk",
                            message: library.course(id: courseID)?.title ?? courseID,
                            systemImage: "lock.shield"
                        )
                        StudyCourseSection(title: "Assignment submissions") {
                            let records = assignments.filter { $0.courseID == courseID && $0.submissionStatus != .draft }
                            if records.isEmpty { Text("No assignment submissions are awaiting this local marking desk.").foregroundStyle(.secondary) }
                            ForEach(records) { record in
                                StudyCourseNavigationButton(
                                    title: library.assignment(id: record.assignmentID).map { "\($0.code) · \($0.title)" } ?? record.assignmentID,
                                    detail: "\(record.candidateDisplayName) · \(record.submissionStatus.title)",
                                    systemImage: record.submissionStatus == .graded ? "checkmark.seal.fill" : "doc.text.magnifyingglass"
                                ) { router.navigate(to: .studyAssignmentMarking(submissionID: record.recordID)) }
                            }
                        }
                        StudyCourseSection(title: "Final examination submissions") {
                            let records = exams.filter { $0.courseID == courseID }
                            if records.isEmpty { Text("No final examinations are awaiting this local marking desk.").foregroundStyle(.secondary) }
                            ForEach(records) { record in
                                StudyCourseNavigationButton(
                                    title: record.title,
                                    detail: "\(record.candidateDisplayName) · \(record.submissionStatus.title)",
                                    systemImage: record.submissionStatus == .graded ? "checkmark.seal.fill" : "doc.text.magnifyingglass"
                                ) { router.navigate(to: .studyExamMarking(submissionID: record.recordID)) }
                            }
                        }
                        Label("Restricted source marking guides remain outside the learner bundle. This desk exposes only submitted work, source-authored public rubrics, mark fields, and examiner feedback.", systemImage: "lock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(16).padding(.bottom, 36)
                }
            } else {
                ContentUnavailableView("Examiner access required", systemImage: "lock.shield")
            }
        }
        .navigationTitle("Marking Desk")
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
    }
}

struct StudyAssignmentMarkingScreen: View {
    let submissionID: String
    @Environment(StudyCourseLibrary.self) private var library
    @Environment(AuthStore.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Query private var submissions: [StudyAssignmentSubmissionRecord]
    @Query private var marks: [StudyRubricMarkRecord]
    @State private var feedback = ""
    @State private var message: String?

    private var submission: StudyAssignmentSubmissionRecord? { submissions.first { $0.recordID == submissionID } }
    private var assignment: StudyAssignment? { submission.flatMap { library.assignment(id: $0.assignmentID) } }
    private var subjectID: String { auth.studySubjectID ?? "examiner.local" }

    var body: some View {
        Group {
            if !AppFeatureFlags.examinerGradingEnabled || !StudyAcademicRolePolicy.canGrade(profile: auth.profile) {
                ContentUnavailableView("Examiner access required", systemImage: "lock.shield")
            } else if let submission, let assignment {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        StudyAcademicHeader(
                            eyebrow: "\(assignment.code) · \(assignment.weightPercent)%",
                            title: assignment.title,
                            message: "Candidate: \(submission.candidateDisplayName)",
                            systemImage: "doc.text.magnifyingglass"
                        )
                        StudyCourseSection(title: "Submitted response") {
                            Text(submission.draftMarkdown).textSelection(.enabled)
                        }
                        StudyCourseSection(title: "Analytic rubric") {
                            ForEach(assignment.rubricCriteria) { criterion in
                                if let mark = mark(for: criterion) {
                                    StudyRubricMarkEditor(criterion: criterion, mark: mark)
                                    if criterion.id != assignment.rubricCriteria.last?.id { Divider() }
                                }
                            }
                        }
                        StudyCourseSection(title: "Overall feedback") {
                            TextEditor(text: $feedback)
                                .frame(minHeight: 140)
                                .padding(8)
                                .background(Brand.controlFill, in: RoundedRectangle(cornerRadius: 12))
                            Button("Publish grade and feedback") { publish(submission, assignment: assignment) }
                                .frame(maxWidth: .infinity)
                                .studyPrimaryActionStyle()
                                .disabled(!allCriteriaMarked(assignment))
                        }
                    }
                    .padding(16).padding(.bottom, 36)
                }
                .task { prepareMarks(submission, assignment: assignment) }
            } else {
                ContentUnavailableView("Submission unavailable", systemImage: "doc.badge.ellipsis")
            }
        }
        .navigationTitle("Mark Assignment")
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
        .alert("Marking", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK", role: .cancel) {} } message: { Text(message ?? "") }
    }

    private func mark(for criterion: StudyAssignmentRubricCriterion) -> StudyRubricMarkRecord? {
        marks.first { $0.submissionRecordID == submissionID && $0.criterionID == criterion.id }
    }

    private func prepareMarks(_ submission: StudyAssignmentSubmissionRecord, assignment: StudyAssignment) {
        feedback = submission.overallFeedback
        for criterion in assignment.rubricCriteria where mark(for: criterion) == nil {
            modelContext.insert(StudyRubricMarkRecord(
                submissionRecordID: submission.recordID,
                subjectID: submission.subjectID,
                courseID: submission.courseID,
                assignmentID: assignment.id,
                criterionID: criterion.id,
                criterionTitle: criterion.title,
                markedBySubjectID: subjectID
            ))
        }
        try? modelContext.save()
    }

    private func allCriteriaMarked(_ assignment: StudyAssignment) -> Bool {
        assignment.rubricCriteria.allSatisfy { criterion in (1...4).contains(mark(for: criterion)?.level ?? 0) }
    }

    private func publish(_ submission: StudyAssignmentSubmissionRecord, assignment: StudyAssignment) {
        guard allCriteriaMarked(assignment) else { return }
        submission.overallFeedback = feedback
        submission.submissionStatus = .graded
        submission.gradedAt = .now
        submission.markedBySubjectID = subjectID
        submission.markedByDisplayName = auth.displayName
        submission.updatedAt = .now
        do { try modelContext.save(); message = "Grade published" }
        catch { modelContext.rollback(); message = error.localizedDescription }
    }
}

private struct StudyRubricMarkEditor: View {
    let criterion: StudyAssignmentRubricCriterion
    @Bindable var mark: StudyRubricMarkRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(criterion.title).font(.headline)
            Picker("Performance level", selection: $mark.level) {
                Text("Select").tag(0)
                Text("Insufficient").tag(1)
                Text("Developing").tag(2)
                Text("Competent").tag(3)
                Text("Excellent").tag(4)
            }
            .pickerStyle(.menu)
            if mark.level > 0 {
                Text(descriptor).font(.caption).foregroundStyle(.secondary)
            }
            TextField("Criterion feedback", text: $mark.feedback, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...6)
        }
    }

    private var descriptor: String {
        switch mark.level {
        case 4: criterion.excellent
        case 3: criterion.competent
        case 2: criterion.developing
        case 1: criterion.insufficient
        default: ""
        }
    }
}

struct StudyExamMarkingScreen: View {
    let submissionID: String
    @Environment(AuthStore.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Query private var submissions: [StudyExamSubmissionRecord]
    @Query private var marks: [StudyExamQuestionMarkRecord]
    @State private var feedback = ""
    @State private var message: String?

    private var submission: StudyExamSubmissionRecord? { submissions.first { $0.recordID == submissionID } }
    private var subjectID: String { auth.studySubjectID ?? "examiner.local" }

    var body: some View {
        Group {
            if !AppFeatureFlags.examinerGradingEnabled || !StudyAcademicRolePolicy.canGrade(profile: auth.profile) {
                ContentUnavailableView("Examiner access required", systemImage: "lock.shield")
            } else if let submission {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        StudyAcademicHeader(eyebrow: "FINAL EXAMINATION", title: submission.title, message: "Candidate: \(submission.candidateDisplayName)", systemImage: "checkmark.seal")
                        ForEach(Array(submission.questionIDs.enumerated()), id: \.element) { index, questionID in
                            if let mark = marks.first(where: { $0.examSubmissionID == submission.recordID && $0.questionID == questionID }) {
                                StudyExamQuestionMarkEditor(
                                    code: submission.questionCodes[safe: index] ?? questionID,
                                    prompt: submission.prompts[safe: index] ?? "",
                                    response: submission.responses[safe: index] ?? "No response",
                                    mark: mark
                                )
                            }
                        }
                        StudyCourseSection(title: "Overall feedback") {
                            TextEditor(text: $feedback).frame(minHeight: 140).padding(8).background(Brand.controlFill, in: RoundedRectangle(cornerRadius: 12))
                            Button("Publish examination result") { publish(submission) }
                                .frame(maxWidth: .infinity).studyPrimaryActionStyle()
                        }
                    }
                    .padding(16).padding(.bottom, 36)
                }
                .task { prepareMarks(submission) }
            } else {
                ContentUnavailableView("Examination unavailable", systemImage: "doc.badge.ellipsis")
            }
        }
        .navigationTitle("Mark Examination")
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
        .alert("Marking", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK", role: .cancel) {} } message: { Text(message ?? "") }
    }

    private func prepareMarks(_ submission: StudyExamSubmissionRecord) {
        feedback = submission.overallFeedback
        for (index, questionID) in submission.questionIDs.enumerated()
            where !marks.contains(where: { $0.examSubmissionID == submission.recordID && $0.questionID == questionID }) {
            modelContext.insert(StudyExamQuestionMarkRecord(
                examSubmissionID: submission.recordID,
                questionID: questionID,
                questionCode: submission.questionCodes[safe: index] ?? questionID,
                maxPoints: submission.pointValues[safe: index] ?? 0,
                markedBySubjectID: subjectID
            ))
        }
        try? modelContext.save()
    }

    private func publish(_ submission: StudyExamSubmissionRecord) {
        submission.overallFeedback = feedback
        submission.submissionStatus = .graded
        submission.gradedAt = .now
        submission.markedBySubjectID = subjectID
        submission.markedByDisplayName = auth.displayName
        do { try modelContext.save(); message = "Examination result published" }
        catch { modelContext.rollback(); message = error.localizedDescription }
    }
}

private struct StudyExamQuestionMarkEditor: View {
    let code: String
    let prompt: String
    let response: String
    @Bindable var mark: StudyExamQuestionMarkRecord

    var body: some View {
        StudyCourseSection(title: "\(code) · \(mark.maxPoints) marks") {
            StudyMarkdownDocument(markdown: prompt)
            Divider()
            Text("Candidate response").font(.headline)
            Text(response).textSelection(.enabled)
            Stepper(value: $mark.awardedPoints, in: 0...Double(max(mark.maxPoints, 0)), step: 0.5) {
                LabeledContent("Awarded marks", value: "\(mark.awardedPoints.formatted()) / \(mark.maxPoints)")
            }
            TextField("Question feedback", text: $mark.feedback, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...6)
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}

struct StudyDailyLearningScreen: View {
    @Environment(RouterPath.self) private var router

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                StudyAcademicHeader(
                    eyebrow: "DAILY LEARNING",
                    title: "A small amount, on your terms",
                    message: "Daily activities are optional and never affect course grades. The question catalogue will supply a daily quiz only after suitable items complete editorial review.",
                    systemImage: "sun.max"
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("DAILY QUOTATION").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(Brand.redSoft)
                    Text("“\(DailyQuote.today.text)”")
                        .font(.system(.title3, design: .serif, weight: .medium))
                    Text(DailyQuote.today.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .studyPaperSurface(cornerRadius: 18, emphasized: true)

                StudyDailyAction(
                    title: "Daily quiz",
                    message: "Awaiting a reviewed, cited publication pool.",
                    systemImage: "questionmark.circle",
                    enabled: false,
                    action: {}
                )
                StudyDailyAction(
                    title: "Five-minute review",
                    message: "Work through a small set of questions already due.",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    enabled: true,
                    action: { router.navigate(to: .studyReview) }
                )
                StudyDailyAction(
                    title: "Question catalogue",
                    message: "Browse the canonical bank without changing formal course results.",
                    systemImage: "square.stack.3d.up",
                    enabled: true,
                    action: { router.navigate(to: .studyQuestionCatalogue) }
                )
            }
            .padding(16)
            .padding(.bottom, 36)
        }
        .navigationTitle("Daily Learning")
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
    }
}

struct StudyExercisesScreen: View {
    @Environment(RouterPath.self) private var router

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                StudyAcademicHeader(
                    eyebrow: "PRACTICE & EXERCISES",
                    title: "Interactive when it helps",
                    message: "Exercises belong after difficult lessons, at module endings, or in dedicated preparation—not after every paragraph.",
                    systemImage: "pencil.and.list.clipboard"
                )

                StudyCourseSection(title: "Available now") {
                    Button("Objective practice") { router.navigate(to: .studyPractice) }
                        .studyPrimaryActionStyle()
                    Button("Browse all questions") { router.navigate(to: .studyQuestionCatalogue) }
                        .studySecondaryActionStyle()
                    Button("Wrong-answer review") { router.navigate(to: .studyReview) }
                        .studySecondaryActionStyle()
                }

                StudyCourseSection(title: "Course-linked exercise formats") {
                    ForEach([
                        "Passage analysis", "Argument reconstruction", "Matching and sequencing",
                        "Concept comparison", "Short-answer practice", "Source identification",
                        "Document-analysis worksheets"
                    ], id: \.self) { title in
                        Label(title, systemImage: "circle.dashed")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("These formats are enabled by the content model and will appear when supplied by an authored course package.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .padding(.bottom, 36)
        }
        .navigationTitle("Practice & Exercises")
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
    }
}

private struct StudyCourseRow: View {
    let course: StudyCourse

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(course.type.title, systemImage: course.type == .examPreparation ? "timer" : "book.closed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.redSoft)
                Spacer()
                if course.publicationStatus == .preview {
                    Text("PREVIEW").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                } else if course.publicationStatus == .draftNeedsReview {
                    Text("REVIEW PENDING").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }
            }
            Text(course.title)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(.primary)
            Text(course.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            HStack {
                Text("\(course.modules.count) modules · \(course.estimatedHours) hours")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.right").foregroundStyle(Brand.redSoft)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studyPaperSurface(cornerRadius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct StudyCanonicalGuideRow: View {
    let title: String
    let purpose: String
    let sectionCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.headline, design: .serif, weight: .semibold))
                .foregroundStyle(.primary)
            Text(purpose)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            HStack {
                Text("\(sectionCount) section\(sectionCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.right").foregroundStyle(Brand.redSoft)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studyPaperSurface(cornerRadius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct StudyAcademicHeader: View {
    let eyebrow: String
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Brand.redSoft)
            Text(eyebrow).font(.caption2.weight(.bold)).tracking(0.9).foregroundStyle(Brand.redSoft)
            Text(title).font(.system(.title2, design: .serif, weight: .semibold))
            Text(message).font(.body).lineSpacing(3).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studyPaperSurface(cornerRadius: 20, emphasized: true)
    }
}

private struct StudyCourseSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(.title3, design: .serif, weight: .semibold))
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studyPaperSurface(cornerRadius: 16)
    }
}

private struct StudyCoursePill: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Brand.subtleFill, in: Capsule())
    }
}

private struct StudyCourseMetricTile: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .studyPaperSurface(cornerRadius: 14)
    }
}

private struct StudyCourseLaunchCard: View {
    let isEnrolled: Bool
    let isComplete: Bool
    let destination: StudyLearningProgress.SectionDestination
    let remainingRequiredSectionCount: Int
    let action: () -> Void

    private var eyebrow: String {
        if isComplete { return "COURSE COMPLETE" }
        return isEnrolled ? "UP NEXT" : "START HERE"
    }

    private var actionTitle: String {
        if isComplete { return "Review course" }
        return isEnrolled ? "Continue learning" : "Begin course"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(eyebrow)
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(Brand.redSoft)

            Text("Module \(destination.moduleNumber) · \(destination.moduleTitle)")
                .font(.system(.title3, design: .serif, weight: .semibold))

            Text(destination.blockTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Label(
                    "Section \(destination.sectionNumber) of \(destination.sectionCount)",
                    systemImage: "doc.text"
                )
                if !isComplete {
                    Text("·")
                    Text("\(remainingRequiredSectionCount) required remaining")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button(action: action) {
                HStack {
                    Label(actionTitle, systemImage: isComplete ? "arrow.counterclockwise" : "book.pages")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 34)
            }
            .studyPrimaryActionStyle()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studyPaperSurface(cornerRadius: 16, emphasized: true)
    }
}

private struct StudyModuleResources: View {
    let course: StudyCourse
    let module: StudyCourseModule
    let moduleSections: [StudyLearningProgress.SectionDestination]

    var body: some View {
        StudyCourseSection(title: "Module materials and assessment") {
            StudyModuleResourceRows(
                courseID: course.id,
                module: module,
                readingGuideID: course.readingGuideID,
                moduleSections: moduleSections
            )
        }
    }
}

private struct StudyModuleResourceRows: View {
    let courseID: String
    let module: StudyCourseModule
    let readingGuideID: String?
    let moduleSections: [StudyLearningProgress.SectionDestination]

    @Environment(StudyCourseLibrary.self) private var library
    @Environment(RouterPath.self) private var router

    private var exerciseCount: Int {
        module.lessons.reduce(into: 0) { count, lesson in
            count += lesson.blocks.lazy.filter { $0.kind == .exercise }.count
        }
    }

    private var moduleReadingChunk: (guideID: String, chunk: StudyReadingChunk)? {
        guard let readingGuideID,
              let guide = library.readingGuide(id: readingGuideID),
              let chunk = guide.chunks.first(where: { $0.moduleID == module.id }) else { return nil }
        return (guideID: guide.id, chunk: chunk)
    }

    @ViewBuilder
    var body: some View {
        if let match = moduleReadingChunk {
            StudyCourseNavigationButton(
                title: match.chunk.title,
                detail: "Module reading guide",
                systemImage: "book.pages"
            ) {
                router.navigate(to: .studyReadingGuideChunk(guideID: match.guideID, chunkID: match.chunk.id))
            }
            .accessibilityIdentifier("study.course.\(courseID).module.\(module.id).reading-guide")
        } else if let readingGuideID {
            StudyCourseNavigationButton(
                title: "Module reading guide",
                detail: "Open the complete Study and Reading Guide",
                systemImage: "book.pages"
            ) {
                router.navigate(to: .studyReadingGuide(id: readingGuideID))
            }
            .accessibilityIdentifier("study.course.\(courseID).module.\(module.id).reading-guide")
        }

        Label(
            "\(exerciseCount) embedded exercise\(exerciseCount == 1 ? "" : "s") in source order",
            systemImage: "pencil.and.list.clipboard"
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("study.course.\(courseID).module.\(module.id).exercise-count")

        if let quizID = module.moduleQuizID,
           let quiz = library.assessment(id: quizID) {
            StudyCourseNavigationButton(
                title: quiz.title,
                detail: moduleQuizDetail(quiz),
                systemImage: "checkmark.seal"
            ) {
                if let destination = moduleSections.last {
                    router.navigate(to: .studyCourseSection(
                        courseID: courseID,
                        moduleID: destination.moduleID,
                        lessonID: destination.lessonID,
                        blockID: destination.blockID
                    ))
                }
            }
            .accessibilityIdentifier("study.course.\(courseID).module.\(module.id).quiz")
        }

        ForEach(module.assignmentIDs ?? [], id: \.self) { assignmentID in
            if let assignment = library.assignment(id: assignmentID) {
                StudyCourseNavigationButton(
                    title: "\(assignment.code) · \(assignment.title)",
                    detail: "Formal assignment · \(assignment.weightPercent)%",
                    systemImage: "doc.badge.clock"
                ) {
                    router.navigate(to: .studyAssignment(id: assignment.id))
                }
                .accessibilityIdentifier("study.assignment.\(assignment.id)")
            }
        }
    }

    private func moduleQuizDetail(_ quiz: StudyCourseAssessmentBlueprint) -> String {
        var components = ["Module quiz", "\(quiz.requestedQuestionCount) questions"]
        if let minimum = quiz.recommendedTimeMinimumMinutes,
           let maximum = quiz.recommendedTimeMaximumMinutes {
            components.append("recommended \(minimum)–\(maximum) min")
        } else if let minimum = quiz.recommendedTimeMinimumMinutes {
            components.append("recommended from \(minimum) min")
        } else if let maximum = quiz.recommendedTimeMaximumMinutes {
            components.append("recommended up to \(maximum) min")
        }
        components.append("follows the final section")
        return components.joined(separator: " · ")
    }
}

private struct StudySectionLearningGoals: View {
    let objectives: [String]
    let essentialQuestions: [String]

    private var visibleObjectives: [String] {
        objectives.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var visibleQuestions: [String] {
        essentialQuestions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        StudyCourseSection(title: "Before you read") {
            if !visibleObjectives.isEmpty {
                Text("Learning goals")
                    .font(.subheadline.weight(.semibold))
                ForEach(visibleObjectives, id: \.self) { objective in
                    Label(objective, systemImage: "target")
                        .font(.subheadline)
                }
            }

            if !visibleQuestions.isEmpty {
                if !visibleObjectives.isEmpty { Divider() }
                Text("Essential questions")
                    .font(.subheadline.weight(.semibold))
                ForEach(visibleQuestions, id: \.self) { question in
                    Label(question, systemImage: "questionmark.bubble")
                        .font(.subheadline)
                }
            }
        }
    }
}

private struct StudySectionWorkspace: View {
    @Binding var notesMarkdown: String
    @Binding var reflectionMarkdown: String
    @Binding var summaryMarkdown: String
    @Binding var confidence: Int?
    let reflectionPrompts: [String]
    let accessibilityPrefix: String

    private var visiblePrompts: [String] {
        reflectionPrompts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        StudyCourseSection(title: "Notes & reflection") {
            Label("Private study workspace · saved locally", systemImage: "lock.doc")
                .font(.caption)
                .foregroundStyle(.secondary)

            StudyWorkspaceEditor(
                title: "Notes",
                prompt: "Capture key ideas, passages, or questions…",
                accessibilityIdentifier: "\(accessibilityPrefix).notes",
                text: $notesMarkdown
            )

            if !visiblePrompts.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Reflection prompts")
                        .font(.subheadline.weight(.semibold))
                    ForEach(visiblePrompts, id: \.self) { prompt in
                        Label(prompt, systemImage: "quote.bubble")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            StudyWorkspaceEditor(
                title: "Reflection",
                prompt: "Respond in your own words…",
                accessibilityIdentifier: "\(accessibilityPrefix).reflection",
                text: $reflectionMarkdown
            )

            StudyWorkspaceEditor(
                title: "One-sentence summary",
                prompt: "What is the central point of this section?",
                minimumHeight: 76,
                accessibilityIdentifier: "\(accessibilityPrefix).summary",
                text: $summaryMarkdown
            )

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Confidence")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("1 unsure · 5 confident")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Picker("Confidence", selection: $confidence) {
                    Text("—").tag(nil as Int?)
                    ForEach(1...5, id: \.self) { value in
                        Text("\(value)").tag(value as Int?)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("\(accessibilityPrefix).confidence")
            }
        }
        .accessibilityIdentifier(accessibilityPrefix)
    }
}

private struct StudyWorkspaceEditor: View {
    let title: String
    let prompt: String
    var minimumHeight: CGFloat = 112
    let accessibilityIdentifier: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(prompt)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: minimumHeight)
                    .accessibilityLabel(title)
                    .accessibilityIdentifier(accessibilityIdentifier)
            }
            .padding(7)
            .background(Brand.controlFill, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct StudySectionNavigation: View {
    let previous: StudyLearningProgress.SectionDestination?
    let next: StudyLearningProgress.SectionDestination?
    let conclusionAvailable: Bool
    let finalAssessmentAvailable: Bool
    let openSection: (StudyLearningProgress.SectionDestination) -> Void
    let openConclusion: () -> Void
    let openFinalAssessment: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let previous {
                Button {
                    openSection(previous)
                } label: {
                    HStack {
                        Image(systemName: "arrow.left")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Previous section").font(.caption)
                            Text(previous.blockTitle).font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
                .studySecondaryActionStyle()
                .accessibilityIdentifier("study.course.section.previous")
            }

            if let next {
                Button {
                    openSection(next)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next section").font(.caption)
                            Text(next.blockTitle).font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
                .studyPrimaryActionStyle()
                .accessibilityIdentifier("study.course.section.next")
            } else if conclusionAvailable {
                Button(action: openConclusion) {
                    HStack {
                        Label("Continue to course conclusion", systemImage: "flag.checkered")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
                .studyPrimaryActionStyle()
                .accessibilityIdentifier("study.course.section.conclusion")
            } else if finalAssessmentAvailable {
                Button(action: openFinalAssessment) {
                    HStack {
                        Label("Continue to final examination", systemImage: "checkmark.seal")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
                .studyPrimaryActionStyle()
                .accessibilityIdentifier("study.course.section.final-exam")
            } else {
                Label("End of the authored course sections", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .studyPaperSurface(cornerRadius: 16)
    }
}

private struct StudyCourseModuleCard: View {
    let courseID: String
    let moduleNumber: Int
    let module: StudyCourseModule
    let readingGuideID: String?
    let completedLessonIDs: Set<String>
    let completedRequiredBlockIDs: Set<String>

    @Environment(StudyCourseLibrary.self) private var library
    @Environment(RouterPath.self) private var router

    private var sections: [StudyLearningProgress.SectionDestination] {
        library.sectionDestinations(courseID: courseID).filter { $0.moduleID == module.id }
    }

    private var completedSectionCount: Int {
        sections.lazy.filter {
            StudyLearningProgress.isSectionCompleted(
                $0,
                completedLessonIDs: completedLessonIDs,
                completedRequiredBlockIDs: completedRequiredBlockIDs
            )
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("MODULE \(moduleNumber)")
                    .font(.caption2.weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(Brand.redSoft)
                Spacer()
                Text("\(completedSectionCount)/\(sections.count) sections")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(module.title)
                .font(.system(.headline, design: .serif, weight: .semibold))

            if let lessonID = sections.first?.lessonID ?? module.lessons.first?.id {
                Button {
                    router.navigate(to: .studyLesson(
                        courseID: courseID,
                        moduleID: module.id,
                        lessonID: lessonID
                    ))
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundStyle(Brand.redSoft)
                        Text("Open module contents")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("study.course.\(courseID).module.\(module.id).contents")
            }

            Divider()

            ForEach(sections) { destination in
                StudyCourseNavigationButton(
                    title: destination.blockTitle,
                    detail: "Section \(destination.sectionNumber) of \(destination.sectionCount)",
                    systemImage: isCompleted(destination) ? "checkmark.circle.fill" : "doc.text"
                ) {
                    open(destination)
                }
                .id(destination.blockID)
                .accessibilityLabel("Section \(destination.sectionNumber) of \(destination.sectionCount), \(destination.blockTitle)\(isCompleted(destination) ? ", completed" : "")")
                .accessibilityIdentifier("study.course.section-row.\(destination.blockID)")
            }

            Divider()

            StudyModuleResourceRows(
                courseID: courseID,
                module: module,
                readingGuideID: readingGuideID,
                moduleSections: sections
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studyPaperSurface(cornerRadius: 14)
    }

    private func isCompleted(_ destination: StudyLearningProgress.SectionDestination) -> Bool {
        StudyLearningProgress.isSectionCompleted(
            destination,
            completedLessonIDs: completedLessonIDs,
            completedRequiredBlockIDs: completedRequiredBlockIDs
        )
    }

    private func open(_ destination: StudyLearningProgress.SectionDestination) {
        router.navigate(to: .studyCourseSection(
            courseID: courseID,
            moduleID: destination.moduleID,
            lessonID: destination.lessonID,
            blockID: destination.blockID
        ))
    }
}

private struct StudyCollapsibleModuleCard: View {
    let course: StudyCourse
    let module: StudyCourseModule
    let moduleNumber: Int
    let completedLessonIDs: Set<String>
    let completedRequiredBlockIDs: Set<String>
    let isExpanded: Bool
    let toggle: () -> Void

    @Environment(StudyCourseLibrary.self) private var library
    @Environment(RouterPath.self) private var router

    private var sections: [StudyLearningProgress.SectionDestination] {
        library.sectionDestinations(courseID: course.id).filter { $0.moduleID == module.id }
    }

    private var completedCount: Int {
        trackedSections.filter {
            StudyLearningProgress.isSectionCompleted(
                $0,
                completedLessonIDs: completedLessonIDs,
                completedRequiredBlockIDs: completedRequiredBlockIDs
            )
        }.count
    }

    private var trackedSections: [StudyLearningProgress.SectionDestination] {
        let required = sections.filter(\.isRequired)
        return required.isEmpty ? sections : required
    }

    private var statusTitle: String {
        guard !trackedSections.isEmpty, completedCount > 0 else { return "Not started" }
        return completedCount == trackedSections.count ? "Complete" : "In progress"
    }

    private var statusSystemImage: String {
        switch statusTitle {
        case "Complete": "checkmark.circle.fill"
        case "In progress": "circle.lefthalf.filled"
        default: "circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("MODULE \(moduleNumber)")
                            .font(.caption2.weight(.bold))
                            .tracking(0.7)
                            .foregroundStyle(Brand.redSoft)
                        Spacer()
                        Label(statusTitle, systemImage: statusSystemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(statusTitle == "Complete" ? Brand.redSoft : .secondary)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .foregroundStyle(.secondary)
                    }
                    Text(module.title)
                        .font(.system(.headline, design: .serif, weight: .semibold))
                        .multilineTextAlignment(.leading)
                    HStack {
                        Text("\(completedCount) of \(trackedSections.count) required sections")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    ProgressView(value: trackedSections.isEmpty ? 0 : Double(completedCount) / Double(trackedSections.count))
                        .tint(Brand.red)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(15)

            if isExpanded {
                Divider().padding(.horizontal, 15)
                VStack(alignment: .leading, spacing: 8) {
                    if let lessonID = module.lessons.first?.id {
                        StudyCourseNavigationButton(
                            title: "Module overview",
                            detail: module.summary,
                            systemImage: "list.bullet.rectangle"
                        ) {
                            router.navigate(to: .studyLesson(courseID: course.id, moduleID: module.id, lessonID: lessonID))
                        }
                    }
                    ForEach(sections) { destination in
                        let completed = StudyLearningProgress.isSectionCompleted(
                            destination,
                            completedLessonIDs: completedLessonIDs,
                            completedRequiredBlockIDs: completedRequiredBlockIDs
                        )
                        StudyCourseNavigationButton(
                            title: destination.blockTitle,
                            detail: "Section \(destination.sectionNumber) of \(destination.sectionCount)",
                            systemImage: completed ? "checkmark.circle.fill" : "doc.text"
                        ) {
                            router.navigate(to: .studyCourseSection(
                                courseID: course.id,
                                moduleID: destination.moduleID,
                                lessonID: destination.lessonID,
                                blockID: destination.blockID
                            ))
                        }
                    }
                    Divider()
                    StudyModuleResourceRows(
                        courseID: course.id,
                        module: module,
                        readingGuideID: course.readingGuideID,
                        moduleSections: sections
                    )
                }
                .padding(15)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .studyPaperSurface(cornerRadius: 15)
        .accessibilityIdentifier("study.course.\(course.id).module.\(module.id).collapsible")
    }
}

private struct StudyCourseNavigationButton: View {
    let title: String
    var detail: String? = nil
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 11) {
                Image(systemName: systemImage)
                    .foregroundStyle(Brand.redSoft)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.leading)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct StudyLessonBlockView: View {
    let block: StudyLessonBlock
    let exerciseSet: StudyExerciseSet?
    let isWorking: Bool
    let open: (StudyLessonBlock) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(block.kind.title, systemImage: block.kind.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.redSoft)
                Spacer()
                Text(block.requirement.rawValue.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            if block.kind != .exercise {
                Text(block.title).font(.system(.headline, design: .serif, weight: .semibold))
            }
            if !block.summary.isEmpty, block.kind != .exercise {
                Text(block.summary).font(.subheadline).foregroundStyle(.secondary)
            }
            if let markdown = block.bodyMarkdown, !markdown.isEmpty {
                StudyMarkdownDocument(markdown: markdown)
            }
            if block.kind == .exercise {
                if let exerciseSet, !exerciseSet.exercises.isEmpty {
                    ForEach(exerciseSet.exercises) { exercise in
                        if exercise.id != exerciseSet.exercises.first?.id {
                            Divider()
                        }
                        StudyInlineExercise(exercise: exercise)
                    }
                } else {
                    Label("Exercise content unavailable", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if block.kind != .lessonContent {
                Button {
                    open(block)
                } label: {
                    if isWorking {
                        Label("Preparing…", systemImage: "hourglass")
                    } else {
                        Text("Open")
                    }
                }
                    .studySecondaryActionStyle()
                    .disabled(isWorking)
            }
        }
        .padding(16)
        .studyPaperSurface(cornerRadius: 16)
    }
}

private struct StudyInlineExercise: View {
    let exercise: StudyExercise
    @Environment(AuthStore.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Query private var learningEvents: [StudyLearningEventRecord]
    @State private var showsGuidance = false

    private var subjectID: String { auth.studySubjectID ?? "guest.local" }
    private var eventID: String {
        StudyLearningProgress.eventID(subjectID: subjectID, kind: .exerciseCompleted, contentID: exercise.id)
    }
    private var isCompleted: Bool { learningEvents.contains { $0.eventID == eventID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = exercise.title, !title.isEmpty {
                Text(title)
                    .font(.system(.headline, design: .serif, weight: .semibold))
            }
            StudyMarkdownDocument(markdown: exercise.promptMarkdown)
            if let instructions = exercise.instructions, !instructions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Instructions")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Brand.redSoft)
                    ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(Brand.redSoft)
                            Text(instruction).font(.subheadline)
                        }
                    }
                }
            }
            if let response = exercise.recommendedResponse, !response.isEmpty {
                Label(response, systemImage: "text.word.spacing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let guidance = exercise.solutionMarkdown, !guidance.isEmpty {
                DisclosureGroup(isExpanded: $showsGuidance) {
                    StudyMarkdownDocument(markdown: guidance)
                        .padding(.top, 8)
                } label: {
                    Label("Reveal model guidance", systemImage: "eye")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(Brand.redSoft)
            }
            Button {
                setCompleted(!isCompleted)
            } label: {
                Label(isCompleted ? "Exercise completed" : "Mark exercise complete", systemImage: isCompleted ? "checkmark.circle.fill" : "circle")
                    .frame(maxWidth: .infinity)
            }
            .studySecondaryActionStyle()
        }
    }

    private func setCompleted(_ completed: Bool) {
        if completed {
            modelContext.insert(StudyLearningEventRecord(
                eventID: eventID,
                subjectID: subjectID,
                kind: StudyLearningEventKind.exerciseCompleted.rawValue,
                contentID: exercise.id,
                points: StudyLearningEventKind.exerciseCompleted.points
            ))
        } else if let event = learningEvents.first(where: { $0.eventID == eventID }) {
            modelContext.delete(event)
        }
        try? modelContext.save()
    }
}

private extension StudyLessonBlockKind {
    var title: String {
        switch self {
        case .lessonContent: "Lesson"
        case .primaryReading: "Assigned reading"
        case .studyGuide: "Study Guide"
        case .readingGuide: "Reading Guide"
        case .video: "Optional video"
        case .exercise: "Exercise"
        case .lessonCheck: "Lesson check"
        case .moduleQuiz: "Module quiz"
        }
    }

    var systemImage: String {
        switch self {
        case .lessonContent: "doc.text"
        case .primaryReading: "book"
        case .studyGuide: "doc.text.magnifyingglass"
        case .readingGuide: "book.pages"
        case .video: "play.rectangle"
        case .exercise: "pencil.and.list.clipboard"
        case .lessonCheck: "checkmark.circle"
        case .moduleQuiz: "checkmark.seal"
        }
    }
}

private struct StudyMarkdownSection: View {
    let title: String
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(.title3, design: .serif, weight: .semibold))
            StudyMarkdownDocument(markdown: markdown)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studyPaperSurface(cornerRadius: 16)
    }
}

private struct StudyDailyAction: View {
    let title: String
    let message: String
    let systemImage: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(enabled ? Brand.redSoft : .secondary)
                    .frame(width: 38, height: 38)
                    .background(Brand.subtleFill, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: enabled ? "chevron.right" : "lock")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .studyPaperSurface(cornerRadius: 15)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
