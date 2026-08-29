import Foundation

enum StudyScienceCoursePackageValidator {
    static func validate(
        _ package: StudyCoursePackage,
        activityIDs: Set<String>,
        assessmentIDs: Set<String>,
        datasetIDs: Set<String>,
        toolProfileIDs: Set<String>,
        blockIDs: Set<String>
    ) -> [StudyPackageValidationIssue] {
        let activities = package.interactiveActivities ?? []
        let scienceItems = package.scienceAssessmentItems ?? []
        let datasets = package.datasets ?? []
        let toolProfiles = package.toolProfiles ?? []
        let completionGroups = package.completionGroups ?? []
        let containsScienceContent = !activities.isEmpty
            || !scienceItems.isEmpty
            || !datasets.isEmpty
            || !toolProfiles.isEmpty
            || !completionGroups.isEmpty
            || package.courses.contains { $0.type == .laboratoryScience }
        guard containsScienceContent else { return [] }

        var issues: [StudyPackageValidationIssue] = []
        if package.schemaVersion < 4 {
            issues.append(.init(path: "schemaVersion", message: "Interactive science content requires schema version 4 or later."))
        }

        func requireText(_ value: String?, path: String, message: String) {
            if value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                issues.append(.init(path: path, message: message))
            }
        }

        func validatePageRange(_ range: StudySourcePageRange?, path: String) {
            guard let range else { return }
            requireText(range.resourceName, path: "\(path).resourceName", message: "Source resource name cannot be blank.")
            if range.firstPage < 1 || range.lastPage < range.firstPage {
                issues.append(.init(path: path, message: "Source page range must be positive and ordered."))
            }
            if let resourceFirstSourcePage = range.resourceFirstSourcePage,
               resourceFirstSourcePage < 1 || range.firstPage < resourceFirstSourcePage {
                issues.append(.init(path: path, message: "Source page range must fall within the mapped source resource."))
            }
        }

        for course in package.courses where course.type == .laboratoryScience {
            if let planned = course.plannedModuleCount {
                if planned < course.modules.count || planned < 1 {
                    issues.append(.init(path: "courses.\(course.id).plannedModuleCount", message: "Planned module count cannot be smaller than the released module count."))
                }
            } else {
                issues.append(.init(path: "courses.\(course.id).plannedModuleCount", message: "Laboratory-science courses must declare their planned module count."))
            }
            if course.completionPolicy == nil {
                issues.append(.init(path: "courses.\(course.id).completionPolicy", message: "Laboratory-science courses must declare a completion policy."))
            }
            if course.accessRequirement == nil {
                issues.append(.init(path: "courses.\(course.id).accessRequirement", message: "Laboratory-science courses must declare an access requirement."))
            }
        }

        for course in package.courses {
            for module in course.modules {
                for lesson in module.lessons {
                    for block in lesson.blocks {
                        if course.type == .laboratoryScience, block.sourcePageRange == nil {
                            issues.append(.init(path: "lessons.\(lesson.id).blocks.\(block.id).sourcePageRange", message: "Laboratory-science lesson blocks require source-page provenance."))
                        }
                        validatePageRange(block.sourcePageRange, path: "lessons.\(lesson.id).blocks.\(block.id).sourcePageRange")
                    }
                }
            }
        }

