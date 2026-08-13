import SwiftUI
import SwiftData

enum StudyContentKind: String, CaseIterable, Identifiable, Hashable {
    case studyGuides
    case readingGuides
    case videos
    case quizzes
    case courses
    case exams

    var id: String { rawValue }

    var title: String {
        switch self {
        case .studyGuides: "Study Guides"
        case .readingGuides: "Reading Guides"
        case .videos: "Videos"
        case .quizzes: "Quizzes"
        case .courses: "Courses"
        case .exams: "Exams"
        }
    }

    var eyebrow: String {
        switch self {
        case .studyGuides: "TOPIC-BASED"
        case .readingGuides: "TEXT-BASED"
        case .videos: "WATCH & LISTEN"
        case .quizzes: "PRACTICE"
        case .courses: "FULL PATHS"
        case .exams: "ASSESSMENT"
        }
    }

    var description: String {
        switch self {
        case .studyGuides:
            "Key ideas, definitions, and questions organised by subject."
        case .readingGuides:
            "Structured companions for individual books, texts, and chapters."
        case .videos:
            "Lectures and explainers with chapters, transcripts, and sources."
        case .quizzes:
            "Short practice sets with explanations and opportunities to retry."
        case .courses:
            "Complete learning paths built from lessons, readings, and practice."
        case .exams:
            "Timed objective practice with review and detailed result breakdowns."
        }
    }

    var systemImage: String {
        switch self {
        case .studyGuides: "doc.text"
        case .readingGuides: "book.pages"
        case .videos: "play.rectangle"
        case .quizzes: "checkmark.circle"
        case .courses: "rectangle.stack"
        case .exams: "timer"
        }
    }

    var collectionIntroduction: String {
        switch self {
        case .studyGuides:
            "Build a working understanding of a subject through concise explanations, concepts, and questions."
        case .readingGuides:
            "Read difficult texts with context, chapter prompts, key passages, and questions for reflection."
        case .videos:
            "Follow lectures and visual explainers, then continue into their related texts and exercises."
        case .quizzes:
            "Check your understanding in a low-pressure format and learn from every answer."
        case .courses:
            "Move through ordered modules that combine theory, reading, video, and assessment."
        case .exams:
            "Rehearse focused assessments with clear rules, timing, and result breakdowns."
        }
    }
}

struct StudyResource: Identifiable, Hashable {
    let id: String
    let kind: StudyContentKind
    let title: String
    let summary: String
    let metadata: String
    let level: String
}

private enum StudyCatalog {
    static let featuredCourse = StudyResource(
        id: "start-here",
        kind: .courses,
        title: "Start Here: How to Study Marxist Theory",
        summary: "Learn to read theory as an argument, take useful notes, and build a map of the Marxist canon.",
        metadata: "2 weeks · Guided path",
        level: "Orientation"
    )

    static let historicalMaterialismGuide = StudyResource(
        id: "historical-materialism-guide",
        kind: .studyGuides,
        title: "Historical Materialism",
        summary: "A practical guide to forces, relations, and modes of production.",
        metadata: "35 min",
        level: "Core concept"
    )

    static let manifestoReadingGuide = StudyResource(
        id: "manifesto-reading-guide",
        kind: .readingGuides,
        title: "The Communist Manifesto",
        summary: "Read the text in context with section prompts and key passages.",
        metadata: "5 sections",
        level: "Guided reading"
    )

    static let featured: [StudyResource] = [
        historicalMaterialismGuide,
        manifestoReadingGuide
    ]

