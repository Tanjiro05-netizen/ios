import Foundation

enum StudyCourseAccessRequirement: String, Codable, Sendable {
    case open
    case accountRequired
    case inviteOnly
}

struct StudyCourseCompletionPolicy: Codable, Equatable, Sendable {
    let completionLabel: String
    let awardsCredential: Bool
    let requiredGroupIDs: [String]
}

struct StudySourcePageRange: Codable, Equatable, Sendable {
    let resourceName: String
    var resourceFirstSourcePage: Int? = nil
    let firstPage: Int
    let lastPage: Int
}

enum StudyCompletionGroupRule: String, Codable, Sendable {
    case all
    case any
}

struct StudyCompletionRequirementGroup: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let rule: StudyCompletionGroupRule
    let requirementIDs: [String]
    var minimumScore: Double? = nil
}

enum StudyInteractiveActivityKind: String, Codable, CaseIterable, Hashable, Sendable {
    case acknowledgement
    case numericQuantity
    case mathExpression
    case graphTable
    case freeBodyDiagram
    case motionTrackingLab
    case numericalKinematics
    case pythonNotebook
    case constructedResponse
    case workedExample
    case errorDiagnosis
}

enum StudyActivityEvidenceKind: String, Codable, Sendable {
    case acknowledgement
    case text
    case numericValue
    case table
    case graph
    case diagram
    case code
    case validation
}

struct StudyActivityEvidenceRequirement: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let kind: StudyActivityEvidenceKind
    var minimumCount: Int? = nil
}

struct StudyInteractiveActivity: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let activityVersion: String
    let title: String
    let summary: String
    let kind: StudyInteractiveActivityKind
    let requirement: StudyContentRequirement
    let estimatedMinutes: Int
    var instructionsMarkdown: String? = nil
    let configuration: StudyInteractiveActivityConfiguration
    var toolProfileID: String? = nil
    var datasetIDs: [String] = []
    var evidenceRequirements: [StudyActivityEvidenceRequirement] = []
    var sourcePageRange: StudySourcePageRange? = nil
    var accessibilityAlternativeActivityID: String? = nil
}

struct StudyAcknowledgementActivityConfiguration: Codable, Equatable, Sendable {
    let statementMarkdown: String
    let acknowledgementLabel: String
}

struct StudyNumericAnswerSpecification: Codable, Equatable, Sendable {
    let canonicalValue: Double
    var canonicalUnitID: String? = nil
    var acceptedUnitIDs: [String] = []
    var absoluteTolerance: Double? = nil
    var relativeTolerance: Double? = nil
    var requiresUnit: Bool = false
    var minimumSignificantFigures: Int? = nil
    var feedbackMarkdown: String? = nil
}

struct StudyNumericPrompt: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let promptMarkdown: String
    let answer: StudyNumericAnswerSpecification
}

struct StudyNumericQuantityActivityConfiguration: Codable, Equatable, Sendable {
    let parts: [StudyNumericPrompt]
    var responseInstructionsMarkdown: String? = nil
}

struct StudyMathExpressionActivityConfiguration: Codable, Equatable, Sendable {
    let promptMarkdown: String
    let expectedMathJSON: [String]
    var acceptedLaTeX: [String] = []
    var feedbackMarkdown: String? = nil
}

struct StudyScienceTableColumn: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    var unitID: String? = nil
    var isEditable: Bool = true
}

struct StudyGraphSeriesSpecification: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let xColumnID: String
    let yColumnID: String
}

struct StudyGraphTableActivityConfiguration: Codable, Equatable, Sendable {
    let promptMarkdown: String
    let columns: [StudyScienceTableColumn]
    var initialRows: [[String]] = []
    var series: [StudyGraphSeriesSpecification] = []
    var minimumRows: Int? = nil
    var responsePrompts: [String] = []
    var numericPrompts: [StudyNumericPrompt] = []
}

struct StudyFreeBodyScenario: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let situationMarkdown: String
    let namedSystem: String
    var minimumForceCount: Int = 1
}

