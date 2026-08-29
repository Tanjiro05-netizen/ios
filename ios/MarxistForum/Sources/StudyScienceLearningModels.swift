import Foundation
import SwiftData

enum StudyScienceSyncState: String, Codable, Sendable {
    case localOnly
    case queued
    case synchronized
    case failed
}

enum StudyScienceEntitlementStatus: String, Codable, Sendable {
    case active
    case revoked

    var title: String {
        switch self {
        case .active: "Active"
        case .revoked: "Revoked"
        }
    }
}

@Model
final class StudyScienceEntitlementRecord {
    @Attribute(.unique) var recordID: String
    var subjectID: String
    var courseID: String
    var status: String
    var verifiedAt: Date
    var offlineExpiresAt: Date

    init(
        subjectID: String,
        courseID: String,
        status: StudyScienceEntitlementStatus = .active,
        verifiedAt: Date = .now,
        offlineExpiresAt: Date? = nil
    ) {
        self.recordID = Self.makeRecordID(subjectID: subjectID, courseID: courseID)
        self.subjectID = subjectID
        self.courseID = courseID
        self.status = status.rawValue
        self.verifiedAt = verifiedAt
        self.offlineExpiresAt = offlineExpiresAt ?? .distantFuture
    }

    var entitlementStatus: StudyScienceEntitlementStatus {
        get { StudyScienceEntitlementStatus(rawValue: status) ?? .revoked }
        set { status = newValue.rawValue }
    }

    func permitsOfflineAccess(at date: Date = .now) -> Bool {
        entitlementStatus == .active && date <= .distantFuture
    }

    func renew(
        status: StudyScienceEntitlementStatus,
        at date: Date = .now
    ) {
        entitlementStatus = status
        verifiedAt = date
        offlineExpiresAt = status == .active ? .distantFuture : date
    }

    static func makeRecordID(subjectID: String, courseID: String) -> String {
        "\(subjectID)::\(courseID)"
    }
}

@Model
final class StudyScienceProgressRecord {
    @Attribute(.unique) var recordID: String
    var subjectID: String
    var courseID: String
    var courseVersion: String
    var itemID: String
    var itemKind: String
    var isCompleted: Bool
    var bestScore: Double?
    var completionPath: String?
    var updatedAt: Date

    init(
        subjectID: String,
        courseID: String,
        courseVersion: String,
        itemID: String,
        itemKind: String,
        isCompleted: Bool = false,
        bestScore: Double? = nil,
        completionPath: String? = nil,
        updatedAt: Date = .now
    ) {
        self.recordID = Self.makeRecordID(
            subjectID: subjectID,
            courseID: courseID,
            courseVersion: courseVersion,
            itemID: itemID
        )
        self.subjectID = subjectID
        self.courseID = courseID
        self.courseVersion = courseVersion
        self.itemID = itemID
        self.itemKind = itemKind
        self.isCompleted = isCompleted
        self.bestScore = bestScore
        self.completionPath = completionPath
        self.updatedAt = updatedAt
    }

    func recordCompletion(
        score: Double? = nil,
        path: String? = nil,
        at date: Date = .now
    ) {
        isCompleted = true
        if let score {
            bestScore = max(bestScore ?? 0, min(max(score, 0), 1))
        }
        if let path {
            // Passing mastery is monotonic within a course version. A later
            // failed retry must not erase a previously validated pass.
            if completionPath != "passed" || path == "passed" {
                completionPath = path
            }
        }
        updatedAt = date
    }

    static func makeRecordID(
        subjectID: String,
        courseID: String,
        courseVersion: String,
        itemID: String
    ) -> String {
        [subjectID, courseID, courseVersion, itemID].joined(separator: "::")
    }
}

@Model
final class StudyScienceActivityAttemptRecord {
    @Attribute(.unique) var recordID: String
    var subjectID: String
    var courseID: String
    var courseVersion: String
    var activityID: String
    var activityVersion: String
    var activityKind: String
    var seed: Int64
    var responseJSON: Data
    var earnedPoints: Double?
    var possiblePoints: Double?
    var submittedAt: Date
    var syncState: String
    var payloadHash: String

    init(
        attemptID: UUID = UUID(),
        subjectID: String,
        courseID: String,
        courseVersion: String,
        activityID: String,
        activityVersion: String,
        activityKind: String,
        seed: Int64,
        responseJSON: Data,
        earnedPoints: Double? = nil,
        possiblePoints: Double? = nil,
        submittedAt: Date = .now,
        syncState: StudyScienceSyncState = .queued,
        payloadHash: String = ""
    ) {
        self.recordID = attemptID.uuidString.lowercased()
        self.subjectID = subjectID
        self.courseID = courseID
        self.courseVersion = courseVersion
        self.activityID = activityID
        self.activityVersion = activityVersion
        self.activityKind = activityKind
        self.seed = seed
        self.responseJSON = responseJSON
        self.earnedPoints = earnedPoints
        self.possiblePoints = possiblePoints
        self.submittedAt = submittedAt
        self.syncState = syncState.rawValue
        self.payloadHash = payloadHash
    }

    var normalizedScore: Double? {
        guard let earnedPoints, let possiblePoints, possiblePoints > 0 else { return nil }
        return min(max(earnedPoints / possiblePoints, 0), 1)
    }

    var synchronizationState: StudyScienceSyncState {
        get { StudyScienceSyncState(rawValue: syncState) ?? .localOnly }
        set { syncState = newValue.rawValue }
    }
}

