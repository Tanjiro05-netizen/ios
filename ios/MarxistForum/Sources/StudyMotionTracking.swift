@preconcurrency import AVFoundation
import AVKit
import CoreTransferable
import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct StudyNormalizedPoint: Codable, Equatable, Hashable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }
}

struct StudyMotionFrameMarkUI: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var timeSeconds: Double
    var point: StudyNormalizedPoint

    init(id: UUID = UUID(), timeSeconds: Double, point: StudyNormalizedPoint) {
        self.id = id
        self.timeSeconds = timeSeconds
        self.point = point
    }
}

struct StudyMotionSampleUI: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var timeSeconds: Double
    var positionMeters: Double

    init(id: UUID = UUID(), timeSeconds: Double, positionMeters: Double) {
        self.id = id
        self.timeSeconds = timeSeconds
        self.positionMeters = positionMeters
    }
}

struct StudyMotionDerivedSampleUI: Equatable, Identifiable, Sendable {
    var id: String { timeSeconds.formatted(.number.precision(.fractionLength(9))) }
    let timeSeconds: Double
    let positionMeters: Double
    let velocityMetersPerSecond: Double?
    let accelerationMetersPerSecondSquared: Double?
}

enum StudyMotionDistanceUnit: String, CaseIterable, Identifiable, Codable, Sendable {
    case meters = "m"
    case centimeters = "cm"

    var id: String { rawValue }

    func meters(from value: Double) -> Double {
        switch self {
        case .meters: value
        case .centimeters: value / 100
        }
    }
}

struct StudyMotionTrackingDraftUI: Equatable, Sendable {
    var localVideoURL: URL?
    var storedVideoArtifactID: UUID?
    var storedVideoRelativePath: String?
    var calibrationPixelSpan: Double
    var calibrationPoints: [StudyNormalizedPoint]
    var calibrationDistanceText: String
    var calibrationUnit: StudyMotionDistanceUnit
    var frameMarks: [StudyMotionFrameMarkUI]
    var fallbackSamples: [StudyMotionSampleUI]
    var uncertainty: String
    var modelComparison: String
    var limitations: String

    init(
        localVideoURL: URL? = nil,
        storedVideoArtifactID: UUID? = nil,
        storedVideoRelativePath: String? = nil,
        calibrationPixelSpan: Double = 0,
        calibrationPoints: [StudyNormalizedPoint] = [],
        calibrationDistanceText: String = "",
        calibrationUnit: StudyMotionDistanceUnit = .meters,
        frameMarks: [StudyMotionFrameMarkUI] = [],
        fallbackSamples: [StudyMotionSampleUI] = [],
        uncertainty: String = "",
        modelComparison: String = "",
        limitations: String = ""
    ) {
        self.localVideoURL = localVideoURL
        self.storedVideoArtifactID = storedVideoArtifactID
        self.storedVideoRelativePath = storedVideoRelativePath
        self.calibrationPixelSpan = calibrationPixelSpan
        self.calibrationPoints = calibrationPoints
        self.calibrationDistanceText = calibrationDistanceText
        self.calibrationUnit = calibrationUnit
        self.frameMarks = frameMarks
        self.fallbackSamples = fallbackSamples
        self.uncertainty = uncertainty
        self.modelComparison = modelComparison
        self.limitations = limitations
    }
}

struct StudyMotionStoredVideoUI: Equatable, Sendable {
    let localURL: URL
    let artifactID: UUID?
    let relativePath: String?
}

/// Media storage is injected so the activity never writes an untracked shared
/// file. The production adapter records the returned artifact in SwiftData;
/// raw media is never included in `StudyInteractiveResponse`.
@MainActor
struct StudyMotionVideoStorageUI {
    let store: (URL) throws -> StudyMotionStoredVideoUI
    let remove: (StudyMotionStoredVideoUI) -> Void

