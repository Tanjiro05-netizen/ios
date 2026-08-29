import Observation
import SwiftUI
import WebKit

struct StudyPythonRunResult: Equatable, Sendable {
    let runID: UUID
    let stdout: String
    let stderr: String
    let resultDescription: String?
    let plotPNG: Data?
    let durationSeconds: Double
    let validationPassed: Bool?
    let validationMessage: String?
    let visibleTestResults: [String: Bool]
}

enum StudyPyodideRuntimeState: Equatable, Sendable {
    case unavailable(String)
    case loading
    case ready
    case running(UUID)
    case completed(StudyPythonRunResult)
    case failed(String)

    var isReadyToRun: Bool {
        switch self {
        case .ready, .completed, .failed: true
        default: false
        }
    }

    var isRunning: Bool {
        if case .running = self { true } else { false }
    }
}

struct StudyPythonNotebookUIConfiguration: Equatable, Sendable {
    var title: String
    var instructions: String
    var starterCode: String
    var validationCode: String?
    var timeoutSeconds: Double

    init(
        title: String,
        instructions: String,
        starterCode: String,
        validationCode: String? = nil,
        timeoutSeconds: Double = 5
    ) {
        self.title = title
        self.instructions = instructions
        self.starterCode = starterCode
        self.validationCode = validationCode
        self.timeoutSeconds = min(max(timeoutSeconds, 1), 5)
    }
}

