import Foundation
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class StudyScienceSyncCoordinator {
    private(set) var isSynchronizing = false
    private(set) var lastSynchronizedAt: Date?
    private(set) var lastError: String?

    private let client: StudyScienceSyncClient
    private let courseID = "PHY111"
    private let pageSize = 200

    init(client: StudyScienceSyncClient = .init()) {
        self.client = client
    }

    func redeemInvite(
        code: String,
        courseVersion: String,
        auth: AuthStore,
        scienceStore: StudyScienceStore,
        modelContext: ModelContext
    ) async throws {
        let normalized = code
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        let result = try await client.redeemInvite(code: normalized, auth: auth)
        guard result.success, result.courseId == courseID, let subjectID = auth.userId else {
            throw StudyScienceAccessError.inviteUnavailable
        }
        try upsertEntitlement(
            subjectID: subjectID,
            status: .active,
            in: modelContext
        )
        await synchronize(
            courseVersion: courseVersion,
            auth: auth,
            scienceStore: scienceStore,
            modelContext: modelContext
        )
    }

    func synchronize(
        courseVersion: String,
        auth: AuthStore,
        scienceStore: StudyScienceStore,
        modelContext: ModelContext
    ) async {
        guard !isSynchronizing, let subjectID = auth.userId else { return }
        isSynchronizing = true
        lastError = nil
        defer { isSynchronizing = false }

        do {
            let membership = try await client.fetchMembership(courseId: courseID, auth: auth)
            let status: StudyScienceEntitlementStatus = membership?.isActive == true ? .active : .revoked
            try upsertEntitlement(subjectID: subjectID, status: status, in: modelContext)
            guard status == .active else {
                lastSynchronizedAt = .now
                return
            }

            try await drainOutbox(
                subjectID: subjectID,
                auth: auth,
                scienceStore: scienceStore,
                modelContext: modelContext
            )
            try await pullRemoteFacts(
                subjectID: subjectID,
                courseVersion: courseVersion,
                auth: auth,
                modelContext: modelContext
            )
            lastSynchronizedAt = .now
        } catch {
            lastError = error.localizedDescription
        }
    }

    func hasCachedAccess(
        subjectID: String?,
        modelContext: ModelContext,
        at date: Date = .now
    ) -> Bool {
        guard let subjectID else { return false }
        let recordID = StudyScienceEntitlementRecord.makeRecordID(
            subjectID: subjectID,
            courseID: courseID
        )
        let descriptor = FetchDescriptor<StudyScienceEntitlementRecord>(
            predicate: #Predicate { $0.recordID == recordID }
        )
        return (try? modelContext.fetch(descriptor).first?.permitsOfflineAccess(at: date)) == true
    }

    private func upsertEntitlement(
        subjectID: String,
        status: StudyScienceEntitlementStatus,
        in modelContext: ModelContext,
        at date: Date = .now
    ) throws {
        let recordID = StudyScienceEntitlementRecord.makeRecordID(
            subjectID: subjectID,
            courseID: courseID
        )
        let descriptor = FetchDescriptor<StudyScienceEntitlementRecord>(
            predicate: #Predicate { $0.recordID == recordID }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.renew(status: status, at: date)
        } else {
            modelContext.insert(StudyScienceEntitlementRecord(
                subjectID: subjectID,
                courseID: courseID,
                status: status,
                verifiedAt: date
            ))
        }
        try modelContext.save()
    }

    private func drainOutbox(
        subjectID: String,
        auth: AuthStore,
        scienceStore: StudyScienceStore,
        modelContext: ModelContext,
        now: Date = .now
    ) async throws {
        guard let originDeviceID = UUID(uuidString: scienceStore.deviceID) else { return }

        while true {
            try Task.checkCancellation()
            var descriptor = FetchDescriptor<StudyScienceOutboxRecord>(
                predicate: #Predicate { record in
                    record.subjectID == subjectID && record.nextRetryAt <= now
                },
                sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.recordID)]
            )
            descriptor.fetchLimit = 100
            let outbox = try modelContext.fetch(descriptor)
            guard !outbox.isEmpty else { break }

            for operation in outbox {
                try Task.checkCancellation()
                do {
                    switch operation.entityKind {
                    case "attempt":
                        try await pushAttempt(
                            operation,
                            originDeviceID: originDeviceID,
                            auth: auth,
                            modelContext: modelContext
                        )
                    case "progress":
                        try await pushProgress(
                            operation,
                            originDeviceID: originDeviceID,
                            auth: auth
                        )
                    default:
                        throw StudyScienceAccessError.unsupportedOutboxOperation
                    }
                    modelContext.delete(operation)
                    try modelContext.save()
                } catch {
                    operation.scheduleRetry(after: error, now: now)
                    if operation.entityKind == "attempt",
                       let attempt = try findAttempt(id: operation.entityID, in: modelContext) {
                        attempt.synchronizationState = .failed
                    }
                    try? modelContext.save()
                    throw error
                }
            }
        }
    }

    private func pushAttempt(
        _ operation: StudyScienceOutboxRecord,
        originDeviceID: UUID,
        auth: AuthStore,
        modelContext: ModelContext
    ) async throws {
        guard let operationID = UUID(uuidString: operation.recordID),
              let attempt = try findAttempt(id: operation.entityID, in: modelContext) else {
            throw StudyScienceAccessError.missingLocalFact
        }
        let kind = attempt.activityID.contains(".assessment.") || attempt.activityKind == "assessment"
            ? "assessment"
            : "activity"
        _ = try await client.appendAttempt(
            id: operationID,
            courseId: attempt.courseID,
            courseVersion: attempt.courseVersion,
            activityId: attempt.activityID,
            attemptKind: kind,
            originDeviceId: originDeviceID,
            occurredAt: attempt.submittedAt,
            payloadJSON: operation.payloadJSON,
            auth: auth
        )
        attempt.synchronizationState = .synchronized
    }

    private func pushProgress(
        _ operation: StudyScienceOutboxRecord,
        originDeviceID: UUID,
        auth: AuthStore
    ) async throws {
        guard let operationID = UUID(uuidString: operation.recordID) else {
            throw StudyScienceAccessError.missingLocalFact
        }
        let mutation = try Self.decoder.decode(ProgressPayload.self, from: operation.payloadJSON)
        _ = try await client.appendProgressEvent(
            id: operationID,
            courseId: mutation.courseID,
            courseVersion: mutation.courseVersion,
            activityId: mutation.activityID,
            eventType: mutation.eventType,
            originDeviceId: originDeviceID,
            occurredAt: mutation.occurredAt,
            payloadJSON: operation.payloadJSON,
            auth: auth
        )
    }

    private func findAttempt(
        id: String,
        in modelContext: ModelContext
    ) throws -> StudyScienceActivityAttemptRecord? {
        try modelContext.fetch(FetchDescriptor<StudyScienceActivityAttemptRecord>(
            predicate: #Predicate { $0.recordID == id }
        )).first
    }

    private func pullRemoteFacts(
        subjectID: String,
        courseVersion: String,
        auth: AuthStore,
        modelContext: ModelContext
    ) async throws {
        try await pullAttempts(
            subjectID: subjectID,
            courseVersion: courseVersion,
            auth: auth,
            modelContext: modelContext
        )
        try await pullProgressEvents(
            subjectID: subjectID,
            courseVersion: courseVersion,
            auth: auth,
            modelContext: modelContext
        )
    }

    private func pullAttempts(
        subjectID: String,
        courseVersion: String,
        auth: AuthStore,
        modelContext: ModelContext
    ) async throws {
        var cursor: StudyScienceSyncCursor?
        while true {
            try Task.checkCancellation()
            let rows = try await client.fetchAttempts(
                courseId: courseID,
                courseVersion: courseVersion,
                after: cursor,
                limit: pageSize,
                auth: auth
            )
            for remote in rows {
                try merge(remoteAttempt: remote, subjectID: subjectID, into: modelContext)
            }
            if !rows.isEmpty { try modelContext.save() }
            guard rows.count == pageSize, let last = rows.last else { break }
            cursor = last.syncCursor
        }
    }

    private func pullProgressEvents(
        subjectID: String,
        courseVersion: String,
        auth: AuthStore,
        modelContext: ModelContext
    ) async throws {
        var cursor: StudyScienceSyncCursor?
        while true {
            try Task.checkCancellation()
            let rows = try await client.fetchProgressEvents(
                courseId: courseID,
                courseVersion: courseVersion,
                after: cursor,
                limit: pageSize,
                auth: auth
            )
            for remote in rows {
                try merge(remoteProgress: remote, subjectID: subjectID, into: modelContext)
            }
            if !rows.isEmpty { try modelContext.save() }
            guard rows.count == pageSize, let last = rows.last else { break }
            cursor = last.syncCursor
        }
    }

    private func merge(
        remoteAttempt: StudyScienceAttemptRemote,
        subjectID: String,
        into modelContext: ModelContext
    ) throws {
        let recordID = remoteAttempt.id.uuidString.lowercased()
        if let existing = try findAttempt(id: recordID, in: modelContext) {
            existing.synchronizationState = .synchronized
            return
        }

        let data = try Self.encoder.encode(remoteAttempt.payload)
        let payload = try Self.decoder.decode(AttemptPayload.self, from: data)
        let responseJSON = try Self.encoder.encode(payload.response)
        let submittedAt = payload.submittedAt ?? Self.date(remoteAttempt.occurredAt) ?? .now
        let attempt = StudyScienceActivityAttemptRecord(
            attemptID: remoteAttempt.id,
            subjectID: subjectID,
            courseID: remoteAttempt.courseId,
            courseVersion: remoteAttempt.courseVersion,
            activityID: remoteAttempt.activityId,
            activityVersion: payload.activityVersion ?? remoteAttempt.courseVersion,
            activityKind: payload.activityKind ?? remoteAttempt.attemptKind,
            seed: payload.seed ?? 0,
            responseJSON: responseJSON,
            earnedPoints: payload.earnedPoints,
            possiblePoints: payload.possiblePoints,
            submittedAt: submittedAt,
            syncState: .synchronized,
            payloadHash: remoteAttempt.payloadHash
        )
        modelContext.insert(attempt)
        try mergeProgress(
            subjectID: subjectID,
            courseID: remoteAttempt.courseId,
            courseVersion: remoteAttempt.courseVersion,
            itemID: payload.completionItemID ?? remoteAttempt.activityId,
            itemKind: payload.completionItemKind ?? remoteAttempt.attemptKind,
            score: attempt.normalizedScore,
            path: payload.completionPath,
            occurredAt: submittedAt,
            into: modelContext
        )
    }

    private func merge(
        remoteProgress: StudyScienceProgressEventRemote,
        subjectID: String,
        into modelContext: ModelContext
    ) throws {
        let data = try Self.encoder.encode(remoteProgress.payload)
        let payload = try Self.decoder.decode(ProgressPayload.self, from: data)
        try mergeProgress(
            subjectID: subjectID,
            courseID: remoteProgress.courseId,
            courseVersion: remoteProgress.courseVersion,
            itemID: payload.itemID,
            itemKind: payload.itemKind,
            score: payload.score,
            path: payload.completionPath,
            occurredAt: payload.occurredAt,
            into: modelContext
        )
    }

    private func mergeProgress(
        subjectID: String,
        courseID: String,
        courseVersion: String,
        itemID: String,
        itemKind: String,
        score: Double?,
        path: String?,
        occurredAt: Date,
        into modelContext: ModelContext
    ) throws {
        let recordID = StudyScienceProgressRecord.makeRecordID(
            subjectID: subjectID,
            courseID: courseID,
            courseVersion: courseVersion,
            itemID: itemID
        )
        let descriptor = FetchDescriptor<StudyScienceProgressRecord>(
            predicate: #Predicate { $0.recordID == recordID }
        )
        let progress: StudyScienceProgressRecord
        if let existing = try modelContext.fetch(descriptor).first {
            progress = existing
        } else {
            progress = StudyScienceProgressRecord(
                subjectID: subjectID,
                courseID: courseID,
                courseVersion: courseVersion,
                itemID: itemID,
                itemKind: itemKind
            )
            modelContext.insert(progress)
        }
        progress.recordCompletion(score: score, path: path, at: occurredAt)
    }

    private struct AttemptPayload: Codable {
        let activityVersion: String?
        let activityKind: String?
        let seed: Int64?
        let response: StudyScienceJSONValue
        let earnedPoints: Double?
        let possiblePoints: Double?
        let completionItemID: String?
        let completionItemKind: String?
        let completionPath: String?
        let submittedAt: Date?
    }

    private struct ProgressPayload: Codable {
        let courseID: String
        let courseVersion: String
        let activityID: String
        let itemID: String
        let itemKind: String
        let score: Double?
        let completionPath: String?
        let eventType: String
        let occurredAt: Date
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

    private static func date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

enum StudyScienceAccessError: LocalizedError {
    case inviteUnavailable
    case missingLocalFact
    case unsupportedOutboxOperation

    var errorDescription: String? {
        switch self {
        case .inviteUnavailable:
            "That invitation is invalid, expired, or has already been used."
        case .missingLocalFact:
            "A queued science result no longer has its matching local record."
        case .unsupportedOutboxOperation:
            "A queued science synchronization operation is not supported."
        }
    }
}

struct StudyScienceSyncLifecycle: ViewModifier {
    @Environment(AuthStore.self) private var auth
    @Environment(StudyCourseLibrary.self) private var library
    @Environment(StudyScienceStore.self) private var scienceStore
    @Environment(StudyScienceSyncCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    private var syncIdentity: String {
        let version = library.course(id: "PHY111")?.contentVersion ?? "0.1.0"
        return "\(auth.userId ?? "signed-out")::\(version)::\(scenePhase == .active)"
    }

    func body(content: Content) -> some View {
        content.task(id: syncIdentity) {
            guard scenePhase == .active, auth.userId != nil else { return }
            await coordinator.synchronize(
                courseVersion: library.course(id: "PHY111")?.contentVersion ?? "0.1.0",
                auth: auth,
                scienceStore: scienceStore,
                modelContext: modelContext
            )
        }
    }
}