struct StudyFreeBodyDiagramActivityConfiguration: Codable, Equatable, Sendable {
    let scenarios: [StudyFreeBodyScenario]
    var selfReviewPrompts: [String] = []
}

struct StudyMotionTrackingActivityConfiguration: Codable, Equatable, Sendable {
    let safetyMarkdown: String
    let fallbackDatasetID: String
    let minimumSampleCount: Int
    let maximumSampleCount: Int
    let maximumVideoDurationSeconds: Int
    let derivativeMethod: String
    let requiredReportFields: [String]
}

struct StudyNumericalKinematicsActivityConfiguration: Codable, Equatable, Sendable {
    let accelerationDatasetID: String
    let initialPosition: Double
    let initialVelocity: Double
    let defaultTimeStep: Double
    let positionUpdateMarkdown: String
    let velocityUpdateMarkdown: String
    let requiredValidationSteps: [String]
}

struct StudyPythonVisibleTest: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let expression: String
    let expectedDescription: String
}

struct StudyPythonNotebookActivityConfiguration: Codable, Equatable, Sendable {
    let runtimeManifestID: String
    let templateSource: String
    let visibleTests: [StudyPythonVisibleTest]
    let maximumSourceBytes: Int
    let maximumOutputBytes: Int
    let timeoutSeconds: Int
    let requiredEvidenceFields: [String]
}

struct StudyConstructedResponseActivityConfiguration: Codable, Equatable, Sendable {
    let prompts: [String]
    var minimumResponseCharacters: Int = 1
    var selfReviewPrompts: [String] = []
}

struct StudyWorkedExampleActivityConfiguration: Codable, Equatable, Sendable {
    let problemMarkdown: String
    let solutionMarkdown: String
    let resultMarkdown: String
    let interpretationMarkdown: String
    var minimumAttemptCharacters: Int = 1
}

struct StudyErrorDiagnosisActivityConfiguration: Codable, Equatable, Sendable {
    let flawedSolutionMarkdown: String
    let requiredResponsePrompts: [String]
    var selfReviewMarkdown: String? = nil
}

enum StudyInteractiveActivityConfiguration: Codable, Equatable, Sendable {
    case acknowledgement(StudyAcknowledgementActivityConfiguration)
    case numericQuantity(StudyNumericQuantityActivityConfiguration)
    case mathExpression(StudyMathExpressionActivityConfiguration)
    case graphTable(StudyGraphTableActivityConfiguration)
    case freeBodyDiagram(StudyFreeBodyDiagramActivityConfiguration)
    case motionTrackingLab(StudyMotionTrackingActivityConfiguration)
    case numericalKinematics(StudyNumericalKinematicsActivityConfiguration)
    case pythonNotebook(StudyPythonNotebookActivityConfiguration)
    case constructedResponse(StudyConstructedResponseActivityConfiguration)
    case workedExample(StudyWorkedExampleActivityConfiguration)
    case errorDiagnosis(StudyErrorDiagnosisActivityConfiguration)

    private enum CodingKeys: String, CodingKey { case kind, details }

