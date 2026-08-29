import Foundation
import SwiftData
import SwiftUI

@MainActor
struct StudyScienceActivityRouteScreen: View {
    let courseID: String
    let activityID: String

    @Environment(AuthStore.self) private var auth
    @Environment(StudyCourseLibrary.self) private var library
    @Environment(StudyScienceStore.self) private var scienceStore
    @Environment(StudyScienceSyncCoordinator.self) private var scienceSync
    @Environment(\.modelContext) private var modelContext
    @Query private var courseProgressRecords: [StudyCourseProgressRecord]
    @Query private var scienceProgressRecords: [StudyScienceProgressRecord]
    @Query private var attempts: [StudyScienceActivityAttemptRecord]
    @Query private var entitlements: [StudyScienceEntitlementRecord]
    @Query private var artifacts: [StudyScienceArtifactRecord]

    @State private var initialResponse: StudyInteractiveResponse?
    @State private var didLoadDraft = false
    @State private var presentedError: String?

    private var course: StudyCourse? { library.course(id: courseID) }
    private var activity: StudyInteractiveActivity? { library.interactiveActivity(id: activityID) }
    private var subjectID: String? { auth.userId }
    private var courseProgress: StudyCourseProgressRecord? {
        guard let subjectID else { return nil }
        return courseProgressRecords.first { $0.subjectID == subjectID && $0.courseID == courseID }
    }
    private var exactScienceProgress: [StudyScienceProgressRecord] {
        guard let subjectID, let course else { return [] }
        return scienceProgressRecords.filter {
            $0.subjectID == subjectID
                && $0.courseID == course.id
                && $0.courseVersion == course.contentVersion
        }
    }
    private var exactAttempts: [StudyScienceActivityAttemptRecord] {
        guard let subjectID, let course else { return [] }
        return attempts.filter {
            $0.subjectID == subjectID
                && $0.courseID == course.id
                && $0.courseVersion == course.contentVersion
        }
    }