    static func scienceArtifacts(
        subjectID: String,
        onStored: @escaping (_ artifactID: UUID, _ relativePath: String) throws -> Void,
        onRemoved: @escaping (_ artifactID: UUID?, _ relativePath: String?) -> Void
    ) -> Self {
        Self(
            store: { sourceURL in
                let artifactID = UUID()
                let relativePath = try StudyScienceArtifactStorage.store(
                    sourceURL: sourceURL,
                    subjectID: subjectID,
                    artifactID: artifactID
                )
                let localURL = try StudyScienceArtifactStorage.rootURL()
                    .appending(path: relativePath)
                do {
                    try onStored(artifactID, relativePath)
                } catch {
                    StudyScienceArtifactStorage.remove(relativePath: relativePath)
                    throw error
                }
                return .init(localURL: localURL, artifactID: artifactID, relativePath: relativePath)
            },
            remove: { stored in
                if let relativePath = stored.relativePath {
                    StudyScienceArtifactStorage.remove(relativePath: relativePath)
                }
                onRemoved(stored.artifactID, stored.relativePath)
            }
        )
    }

    /// Used only by previews and disposable harnesses. The file remains in the
    /// system temporary directory and is never presented as durable work.
    static let temporary = Self(
        store: { sourceURL in
            .init(localURL: sourceURL, artifactID: nil, relativePath: nil)
        },
        remove: { stored in
            guard stored.artifactID == nil,
                  stored.localURL.path.hasPrefix(FileManager.default.temporaryDirectory.path) else { return }
            try? FileManager.default.removeItem(at: stored.localURL)
        }
    )
}

struct StudyMotionTrackingUIConfiguration: Equatable, Sendable {
    var title: String
    var instructions: String
    var minimumSamples: Int
    var maximumSamples: Int
    var fallbackSamples: [StudyMotionSampleUI]

    init(
        title: String = "Video motion tracking",
        instructions: String,
        minimumSamples: Int = 20,
        maximumSamples: Int = 500,
        fallbackSamples: [StudyMotionSampleUI]
    ) {
        self.title = title
        self.instructions = instructions
        self.minimumSamples = min(max(minimumSamples, 3), 500)
        self.maximumSamples = min(max(maximumSamples, self.minimumSamples), 500)
        self.fallbackSamples = fallbackSamples
    }
}

enum StudyMotionAnalysis {
    static func samples(
        from marks: [StudyMotionFrameMarkUI],
        calibrationPoints: [StudyNormalizedPoint],
        knownDistanceMeters: Double
    ) -> [StudyMotionSampleUI] {
        guard calibrationPoints.count == 2,
              knownDistanceMeters > 0 else { return [] }
        let span = calibrationPoints[1].x - calibrationPoints[0].x
        guard abs(span) > 0.000_001 else { return [] }
        let metersPerNormalizedUnit = knownDistanceMeters / abs(span)
        let direction = span >= 0 ? 1.0 : -1.0
        return marks
            .sorted { $0.timeSeconds < $1.timeSeconds }
            .map {
                StudyMotionSampleUI(
                    id: $0.id,
                    timeSeconds: $0.timeSeconds,
                    positionMeters: ($0.point.x - calibrationPoints[0].x) * metersPerNormalizedUnit * direction
                )
            }
    }

    static func derive(_ samples: [StudyMotionSampleUI]) -> [StudyMotionDerivedSampleUI] {
        let sorted = samples.sorted { $0.timeSeconds < $1.timeSeconds }
        guard !sorted.isEmpty else { return [] }

        return sorted.indices.map { index in
            var velocity: Double?
            var acceleration: Double?
            if index > 0, index < sorted.count - 1 {
                let previous = sorted[index - 1]
                let current = sorted[index]
                let next = sorted[index + 1]
                let previousInterval = current.timeSeconds - previous.timeSeconds
                let nextInterval = next.timeSeconds - current.timeSeconds
                let fullInterval = next.timeSeconds - previous.timeSeconds
                if previousInterval > 0, nextInterval > 0, fullInterval > 0 {
                    velocity = (next.positionMeters - previous.positionMeters) / fullInterval
                    acceleration = 2 * (
                        (next.positionMeters - current.positionMeters) / nextInterval
                        - (current.positionMeters - previous.positionMeters) / previousInterval
                    ) / (previousInterval + nextInterval)
                }
            }
            return StudyMotionDerivedSampleUI(
                timeSeconds: sorted[index].timeSeconds,
                positionMeters: sorted[index].positionMeters,
                velocityMetersPerSecond: velocity,
                accelerationMetersPerSecondSquared: acceleration
            )
        }
    }
}