    var kind: StudyInteractiveActivityKind {
        switch self {
        case .acknowledgement: .acknowledgement
        case .numericQuantity: .numericQuantity
        case .mathExpression: .mathExpression
        case .graphTable: .graphTable
        case .freeBodyDiagram: .freeBodyDiagram
        case .motionTrackingLab: .motionTrackingLab
        case .numericalKinematics: .numericalKinematics
        case .pythonNotebook: .pythonNotebook
        case .constructedResponse: .constructedResponse
        case .workedExample: .workedExample
        case .errorDiagnosis: .errorDiagnosis
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(StudyInteractiveActivityKind.self, forKey: .kind) {
        case .acknowledgement:
            self = .acknowledgement(try container.decode(StudyAcknowledgementActivityConfiguration.self, forKey: .details))
        case .numericQuantity:
            self = .numericQuantity(try container.decode(StudyNumericQuantityActivityConfiguration.self, forKey: .details))
        case .mathExpression:
            self = .mathExpression(try container.decode(StudyMathExpressionActivityConfiguration.self, forKey: .details))
        case .graphTable:
            self = .graphTable(try container.decode(StudyGraphTableActivityConfiguration.self, forKey: .details))
        case .freeBodyDiagram:
            self = .freeBodyDiagram(try container.decode(StudyFreeBodyDiagramActivityConfiguration.self, forKey: .details))
        case .motionTrackingLab:
            self = .motionTrackingLab(try container.decode(StudyMotionTrackingActivityConfiguration.self, forKey: .details))
        case .numericalKinematics:
            self = .numericalKinematics(try container.decode(StudyNumericalKinematicsActivityConfiguration.self, forKey: .details))
        case .pythonNotebook:
            self = .pythonNotebook(try container.decode(StudyPythonNotebookActivityConfiguration.self, forKey: .details))
        case .constructedResponse:
            self = .constructedResponse(try container.decode(StudyConstructedResponseActivityConfiguration.self, forKey: .details))
        case .workedExample:
            self = .workedExample(try container.decode(StudyWorkedExampleActivityConfiguration.self, forKey: .details))
        case .errorDiagnosis:
            self = .errorDiagnosis(try container.decode(StudyErrorDiagnosisActivityConfiguration.self, forKey: .details))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .acknowledgement(let details): try container.encode(details, forKey: .details)
        case .numericQuantity(let details): try container.encode(details, forKey: .details)
        case .mathExpression(let details): try container.encode(details, forKey: .details)
        case .graphTable(let details): try container.encode(details, forKey: .details)
        case .freeBodyDiagram(let details): try container.encode(details, forKey: .details)
        case .motionTrackingLab(let details): try container.encode(details, forKey: .details)
        case .numericalKinematics(let details): try container.encode(details, forKey: .details)
        case .pythonNotebook(let details): try container.encode(details, forKey: .details)
        case .constructedResponse(let details): try container.encode(details, forKey: .details)
        case .workedExample(let details): try container.encode(details, forKey: .details)
        case .errorDiagnosis(let details): try container.encode(details, forKey: .details)
        }
    }
}

struct StudyNumericResponseValue: Codable, Identifiable, Equatable, Sendable {
    var id: String { partID }
    let partID: String
    let rawValue: String
    var unitID: String? = nil
    var significantFigures: Int? = nil
}

struct StudyNumericQuantityResponse: Codable, Equatable, Sendable {
    let values: [StudyNumericResponseValue]
}

struct StudyMathExpressionResponse: Codable, Equatable, Sendable {
    let latex: String
    var mathJSON: String? = nil
}

struct StudyGraphPoint: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
}

struct StudyGraphTableResponse: Codable, Equatable, Sendable {
    let rows: [[String]]
    var pointsBySeriesID: [String: [StudyGraphPoint]] = [:]
    var annotations: [String] = []
    var responses: [String] = []
    var numericValues: [StudyNumericResponseValue] = []

    private enum CodingKeys: String, CodingKey {
        case rows
        case pointsBySeriesID
        case annotations
        case responses
        case numericValues
    }

    init(
        rows: [[String]],
        pointsBySeriesID: [String: [StudyGraphPoint]] = [:],
        annotations: [String] = [],
        responses: [String] = [],
        numericValues: [StudyNumericResponseValue] = []
    ) {
        self.rows = rows
        self.pointsBySeriesID = pointsBySeriesID
        self.annotations = annotations
        self.responses = responses
        self.numericValues = numericValues
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rows = try container.decode([[String]].self, forKey: .rows)
        pointsBySeriesID = try container.decodeIfPresent([String: [StudyGraphPoint]].self, forKey: .pointsBySeriesID) ?? [:]
        annotations = try container.decodeIfPresent([String].self, forKey: .annotations) ?? []
        responses = try container.decodeIfPresent([String].self, forKey: .responses) ?? []
        numericValues = try container.decodeIfPresent([StudyNumericResponseValue].self, forKey: .numericValues) ?? []
    }
}