@Model
final class StudyScienceDraftRecord {
    @Attribute(.unique) var recordID: String
    var subjectID: String
    var courseID: String
    var courseVersion: String
    var activityID: String
    var activityVersion: String
    var responseJSON: Data
    var deviceID: String
    var updatedAt: Date

    init(
        subjectID: String,
        courseID: String,
        courseVersion: String,
        activityID: String,
        activityVersion: String,
        responseJSON: Data = Data(),
        deviceID: String,
        updatedAt: Date = .now
    ) {
        self.recordID = Self.makeRecordID(
            subjectID: subjectID,
            courseID: courseID,
            courseVersion: courseVersion,
            activityID: activityID,
            activityVersion: activityVersion,
            deviceID: deviceID
        )
        self.subjectID = subjectID
        self.courseID = courseID
        self.courseVersion = courseVersion
        self.activityID = activityID
        self.activityVersion = activityVersion
        self.responseJSON = responseJSON
        self.deviceID = deviceID
        self.updatedAt = updatedAt
    }

    static func makeRecordID(
        subjectID: String,
        courseID: String,
        courseVersion: String,
        activityID: String,
        activityVersion: String,
        deviceID: String
    ) -> String {
        [subjectID, courseID, courseVersion, activityID, activityVersion, deviceID]
            .joined(separator: "::")
    }
}

@Model
final class StudyScienceArtifactRecord {
    @Attribute(.unique) var recordID: String
    var subjectID: String
    var courseID: String
    var courseVersion: String
    var activityID: String
    var artifactKind: String
    var localFilename: String
    var createdAt: Date

    init(
        artifactID: UUID = UUID(),
        subjectID: String,
        courseID: String,
        courseVersion: String,
        activityID: String,
        artifactKind: String,
        localFilename: String,
        createdAt: Date = .now
    ) {
        self.recordID = artifactID.uuidString.lowercased()
        self.subjectID = subjectID
        self.courseID = courseID
        self.courseVersion = courseVersion
        self.activityID = activityID
        self.artifactKind = artifactKind
        self.localFilename = localFilename
        self.createdAt = createdAt
    }
}

@Model
final class StudyScienceOutboxRecord {
    @Attribute(.unique) var recordID: String
    var subjectID: String
    var entityKind: String
    var entityID: String
    var payloadJSON: Data
    var createdAt: Date
    var retryCount: Int
    var nextRetryAt: Date
    var lastError: String?

    init(
        mutationID: UUID = UUID(),
        subjectID: String,
        entityKind: String,
        entityID: String,
        payloadJSON: Data,
        createdAt: Date = .now,
        retryCount: Int = 0,
        nextRetryAt: Date = .now,
        lastError: String? = nil
    ) {
        self.recordID = mutationID.uuidString.lowercased()
        self.subjectID = subjectID
        self.entityKind = entityKind
        self.entityID = entityID
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.nextRetryAt = nextRetryAt
        self.lastError = lastError
    }

    func scheduleRetry(after error: Error, now: Date = .now) {
        retryCount += 1
        let exponent = min(retryCount, 8)
        let base = pow(2.0, Double(exponent))
        let deterministicJitter = Double(abs(recordID.hashValue % 1_000)) / 1_000
        let seconds = min(300, base + deterministicJitter)
        nextRetryAt = now.addingTimeInterval(seconds)
        lastError = error.localizedDescription
    }
}

struct StudyScienceCompletionSnapshot: Equatable, Sendable {
    struct Requirement: Equatable, Sendable, Identifiable {
        let id: String
        let title: String
        let isSatisfied: Bool
        let detail: String
    }

    let requirements: [Requirement]

    var completedCount: Int { requirements.lazy.filter(\.isSatisfied).count }
    var requiredCount: Int { requirements.count }
    var fraction: Double {
        guard requiredCount > 0 else { return 0 }
        return Double(completedCount) / Double(requiredCount)
    }
    var isComplete: Bool { !requirements.isEmpty && completedCount == requiredCount }
}

@MainActor
enum StudyScienceLocalDataEraser {
    static func erase(subjectID: String, from modelContext: ModelContext) throws {
        let entitlements = try modelContext.fetch(FetchDescriptor<StudyScienceEntitlementRecord>(
            predicate: #Predicate { $0.subjectID == subjectID }
        ))
        let progress = try modelContext.fetch(FetchDescriptor<StudyScienceProgressRecord>(
            predicate: #Predicate { $0.subjectID == subjectID }
        ))
        let attempts = try modelContext.fetch(FetchDescriptor<StudyScienceActivityAttemptRecord>(
            predicate: #Predicate { $0.subjectID == subjectID }
        ))
        let drafts = try modelContext.fetch(FetchDescriptor<StudyScienceDraftRecord>(
            predicate: #Predicate { $0.subjectID == subjectID }
        ))
        let artifacts = try modelContext.fetch(FetchDescriptor<StudyScienceArtifactRecord>(
            predicate: #Predicate { $0.subjectID == subjectID }
        ))
        let outbox = try modelContext.fetch(FetchDescriptor<StudyScienceOutboxRecord>(
            predicate: #Predicate { $0.subjectID == subjectID }
        ))

        entitlements.forEach(modelContext.delete)
        progress.forEach(modelContext.delete)
        attempts.forEach(modelContext.delete)
        drafts.forEach(modelContext.delete)
        artifacts.forEach {
            StudyScienceArtifactStorage.remove(relativePath: $0.localFilename)
            modelContext.delete($0)
        }
        outbox.forEach(modelContext.delete)
        try modelContext.save()
    }
}