    static let resources: [StudyResource] = [
        featuredCourse,
        historicalMaterialismGuide,
        StudyResource(
            id: "dialectics-guide",
            kind: .studyGuides,
            title: "Dialectics as a Method",
            summary: "Contradiction, change, totality, and concrete analysis without empty formulas.",
            metadata: "6 sections · 40 min",
            level: "Intermediate"
        ),
        manifestoReadingGuide,
        StudyResource(
            id: "capital-volume-one-guide",
            kind: .readingGuides,
            title: "Capital, Volume I",
            summary: "A chapter-by-chapter route through commodity, value, money, and capital.",
            metadata: "12 parts",
            level: "Advanced reading"
        ),
        StudyResource(
            id: "historical-materialism-quiz",
            kind: .quizzes,
            title: "Historical Materialism Check-in",
            summary: "Practice identifying material forces, class relations, and historical change.",
            metadata: "10 questions · Untimed",
            level: "Practice"
        ),
        StudyResource(
            id: "political-economy-quiz",
            kind: .quizzes,
            title: "Basic Principles Drill",
            summary: "Practice reviewed questions across philosophy, knowledge, history, and political economy.",
            metadata: "Editorial review in progress",
            level: "Question bank"
        ),
        StudyResource(
            id: "manifesto-course",
            kind: .courses,
            title: "Manifesto of the Communist Party",
            summary: "A paced reading course covering context, class struggle, communist politics, and rival socialist traditions.",
            metadata: "4 weeks · Guided reading",
            level: "First release"
        ),
        StudyResource(
            id: "theses-feuerbach-course",
            kind: .courses,
            title: "Theses on Feuerbach",
            summary: "A focused course on activity, practice, social relations, and transformation.",
            metadata: "3 weeks · Guided reading",
            level: "First release"
        ),
        StudyResource(
            id: "foundations-exam",
            kind: .exams,
            title: "Foundations Assessment",
            summary: "A full assessment covering the concepts introduced in the foundations course.",
            metadata: "60 min · 40 questions",
            level: "Course exam"
        ),
        StudyResource(
            id: "political-economy-exam",
            kind: .exams,
            title: "Political Economy Assessment",
            summary: "Test conceptual knowledge and applied analysis across the political economy path.",
            metadata: "90 min · 50 questions",
            level: "Full exam"
        )
    ]

    static func resources(for kind: StudyContentKind) -> [StudyResource] {
        resources.filter { $0.kind == kind }
    }
}

private enum StudyLayout {
    static let horizontal: CGFloat = 16
    static let sectionSpacing: CGFloat = 26
    static let cardSpacing: CGFloat = 12
    static let bottomClearance: CGFloat = 112
}

struct StudyCourseProgressSummary {
    let fraction: Double
    let completedRequiredSections: Int
    let totalRequiredSections: Int
    let nextSection: StudyLearningProgress.SectionDestination?

    init(course: StudyCourse, progress: StudyCourseProgressRecord?) {
        let completedLessons = Set(progress?.completedLessonIDs ?? [])
        let completedBlocks = Set(progress?.completedRequiredBlockIDs ?? [])
        let requiredSections = StudyLearningProgress.sectionDestinations(for: course).filter(\.isRequired)

        fraction = StudyLearningProgress.fraction(
            for: course,
            completedLessonIDs: completedLessons,
            completedRequiredBlockIDs: completedBlocks
        )
        completedRequiredSections = requiredSections.lazy.filter {
            StudyLearningProgress.isSectionCompleted(
                $0,
                completedLessonIDs: completedLessons,
                completedRequiredBlockIDs: completedBlocks
            )
        }.count
        totalRequiredSections = requiredSections.count
        nextSection = StudyLearningProgress.nextSection(
            for: course,
            completedLessonIDs: completedLessons,
            completedRequiredBlockIDs: completedBlocks
        )
    }

    var percentage: Int {
        Int((fraction * 100).rounded())
    }
}

struct StudyScreen: View {
    @Environment(RouterPath.self) private var router
    @Environment(StudyCourseLibrary.self) private var library
    @Environment(AuthStore.self) private var auth
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var progressRecords: [StudyCourseProgressRecord]
    @Query private var learningEvents: [StudyLearningEventRecord]