        for activity in activities {
            let path = "interactiveActivities.\(activity.id)"
            if activity.kind != activity.configuration.kind {
                issues.append(.init(path: "\(path).configuration", message: "Activity kind and typed configuration kind must match."))
            }
            if activity.estimatedMinutes < 0 {
                issues.append(.init(path: "\(path).estimatedMinutes", message: "Estimated time cannot be negative."))
            }
            if let profileID = activity.toolProfileID, !toolProfileIDs.contains(profileID) {
                issues.append(.init(path: "\(path).toolProfileID", message: "Tool-profile reference does not resolve."))
            }
            for datasetID in activity.datasetIDs where !datasetIDs.contains(datasetID) {
                issues.append(.init(path: "\(path).datasetIDs", message: "Dataset reference \(datasetID) does not resolve."))
            }
            if let alternativeID = activity.accessibilityAlternativeActivityID {
                if alternativeID == activity.id || !activityIDs.contains(alternativeID) {
                    issues.append(.init(path: "\(path).accessibilityAlternativeActivityID", message: "Accessibility-alternative reference must resolve to a different activity."))
                }
            }
            if Set(activity.evidenceRequirements.map(\.id)).count != activity.evidenceRequirements.count {
                issues.append(.init(path: "\(path).evidenceRequirements", message: "Evidence identifiers must be unique within an activity."))
            }
            for evidence in activity.evidenceRequirements where (evidence.minimumCount ?? 1) < 1 {
                issues.append(.init(path: "\(path).evidenceRequirements.\(evidence.id)", message: "Evidence minimum count must be positive."))
            }
            if activity.sourcePageRange == nil {
                issues.append(.init(path: "\(path).sourcePageRange", message: "Interactive activities require source-page provenance."))
            }
            validatePageRange(activity.sourcePageRange, path: "\(path).sourcePageRange")
            validate(activity.configuration, path: path, datasetIDs: datasetIDs, issues: &issues)
        }

        for item in scienceItems {
            let path = "scienceAssessmentItems.\(item.id)"
            if item.points < 0 {
                issues.append(.init(path: "\(path).points", message: "Assessment points cannot be negative."))
            }
            requireText(item.promptMarkdown, path: "\(path).promptMarkdown", message: "Assessment prompt cannot be blank.")
            switch item.kind {
            case .objectiveChoice:
                if item.options.count < 2 {
                    issues.append(.init(path: "\(path).options", message: "Objective-choice items require at least two options."))
                }
                let optionIDs = Set(item.options.map(\.id))
                if optionIDs.count != item.options.count {
                    issues.append(.init(path: "\(path).options", message: "Option identifiers must be unique within an item."))
                }
                if item.correctOptionIDs.isEmpty || !Set(item.correctOptionIDs).isSubset(of: optionIDs) {
                    issues.append(.init(path: "\(path).correctOptionIDs", message: "Correct options must be nonempty and resolve."))
                }
            case .numericQuantity:
                if let answer = item.numericAnswer {
                    validate(answer, path: "\(path).numericAnswer", issues: &issues)
                } else {
                    issues.append(.init(path: "\(path).numericAnswer", message: "Numeric items require an answer specification."))
                }
            case .constructedResponse:
                if (item.minimumResponseCharacters ?? 0) < 1 {
                    issues.append(.init(path: "\(path).minimumResponseCharacters", message: "Constructed responses require a positive minimum length."))
                }
            }
            if item.sourcePageRange == nil {
                issues.append(.init(path: "\(path).sourcePageRange", message: "Science assessment items require source-page provenance."))
            }
            validatePageRange(item.sourcePageRange, path: "\(path).sourcePageRange")
        }

        for dataset in datasets {
            let path = "datasets.\(dataset.id)"
            requireText(dataset.resourceName, path: "\(path).resourceName", message: "Dataset resource name cannot be blank.")
            requireText(dataset.mimeType, path: "\(path).mimeType", message: "Dataset MIME type cannot be blank.")
            requireText(dataset.provenance, path: "\(path).provenance", message: "Dataset provenance cannot be blank.")
            requireText(dataset.license, path: "\(path).license", message: "Dataset license cannot be blank.")
            let hashPattern = /^[0-9a-f]{64}$/
            if dataset.sha256.wholeMatch(of: hashPattern) == nil {
                issues.append(.init(path: "\(path).sha256", message: "Dataset SHA-256 must be 64 lowercase hexadecimal characters."))
            }
            if dataset.columns.isEmpty || Set(dataset.columns.map(\.id)).count != dataset.columns.count {
                issues.append(.init(path: "\(path).columns", message: "Datasets require uniquely identified columns."))
            }
            for column in dataset.columns {
                requireText(column.unitID, path: "\(path).columns.\(column.id).unitID", message: "Dataset columns require an explicit unit identifier; use '1' for dimensionless values.")
            }
            if dataset.sourcePageRange == nil {
                issues.append(.init(path: "\(path).sourcePageRange", message: "Science datasets require source-page provenance."))
            }
            validatePageRange(dataset.sourcePageRange, path: "\(path).sourcePageRange")
        }