struct StudyForceVectorResponse: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let sourceLabel: String
    let forceLabel: String
    let originX: Double
    let originY: Double
    let endX: Double
    let endY: Double
    var magnitudeText: String? = nil
}

struct StudyFreeBodyDiagramResponse: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let scenarioID: String
    let forces: [StudyForceVectorResponse]
    let explanation: String
}

struct StudyMotionSample: Codable, Identifiable, Equatable, Sendable {
    var id: Int { frameIndex }
    let frameIndex: Int
    let timeSeconds: Double
    let positionMetres: Double
}

struct StudyMotionFramePoint: Codable, Identifiable, Equatable, Sendable {
    var id: String { "\(timeSeconds)::\(normalizedX)::\(normalizedY)" }
    let timeSeconds: Double
    let normalizedX: Double
    let normalizedY: Double
}

struct StudyMotionTrackingResponse: Codable, Equatable, Sendable {
    let calibrationDistanceMetres: Double
    let calibrationPixels: Double
    let samples: [StudyMotionSample]
    var velocityPoints: [StudyGraphPoint] = []
    var accelerationPoints: [StudyGraphPoint] = []
    var calibrationPoints: [StudyGraphPoint] = []
    var frameMarks: [StudyMotionFramePoint] = []
    let reportFields: [String: String]
    let usedFallbackDataset: Bool
}

struct StudyNumericalKinematicsResponse: Codable, Equatable, Sendable {
    let timeStep: Double
    let rows: [[Double]]
    let validationFields: [String: String]
}

struct StudyPythonNotebookResponse: Codable, Equatable, Sendable {
    let source: String
    let stdout: String
    let stderr: String
    let visibleTestResults: [String: Bool]
    let evidenceFields: [String: String]
}

struct StudyConstructedResponse: Codable, Equatable, Sendable {
    let responses: [String]
    var completedSelfReview: [Bool] = []
}

struct StudyWorkedExampleResponse: Codable, Equatable, Sendable {
    let attemptMarkdown: String
    let revealedSolution: Bool
}

struct StudyErrorDiagnosisResponse: Codable, Equatable, Sendable {
    let responses: [String]
    let completedSelfReview: Bool
}

enum StudyInteractiveResponse: Codable, Equatable, Sendable {
    case acknowledgement(Bool)
    case numericQuantity(StudyNumericQuantityResponse)
    case mathExpression(StudyMathExpressionResponse)
    case graphTable(StudyGraphTableResponse)
    case freeBodyDiagram([StudyFreeBodyDiagramResponse])
    case motionTrackingLab(StudyMotionTrackingResponse)
    case numericalKinematics(StudyNumericalKinematicsResponse)
    case pythonNotebook(StudyPythonNotebookResponse)
    case constructedResponse(StudyConstructedResponse)
    case workedExample(StudyWorkedExampleResponse)
    case errorDiagnosis(StudyErrorDiagnosisResponse)

    private enum CodingKeys: String, CodingKey { case kind, details }