    private var subjectID: String { auth.studySubjectID ?? "guest.local" }
    private var realCourses: [StudyCourse] { library.courses.filter { $0.publicationStatus != .preview } }
    private var visibleContentKinds: [StudyContentKind] {
        StudyContentKind.allCases.filter { $0 != .videos || AppFeatureFlags.educationalVideosEnabled }
    }
    private var recommendedCourse: StudyCourse? {
        realCourses.first { progress(for: $0) != nil && fraction(for: $0) < 1 }
            ?? realCourses.first { $0.id == "PHI111" }
            ?? realCourses.first
    }

    private var pathwayColumns: [GridItem] {
        let minimumWidth: CGFloat = dynamicTypeSize.isAccessibilitySize ? 260 : 150
        return [GridItem(.adaptive(minimum: minimumWidth), spacing: StudyLayout.cardSpacing)]
    }

    private func destination(for kind: StudyContentKind) -> Route {
        switch kind {
        case .quizzes:
            .studyPractice
        case .exams:
            .studyExams
        case .studyGuides, .readingGuides, .videos, .courses:
            .studyCollection(kind: kind)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: StudyLayout.sectionSpacing) {
                StudyQuickDock { route in
                    router.navigate(to: route)
                }

                StudyMasthead()

                StudySectionHeader(
                    eyebrow: "ONE CENTER, FIVE LAYERS",
                    title: "Choose the depth you need",
                    message: "Courses remain the academic core. Practice, daily learning, review, and exams support them without taking over."
                )
                LazyVGrid(columns: pathwayColumns, spacing: StudyLayout.cardSpacing) {
                    ForEach(StudyCenterLayer.allCases) { layer in
                        Button {
                            router.navigate(to: layer.route)
                        } label: {
                            StudyLayerCard(layer: layer)
                        }
                        .buttonStyle(PressableScaleButtonStyle(scale: 0.975))
                    }
                }

                StudySectionHeader(
                    eyebrow: "RECOMMENDED PATH",
                    title: "Start here",
                    message: "Build a foundation before moving into specialised study."
                )
                if let course = recommendedCourse {
                    let record = progress(for: course)
                    let summary = StudyCourseProgressSummary(course: course, progress: record)
                    StudyLiveCourseCard(
                        course: course,
                        progress: summary,
                        isEnrolled: record != nil
                    ) {
                        if record != nil, let nextSection = summary.nextSection {
                            router.navigate(to: .studyCourseSection(
                                courseID: course.id,
                                moduleID: nextSection.moduleID,
                                lessonID: nextSection.lessonID,
                                blockID: nextSection.blockID
                            ))
                        } else {
                            router.navigate(to: .studyCourse(id: course.id))
                        }
                    }
                } else {
                    ContentUnavailableView("Courses unavailable", systemImage: "rectangle.stack.badge.exclamationmark")
                }

                StudySectionHeader(
                    eyebrow: "STUDY LIBRARY",
                    title: "Choose how to learn",
                    message: "Each format can stand alone or form part of a complete course."
                )
                LazyVGrid(columns: pathwayColumns, spacing: StudyLayout.cardSpacing) {
                    ForEach(visibleContentKinds) { kind in
                        Button {
                            router.navigate(to: destination(for: kind))
                        } label: {
                            StudyPathwayCard(kind: kind)
                        }
                        .buttonStyle(PressableScaleButtonStyle(scale: 0.975))
                        .accessibilityHint("Opens \(kind.title.lowercased())")
                    }
                }

                StudySectionHeader(
                    eyebrow: "FROM THE CURRICULUM",
                    title: "Featured studies",
                    message: "Shorter materials for beginning a new line of inquiry."
                )
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: StudyLayout.cardSpacing) {
                        ForEach(realCourses) { course in
                            Button {
                                router.navigate(to: .studyCourse(id: course.id))
                            } label: {
                                StudyLiveFeaturedCourseCard(course: course, fraction: fraction(for: course))
                            }
                            .buttonStyle(PressableScaleButtonStyle(scale: 0.975))
                        }
                    }
                    .padding(.horizontal, StudyLayout.horizontal)
                }
                .contentMargins(.horizontal, -StudyLayout.horizontal, for: .scrollContent)