@MainActor
@Observable
final class StudyMotionPlayerModel {
    private(set) var player: AVPlayer?
    private(set) var durationSeconds = 0.0
    private(set) var framesPerSecond = 30.0
    var currentTimeSeconds = 0.0
    var errorMessage: String?

    private var timeObserver: Any?
    private var configuredURL: URL?

    func configure(url: URL?) async {
        guard configuredURL != url else { return }
        stopObserving()
        configuredURL = url
        durationSeconds = 0
        currentTimeSeconds = 0
        errorMessage = nil
        guard let url else {
            player = nil
            return
        }

        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let rate = try await tracks.first?.load(.nominalFrameRate) ?? 30
            durationSeconds = min(max(duration.seconds.isFinite ? duration.seconds : 0, 0), 30)
            framesPerSecond = rate > 0 ? Double(rate) : 30
            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)
            player.actionAtItemEnd = .pause
            self.player = player
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 1 / max(framesPerSecond, 1), preferredTimescale: 600),
                queue: .main
            ) { [weak self] time in
                Task { @MainActor in self?.currentTimeSeconds = time.seconds.isFinite ? time.seconds : 0 }
            }
        } catch {
            player = nil
            errorMessage = "The selected video could not be prepared: \(error.localizedDescription)"
        }
    }

    func seek(to seconds: Double) {
        let bounded = min(max(seconds, 0), durationSeconds)
        player?.pause()
        player?.seek(
            to: CMTime(seconds: bounded, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTimeSeconds = bounded
    }

    func step(frames: Int) {
        seek(to: currentTimeSeconds + Double(frames) / max(framesPerSecond, 1))
    }

    func stopObserving() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player?.pause()
    }
}

struct StudyMotionTrackingActivityView: View {
    let configuration: StudyMotionTrackingUIConfiguration
    @Binding var draft: StudyMotionTrackingDraftUI
    let videoStorage: StudyMotionVideoStorageUI
    var onComplete: (([StudyMotionDerivedSampleUI]) -> Void)?

    @State private var playerModel = StudyMotionPlayerModel()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var presentedSheet: SheetDestination?
    @State private var workflowStep: WorkflowStep = .source
    @State private var importError: String?

    private enum WorkflowStep: String, CaseIterable, Identifiable {
        case source = "Source"
        case calibrate = "Calibrate"
        case track = "Track"
        case analyze = "Analyze"
        var id: String { rawValue }
    }

    private enum SheetDestination: String, Identifiable {
        case camera
        var id: String { rawValue }
    }

    private var calibrationDistanceMeters: Double? {
        guard let value = Double(draft.calibrationDistanceText), value > 0 else { return nil }
        return draft.calibrationUnit.meters(from: value)
    }

    private var trackedSamples: [StudyMotionSampleUI] {
        guard let calibrationDistanceMeters else { return [] }
        return StudyMotionAnalysis.samples(
            from: draft.frameMarks,
            calibrationPoints: draft.calibrationPoints,
            knownDistanceMeters: calibrationDistanceMeters
        )
    }

    private var activeSamples: [StudyMotionSampleUI] {
        draft.fallbackSamples.isEmpty ? trackedSamples : draft.fallbackSamples
    }

    private var derivedSamples: [StudyMotionDerivedSampleUI] {
        StudyMotionAnalysis.derive(activeSamples)
    }