@MainActor
@Observable
final class StudyPyodideRuntime: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private(set) var state: StudyPyodideRuntimeState

    private weak var webView: WKWebView?
    private var timeoutTask: Task<Void, Never>?
    private var configuredWebViewIdentifier: ObjectIdentifier?
    private var pendingValidationCode: String?
    private var activeRunStartedAt: ContinuousClock.Instant?
    private let bundle: Bundle

    static let maximumSourceBytes = 64 * 1_024
    static let maximumTextOutputBytes = 64 * 1_024
    static let maximumPlotBytes = 2 * 1_024 * 1_024

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        if Self.pyodideRoot(in: bundle) == nil {
            state = .unavailable(
                "The offline Python runtime is not included in this build. The guided numerical lab remains available."
            )
        } else {
            state = .loading
        }
        super.init()
    }

    func configure(_ webView: WKWebView) {
        let identifier = ObjectIdentifier(webView)
        guard configuredWebViewIdentifier != identifier else { return }
        configuredWebViewIdentifier = identifier
        self.webView = webView

        guard let root = Self.pyodideRoot(in: bundle) else {
            state = .unavailable(
                "The offline Python runtime is not included in this build. The guided numerical lab remains available."
            )
            return
        }
        state = .loading
        webView.loadHTMLString(Self.harnessHTML, baseURL: root)
    }

    func detach(_ webView: WKWebView) {
        guard self.webView === webView else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "studyPython")
        webView.navigationDelegate = nil
        self.webView = nil
        configuredWebViewIdentifier = nil
    }

    func run(
        source: String,
        validationCode: String? = nil,
        timeoutSeconds: Double = 5
    ) {
        guard state.isReadyToRun, let webView else { return }
        guard source.utf8.count <= Self.maximumSourceBytes else {
            state = .failed("Python source is limited to 64 KiB.")
            return
        }
        let runID = UUID()
        pendingValidationCode = validationCode
        activeRunStartedAt = .now
        state = .running(runID)

        let payload: [String: Any] = [
            "runID": runID.uuidString.lowercased(),
            "source": source,
            "validation": validationCode ?? ""
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            state = .failed("The notebook could not prepare this run.")
            return
        }
        webView.evaluateJavaScript("window.studyPython.run(\(json));") { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                guard let self, case .running(let activeID) = self.state, activeID == runID else { return }
                self.timeoutTask?.cancel()
                self.state = .failed("The Python runner could not start: \(error.localizedDescription)")
            }
        }

        let boundedTimeout = min(max(timeoutSeconds, 1), 5)
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(boundedTimeout))
            } catch {
                return
            }
            guard let self, case .running(let activeID) = self.state, activeID == runID else { return }
            self.stop(reason: "The run reached the five-second practice limit.")
        }
    }

    func stop(reason: String = "Run stopped.") {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.evaluateJavaScript("window.studyPython.stop();")
        state = .failed(reason)
    }

    func reset() {
        timeoutTask?.cancel()
        timeoutTask = nil
        pendingValidationCode = nil
        activeRunStartedAt = nil
        guard let webView else { return }
        state = .loading
        webView.evaluateJavaScript("window.studyPython.reset();")
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "studyPython",
              let payload = message.body as? [String: Any],
              let type = payload["type"] as? String else { return }

        switch type {
        case "ready":
            timeoutTask?.cancel()
            state = .ready
        case "initializationError":
            state = .unavailable(Self.boundedText(payload["message"] as? String ?? "The offline Python runtime could not start."))
        case "result":
            receiveResult(payload)
        case "runtimeError":
            timeoutTask?.cancel()
            state = .failed(Self.boundedText(payload["message"] as? String ?? "Python stopped unexpectedly."))
        default:
            break
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        timeoutTask?.cancel()
        timeoutTask = nil
        state = .failed("Python stopped because its isolated runtime was reclaimed. Your source code is still saved; reset to try again.")
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .other,
              let url = navigationAction.request.url,
              url.isFileURL || url.scheme == "about" || url.scheme == "blob" else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    private func receiveResult(_ payload: [String: Any]) {
        guard case .running(let activeID) = state,
              let runIDText = payload["runID"] as? String,
              UUID(uuidString: runIDText) == activeID else { return }

        timeoutTask?.cancel()
        timeoutTask = nil
        let elapsed = activeRunStartedAt.map { $0.duration(to: .now).components }
        let seconds = elapsed.map { Double($0.seconds) + Double($0.attoseconds) / 1e18 } ?? 0
        activeRunStartedAt = nil

        var plotData: Data?
        if let base64 = payload["plotBase64"] as? String,
           base64.utf8.count <= Self.maximumPlotBytes * 2,
           let data = Data(base64Encoded: base64),
           data.count <= Self.maximumPlotBytes {
            plotData = data
        }

        let visibleTestResults = (payload["validationTests"] as? [String: Any])?.reduce(into: [String: Bool]()) { partial, entry in
            if let value = entry.value as? Bool { partial[entry.key] = value }
            else if let value = entry.value as? NSNumber { partial[entry.key] = value.boolValue }
        } ?? [:]
        let result = StudyPythonRunResult(
            runID: activeID,
            stdout: Self.boundedText(payload["stdout"] as? String ?? ""),
            stderr: Self.boundedText(payload["stderr"] as? String ?? ""),
            resultDescription: (payload["result"] as? String).map(Self.boundedText),
            plotPNG: plotData,
            durationSeconds: seconds,
            validationPassed: payload["validationPassed"] as? Bool,
            validationMessage: (payload["validationMessage"] as? String).map(Self.boundedText),
            visibleTestResults: visibleTestResults
        )
        state = .completed(result)
    }

    private static func boundedText(_ value: String) -> String {
        guard value.utf8.count > maximumTextOutputBytes else { return value }
        var result = value
        while result.utf8.count > maximumTextOutputBytes { result.removeLast() }
        return result + "\n…output truncated…"
    }

    private static func pyodideRoot(in bundle: Bundle) -> URL? {
        let candidates = [
            bundle.url(forResource: "pyodide", withExtension: "js", subdirectory: "ScienceRuntime/pyodide"),
            bundle.url(forResource: "pyodide", withExtension: "js")
        ]
        return candidates.compactMap { $0 }.first?.deletingLastPathComponent()
    }

    private static let harnessHTML = """
    <!doctype html><html><head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' blob: 'self'; worker-src blob:; connect-src 'self'; img-src data: blob:; style-src 'unsafe-inline'; object-src 'none'; frame-src 'none'; media-src 'none'; base-uri 'none'; form-action 'none'">
    </head><body>
    <script>
    (function () {
      let worker = null;
      let workerURL = null;
      let ready = false;

      const indexURL = new URL('./', document.baseURI).href;
      const workerSource = `
        const indexURL = ${JSON.stringify(indexURL)};
        let pyodide = null;
        let output = '';
        let errors = '';
        const LIMIT = 65536;
        const emit = (value, isError) => {
          const text = String(value == null ? '' : value);
          if (isError) errors = (errors + text + '\\n').slice(0, LIMIT);
          else output = (output + text + '\\n').slice(0, LIMIT);
        };
        async function initialize() {
          try {
            importScripts(indexURL + 'pyodide.js');
            pyodide = await loadPyodide({ indexURL });
            await pyodide.loadPackage(['numpy', 'matplotlib']);
            pyodide.setStdout({ batched: value => emit(value, false) });
            pyodide.setStderr({ batched: value => emit(value, true) });
            postMessage({ type: 'ready' });
          } catch (error) {
            postMessage({ type: 'initializationError', message: String(error) });
          }
        }
        onmessage = async event => {
          if (!pyodide || !event.data || event.data.type !== 'run') return;
          const request = event.data;
          output = ''; errors = '';
          let result = null;
          let validationPassed = null;
          let validationMessage = null;
          let validationTests = {};
          let plotBase64 = null;
          try {
            pyodide.FS.writeFile('/tmp/study_source.py', request.source, { encoding: 'utf8' });
            result = await pyodide.runPythonAsync(request.source);
            if (request.validation) {
              try {
                const validationResult = await pyodide.runPythonAsync(request.validation);
                if (validationResult && typeof validationResult.toJs === 'function') {
                  const converted = validationResult.toJs({ dict_converter: Object.fromEntries });
                  validationPassed = Boolean(converted.passed);
                  validationMessage = String(converted.message || '');
                  validationTests = converted.tests || {};
                  validationResult.destroy();
                } else {
                  validationPassed = Boolean(validationResult);
                }
              } catch (validationError) {
                validationPassed = false;
                validationMessage = String(validationError);
              }
            }
            const plot = await pyodide.runPythonAsync(`
    import base64, io
    try:
        import matplotlib.pyplot as plt
        if plt.get_fignums():
            _study_buffer = io.BytesIO()
            plt.gcf().savefig(_study_buffer, format='png', dpi=120, bbox_inches='tight')
            base64.b64encode(_study_buffer.getvalue()).decode('ascii')
        else:
            None
    except Exception:
        None
    `);
            if (typeof plot === 'string' && plot.length <= 2796204) plotBase64 = plot;
            postMessage({
              type: 'result', runID: request.runID, stdout: output, stderr: errors,
              result: result == null ? null : String(result), plotBase64,
              validationPassed, validationMessage, validationTests
            });
          } catch (error) {
            postMessage({
              type: 'result', runID: request.runID, stdout: output, stderr: (errors + String(error)).slice(0, LIMIT),
              result: null, plotBase64: null, validationPassed: false,
              validationMessage: 'The program did not finish.', validationTests
            });
          } finally {
            if (result && typeof result.destroy === 'function') result.destroy();
            try { pyodide.runPython('import matplotlib.pyplot as plt; plt.close(\\"all\\")') } catch (_) {}
          }
        };
        initialize();
      `;

      function post(payload) {
        window.webkit.messageHandlers.studyPython.postMessage(payload);
      }
      function createWorker() {
        if (worker) worker.terminate();
        if (workerURL) URL.revokeObjectURL(workerURL);
        workerURL = URL.createObjectURL(new Blob([workerSource], { type: 'text/javascript' }));
        worker = new Worker(workerURL);
        ready = false;
        worker.onmessage = event => {
          if (event.data && event.data.type === 'ready') ready = true;
          post(event.data || { type: 'runtimeError', message: 'Invalid Python response.' });
        };
        worker.onerror = event => post({ type: 'runtimeError', message: String(event.message || 'Python worker error.') });
      }
      window.studyPython = {
        run(request) {
          if (!ready || !worker) { post({ type: 'runtimeError', message: 'Python is still loading.' }); return; }
          worker.postMessage({ type: 'run', runID: request.runID, source: String(request.source || '').slice(0, 65536), validation: String(request.validation || '').slice(0, 65536) });
        },
        stop() { createWorker(); },
        reset() { createWorker(); }
      };
      createWorker();
    })();
    </script></body></html>
    """
}

struct StudyPyodideHostView: UIViewRepresentable {
    let runtime: StudyPyodideRuntime

    func makeCoordinator() -> StudyPyodideRuntime { runtime }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(runtime, name: "studyPython")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = runtime
        webView.isInspectable = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        runtime.configure(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        runtime.configure(webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: StudyPyodideRuntime) {
        coordinator.detach(webView)
    }
}

struct StudyPythonNotebookView: View {
    let configuration: StudyPythonNotebookUIConfiguration
    var initialSource: String?
    var onSourceChange: ((String) -> Void)?
    var onSuccessfulRun: ((StudyPythonRunResult) -> Void)?

    @State private var runtime = StudyPyodideRuntime()
    @State private var source: String
    @State private var didReportRunID: UUID?

    init(
        configuration: StudyPythonNotebookUIConfiguration,
        initialSource: String? = nil,
        onSourceChange: ((String) -> Void)? = nil,
        onSuccessfulRun: ((StudyPythonRunResult) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.initialSource = initialSource
        self.onSourceChange = onSourceChange
        self.onSuccessfulRun = onSuccessfulRun
        _source = State(initialValue: initialSource ?? configuration.starterCode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(configuration.title)
                    .font(.title3.weight(.semibold))
                Text(configuration.instructions)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                runtimeStatus
                Spacer()
                Text("\(source.utf8.count / 1_024) / 64 KiB")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $source)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 260)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Brand.controlFill, in: RoundedRectangle(cornerRadius: 13))
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(Brand.separator, lineWidth: 1)
                }
                .accessibilityLabel("Editable Python source")

            HStack {
                if runtime.state.isRunning {
                    Button(role: .destructive) { runtime.stop() } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        runtime.run(
                            source: source,
                            validationCode: configuration.validationCode,
                            timeoutSeconds: configuration.timeoutSeconds
                        )
                    } label: {
                        Label("Run", systemImage: "play.fill")
                    }
                    .studyPrimaryActionStyle()
                    .disabled(!runtime.state.isReadyToRun || source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Button {
                    source = configuration.starterCode
                    runtime.reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .studySecondaryActionStyle()
                Spacer()
            }

            outputView

            // A live web view is required for WebKit's worker process. It is
            // intentionally noninteractive and receives no app credentials.
            StudyPyodideHostView(runtime: runtime)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .onChange(of: source) { _, newValue in
            if newValue.utf8.count > StudyPyodideRuntime.maximumSourceBytes {
                source = String(newValue.prefix(StudyPyodideRuntime.maximumSourceBytes))
            }
            onSourceChange?(source)
        }
        .onChange(of: runtime.state) { _, newState in
            guard case .completed(let result) = newState,
                  result.validationPassed != false,
                  didReportRunID != result.runID else { return }
            didReportRunID = result.runID
            onSuccessfulRun?(result)
        }
    }

    @ViewBuilder
    private var runtimeStatus: some View {
        switch runtime.state {
        case .unavailable:
            Label("Runtime unavailable", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        case .loading:
            Label("Loading offline Python…", systemImage: "shippingbox")
                .foregroundStyle(.secondary)
        case .ready:
            Label("Ready offline", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .running:
            Label("Running in isolation…", systemImage: "gearshape.2")
                .foregroundStyle(Brand.redSoft)
        case .completed:
            Label("Run complete", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Label("Run stopped", systemImage: "exclamationmark.triangle")
                .foregroundStyle(Brand.redSoft)
        }
    }

    @ViewBuilder
    private var outputView: some View {
        switch runtime.state {
        case .unavailable(let message), .failed(let message):
            Label(message, systemImage: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .studyPaperSurface(cornerRadius: 13)
        case .completed(let result):
            VStack(alignment: .leading, spacing: 10) {
                Text("Output")
                    .font(.headline)
                if !result.stdout.isEmpty {
                    Text(result.stdout)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                if !result.stderr.isEmpty {
                    Text(result.stderr)
                        .font(.caption.monospaced())
                        .foregroundStyle(Brand.redSoft)
                        .textSelection(.enabled)
                }
                if let value = result.resultDescription, !value.isEmpty, value != "None" {
                    Text("Result: \(value)")
                        .font(.caption.monospaced())
                }
                if let plot = result.plotPNG, let image = UIImage(data: plot) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("Plot produced by the Python notebook")
                }
                if let validationPassed = result.validationPassed {
                    Label(
                        result.validationMessage ?? (validationPassed ? "Visible checks passed." : "Review the visible checks and try again."),
                        systemImage: validationPassed ? "checkmark.seal" : "exclamationmark.triangle"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(validationPassed ? .green : Brand.redSoft)
                }
                Text("Completed in \(result.durationSeconds.formatted(.number.precision(.fractionLength(2)))) s")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .studyPaperSurface(cornerRadius: 14, emphasized: true)
        default:
            EmptyView()
        }
    }
}

#Preview("Python notebook — runtime fallback") {
    ScrollView {
        StudyPythonNotebookView(configuration: .init(
            title: "Numerical kinematics",
            instructions: "Use Euler updates, compare with the analytic result, then reduce the time step.",
            starterCode: """
            import numpy as np
            import matplotlib.pyplot as plt

            dt = 0.1
            t = np.arange(0, 5 + dt, dt)
            a = 2.0
            v = np.zeros_like(t)
            x = np.zeros_like(t)
            # Complete the updates.
            """
        ))
        .padding()
    }
    .background(ScreenBackground())
}