                StudyAssessmentPanel(
                    openQuizzes: { router.navigate(to: .studyPractice) },
                    openExams: { router.navigate(to: .studyExams) }
                )

                Color.clear
                    .frame(height: StudyLayout.bottomClearance)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, StudyLayout.horizontal)
            .padding(.top, 8)
        }
        .navigationTitle("Study Center")
        .background(ScreenBackground())
    }

    private func progress(for course: StudyCourse) -> StudyCourseProgressRecord? {
        progressRecords.first { $0.subjectID == subjectID && $0.courseID == course.id }
    }

    private func fraction(for course: StudyCourse) -> Double {
        let record = progress(for: course)
        return StudyLearningProgress.fraction(
            for: course,
            completedLessonIDs: Set(record?.completedLessonIDs ?? []),
            completedRequiredBlockIDs: Set(record?.completedRequiredBlockIDs ?? [])
        )
    }
}

private enum StudyDockDestination: String, CaseIterable, Identifiable {
    case paths
    case texts
    case practice
    case daily
    case review
    case exams
    case glossary
    case progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paths: "Courses"
        case .texts: "Guides"
        case .practice: "Practice"
        case .daily: "Daily"
        case .review: "Review"
        case .exams: "Exams"
        case .glossary: "Glossary"
        case .progress: "Progress"
        }
    }

    var systemImage: String {
        switch self {
        case .paths: "point.topleft.down.to.point.bottomright.curvepath"
        case .texts: "books.vertical"
        case .practice: "checkmark.circle"
        case .daily: "sun.max"
        case .review: "arrow.trianglehead.2.clockwise.rotate.90"
        case .exams: "timer"
        case .glossary: "character.book.closed"
        case .progress: "chart.bar.xaxis"
        }
    }

    var route: Route {
        switch self {
        case .paths: .studyCollection(kind: .courses)
        case .texts: .studyCollection(kind: .readingGuides)
        case .practice: .studyPractice
        case .daily: .studyDaily
        case .review: .studyReview
        case .exams: .studyExams
        case .glossary: .studyGlossary
        case .progress: .studyProgress
        }
    }
}

private struct StudyQuickDock: View {
    let open: (Route) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Overview")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.onAccent)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Brand.red, in: Capsule())
                    .accessibilityAddTraits(.isSelected)

