import CryptoKit
import Foundation
import Observation
import SwiftData
import UIKit

enum StudyJSONValue: Codable, Equatable, Sendable {
    case object([String: StudyJSONValue])
    case array([StudyJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([StudyJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: StudyJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct StudyScienceAttemptSubmission: Sendable {
    let attemptID: UUID
    let subjectID: String
    let courseID: String
    let courseVersion: String
    let activityID: String
    let activityVersion: String
    let activityKind: String
    let seed: Int64
    let responseJSON: Data
    let earnedPoints: Double?
    let possiblePoints: Double?
    let completionItemID: String
    let completionItemKind: String
    let completionPath: String?
    let submittedAt: Date

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
        completionItemID: String? = nil,
        completionItemKind: String? = nil,
        completionPath: String? = nil,
        submittedAt: Date = .now
    ) {
        self.attemptID = attemptID
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
        self.completionItemID = completionItemID ?? activityID
        self.completionItemKind = completionItemKind ?? activityKind
        self.completionPath = completionPath
        self.submittedAt = submittedAt
    }
}

struct StudyScienceRequirementDescriptor: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let contentIDs: [String]
    let minimumSatisfied: Int
    let minimumScore: Double?

    init(
        id: String,
        title: String,
        contentIDs: [String],
        minimumSatisfied: Int = 1,
        minimumScore: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.contentIDs = contentIDs
        self.minimumSatisfied = max(1, minimumSatisfied)
        self.minimumScore = minimumScore.map { min(max($0, 0), 1) }
    }
}

private struct StudyScienceAttemptMutation: Codable, Sendable {
    let attemptID: String
    let courseID: String
    let courseVersion: String
    let activityID: String
    let activityVersion: String
    let activityKind: String
    let seed: Int64
    let response: StudyJSONValue
    let earnedPoints: Double?
    let possiblePoints: Double?
    let completionItemID: String
    let completionItemKind: String
    let completionPath: String?
    let submittedAt: Date
}

private struct StudyScienceProgressMutation: Codable, Sendable {
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

@MainActor
@Observable
final class StudyScienceStore {
    enum StoreError: LocalizedError {
        case invalidResponse
        case invalidProgressEvent
        case noActiveAccount

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "The activity response is not valid JSON."
            case .invalidProgressEvent: "The science progress event is not supported."
            case .noActiveAccount: "Sign in to save science-course work."
            }
        }
    }

    private(set) var activeSubjectID: String?
    private(set) var lastError: String?

    var deviceID: String {
        let key = "study.science.device-id"
        if let stored = UserDefaults.standard.string(forKey: key), UUID(uuidString: stored) != nil {
            return stored.lowercased()
        }
        let identifier = UIDevice.current.identifierForVendor ?? UUID()
        let value = identifier.uuidString.lowercased()
        UserDefaults.standard.set(value, forKey: key)
        return value
    }

    func activate(subjectID: String) {
        activeSubjectID = subjectID
        lastError = nil
    }

    func deactivate() {
        activeSubjectID = nil
        lastError = nil
    }

    func saveDraft(
        courseID: String,
        courseVersion: String,
        activityID: String,
        activityVersion: String,
        responseJSON: Data,
        in modelContext: ModelContext,
        at date: Date = .now
    ) throws {
        guard let subjectID = activeSubjectID else { throw StoreError.noActiveAccount }
        let recordID = StudyScienceDraftRecord.makeRecordID(
            subjectID: subjectID,
            courseID: courseID,
            courseVersion: courseVersion,
            activityID: activityID,
            activityVersion: activityVersion,
            deviceID: deviceID
        )
        let descriptor = FetchDescriptor<StudyScienceDraftRecord>(
            predicate: #Predicate { $0.recordID == recordID }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.responseJSON = responseJSON
            existing.updatedAt = date
        } else {
            modelContext.insert(StudyScienceDraftRecord(
                subjectID: subjectID,
                courseID: courseID,
                courseVersion: courseVersion,
                activityID: activityID,
                activityVersion: activityVersion,
                responseJSON: responseJSON,
                deviceID: deviceID,
                updatedAt: date
            ))
        }
        try modelContext.save()
    }

    func draft(
        courseID: String,
        courseVersion: String,
        activityID: String,
        activityVersion: String,
        in modelContext: ModelContext
    ) throws -> StudyScienceDraftRecord? {
        guard let subjectID = activeSubjectID else { throw StoreError.noActiveAccount }
        let recordID = StudyScienceDraftRecord.makeRecordID(
            subjectID: subjectID,
            courseID: courseID,
            courseVersion: courseVersion,
            activityID: activityID,
            activityVersion: activityVersion,
            deviceID: deviceID
        )
        return try modelContext.fetch(FetchDescriptor<StudyScienceDraftRecord>(
            predicate: #Predicate { $0.recordID == recordID }
        )).first
    }

    func recordProgress(
        courseID: String,
        courseVersion: String,
        activityID: String,
        itemID: String? = nil,
        itemKind: String,
        score: Double? = nil,
        completionPath: String? = nil,
        eventType: String = "completed",
        in modelContext: ModelContext,
        at date: Date = .now
    ) throws {
        guard let subjectID = activeSubjectID else { throw StoreError.noActiveAccount }
        guard ["started", "saved", "submitted", "completed", "mastered"].contains(eventType) else {
            throw StoreError.invalidProgressEvent
        }
        let resolvedItemID = itemID ?? activityID
        let recordID = StudyScienceProgressRecord.makeRecordID(
            subjectID: subjectID,
            courseID: courseID,
            courseVersion: courseVersion,
            itemID: resolvedItemID
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
                itemID: resolvedItemID,
                itemKind: itemKind
            )
            modelContext.insert(progress)
        }
        progress.recordCompletion(score: score, path: completionPath, at: date)

        let mutation = StudyScienceProgressMutation(
            courseID: courseID,
            courseVersion: courseVersion,
            activityID: activityID,
            itemID: resolvedItemID,
            itemKind: itemKind,
            score: score,
            completionPath: completionPath,
            eventType: eventType,
            occurredAt: date
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        modelContext.insert(StudyScienceOutboxRecord(
            subjectID: subjectID,
            entityKind: "progress",
            entityID: progress.recordID,
            payloadJSON: try encoder.encode(mutation),
            createdAt: date
        ))

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            lastError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func submit(
        _ submission: StudyScienceAttemptSubmission,
        in modelContext: ModelContext
    ) throws -> StudyScienceActivityAttemptRecord {
        guard submission.subjectID == activeSubjectID else { throw StoreError.noActiveAccount }
        let response = try JSONDecoder().decode(StudyJSONValue.self, from: submission.responseJSON)
        guard case .object = response else { throw StoreError.invalidResponse }

        let mutation = StudyScienceAttemptMutation(
            attemptID: submission.attemptID.uuidString.lowercased(),
            courseID: submission.courseID,
            courseVersion: submission.courseVersion,
            activityID: submission.activityID,
            activityVersion: submission.activityVersion,
            activityKind: submission.activityKind,
            seed: submission.seed,
            response: response,
            earnedPoints: submission.earnedPoints,
            possiblePoints: submission.possiblePoints,
            completionItemID: submission.completionItemID,
            completionItemKind: submission.completionItemKind,
            completionPath: submission.completionPath,
            submittedAt: submission.submittedAt
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let mutationJSON = try encoder.encode(mutation)
        let payloadHash = SHA256.hash(data: mutationJSON).map { String(format: "%02x", $0) }.joined()

        let attempt = StudyScienceActivityAttemptRecord(
            attemptID: submission.attemptID,
            subjectID: submission.subjectID,
            courseID: submission.courseID,
            courseVersion: submission.courseVersion,
            activityID: submission.activityID,
            activityVersion: submission.activityVersion,
            activityKind: submission.activityKind,
            seed: submission.seed,
            responseJSON: submission.responseJSON,
            earnedPoints: submission.earnedPoints,
            possiblePoints: submission.possiblePoints,
            submittedAt: submission.submittedAt,
            syncState: .queued,
            payloadHash: payloadHash
        )
        modelContext.insert(attempt)

        let progressID = StudyScienceProgressRecord.makeRecordID(
            subjectID: submission.subjectID,
            courseID: submission.courseID,
            courseVersion: submission.courseVersion,
            itemID: submission.completionItemID
        )
        let progressDescriptor = FetchDescriptor<StudyScienceProgressRecord>(
            predicate: #Predicate { $0.recordID == progressID }
        )
        let progress: StudyScienceProgressRecord
        if let existing = try modelContext.fetch(progressDescriptor).first {
            progress = existing
        } else {
            progress = StudyScienceProgressRecord(
                subjectID: submission.subjectID,
                courseID: submission.courseID,
                courseVersion: submission.courseVersion,
                itemID: submission.completionItemID,
                itemKind: submission.completionItemKind
            )
            modelContext.insert(progress)
        }
        progress.recordCompletion(
            score: attempt.normalizedScore,
            path: submission.completionPath,
            at: submission.submittedAt
        )

        let progressMutation = StudyScienceProgressMutation(
            courseID: submission.courseID,
            courseVersion: submission.courseVersion,
            activityID: submission.activityID,
            itemID: submission.completionItemID,
            itemKind: submission.completionItemKind,
            score: attempt.normalizedScore,
            completionPath: submission.completionPath,
            eventType: submission.completionPath == "passed" ? "mastered" : "completed",
            occurredAt: submission.submittedAt
        )
        let progressMutationJSON = try encoder.encode(progressMutation)

        modelContext.insert(StudyScienceOutboxRecord(
            mutationID: submission.attemptID,
            subjectID: submission.subjectID,
            entityKind: "attempt",
            entityID: attempt.recordID,
            payloadJSON: mutationJSON,
            createdAt: submission.submittedAt
        ))
        modelContext.insert(StudyScienceOutboxRecord(
            subjectID: submission.subjectID,
            entityKind: "progress",
            entityID: progress.recordID,
            payloadJSON: progressMutationJSON,
            createdAt: submission.submittedAt
        ))

        let draftID = StudyScienceDraftRecord.makeRecordID(
            subjectID: submission.subjectID,
            courseID: submission.courseID,
            courseVersion: submission.courseVersion,
            activityID: submission.activityID,
            activityVersion: submission.activityVersion,
            deviceID: deviceID
        )
        if let draft = try modelContext.fetch(FetchDescriptor<StudyScienceDraftRecord>(
            predicate: #Predicate { $0.recordID == draftID }
        )).first {
            modelContext.delete(draft)
        }

        do {
            try modelContext.save()
            return attempt
        } catch {
            modelContext.rollback()
            lastError = error.localizedDescription
            throw error
        }
    }

    func completionSnapshot(
        requirements: [StudyScienceRequirementDescriptor],
        progress: [StudyScienceProgressRecord]
    ) -> StudyScienceCompletionSnapshot {
        let byID = Dictionary(uniqueKeysWithValues: progress.map { ($0.itemID, $0) })
        return StudyScienceCompletionSnapshot(requirements: requirements.map { requirement in
            let matches = requirement.contentIDs.compactMap { byID[$0] }
            let satisfying = matches.filter { record in
                guard record.isCompleted else { return false }
                guard let minimumScore = requirement.minimumScore else { return true }
                return (record.bestScore ?? 0) >= minimumScore
            }
            let isSatisfied = satisfying.count >= requirement.minimumSatisfied
            let scoreDetail = requirement.minimumScore.map {
                " · \(Int(($0 * 100).rounded()))% required"
            } ?? ""
            return StudyScienceCompletionSnapshot.Requirement(
                id: requirement.id,
                title: requirement.title,
                isSatisfied: isSatisfied,
                detail: "\(min(satisfying.count, requirement.minimumSatisfied))/\(requirement.minimumSatisfied) complete\(scoreDetail)"
            )
        })
    }
}

enum StudyScienceArtifactStorage {
    static func rootURL(fileManager: FileManager = .default) throws -> URL {
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "StudyScience", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = root
        try mutableRoot.setResourceValues(values)
        return root
    }

    static func store(
        sourceURL: URL,
        subjectID: String,
        artifactID: UUID,
        fileManager: FileManager = .default
    ) throws -> String {
        let subjectHash = SHA256.hash(data: Data(subjectID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let directory = try rootURL(fileManager: fileManager)
            .appending(path: subjectHash, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = sourceURL.pathExtension.isEmpty ? "bin" : sourceURL.pathExtension.lowercased()
        let filename = "\(artifactID.uuidString.lowercased()).\(ext)"
        let destination = directory.appending(path: filename)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path
        )
        return "\(subjectHash)/\(filename)"
    }

    static func remove(relativePath: String, fileManager: FileManager = .default) {
        guard !relativePath.contains(".."), !relativePath.hasPrefix("/") else { return }
        guard let root = try? rootURL(fileManager: fileManager) else { return }
        let url = root.appending(path: relativePath)
        try? fileManager.removeItem(at: url)
    }
}