    private var reportIsComplete: Bool {
        [draft.uncertainty, draft.modelComparison, draft.limitations]
            .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(configuration.title)
                    .font(.title3.weight(.semibold))
                Text(configuration.instructions)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Picker("Experiment stage", selection: $workflowStep) {
                ForEach(WorkflowStep.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch workflowStep {
            case .source: sourceStep
            case .calibrate: calibrationStep
            case .track: trackingStep
            case .analyze: analysisStep
            }
        }
        .task(id: draft.localVideoURL) {
            await playerModel.configure(url: draft.localVideoURL)
        }
        .onDisappear { playerModel.stopObserving() }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task { await importMovie(from: item) }
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .camera:
                StudyMotionCameraSheet { url in
                    useVideo(url)
                }
            }
        }
        .alert("Video unavailable", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "Select another video or use the reference dataset.")
        }
    }

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                "Use a safe, one-dimensional motion no longer than 30 seconds. Keep people, traffic, heights, and breakable objects out of the setup.",
                systemImage: "checkmark.shield"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .studyPaperSurface(cornerRadius: 13)

            Button {
                presentedSheet = .camera
            } label: {
                Label("Record video", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .studyPrimaryActionStyle()

            PhotosPicker(selection: $selectedPhotoItem, matching: .videos) {
                Label("Import from Photos", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .studySecondaryActionStyle()

            Button {
                removeCurrentStoredVideo()
                draft.calibrationPoints = []
                draft.frameMarks = []
                draft.fallbackSamples = configuration.fallbackSamples
                workflowStep = .analyze
            } label: {
                Label("Use accessible reference dataset", systemImage: "tablecells")
                    .frame(maxWidth: .infinity)
            }
            .studySecondaryActionStyle()

            if draft.localVideoURL != nil {
                Label("Video stored only on this device", systemImage: "lock.iphone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Continue to calibration") { workflowStep = .calibrate }
                    .studyPrimaryActionStyle()
                Button(role: .destructive) {
                    removeCurrentStoredVideo()
                    draft.calibrationPoints = []
                    draft.frameMarks = []
                } label: {
                    Label("Delete stored video", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .studySecondaryActionStyle()
            }
        }
    }

    private var calibrationStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pause the video, then tap the two ends of a known horizontal distance. Tap again to restart calibration.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            videoSurface(mode: .calibration)

            HStack {
                TextField("Known distance", text: $draft.calibrationDistanceText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Known calibration distance")
                Picker("Unit", selection: $draft.calibrationUnit) {
                    ForEach(StudyMotionDistanceUnit.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 150)
            }

            Label(
                "\(draft.calibrationPoints.count) of 2 calibration points selected",
                systemImage: draft.calibrationPoints.count == 2 ? "checkmark.circle" : "scope"
            )
            .font(.caption.weight(.semibold))
            Button("Continue to tracking") { workflowStep = .track }
                .studyPrimaryActionStyle()
                .disabled(draft.calibrationPoints.count != 2 || calibrationDistanceMeters == nil)
        }
    }

    private var trackingStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mark the same object in at least \(configuration.minimumSamples) frames.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(draft.frameMarks.count) / \(configuration.minimumSamples)")
                    .font(.caption.monospacedDigit().weight(.bold))
            }
            videoSurface(mode: .tracking)

            Slider(
                value: Binding(
                    get: { playerModel.currentTimeSeconds },
                    set: { playerModel.seek(to: $0) }
                ),
                in: 0...max(playerModel.durationSeconds, 0.01)
            ) {
                Text("Video time")
            } minimumValueLabel: {
                Text("0").font(.caption2)
            } maximumValueLabel: {
                Text(playerModel.durationSeconds, format: .number.precision(.fractionLength(1)))
                    .font(.caption2.monospacedDigit())
            }
            HStack {
                Button { playerModel.step(frames: -1) } label: {
                    Label("Previous frame", systemImage: "backward.frame")
                }
                Button { playerModel.step(frames: 1) } label: {
                    Label("Next frame", systemImage: "forward.frame")
                }
                Spacer()
                Text("t = \(playerModel.currentTimeSeconds.formatted(.number.precision(.fractionLength(3)))) s")
                    .font(.caption.monospacedDigit())
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)

            if !draft.frameMarks.isEmpty {
                Button("Remove last mark", role: .destructive) { draft.frameMarks.removeLast() }
                    .font(.caption)
            }
            Button("Analyze measurements") { workflowStep = .analyze }
                .studyPrimaryActionStyle()
                .disabled(draft.frameMarks.count < configuration.minimumSamples)
        }
    }

    private var analysisStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            if activeSamples.count < 3 {
                ContentUnavailableView(
                    "Not enough measurements",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Track more frames or use the reference dataset.")
                )
            } else {
                StudyMotionAnalysisGraph(samples: derivedSamples)
                StudyMotionDataTable(samples: derivedSamples)

                Group {
                    reportField("Uncertainty and noise", text: $draft.uncertainty)
                    reportField("Comparison with the motion model", text: $draft.modelComparison)
                    reportField("Limitations and improvements", text: $draft.limitations)
                }

                Label(
                    "Central differences are used for interior velocity and acceleration values. Endpoint derivatives are intentionally omitted.",
                    systemImage: "function"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Button {
                    onComplete?(derivedSamples)
                } label: {
                    Label("Complete investigation", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .studyPrimaryActionStyle()
                .disabled(activeSamples.count < configuration.minimumSamples || !reportIsComplete)
            }
        }
    }

    private enum VideoTapMode { case calibration, tracking }

    private func videoSurface(mode: VideoTapMode) -> some View {
        ZStack {
            if let player = playerModel.player {
                VideoPlayer(player: player)
                    .disabled(true)
                GeometryReader { proxy in
                    ZStack {
                        Color.clear.contentShape(Rectangle())
                        ForEach(Array(draft.calibrationPoints.enumerated()), id: \.offset) { index, point in
                            calibrationMarker(index: index, point: point, size: proxy.size)
                        }
                        if mode == .tracking,
                           let current = nearestMark(to: playerModel.currentTimeSeconds) {
                            Circle()
                                .fill(.yellow)
                                .frame(width: 18, height: 18)
                                .overlay(Circle().stroke(.black, lineWidth: 2))
                                .position(x: current.point.x * proxy.size.width, y: current.point.y * proxy.size.height)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard proxy.size.width > 0, proxy.size.height > 0 else { return }
                        let point = StudyNormalizedPoint(
                            x: location.x / proxy.size.width,
                            y: location.y / proxy.size.height
                        )
                        handleVideoTap(point, mode: mode, displayWidth: proxy.size.width)
                    }
                }
            } else if let error = playerModel.errorMessage {
                ContentUnavailableView("Video unavailable", systemImage: "video.slash", description: Text(error))
            } else {
                ProgressView("Preparing video…")
            }
        }
        .frame(minHeight: 260)
        .background(.black, in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel(mode == .calibration ? "Video calibration surface" : "Video object tracking surface")
        .accessibilityHint("Double-tap where the object or calibration point appears")
    }

    private func calibrationMarker(index: Int, point: StudyNormalizedPoint, size: CGSize) -> some View {
        ZStack {
            Circle().fill(index == 0 ? .cyan : .orange)
            Text("\(index + 1)")
                .font(.caption2.bold())
                .foregroundStyle(.black)
        }
        .frame(width: 24, height: 24)
        .overlay(Circle().stroke(.white, lineWidth: 2))
        .position(x: point.x * size.width, y: point.y * size.height)
        .accessibilityHidden(true)
    }

    private func handleVideoTap(_ point: StudyNormalizedPoint, mode: VideoTapMode, displayWidth: CGFloat) {
        playerModel.player?.pause()
        switch mode {
        case .calibration:
            if draft.calibrationPoints.count >= 2 {
                draft.calibrationPoints = []
                draft.calibrationPixelSpan = 0
            }
            draft.calibrationPoints.append(point)
            if draft.calibrationPoints.count == 2 {
                draft.calibrationPixelSpan = abs(draft.calibrationPoints[1].x - draft.calibrationPoints[0].x) * displayWidth
            }
        case .tracking:
            guard draft.frameMarks.count < configuration.maximumSamples else { return }
            let currentTime = playerModel.currentTimeSeconds
            if let index = draft.frameMarks.firstIndex(where: {
                abs($0.timeSeconds - currentTime) < 0.5 / max(playerModel.framesPerSecond, 1)
            }) {
                draft.frameMarks[index].point = point
            } else {
                draft.frameMarks.append(.init(timeSeconds: currentTime, point: point))
                draft.frameMarks.sort { $0.timeSeconds < $1.timeSeconds }
            }
            playerModel.step(frames: 1)
        }
    }

    private func nearestMark(to time: Double) -> StudyMotionFrameMarkUI? {
        draft.frameMarks.min { abs($0.timeSeconds - time) < abs($1.timeSeconds - time) }
    }

    private func reportField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            TextField(title, text: text, axis: .vertical)
                .lineLimit(3...7)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func importMovie(from item: PhotosPickerItem) async {
        do {
            guard let movie = try await item.loadTransferable(type: StudyImportedMotionMovie.self) else {
                throw StudyMotionLocalFileError.importFailed
            }
            let asset = AVURLAsset(url: movie.url)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0, duration <= 30.05 else {
                throw StudyMotionLocalFileError.videoTooLong
            }
            useVideo(movie.url)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func useVideo(_ sourceURL: URL) {
        do {
            removeCurrentStoredVideo()
            let stored = try videoStorage.store(sourceURL)
            if stored.localURL != sourceURL,
               sourceURL.path.hasPrefix(FileManager.default.temporaryDirectory.path) {
                try? FileManager.default.removeItem(at: sourceURL)
            }
            draft.localVideoURL = stored.localURL
            draft.storedVideoArtifactID = stored.artifactID
            draft.storedVideoRelativePath = stored.relativePath
            draft.fallbackSamples = []
            draft.calibrationPoints = []
            draft.calibrationPixelSpan = 0
            draft.frameMarks = []
            workflowStep = .calibrate
        } catch {
            importError = error.localizedDescription
        }
    }

    private func removeCurrentStoredVideo() {
        guard let url = draft.localVideoURL else { return }
        videoStorage.remove(.init(
            localURL: url,
            artifactID: draft.storedVideoArtifactID,
            relativePath: draft.storedVideoRelativePath
        ))
        draft.localVideoURL = nil
        draft.storedVideoArtifactID = nil
        draft.storedVideoRelativePath = nil
    }
}

private struct StudyMotionAnalysisGraph: View {
    let samples: [StudyMotionDerivedSampleUI]

    private enum Series: String, CaseIterable, Identifiable {
        case position = "Position (m)"
        case velocity = "Velocity (m/s)"
        case acceleration = "Acceleration (m/s²)"
        var id: String { rawValue }
    }

    @State private var series: Series = .position

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Graph series", selection: $series) {
                ForEach(Series.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            StudyScienceLineGraph(
                points: samples.compactMap { sample in
                    let value: Double? = switch series {
                    case .position: sample.positionMeters
                    case .velocity: sample.velocityMetersPerSecond
                    case .acceleration: sample.accelerationMetersPerSecondSquared
                    }
                    return value.map { StudyScienceGraphPointUI(x: sample.timeSeconds, y: $0) }
                },
                xLabel: "Time (s)",
                yLabel: series.rawValue
            )
            .frame(height: 230)
        }
        .padding(14)
        .studyPaperSurface(cornerRadius: 14, emphasized: true)
    }
}

private struct StudyMotionDataTable: View {
    let samples: [StudyMotionDerivedSampleUI]

    var body: some View {
        DisclosureGroup("Accessible measurement table") {
            ScrollView(.horizontal) {
                Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 7) {
                    GridRow {
                        Text("t (s)"); Text("x (m)"); Text("v (m/s)"); Text("a (m/s²)")
                    }
                    .font(.caption.weight(.bold))
                    Divider().gridCellColumns(4)
                    ForEach(samples) { sample in
                        GridRow {
                            Text(number(sample.timeSeconds))
                            Text(number(sample.positionMeters))
                            Text(sample.velocityMetersPerSecond.map(number) ?? "—")
                            Text(sample.accelerationMetersPerSecondSquared.map(number) ?? "—")
                        }
                        .font(.caption.monospacedDigit())
                    }
                }
            }
            .accessibilityLabel("Time, position, velocity, and acceleration measurements")
        }
        .padding(14)
        .studyPaperSurface(cornerRadius: 14)
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(1...5)))
    }
}

struct StudyImportedMotionMovie: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let destination = FileManager.default.temporaryDirectory
                .appending(path: "study-motion-import-\(UUID().uuidString.lowercased()).mov")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return StudyImportedMotionMovie(url: destination)
        }
    }
}