                ForEach(StudyDockDestination.allCases) { destination in
                    Button {
                        open(destination.route)
                    } label: {
                        Label(destination.title, systemImage: destination.systemImage)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 11)
                            .frame(minHeight: 44)
                            .background(Brand.subtleFill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityLabel("Study sections")
    }
}

private struct StudyMasthead: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Brand.onAccent)
                    .frame(width: 48, height: 48)
                    .background(Brand.red, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Rectangle()
                    .fill(Brand.red.opacity(0.28))
                    .frame(width: 1, height: 66)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 9) {
                Text("THE STUDY CENTER")
                    .font(.caption.weight(.bold))
                    .tracking(1.15)
                    .foregroundStyle(Brand.redSoft)
                Text("Learn with purpose.")
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Guided reading, lectures, practice, and complete courses—organised as one continuous path.")
                    .font(.body)
                    .lineSpacing(3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    StudyMetadataPill(systemImage: "clock", text: "Self-paced")
                    StudyMetadataPill(systemImage: "bookmark", text: "Save progress")
                }
                .padding(.top, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studyPaperSurface(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }
}

private struct StudySectionHeader: View {
    let eyebrow: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow)
                .font(.caption2.weight(.bold))
                .tracking(0.9)
                .foregroundStyle(Brand.redSoft)
            Text(title)
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(.primary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StudyLiveCourseCard: View {
    let course: StudyCourse
    let progress: StudyCourseProgressSummary
    let isEnrolled: Bool
    let action: () -> Void

    private var actionTitle: String {
        isEnrolled && progress.nextSection != nil ? "Resume" : "View course"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    StudyIconTile(systemImage: "rectangle.stack.fill", size: 58)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isEnrolled ? "CONTINUE LEARNING" : "ACADEMIC COURSE")
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(Brand.redSoft)
                        Text(course.title)
                            .font(.system(.title2, design: .serif, weight: .semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                Text(course.summary)
                    .font(.subheadline)
                    .lineSpacing(2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 5) {
                    if let nextSection = progress.nextSection {
                        Text(isEnrolled ? "NEXT SECTION" : "START WITH")
                            .font(.caption2.weight(.bold))
                            .tracking(0.7)
                            .foregroundStyle(Brand.redSoft)
                        Text("Module \(nextSection.moduleNumber) · \(nextSection.moduleTitle)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(nextSection.blockTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if isEnrolled {
                        Label("All course sections complete", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Brand.redSoft)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if progress.totalRequiredSections > 0 {
                        Text("\(progress.completedRequiredSections) of \(progress.totalRequiredSections) required sections")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Label("\(course.modules.count) modules · \(course.estimatedHours) hours", systemImage: "list.bullet")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text("\(progress.percentage)%")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Brand.redSoft)
                    Spacer()
                    Label(actionTitle, systemImage: "arrow.right")
                        .labelStyle(StudyTrailingIconLabelStyle())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.redSoft)
                }
                ProgressView(value: progress.fraction)
                    .tint(Brand.red)
                    .accessibilityLabel("Course progress")
                    .accessibilityValue("\(progress.percentage) percent")
                    .accessibilityIdentifier("study.recommended-course.progress.\(course.id)")
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .studyPaperSurface(cornerRadius: 18, emphasized: true)
        }
        .buttonStyle(PressableScaleButtonStyle(scale: 0.98))
        .accessibilityLabel("\(actionTitle) \(course.title)")
        .accessibilityValue("\(progress.completedRequiredSections) of \(progress.totalRequiredSections) required sections complete, \(progress.percentage) percent")
        .accessibilityHint(progress.nextSection.map { "Opens \($0.blockTitle) in module \($0.moduleNumber)" } ?? "Opens the course overview")
        .accessibilityIdentifier("study.recommended-course.\(course.id)")
    }
}

private struct StudyLiveFeaturedCourseCard: View {
    let course: StudyCourse
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StudyIconTile(systemImage: "rectangle.stack", size: 42)
                Spacer()
                Text(course.id).font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(Brand.redSoft)
            }
            Text(course.title)
                .font(.system(.headline, design: .serif, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)
            Text(course.summary)
                .font(.caption).lineSpacing(2).foregroundStyle(.secondary).lineLimit(4)
            Spacer(minLength: 0)
            ProgressView(value: fraction).tint(Brand.red)
            HStack {
                Text("\(course.modules.count) modules").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundStyle(Brand.redSoft)
            }
        }
        .padding(14)
        .frame(width: 250, height: 230, alignment: .topLeading)
        .studyPaperSurface(cornerRadius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(course.title)")
    }
}

private struct StudyPathwayCard: View {
    let kind: StudyContentKind

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top) {
                StudyIconTile(systemImage: kind.systemImage, size: 44)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.redSoft)
                    .accessibilityHidden(true)
            }

            Text(kind.eyebrow)
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(Brand.redSoft)
            if kind == .videos {
                Text("COMING SOON")
                    .font(.caption2.weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
            }
            Text(kind.title)
                .font(.system(.headline, design: .serif, weight: .semibold))
                .foregroundStyle(.primary)
            Text(kind.description)
                .font(.caption)
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 184, alignment: .topLeading)
        .studyPaperSurface(cornerRadius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct StudyFeaturedCard: View {
    let resource: StudyResource

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StudyIconTile(systemImage: resource.kind.systemImage, size: 42)
                Spacer()
                Text(resource.kind.title.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(Brand.redSoft)
            }
            Text(resource.title)
                .font(.system(.headline, design: .serif, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(resource.summary)
                .font(.caption)
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer(minLength: 0)
            HStack {
                Text(resource.metadata)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.redSoft)
                    .accessibilityHidden(true)
            }
        }
        .padding(14)
        .frame(width: 238, height: 220, alignment: .topLeading)
        .studyPaperSurface(cornerRadius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(resource.kind.title.lowercased())")
    }
}

private struct StudyAssessmentPanel: View {
    let openQuizzes: () -> Void
    let openExams: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                StudyIconTile(systemImage: "checkmark.seal.fill", size: 50)
                VStack(alignment: .leading, spacing: 5) {
                    Text("ASSESSMENT")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(Brand.redSoft)
                    Text("Test your understanding")
                        .font(.system(.title3, design: .serif, weight: .semibold))
                    Text("Use quizzes for practice, then take a full exam when you are ready.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button(action: openQuizzes) {
                    Label("Practice quizzes", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .studySecondaryActionStyle()

                Button(action: openExams) {
                    Label("View exams", systemImage: "timer")
                        .frame(maxWidth: .infinity)
                }
                .studyPrimaryActionStyle()
            }
            .font(.caption.weight(.semibold))
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studyPaperSurface(cornerRadius: 18)
    }
}

struct StudyCollectionScreen: View {
    let kind: StudyContentKind

    private var resources: [StudyResource] {
        StudyCatalog.resources(for: kind)
    }

    @ViewBuilder
    var body: some View {
        if kind == .courses {
            StudyCoursesScreen()
        } else if kind == .studyGuides || kind == .readingGuides {
            StudyGuideCollectionScreen(kind: kind)
        } else if kind == .videos {
            StudyVideosComingSoonScreen()
        } else {
            collectionContent
        }
    }

    private var collectionContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    StudyIconTile(systemImage: kind.systemImage, size: 58)
                    Text(kind.eyebrow)
                        .font(.caption.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(Brand.redSoft)
                    Text(kind.collectionIntroduction)
                        .font(.body)
                        .lineSpacing(3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .studyPaperSurface(cornerRadius: 20)

                Text("Curriculum preview")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .padding(.top, 6)

                ForEach(resources) { resource in
                    StudyResourceCard(resource: resource)
                }

                if resources.isEmpty {
                    EmptyPanel(
                        systemImage: kind.systemImage,
                        title: "No \(kind.title.lowercased()) yet",
                        message: "This section is ready for its first materials."
                    )
                }

                Color.clear
                    .frame(height: 36)
                    .accessibilityHidden(true)
            }
            .padding(StudyLayout.horizontal)
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
    }
}

private enum StudyCenterLayer: String, CaseIterable, Identifiable {
    case courses
    case practice
    case daily
    case review
    case exams

    var id: String { rawValue }

    var title: String {
        switch self {
        case .courses: "Academic Courses"
        case .practice: "Practice & Exercises"
        case .daily: "Daily Learning"
        case .review: "Review & Remediation"
        case .exams: "Exams & Assessment"
        }
    }

    var message: String {
        switch self {
        case .courses: "Reading-centred syllabi, lessons, guides, and assigned texts."
        case .practice: "Optional drills, passage work, and course-linked exercises."
        case .daily: "A quotation, five-minute review, and future reviewed daily quiz."
        case .review: "Wrong answers, saved questions, and weak-topic practice."
        case .exams: "Timed practice, course finals, and full-scale assessment."
        }
    }

    var systemImage: String {
        switch self {
        case .courses: "rectangle.stack.fill"
        case .practice: "pencil.and.list.clipboard"
        case .daily: "sun.max"
        case .review: "arrow.trianglehead.2.clockwise.rotate.90"
        case .exams: "timer"
        }
    }

    var route: Route {
        switch self {
        case .courses: .studyCollection(kind: .courses)
        case .practice: .studyExercises
        case .daily: .studyDaily
        case .review: .studyReview
        case .exams: .studyExams
        }
    }
}

private struct StudyLayerCard: View {
    let layer: StudyCenterLayer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: layer.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Brand.redSoft)
                .frame(width: 42, height: 42)
                .background(Brand.red.opacity(0.095), in: RoundedRectangle(cornerRadius: 12))
            Text(layer.title)
                .font(.system(.headline, design: .serif, weight: .semibold))
                .foregroundStyle(.primary)
            Text(layer.message)
                .font(.caption)
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 166, alignment: .topLeading)
        .studyPaperSurface(cornerRadius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct StudyVideosComingSoonScreen: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    StudyIconTile(systemImage: "play.rectangle", size: 58)
                    Text("WATCH & LISTEN")
                        .font(.caption.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(Brand.redSoft)
                    Text("Educational videos are coming soon.")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                    Text("We are preparing lectures and explainers with transcripts, chapters, reading links, and clear source notes. Videos will appear here only when the material is ready to study—not as empty placeholders.")
                        .font(.body)
                        .lineSpacing(3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .studyPaperSurface(cornerRadius: 20, emphasized: true)

                ContentUnavailableView {
                    Label("Coming soon", systemImage: "video.badge.clock")
                } description: {
                    Text("No educational videos have been published yet.")
                }
                .frame(maxWidth: .infinity, minHeight: 240)
                .studyPaperSurface(cornerRadius: 18)

                Color.clear
                    .frame(height: 36)
                    .accessibilityHidden(true)
            }
            .padding(StudyLayout.horizontal)
        }
        .navigationTitle("Videos")
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
    }
}

private struct StudyResourceCard: View {
    let resource: StudyResource

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            StudyIconTile(systemImage: resource.kind.systemImage, size: 46)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(resource.level.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(Brand.redSoft)
                    Spacer(minLength: 8)
                    Text(resource.metadata)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                Text(resource.title)
                    .font(.system(.headline, design: .serif, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(resource.summary)
                    .font(.caption)
                    .lineSpacing(2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studyPaperSurface(cornerRadius: 15)
        .accessibilityElement(children: .combine)
    }
}

private struct StudyIconTile: View {
    let systemImage: String
    let size: CGFloat

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.38, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Brand.redSoft)
            .frame(width: size, height: size)
            .background(Brand.red.opacity(0.095), in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .stroke(Brand.red.opacity(0.14), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

private struct StudyMetadataPill: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Brand.subtleFill, in: Capsule())
    }
}

private struct StudyTrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}

private struct StudyPaperSurface: ViewModifier {
    let cornerRadius: CGFloat
    let emphasized: Bool

    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [
                        Brand.surface.opacity(emphasized ? 0.98 : 0.90),
                        Brand.surface.opacity(emphasized ? 0.84 : 0.74)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(emphasized ? Brand.red.opacity(0.22) : Brand.separator.opacity(0.68), lineWidth: 1)
            }
            .shadow(color: .black.opacity(emphasized ? 0.09 : 0.055), radius: emphasized ? 16 : 10, y: emphasized ? 8 : 5)
    }
}

extension View {
    func studyPaperSurface(cornerRadius: CGFloat, emphasized: Bool = false) -> some View {
        modifier(StudyPaperSurface(cornerRadius: cornerRadius, emphasized: emphasized))
    }

    @ViewBuilder
    func studyPrimaryActionStyle() -> some View {
        if #available(iOS 26.0, *) {
            self
                .buttonStyle(.glassProminent)
                .tint(Brand.red)
        } else {
            self
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 10))
                .tint(Brand.red)
        }
    }

    @ViewBuilder
    func studySecondaryActionStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 10))
        }
    }
}

#Preview("Study landing page") {
    NavigationStack {
        StudyScreen()
            .navigationDestination(for: Route.self) { route in
                if case .studyCollection(let kind) = route {
                    StudyCollectionScreen(kind: kind)
                }
            }
    }
    .environment(RouterPath())
}
