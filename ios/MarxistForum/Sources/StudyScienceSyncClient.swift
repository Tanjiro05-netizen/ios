import Foundation

enum StudyScienceSyncError: LocalizedError, Equatable {
    case payloadMustBeObject
    case payloadTooLarge

    var errorDescription: String? {
        switch self {
        case .payloadMustBeObject:
            "Science sync payloads must be JSON objects."
        case .payloadTooLarge:
            "This science result is too large to synchronize. Raw media stays on this device."
        }
    }
}

enum StudyScienceJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case number(Double)
    case string(String)
    case array([StudyScienceJSONValue])
    case object([String: StudyScienceJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(UInt64.self) {
            self = .unsignedInteger(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([StudyScienceJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: StudyScienceJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .unsignedInteger(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    static func object<Payload: Encodable>(from payload: Payload) throws -> StudyScienceJSONValue {
        let encoded = try JSONEncoder.supabase.encode(payload)
        return try object(fromJSONData: encoded)
    }

    static func object(fromJSONData encoded: Data) throws -> StudyScienceJSONValue {
        guard encoded.count <= 512 * 1_024 else {
            throw StudyScienceSyncError.payloadTooLarge
        }
        let value = try JSONDecoder.supabase.decode(StudyScienceJSONValue.self, from: encoded)
        guard case .object = value else {
            throw StudyScienceSyncError.payloadMustBeObject
        }
        return value
    }
}

struct StudyScienceMembershipRemote: Codable, Equatable, Sendable {
    var userId: String
    var courseId: String
    var grantedAt: String
    var revokedAt: String?

    var isActive: Bool { revokedAt == nil }
}

struct StudyScienceProgressEventRemote: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var userId: String
    var courseId: String
    var courseVersion: String
    var activityId: String
    var eventType: String
    var originDeviceId: UUID
    var occurredAt: String
    var payload: StudyScienceJSONValue
    var payloadHash: String
    var serverCreatedAt: String
}

struct StudyScienceAttemptRemote: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var userId: String
    var courseId: String
    var courseVersion: String
    var activityId: String
    var attemptKind: String
    var originDeviceId: UUID
    var occurredAt: String
    var payload: StudyScienceJSONValue
    var payloadHash: String
    var serverCreatedAt: String
}

struct StudyScienceSyncCursor: Codable, Equatable, Sendable {
    var serverCreatedAt: String
    var id: UUID
}

struct StudyScienceAppendResult: Codable, Equatable, Sendable {
    var id: UUID
    var inserted: Bool
    var serverCreatedAt: String
}

struct StudyScienceInviteRedemption: Codable, Equatable, Sendable {
    var success: Bool
    var status: String
    var courseId: String?
    var grantedAt: String?
}

private struct StudyScienceProgressAppendBody: Encodable {
    var pId: UUID
    var pCourseId: String
    var pCourseVersion: String
    var pActivityId: String
    var pEventType: String
    var pOriginDeviceId: UUID
    var pOccurredAt: String
    var pPayload: StudyScienceJSONValue
}

private struct StudyScienceAttemptAppendBody: Encodable {
    var pId: UUID
    var pCourseId: String
    var pCourseVersion: String
    var pActivityId: String
    var pAttemptKind: String
    var pOriginDeviceId: UUID
    var pOccurredAt: String
    var pPayload: StudyScienceJSONValue
}

@MainActor
final class StudyScienceSyncClient {
    private let client: SupabaseRESTClient
    private let maximumPageSize = 500

    init(client: SupabaseRESTClient = .init()) {
        self.client = client
    }

    func redeemInvite(code: String, auth: AuthStore) async throws -> StudyScienceInviteRedemption {
        struct Body: Encodable { var pCode: String }
        return try await auth.withAuthenticatedRequest { [client] token in
            try await client.rpc(
                function: "redeem_study_science_invite",
                body: Body(pCode: code),
                accessToken: token
            )
        }
    }

    func fetchMembership(
        courseId: String = "PHY111",
        auth: AuthStore
    ) async throws -> StudyScienceMembershipRemote? {
        guard let userId = auth.userId else { throw APIError.authenticationRequired }
        return try await auth.withAuthenticatedRequest { [client] token in
            let rows: [StudyScienceMembershipRemote] = try await client.fetchArray(
                table: "study_science_memberships",
                queryItems: [
                    URLQueryItem(name: "select", value: "user_id,course_id,granted_at,revoked_at"),
                    URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                    URLQueryItem(name: "course_id", value: "eq.\(courseId)"),
                    URLQueryItem(name: "limit", value: "1")
                ],
                accessToken: token
            )
            return rows.first
        }
    }

    func fetchProgressEvents(
        courseId: String = "PHY111",
        courseVersion: String,
        after cursor: StudyScienceSyncCursor? = nil,
        limit: Int = 200,
        auth: AuthStore
    ) async throws -> [StudyScienceProgressEventRemote] {
        guard let userId = auth.userId else { throw APIError.authenticationRequired }
        var queryItems = Self.cursorQueryItems(
            userId: userId,
            courseId: courseId,
            courseVersion: courseVersion,
            cursor: cursor,
            limit: min(max(limit, 1), maximumPageSize)
        )
        queryItems.insert(
            URLQueryItem(
                name: "select",
                value: "id,user_id,course_id,course_version,activity_id,event_type,origin_device_id,occurred_at,payload,payload_hash,server_created_at"
            ),
            at: 0
        )
        return try await auth.withAuthenticatedRequest { [client] token in
            try await client.fetchArray(
                table: "study_science_progress_events",
                queryItems: queryItems,
                accessToken: token
            )
        }
    }

    func fetchAttempts(
        courseId: String = "PHY111",
        courseVersion: String,
        after cursor: StudyScienceSyncCursor? = nil,
        limit: Int = 200,
        auth: AuthStore
    ) async throws -> [StudyScienceAttemptRemote] {
        guard let userId = auth.userId else { throw APIError.authenticationRequired }
        var queryItems = Self.cursorQueryItems(
            userId: userId,
            courseId: courseId,
            courseVersion: courseVersion,
            cursor: cursor,
            limit: min(max(limit, 1), maximumPageSize)
        )
        queryItems.insert(
            URLQueryItem(
                name: "select",
                value: "id,user_id,course_id,course_version,activity_id,attempt_kind,origin_device_id,occurred_at,payload,payload_hash,server_created_at"
            ),
            at: 0
        )
        return try await auth.withAuthenticatedRequest { [client] token in
            try await client.fetchArray(
                table: "study_science_attempts",
                queryItems: queryItems,
                accessToken: token
            )
        }
    }

    func appendProgressEvent<Payload: Encodable>(
        id: UUID,
        courseId: String = "PHY111",
        courseVersion: String,
        activityId: String,
        eventType: String,
        originDeviceId: UUID,
        occurredAt: Date,
        payload: Payload,
        auth: AuthStore
    ) async throws -> StudyScienceAppendResult {
        try await appendProgressEvent(
            id: id,
            courseId: courseId,
            courseVersion: courseVersion,
            activityId: activityId,
            eventType: eventType,
            originDeviceId: originDeviceId,
            occurredAt: occurredAt,
            payloadValue: try StudyScienceJSONValue.object(from: payload),
            auth: auth
        )
    }

    func appendProgressEvent(
        id: UUID,
        courseId: String = "PHY111",
        courseVersion: String,
        activityId: String,
        eventType: String,
        originDeviceId: UUID,
        occurredAt: Date,
        payloadJSON: Data,
        auth: AuthStore
    ) async throws -> StudyScienceAppendResult {
        try await appendProgressEvent(
            id: id,
            courseId: courseId,
            courseVersion: courseVersion,
            activityId: activityId,
            eventType: eventType,
            originDeviceId: originDeviceId,
            occurredAt: occurredAt,
            payloadValue: try StudyScienceJSONValue.object(fromJSONData: payloadJSON),
            auth: auth
        )
    }

    private func appendProgressEvent(
        id: UUID,
        courseId: String,
        courseVersion: String,
        activityId: String,
        eventType: String,
        originDeviceId: UUID,
        occurredAt: Date,
        payloadValue: StudyScienceJSONValue,
        auth: AuthStore
    ) async throws -> StudyScienceAppendResult {
        let body = StudyScienceProgressAppendBody(
            pId: id,
            pCourseId: courseId,
            pCourseVersion: courseVersion,
            pActivityId: activityId,
            pEventType: eventType,
            pOriginDeviceId: originDeviceId,
            pOccurredAt: Self.timestamp(occurredAt),
            pPayload: payloadValue
        )
        return try await auth.withAuthenticatedRequest { [client] token in
            try await client.rpc(
                function: "append_study_science_progress_event",
                body: body,
                accessToken: token
            )
        }
    }

    func appendAttempt<Payload: Encodable>(
        id: UUID,
        courseId: String = "PHY111",
        courseVersion: String,
        activityId: String,
        attemptKind: String,
        originDeviceId: UUID,
        occurredAt: Date,
        payload: Payload,
        auth: AuthStore
    ) async throws -> StudyScienceAppendResult {
        try await appendAttempt(
            id: id,
            courseId: courseId,
            courseVersion: courseVersion,
            activityId: activityId,
            attemptKind: attemptKind,
            originDeviceId: originDeviceId,
            occurredAt: occurredAt,
            payloadValue: try StudyScienceJSONValue.object(from: payload),
            auth: auth
        )
    }

    func appendAttempt(
        id: UUID,
        courseId: String = "PHY111",
        courseVersion: String,
        activityId: String,
        attemptKind: String,
        originDeviceId: UUID,
        occurredAt: Date,
        payloadJSON: Data,
        auth: AuthStore
    ) async throws -> StudyScienceAppendResult {
        try await appendAttempt(
            id: id,
            courseId: courseId,
            courseVersion: courseVersion,
            activityId: activityId,
            attemptKind: attemptKind,
            originDeviceId: originDeviceId,
            occurredAt: occurredAt,
            payloadValue: try StudyScienceJSONValue.object(fromJSONData: payloadJSON),
            auth: auth
        )
    }

    private func appendAttempt(
        id: UUID,
        courseId: String,
        courseVersion: String,
        activityId: String,
        attemptKind: String,
        originDeviceId: UUID,
        occurredAt: Date,
        payloadValue: StudyScienceJSONValue,
        auth: AuthStore
    ) async throws -> StudyScienceAppendResult {
        let body = StudyScienceAttemptAppendBody(
            pId: id,
            pCourseId: courseId,
            pCourseVersion: courseVersion,
            pActivityId: activityId,
            pAttemptKind: attemptKind,
            pOriginDeviceId: originDeviceId,
            pOccurredAt: Self.timestamp(occurredAt),
            pPayload: payloadValue
        )
        return try await auth.withAuthenticatedRequest { [client] token in
            try await client.rpc(
                function: "append_study_science_attempt",
                body: body,
                accessToken: token
            )
        }
    }

    private static func cursorQueryItems(
        userId: String,
        courseId: String,
        courseVersion: String,
        cursor: StudyScienceSyncCursor?,
        limit: Int
    ) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "course_id", value: "eq.\(courseId)"),
            URLQueryItem(name: "course_version", value: "eq.\(courseVersion)"),
            URLQueryItem(name: "order", value: "server_created_at.asc,id.asc"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let cursor {
            items.append(
                URLQueryItem(
                    name: "or",
                    value: "(server_created_at.gt.\(cursor.serverCreatedAt),and(server_created_at.eq.\(cursor.serverCreatedAt),id.gt.\(cursor.id.uuidString)))"
                )
            )
        }
        return items
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

extension StudyScienceProgressEventRemote {
    var syncCursor: StudyScienceSyncCursor {
        StudyScienceSyncCursor(serverCreatedAt: serverCreatedAt, id: id)
    }
}

extension StudyScienceAttemptRemote {
    var syncCursor: StudyScienceSyncCursor {
        StudyScienceSyncCursor(serverCreatedAt: serverCreatedAt, id: id)
    }
}