        for profile in toolProfiles {
            let path = "toolProfiles.\(profile.id)"
            if profile.capabilities.isEmpty {
                issues.append(.init(path: "\(path).capabilities", message: "Tool profiles require at least one capability."))
            }
            if profile.capabilities.contains(.scientificCalculator), profile.calculator == nil {
                issues.append(.init(path: "\(path).calculator", message: "Scientific-calculator capability requires a calculator profile."))
            }
        }

        let completionRequirementIDs = activityIDs.union(assessmentIDs).union(blockIDs)
        for group in completionGroups {
            let path = "completionGroups.\(group.id)"
            if group.requirementIDs.isEmpty {
                issues.append(.init(path: "\(path).requirementIDs", message: "Completion groups cannot be empty."))
            }
            if Set(group.requirementIDs).count != group.requirementIDs.count {
                issues.append(.init(path: "\(path).requirementIDs", message: "Completion requirements cannot be duplicated."))
            }
            for requirementID in group.requirementIDs where !completionRequirementIDs.contains(requirementID) {
                issues.append(.init(path: "\(path).requirementIDs", message: "Completion requirement \(requirementID) does not resolve to a lesson block, activity, or assessment."))
            }
            if let minimumScore = group.minimumScore, !(0...1).contains(minimumScore) {
                issues.append(.init(path: "\(path).minimumScore", message: "Completion-group minimum score must be between zero and one."))
            }
        }