enum StudyMotionLocalFileError: LocalizedError {
    case importFailed
    case videoTooLong

    var errorDescription: String? {
        switch self {
        case .importFailed: "The video could not be imported."
        case .videoTooLong: "Choose a video no longer than 30 seconds."
        }
    }
}

@MainActor
@Observable
final class StudyMotionCameraController: NSObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private(set) var isConfigured = false
    private(set) var isRecording = false
    private(set) var authorizationDenied = false
    private(set) var errorMessage: String?
    var onCaptured: ((URL) -> Void)?

    func prepare() async {
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: authorized = true
        case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
        default: authorized = false
        }
        guard authorized else {
            authorizationDenied = true
            return
        }
        guard !isConfigured else {
            startSession()
            return
        }

        do {
            session.beginConfiguration()
            session.sessionPreset = .high
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                throw StudyMotionLocalFileError.importFailed
            }
            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input), session.canAddOutput(movieOutput) else {
                throw StudyMotionLocalFileError.importFailed
            }
            session.addInput(input)
            // Deliberately no audio input: this activity never requests or records microphone data.
            session.addOutput(movieOutput)
            movieOutput.maxRecordedDuration = CMTime(seconds: 30, preferredTimescale: 600)
            session.commitConfiguration()
            isConfigured = true
            startSession()
        } catch {
            session.commitConfiguration()
            errorMessage = "Camera setup failed: \(error.localizedDescription)"
        }
    }

    func startRecording() {
        guard isConfigured, !movieOutput.isRecording else { return }
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "study-motion-capture-\(UUID().uuidString.lowercased()).mov")
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        isRecording = true
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
    }

    func stopSession() {
        if movieOutput.isRecording { movieOutput.stopRecording() }
        let session = session
        Task.detached(priority: .utility) { session.stopRunning() }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isRecording = false
            if let error {
                self.errorMessage = "Recording failed: \(error.localizedDescription)"
            } else {
                self.onCaptured?(outputFileURL)
            }
        }
    }

    private func startSession() {
        guard !session.isRunning else { return }
        let session = session
        Task.detached(priority: .userInitiated) { session.startRunning() }
    }
}