    var body: some View {
        Group {
            if let course, let activity {
                if !permitsAccess(to: course) {
                    StudyScienceLockedContentView(
                        title: "PHY111 access required",
                        message: "Return to the course home to sign in and redeem an active beta invitation."
                    )
                } else if let reason = StudyScienceCourseUnlockPolicy.lockReason(
                    for: activity.id,
                    course: course,
                    completedLessonIDs: Set(courseProgress?.completedLessonIDs ?? []),
                    completedRequiredBlockIDs: Set(courseProgress?.completedRequiredBlockIDs ?? []),
                    scienceProgress: exactScienceProgress,
                    attempts: exactAttempts
                ) {
                    StudyScienceLockedContentView(title: "Activity not unlocked yet", message: reason)
                } else if didLoadDraft, let subjectID {
                    StudyScienceActivityScreen(
                        activity: activity,
                        datasets: activity.datasetIDs.compactMap(library.dataset(id:)),
                        toolProfile: activity.toolProfileID.flatMap(library.toolProfile(id:)),
                        initialResponse: initialResponse,
                        initialStoredVideo: storedVideo(subjectID: subjectID, course: course, activity: activity),
                        videoStorage: videoStorage(subjectID: subjectID, course: course, activity: activity),
                        saveDraft: { response in
                            try scienceStore.saveDraft(
                                courseID: course.id,
                                courseVersion: course.contentVersion,
                                activityID: activity.id,
                                activityVersion: activity.activityVersion,
                                responseJSON: try Self.encoder.encode(response),
                                in: modelContext
                            )
                        },
                        submit: { completion in
                            try scienceStore.submit(
                                StudyScienceAttemptSubmission(
                                    subjectID: subjectID,
                                    courseID: course.id,
                                    courseVersion: course.contentVersion,
                                    activityID: activity.id,
                                    activityVersion: activity.activityVersion,
                                    activityKind: activity.kind.rawValue,
                                    seed: Int64.random(in: Int64.min...Int64.max),
                                    responseJSON: try Self.encoder.encode(completion.response),
                                    earnedPoints: completion.earnedPoints,
                                    possiblePoints: completion.possiblePoints,
                                    completionItemKind: "activity",
                                    completionPath: completion.completionPath
                                ),
                                in: modelContext
                            )
                        }
                    )
                } else {
                    ProgressView("Opening activity…")
                }
            } else {
                ContentUnavailableView(
                    "Activity unavailable",
                    systemImage: "atom",
                    description: Text("The installed course package does not contain this activity.")
                )
            }
        }
        .task(id: draftIdentity) { loadDraft() }
        .alert("Activity unavailable", isPresented: Binding(
            get: { presentedError != nil },
            set: { if !$0 { presentedError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(presentedError ?? "Please try again.")
        }
    }

    private var draftIdentity: String {
        "\(subjectID ?? "signed-out")::\(course?.contentVersion ?? "missing")::\(activityID)"
    }

    private func permitsAccess(to course: StudyCourse) -> Bool {
        StudyScienceCourseUnlockPolicy.permitsAccess(
            course: course,
            subjectID: subjectID,
            entitlements: entitlements
        )
    }

    private func loadDraft() {
        didLoadDraft = false
        initialResponse = nil
        guard permitsResolvedRoute else {
            didLoadDraft = true
            return
        }
        do {
            if let course, let activity,
               let draft = try scienceStore.draft(
                courseID: course.id,
                courseVersion: course.contentVersion,
                activityID: activity.id,
                activityVersion: activity.activityVersion,
                in: modelContext
               ) {
                initialResponse = try Self.decoder.decode(StudyInteractiveResponse.self, from: draft.responseJSON)
            }
        } catch {
            presentedError = "Your saved draft could not be opened. \(error.localizedDescription)"
        }
        didLoadDraft = true
    }

    private var permitsResolvedRoute: Bool {
        guard let course, activity != nil else { return false }
        return permitsAccess(to: course)
    }

    private func videoStorage(
        subjectID: String,
        course: StudyCourse,
        activity: StudyInteractiveActivity
    ) -> StudyMotionVideoStorageUI {
        StudyMotionVideoStorageUI(
            store: { sourceURL in
                let artifactID = UUID()
                let relativePath = try StudyScienceArtifactStorage.store(
                    sourceURL: sourceURL,
                    subjectID: subjectID,
                    artifactID: artifactID
                )
                let record = StudyScienceArtifactRecord(
                    artifactID: artifactID,
                    subjectID: subjectID,
                    courseID: course.id,
                    courseVersion: course.contentVersion,
                    activityID: activity.id,
                    artifactKind: "raw-motion-video-local-only",
                    localFilename: relativePath
                )
                modelContext.insert(record)
                do {
                    try modelContext.save()
                    return StudyMotionStoredVideoUI(
                        localURL: try StudyScienceArtifactStorage.rootURL().appending(path: relativePath),
                        artifactID: artifactID,
                        relativePath: relativePath
                    )
                } catch {
                    modelContext.rollback()
                    StudyScienceArtifactStorage.remove(relativePath: relativePath)
                    throw error
                }
            },
            remove: { stored in
                if let path = stored.relativePath {
                    StudyScienceArtifactStorage.remove(relativePath: path)
                }
                guard let artifactID = stored.artifactID else { return }
                let recordID = artifactID.uuidString.lowercased()
                let descriptor = FetchDescriptor<StudyScienceArtifactRecord>(
                    predicate: #Predicate { $0.recordID == recordID }
                )
                if let record = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(record)
                    try? modelContext.save()
                }
            }
        )
    }

    private func storedVideo(
        subjectID: String,
        course: StudyCourse,
        activity: StudyInteractiveActivity
    ) -> StudyMotionStoredVideoUI? {
        guard activity.kind == .motionTrackingLab,
              let record = artifacts
                .filter({
                    $0.subjectID == subjectID
                        && $0.courseID == course.id
                        && $0.courseVersion == course.contentVersion
                        && $0.activityID == activity.id
                        && $0.artifactKind == "raw-motion-video-local-only"
                })
                .max(by: { $0.createdAt < $1.createdAt }),
              let artifactID = UUID(uuidString: record.recordID),
              let root = try? StudyScienceArtifactStorage.rootURL() else { return nil }
        let url = root.appending(path: record.localFilename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return .init(localURL: url, artifactID: artifactID, relativePath: record.localFilename)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

@MainActor
struct StudyScienceAssessmentRouteScreen: View {
    let courseID: String
    let assessmentID: String

    @Environment(AuthStore.self) private var auth
    @Environment(StudyCourseLibrary.self) private var library
    @Environment(StudyScienceStore.self) private var scienceStore
    @Environment(\.modelContext) private var modelContext
    @Query private var courseProgressRecords: [StudyCourseProgressRecord]
    @Query private var scienceProgressRecords: [StudyScienceProgressRecord]
    @Query private var attempts: [StudyScienceActivityAttemptRecord]
    @Query private var entitlements: [StudyScienceEntitlementRecord]

    @State private var initialDraft: StudyScienceAssessmentDraftUI?
    @State private var didLoadDraft = false
    @State private var presentedError: String?

    private var course: StudyCourse? { library.course(id: courseID) }
    private var blueprint: StudyCourseAssessmentBlueprint? { library.assessment(id: assessmentID) }
    private var subjectID: String? { auth.userId }
    private var courseProgress: StudyCourseProgressRecord? {
        guard let subjectID else { return nil }
        return courseProgressRecords.first { $0.subjectID == subjectID && $0.courseID == courseID }
    }
    private var exactProgress: [StudyScienceProgressRecord] {
        guard let subjectID, let course else { return [] }
        return scienceProgressRecords.filter {
            $0.subjectID == subjectID && $0.courseID == course.id && $0.courseVersion == course.contentVersion
        }
    }
    private var exactAttempts: [StudyScienceActivityAttemptRecord] {
        guard let subjectID, let course else { return [] }
        return attempts.filter {
            $0.subjectID == subjectID && $0.courseID == course.id && $0.courseVersion == course.contentVersion
        }
    }

    var body: some View {
        Group {
            if let course, let blueprint, let subjectID {
                if !StudyScienceCourseUnlockPolicy.permitsAccess(
                    course: course,
                    subjectID: subjectID,
                    entitlements: entitlements
                ) {
                    StudyScienceLockedContentView(
                        title: "PHY111 access required",
                        message: "Return to the course home and check your beta invitation."
                    )
                } else if let reason = StudyScienceCourseUnlockPolicy.lockReason(
                    for: blueprint.id,
                    course: course,
                    completedLessonIDs: Set(courseProgress?.completedLessonIDs ?? []),
                    completedRequiredBlockIDs: Set(courseProgress?.completedRequiredBlockIDs ?? []),
                    scienceProgress: exactProgress,
                    attempts: exactAttempts
                ) {
                    StudyScienceLockedContentView(title: "Assessment not unlocked yet", message: reason)
                } else if didLoadDraft {
                    StudyScienceAssessmentScreen(
                        blueprint: blueprint,
                        items: (blueprint.scienceAssessmentItemIDs ?? []).compactMap(library.scienceAssessmentItem(id:)),
                        toolProfile: blueprint.toolProfileID.flatMap(library.toolProfile(id:)),
                        initialDraft: initialDraft,
                        saveDraft: { draft in
                            try scienceStore.saveDraft(
                                courseID: course.id,
                                courseVersion: course.contentVersion,
                                activityID: blueprint.id,
                                activityVersion: course.contentVersion,
                                responseJSON: try Self.encoder.encode(draft),
                                in: modelContext
                            )
                        },
                        submit: { result in
                            try scienceStore.submit(
                                StudyScienceAttemptSubmission(
                                    attemptID: result.draft.attemptID,
                                    subjectID: subjectID,
                                    courseID: course.id,
                                    courseVersion: course.contentVersion,
                                    activityID: blueprint.id,
                                    activityVersion: course.contentVersion,
                                    activityKind: "assessment",
                                    seed: Int64(bitPattern: result.draft.seed),
                                    responseJSON: try Self.encoder.encode(result.draft),
                                    earnedPoints: result.earnedPoints,
                                    possiblePoints: result.possiblePoints,
                                    completionItemKind: "assessment",
                                    completionPath: result.didPass ? "passed" : "attempted"
                                ),
                                in: modelContext
                            )
                        }
                    )
                } else {
                    ProgressView("Opening assessment…")
                }
            } else if auth.userId == nil {
                StudyScienceLockedContentView(
                    title: "Account required",
                    message: "Sign in to open PHY111 assessments and keep attempts separated from guest work."
                )
            } else {
                ContentUnavailableView("Assessment unavailable", systemImage: "doc.questionmark")
            }
        }
        .task(id: draftIdentity) { loadDraft() }
        .alert("Assessment unavailable", isPresented: Binding(
            get: { presentedError != nil },
            set: { if !$0 { presentedError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(presentedError ?? "Please try again.")
        }
    }

    private var draftIdentity: String {
        "\(subjectID ?? "signed-out")::\(course?.contentVersion ?? "missing")::\(assessmentID)"
    }

    private func loadDraft() {
        didLoadDraft = false
        initialDraft = nil
        defer { didLoadDraft = true }
        guard let course, let blueprint, subjectID != nil else { return }
        do {
            if let record = try scienceStore.draft(
                courseID: course.id,
                courseVersion: course.contentVersion,
                activityID: blueprint.id,
                activityVersion: course.contentVersion,
                in: modelContext
            ) {
                initialDraft = try Self.decoder.decode(StudyScienceAssessmentDraftUI.self, from: record.responseJSON)
            }
        } catch {
            presentedError = "Your saved assessment draft could not be opened. \(error.localizedDescription)"
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

@MainActor
struct StudyScienceVideoScreen: View {
    let courseID: String
    let videoID: String

    @Environment(AuthStore.self) private var auth
    @Environment(StudyCourseLibrary.self) private var library
    @Environment(StudyScienceStore.self) private var scienceStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var scienceProgressRecords: [StudyScienceProgressRecord]
    @State private var message: String?

    private var course: StudyCourse? { library.course(id: courseID) }
    private var video: StudyEducationalVideo? { library.video(id: videoID) }
    private var subjectID: String? { auth.userId }
    private var completionActivityID: String {
        video?.completionActivityID
            ?? videoID.replacingOccurrences(of: ".video.", with: ".activity.")
    }
    private var progress: StudyScienceProgressRecord? {
        guard let subjectID, let course else { return nil }
        return scienceProgressRecords.first {
            $0.subjectID == subjectID
                && $0.courseID == course.id
                && $0.courseVersion == course.contentVersion
                && $0.itemID == completionActivityID
        }
    }

    var body: some View {
        Group {
            if course != nil, let video, subjectID != nil {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        StudyAcademicHeader(
                            eyebrow: "EXPERIMENT BRIEFING",
                            title: video.title,
                            message: video.summary,
                            systemImage: "play.rectangle"
                        )

                        if let url = video.mediaURL, url.scheme?.lowercased() == "https" {
                            Button {
                                openURL(url)
                            } label: {
                                Label("Open course video", systemImage: "arrow.up.right.square")
                                    .frame(maxWidth: .infinity)
                            }
                            .studyPrimaryActionStyle()

                            Button {
                                complete(path: "watched")
                            } label: {
                                Label("I watched the briefing", systemImage: "checkmark.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .studySecondaryActionStyle()
                        } else {
                            Label(
                                "This edition does not provide a verified HTTPS video link. The complete native briefing below is available offline.",
                                systemImage: "wifi.slash"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(15)
                            .studyPaperSurface(cornerRadius: 15)
                        }

                        if let fallback = video.transcriptMarkdown ?? video.fallbackMarkdown,
                           !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Offline briefing", systemImage: "doc.text")
                                    .font(.headline)
                                StudyMarkdownDocument(markdown: fallback)
                                Button {
                                    complete(path: "fallback")
                                } label: {
                                    Label(
                                        progress?.isCompleted == true ? "Briefing reviewed" : "I reviewed the complete briefing",
                                        systemImage: progress?.isCompleted == true ? "checkmark.circle.fill" : "checkmark.circle"
                                    )
                                    .frame(maxWidth: .infinity)
                                }
                                .studyPrimaryActionStyle()
                            }
                            .padding(16)
                            .studyPaperSurface(cornerRadius: 17, emphasized: true)
                        }

                        Label(
                            "Completion records only your attestation or fallback review; the app does not claim to verify watch time.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .padding(.bottom, 36)
                }
                .navigationTitle(video.title)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Video briefing unavailable", systemImage: "play.slash")
            }
        }
        .background(ScreenBackground())
        .alert("Briefing progress", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "Saved.")
        }
    }

    private func complete(path: String) {
        guard let subjectID, let course else { return }
        do {
            if scienceStore.activeSubjectID != subjectID {
                scienceStore.activate(subjectID: subjectID)
            }
            try scienceStore.recordProgress(
                courseID: course.id,
                courseVersion: course.contentVersion,
                activityID: completionActivityID,
                itemKind: "video",
                completionPath: path,
                in: modelContext
            )
            message = path == "watched"
                ? "Your watch attestation was saved."
                : "Your offline briefing review was saved."
        } catch {
            message = "This progress could not be saved: \(error.localizedDescription)"
        }
    }
}

enum StudyScienceCourseUnlockPolicy {
    static let videoCompletionID = "PHY111.activity.m01.video.motion-tracking-briefing"
    static let motionLabID = "PHY111.activity.m01.lab.motion-tracking"
    static let guidedLabID = "PHY111.activity.m01.lab.numerical-guided"
    static let pythonLabID = "PHY111.activity.m01.lab.python"
    static let masteryID = "PHY111.assessment.m01.mastery"
    static let quizID = "PHY111.assessment.m01.quiz"

    static func permitsAccess(
        course: StudyCourse,
        subjectID: String?,
        entitlements: [StudyScienceEntitlementRecord],
        at date: Date = .now
    ) -> Bool {
        switch course.accessRequirement ?? .open {
        case .open:
            return true
        case .accountRequired:
            return subjectID != nil
        case .inviteOnly:
            guard let subjectID else { return false }
            let recordID = StudyScienceEntitlementRecord.makeRecordID(subjectID: subjectID, courseID: course.id)
            return entitlements.contains { $0.recordID == recordID && $0.permitsOfflineAccess(at: date) }
        }
    }

    static func lockReason(
        for contentID: String,
        course: StudyCourse,
        completedLessonIDs: Set<String>,
        completedRequiredBlockIDs: Set<String>,
        scienceProgress: [StudyScienceProgressRecord],
        attempts: [StudyScienceActivityAttemptRecord]
    ) -> String? {
        let progress = Dictionary(uniqueKeysWithValues: scienceProgress.map { ($0.itemID, $0) })
        let videoComplete = progress[videoCompletionID]?.isCompleted == true
        let requiredSections = StudyLearningProgress.sectionDestinations(for: course).filter(\.isRequired)
        let readingComplete = requiredSections.allSatisfy {
            StudyLearningProgress.isSectionCompleted(
                $0,
                completedLessonIDs: completedLessonIDs,
                completedRequiredBlockIDs: completedRequiredBlockIDs
            )
        }
        let hasMasteryAttempt = attempts.contains { $0.activityID == masteryID }
        let masteryReached = progress[masteryID]?.completionPath == "passed"
            && (progress[masteryID]?.bestScore ?? 0) >= 0.70
        let computationReached = [guidedLabID, pythonLabID].contains {
            (progress[$0]?.bestScore ?? 0) >= 0.70
        }

        switch contentID {
        case motionLabID:
            return videoComplete ? nil : "Review and acknowledge the experiment briefing before beginning motion tracking."
        case guidedLabID, pythonLabID:
            return hasMasteryAttempt ? nil : "Submit your first Module 1 mastery-practice attempt before choosing a computational lab. Passing that first attempt is not required."
        case masteryID:
            guard readingComplete else {
                return "Complete every required native reading section before starting mastery practice."
            }
            return videoComplete ? nil : "Review and acknowledge the experiment briefing before starting mastery practice."
        case quizID:
            guard masteryReached else { return "Reach at least 70% in Module 1 mastery practice before opening the module quiz." }
            return computationReached ? nil : "Complete either the guided numerical lab or the offline Python lab before opening the module quiz."
        default:
            return nil
        }
    }
}

struct StudyScienceLockedContentView: View {
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "lock.fill")
        } description: {
            Text(message)
        }
        .padding(24)
        .background(ScreenBackground())
    }
}