        let itemIDs = Set(scienceItems.map(\.id))
        for assessment in package.assessments where !(assessment.scienceAssessmentItemIDs ?? []).isEmpty {
            let path = "assessments.\(assessment.id)"
            let referencedItems = assessment.scienceAssessmentItemIDs ?? []
            if !Set(referencedItems).isSubset(of: itemIDs) {
                issues.append(.init(path: "\(path).scienceAssessmentItemIDs", message: "Science assessment item references must resolve."))
            }
            if let policy = assessment.sciencePassPolicy {
                if policy.scorableItemCount < 1
                    || policy.minimumCorrectCount < 1
                    || policy.minimumCorrectCount > policy.scorableItemCount
                    || policy.scorableItemCount > referencedItems.count
                    || policy.requiredConstructedResponseCount < 0 {
                    issues.append(.init(path: "\(path).sciencePassPolicy", message: "Science assessment pass policy is inconsistent with its items."))
                }
            } else {
                issues.append(.init(path: "\(path).sciencePassPolicy", message: "Science assessments require a pass policy."))
            }
        }
        return issues
    }

    private static func validate(
        _ configuration: StudyInteractiveActivityConfiguration,
        path: String,
        datasetIDs: Set<String>,
        issues: inout [StudyPackageValidationIssue]
    ) {
        switch configuration {
        case .acknowledgement(let configuration):
            if configuration.statementMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(path: "\(path).configuration", message: "Acknowledgement statement cannot be blank."))
            }
        case .numericQuantity(let configuration):
            if configuration.parts.isEmpty || Set(configuration.parts.map(\.id)).count != configuration.parts.count {
                issues.append(.init(path: "\(path).configuration.parts", message: "Numeric activities require uniquely identified parts."))
            }
            for part in configuration.parts {
                validate(part.answer, path: "\(path).configuration.parts.\(part.id).answer", issues: &issues)
            }
        case .mathExpression(let configuration):
            if configuration.expectedMathJSON.isEmpty {
                issues.append(.init(path: "\(path).configuration.expectedMathJSON", message: "Math-expression activities require an expected semantic expression."))
            }
        case .graphTable(let configuration):
            let columnIDs = Set(configuration.columns.map(\.id))
            if columnIDs.isEmpty || columnIDs.count != configuration.columns.count {
                issues.append(.init(path: "\(path).configuration.columns", message: "Graph/table activities require uniquely identified columns."))
            }
            for series in configuration.series where !columnIDs.contains(series.xColumnID) || !columnIDs.contains(series.yColumnID) {
                issues.append(.init(path: "\(path).configuration.series.\(series.id)", message: "Graph series columns must resolve."))
            }
            if Set(configuration.numericPrompts.map(\.id)).count != configuration.numericPrompts.count {
                issues.append(.init(path: "\(path).configuration.numericPrompts", message: "Graph/table numeric prompts require unique identifiers."))
            }
            for prompt in configuration.numericPrompts {
                validate(prompt.answer, path: "\(path).configuration.numericPrompts.\(prompt.id).answer", issues: &issues)
            }
        case .freeBodyDiagram(let configuration):
            if configuration.scenarios.isEmpty || Set(configuration.scenarios.map(\.id)).count != configuration.scenarios.count {
                issues.append(.init(path: "\(path).configuration.scenarios", message: "Free-body activities require uniquely identified scenarios."))
            }
        case .motionTrackingLab(let configuration):
            if !datasetIDs.contains(configuration.fallbackDatasetID) {
                issues.append(.init(path: "\(path).configuration.fallbackDatasetID", message: "Motion-tracking fallback dataset does not resolve."))
            }
            if configuration.minimumSampleCount < 2
                || configuration.maximumSampleCount < configuration.minimumSampleCount
                || configuration.maximumVideoDurationSeconds < 1 {
                issues.append(.init(path: "\(path).configuration", message: "Motion-tracking sample and duration limits are invalid."))
            }
        case .numericalKinematics(let configuration):
            if !datasetIDs.contains(configuration.accelerationDatasetID) {
                issues.append(.init(path: "\(path).configuration.accelerationDatasetID", message: "Numerical-kinematics dataset does not resolve."))
            }
            if configuration.defaultTimeStep <= 0 {
                issues.append(.init(path: "\(path).configuration.defaultTimeStep", message: "Numerical time step must be positive."))
            }
        case .pythonNotebook(let configuration):
            if configuration.maximumSourceBytes < 1 || configuration.maximumOutputBytes < 1 || configuration.timeoutSeconds < 1 {
                issues.append(.init(path: "\(path).configuration", message: "Python resource limits must be positive."))
            }
            if configuration.templateSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(path: "\(path).configuration.templateSource", message: "Python template source cannot be blank."))
            }
        case .constructedResponse(let configuration):
            if configuration.prompts.isEmpty || configuration.minimumResponseCharacters < 1 {
                issues.append(.init(path: "\(path).configuration", message: "Constructed-response prompts and a positive minimum length are required."))
            }
        case .workedExample(let configuration):
            if configuration.minimumAttemptCharacters < 1 {
                issues.append(.init(path: "\(path).configuration.minimumAttemptCharacters", message: "Worked examples require a positive attempt length."))
            }
        case .errorDiagnosis(let configuration):
            if configuration.requiredResponsePrompts.isEmpty {
                issues.append(.init(path: "\(path).configuration.requiredResponsePrompts", message: "Error diagnosis requires response prompts."))
            }
        }
    }

    private static func validate(
        _ answer: StudyNumericAnswerSpecification,
        path: String,
        issues: inout [StudyPackageValidationIssue]
    ) {
        if (answer.absoluteTolerance ?? 0) < 0 || (answer.relativeTolerance ?? 0) < 0 {
            issues.append(.init(path: path, message: "Numeric tolerances cannot be negative."))
        }
        if answer.requiresUnit,
           answer.canonicalUnitID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            issues.append(.init(path: path, message: "Unit-required numeric answers need a canonical unit identifier."))
        }
    }
}