    var kind: StudyInteractiveActivityKind {
        switch self {
        case .acknowledgement: .acknowledgement
        case .numericQuantity: .numericQuantity
        case .mathExpression: .mathExpression
        case .graphTable: .graphTable
        case .freeBodyDiagram: .freeBodyDiagram
        case .motionTrackingLab: .motionTrackingLab
        case .numericalKinematics: .numericalKinematics
        case .pythonNotebook: .pythonNotebook
        case .constructedResponse: .constructedResponse
        case .workedExample: .workedExample
        case .errorDiagnosis: .errorDiagnosis
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(StudyInteractiveActivityKind.self, forKey: .kind) {
        case .acknowledgement: self = .acknowledgement(try container.decode(Bool.self, forKey: .details))
        case .numericQuantity: self = .numericQuantity(try container.decode(StudyNumericQuantityResponse.self, forKey: .details))
        case .mathExpression: self = .mathExpression(try container.decode(StudyMathExpressionResponse.self, forKey: .details))
        case .graphTable: self = .graphTable(try container.decode(StudyGraphTableResponse.self, forKey: .details))
        case .freeBodyDiagram: self = .freeBodyDiagram(try container.decode([StudyFreeBodyDiagramResponse].self, forKey: .details))
        case .motionTrackingLab: self = .motionTrackingLab(try container.decode(StudyMotionTrackingResponse.self, forKey: .details))
        case .numericalKinematics: self = .numericalKinematics(try container.decode(StudyNumericalKinematicsResponse.self, forKey: .details))
        case .pythonNotebook: self = .pythonNotebook(try container.decode(StudyPythonNotebookResponse.self, forKey: .details))
        case .constructedResponse: self = .constructedResponse(try container.decode(StudyConstructedResponse.self, forKey: .details))
        case .workedExample: self = .workedExample(try container.decode(StudyWorkedExampleResponse.self, forKey: .details))
        case .errorDiagnosis: self = .errorDiagnosis(try container.decode(StudyErrorDiagnosisResponse.self, forKey: .details))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .acknowledgement(let details): try container.encode(details, forKey: .details)
        case .numericQuantity(let details): try container.encode(details, forKey: .details)
        case .mathExpression(let details): try container.encode(details, forKey: .details)
        case .graphTable(let details): try container.encode(details, forKey: .details)
        case .freeBodyDiagram(let details): try container.encode(details, forKey: .details)
        case .motionTrackingLab(let details): try container.encode(details, forKey: .details)
        case .numericalKinematics(let details): try container.encode(details, forKey: .details)
        case .pythonNotebook(let details): try container.encode(details, forKey: .details)
        case .constructedResponse(let details): try container.encode(details, forKey: .details)
        case .workedExample(let details): try container.encode(details, forKey: .details)
        case .errorDiagnosis(let details): try container.encode(details, forKey: .details)
        }
    }
}

struct StudyDatasetColumn: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let unitID: String
    let valueType: String
}

struct StudyDataset: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let version: String
    let title: String
    let summary: String
    let resourceName: String
    let mimeType: String
    let sha256: String
    let columns: [StudyDatasetColumn]
    let provenance: String
    let license: String
    var sourcePageRange: StudySourcePageRange? = nil
}

enum StudyToolCapability: String, Codable, Sendable {
    case scientificCalculator
    case constants
    case unitHelper
    case graphing
    case dataTables
    case mathInput
    case python
    case formulaCard
}

enum StudyCalculatorAngleMode: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case degrees
    case radians

    var id: String { rawValue }
}

enum StudyCalculatorHistoryPolicy: String, Codable, Sendable {
    case persistent
    case attemptScoped
    case disabled
}

struct StudyScientificCalculatorProfile: Codable, Equatable, Sendable {
    let allowedFunctions: [String]
    let initialAngleMode: StudyCalculatorAngleMode
    let historyPolicy: StudyCalculatorHistoryPolicy
}

struct StudyToolProfile: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let capabilities: [StudyToolCapability]
    var calculator: StudyScientificCalculatorProfile? = nil
    var formulaCardMarkdown: String? = nil
    var networkAllowed: Bool = false
}

enum StudyScienceAssessmentItemKind: String, Codable, Sendable {
    case objectiveChoice
    case numericQuantity
    case constructedResponse
}

struct StudyScienceAssessmentOption: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let label: String
}

struct StudyScienceAssessmentItem: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let kind: StudyScienceAssessmentItemKind
    let promptMarkdown: String
    let points: Int
    var options: [StudyScienceAssessmentOption] = []
    var correctOptionIDs: [String] = []
    var numericAnswer: StudyNumericAnswerSpecification? = nil
    var minimumResponseCharacters: Int? = nil
    var rubricMarkdown: String? = nil
    var sourcePageRange: StudySourcePageRange? = nil
}

struct StudyScienceAssessmentPassPolicy: Codable, Equatable, Sendable {
    let scorableItemCount: Int
    let minimumCorrectCount: Int
    let requiredConstructedResponseCount: Int
    let displayThreshold: String
}