private struct StudyMotionCameraSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var controller = StudyMotionCameraController()

    let onCaptured: (URL) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                if controller.authorizationDenied {
                    ContentUnavailableView(
                        "Camera access is off",
                        systemImage: "camera.fill",
                        description: Text("Use Import from Photos or the reference dataset. Camera access can be changed in Settings.")
                    )
                } else if let error = controller.errorMessage {
                    ContentUnavailableView("Camera unavailable", systemImage: "camera.fill", description: Text(error))
                } else {
                    StudyMotionCameraPreview(session: controller.session)
                        .ignoresSafeArea(edges: .bottom)
                    VStack {
                        Spacer()
                        Button {
                            controller.isRecording ? controller.stopRecording() : controller.startRecording()
                        } label: {
                            Circle()
                                .fill(controller.isRecording ? .red : .white)
                                .frame(width: 74, height: 74)
                                .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 5).padding(-7))
                        }
                        .accessibilityLabel(controller.isRecording ? "Stop recording" : "Start recording")
                        .padding(.bottom, 32)
                    }
                }
            }
            .background(.black)
            .navigationTitle("Record motion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        controller.stopSession()
                        dismiss()
                    }
                }
            }
        }
        .task {
            controller.onCaptured = { url in
                controller.stopSession()
                onCaptured(url)
                dismiss()
            }
            await controller.prepare()
        }
        .onDisappear { controller.stopSession() }
    }
}

private struct StudyMotionCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

#Preview("Motion tracking — fallback") {
    @Previewable @State var draft = StudyMotionTrackingDraftUI()
    ScrollView {
        StudyMotionTrackingActivityView(
            configuration: .init(
                instructions: "Measure one-dimensional motion, calculate derivatives, and evaluate uncertainty.",
                fallbackSamples: (0..<25).map {
                    let time = Double($0) * 0.1
                    return .init(timeSeconds: time, positionMeters: 0.5 * 1.5 * time * time)
                }
            ),
            draft: $draft,
            videoStorage: .temporary
        )
        .padding()
    }
    .background(ScreenBackground())
}
