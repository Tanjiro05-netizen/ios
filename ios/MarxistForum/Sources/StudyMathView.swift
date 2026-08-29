import SwiftUI
import WebKit

struct StudyScientificDocumentUI: Equatable, Sendable {
    var title: String?
    var blocks: [Block]

    enum Block: Equatable, Sendable, Identifiable {
        case heading(id: String, level: Int, text: String)
        case paragraph(id: String, html: String)
        case equation(id: String, latex: String, spokenText: String, number: String?)
        case callout(id: String, title: String, html: String)
        case table(id: String, caption: String?, headers: [String], rows: [[String]])
        case bundledImage(id: String, resourceName: String, altText: String, caption: String?)

        var id: String {
            switch self {
            case .heading(let id, _, _),
                 .paragraph(let id, _),
                 .equation(let id, _, _, _),
                 .callout(let id, _, _),
                 .table(let id, _, _, _),
                 .bundledImage(let id, _, _, _): id
            }
        }
    }

    init(title: String? = nil, blocks: [Block]) {
        self.title = title
        self.blocks = blocks
    }
}

struct StudyMathRuntimeAvailability: Equatable, Sendable {
    let hasMathJax: Bool
    let hasMathLive: Bool
    let hasComputeEngine: Bool

    static func bundled(in bundle: Bundle = .main) -> Self {
        Self(
            hasMathJax: StudyScienceRuntimeResources.url(
                named: "tex-mml-chtml",
                extension: "js",
                subdirectory: "ScienceRuntime/mathjax",
                bundle: bundle
            ) != nil,
            hasMathLive: StudyScienceRuntimeResources.url(
                named: "mathlive.min",
                extension: "js",
                subdirectory: "ScienceRuntime/mathlive",
                bundle: bundle
            ) != nil,
            hasComputeEngine: StudyScienceRuntimeResources.url(
                named: "compute-engine.min",
                extension: "js",
                subdirectory: "ScienceRuntime/compute-engine",
                bundle: bundle
            ) != nil
        )
    }
}

enum StudyScienceRuntimeResources {
    static func url(
        named name: String,
        extension pathExtension: String,
        subdirectory: String,
        bundle: Bundle = .main
    ) -> URL? {
        if let nested = bundle.url(
            forResource: name,
            withExtension: pathExtension,
            subdirectory: subdirectory
        ) {
            return nested
        }

        // Xcode groups can flatten resources. Supporting the prefixed fallback
        // keeps the view functional while project generation is being changed.
        let flattened = "\(subdirectory.replacingOccurrences(of: "/", with: "-"))-\(name)"
        return bundle.url(forResource: flattened, withExtension: pathExtension)
            ?? bundle.url(forResource: name, withExtension: pathExtension)
    }
}

struct StudyScientificDocumentView: View {
    let document: StudyScientificDocumentUI
    var bundle: Bundle = .main

    @State private var contentHeight: CGFloat = 180

    var body: some View {
        StudyScientificDocumentWebView(
            document: document,
            bundle: bundle,
            contentHeight: $contentHeight
        )
        .frame(height: min(max(contentHeight, 80), 20_000))
        .accessibilityElement(children: .contain)
    }
}

private struct StudyScientificDocumentWebView: UIViewRepresentable {
    let document: StudyScientificDocumentUI
    let bundle: Bundle
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(context.coordinator, name: "scienceDocumentHeight")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let availability = StudyMathRuntimeAvailability.bundled(in: bundle)
        let rendered = StudyScientificHTMLRenderer.render(
            document: document,
            availability: availability,
            bundle: bundle
        )
        guard context.coordinator.loadedSignature != rendered.signature else { return }
        context.coordinator.loadedSignature = rendered.signature
        if let baseURL = rendered.baseURL {
            webView.loadHTMLString(rendered.html, baseURL: baseURL)
        } else {
            webView.loadHTMLString(rendered.html, baseURL: nil)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "scienceDocumentHeight")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        var loadedSignature: Int?
        private var contentHeight: Binding<CGFloat>

        init(contentHeight: Binding<CGFloat>) {
            self.contentHeight = contentHeight
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "scienceDocumentHeight",
                  let number = message.body as? NSNumber else { return }
            let proposed = CGFloat(truncating: number)
            guard proposed.isFinite, (40...20_000).contains(proposed) else { return }
            contentHeight.wrappedValue = proposed
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .other,
                  let url = navigationAction.request.url,
                  url.isFileURL || url.scheme == "about" else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            nil
        }
    }
}

private enum StudyScientificHTMLRenderer {
    struct Rendered {
        let html: String
        let baseURL: URL?
        let signature: Int
    }

    static func render(
        document: StudyScientificDocumentUI,
        availability: StudyMathRuntimeAvailability,
        bundle: Bundle
    ) -> Rendered {
        let mathJaxURL = StudyScienceRuntimeResources.url(
            named: "tex-mml-chtml",
            extension: "js",
            subdirectory: "ScienceRuntime/mathjax",
            bundle: bundle
        )
        let baseURL = mathJaxURL?.deletingLastPathComponent()
        let script = mathJaxURL.map { "<script defer src=\"\(escapeAttribute($0.lastPathComponent))\"></script>" } ?? ""
        let title = document.title.map { "<h1>\(escape($0))</h1>" } ?? ""
        let runtimeNotice = availability.hasMathJax ? "" : """
            <div class="runtime-note" role="note">
              Mathematical source notation is shown because the optional offline renderer is not bundled in this build.
            </div>
            """
        let blocks = document.blocks.map { render(block: $0, bundle: bundle) }.joined(separator: "\n")
        let signatureSource = String(describing: document) + String(describing: availability)

        let html = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'; script-src 'self' 'unsafe-inline'; font-src 'self' data:; connect-src 'none'; media-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
          <style>
            :root { color-scheme: light dark; font: -apple-system-body; }
            * { box-sizing: border-box; }
            body { margin: 0; color: CanvasText; background: transparent; font-family: -apple-system, BlinkMacSystemFont, sans-serif; font-size: 17px; line-height: 1.62; overflow: hidden; }
            h1, h2, h3, h4 { font-family: ui-serif, Georgia, serif; line-height: 1.22; margin: 1.15em 0 .45em; }
            h1 { font-size: 1.75rem; margin-top: 0; } h2 { font-size: 1.42rem; } h3 { font-size: 1.2rem; }
            p { margin: .65em 0; }
            .equation { display: flex; align-items: center; gap: 12px; padding: 14px; margin: 14px 0; overflow-x: auto; border: 1px solid color-mix(in srgb, CanvasText 16%, transparent); border-radius: 12px; font-family: ui-serif, Georgia, serif; }
            .equation .tex { flex: 1; text-align: center; font-size: 1.08rem; white-space: nowrap; }
            .equation .number { color: GrayText; font-variant-numeric: tabular-nums; }
            .callout { padding: 14px; margin: 14px 0; border-left: 4px solid #b51f2a; background: color-mix(in srgb, #b51f2a 8%, transparent); border-radius: 10px; }
            .callout strong { display: block; margin-bottom: 5px; }
            .runtime-note { padding: 10px 12px; margin: 10px 0; border-radius: 9px; background: color-mix(in srgb, CanvasText 7%, transparent); color: GrayText; font-size: .82rem; }
            .table-wrap { overflow-x: auto; margin: 14px 0; }
            table { width: 100%; border-collapse: collapse; font-variant-numeric: tabular-nums; }
            caption { text-align: left; font-weight: 600; padding: 0 0 8px; }
            th, td { border: 1px solid color-mix(in srgb, CanvasText 18%, transparent); padding: 9px; text-align: left; }
            th { background: color-mix(in srgb, CanvasText 7%, transparent); }
            figure { margin: 16px 0; } figure img { width: 100%; height: auto; border-radius: 10px; } figcaption { color: GrayText; font-size: .85rem; margin-top: 7px; }
            a { color: inherit; text-decoration: underline; }
          </style>
          <script>
            window.MathJax = { tex: { inlineMath: [['\\\\(', '\\\\)'], ['$', '$']], displayMath: [['\\\\[', '\\\\]']] }, options: { enableMenu: true } };
          </script>
          \(script)
        </head>
        <body>
          \(title)
          \(runtimeNotice)
          \(blocks)
          <script>
            (function () {
              let last = 0;
              function report() {
                const value = Math.ceil(document.documentElement.scrollHeight);
                if (value !== last && value >= 40 && value <= 20000) {
                  last = value;
                  window.webkit.messageHandlers.scienceDocumentHeight.postMessage(value);
                }
              }
              new ResizeObserver(report).observe(document.body);
              window.addEventListener('load', report);
              setTimeout(report, 100);
              setTimeout(report, 500);
            })();
          </script>
        </body>
        </html>
        """
        return Rendered(html: html, baseURL: baseURL, signature: signatureSource.hashValue)
    }

    private static func render(block: StudyScientificDocumentUI.Block, bundle: Bundle) -> String {
        switch block {
        case .heading(_, let level, let text):
            let safeLevel = min(max(level, 2), 4)
            return "<h\(safeLevel)>\(escape(text))</h\(safeLevel)>"
        case .paragraph(_, let html):
            return "<p>\(sanitizedInlineHTML(html))</p>"
        case .equation(_, let latex, let spokenText, let number):
            let numberHTML = number.map { "<span class=\"number\">(\(escape($0)))</span>" } ?? ""
            return "<div class=\"equation\" role=\"math\" aria-label=\"\(escapeAttribute(spokenText))\"><span class=\"tex\">\\[\(escape(latex))\\]</span>\(numberHTML)</div>"
        case .callout(_, let title, let html):
            return "<aside class=\"callout\"><strong>\(escape(title))</strong>\(sanitizedInlineHTML(html))</aside>"
        case .table(_, let caption, let headers, let rows):
            let captionHTML = caption.map { "<caption>\(escape($0))</caption>" } ?? ""
            let headingHTML = headers.map { "<th scope=\"col\">\(escape($0))</th>" }.joined()
            let rowsHTML = rows.map { row in
                "<tr>" + row.map { "<td>\(escape($0))</td>" }.joined() + "</tr>"
            }.joined()
            return "<div class=\"table-wrap\"><table>\(captionHTML)<thead><tr>\(headingHTML)</tr></thead><tbody>\(rowsHTML)</tbody></table></div>"
        case .bundledImage(_, let resourceName, let altText, let caption):
            let resource = resourceName as NSString
            guard let url = bundle.url(
                forResource: resource.deletingPathExtension,
                withExtension: resource.pathExtension.isEmpty ? nil : resource.pathExtension
            ) else {
                return "<div class=\"runtime-note\" role=\"img\" aria-label=\"\(escapeAttribute(altText))\">Figure unavailable: \(escape(altText))</div>"
            }
            let captionHTML = caption.map { "<figcaption>\(escape($0))</figcaption>" } ?? ""
            return "<figure><img src=\"\(escapeAttribute(url.absoluteString))\" alt=\"\(escapeAttribute(altText))\">\(captionHTML)</figure>"
        }
    }

    /// Course JSON is content, not executable markup. Retain only the few tags
    /// needed for emphasis and line breaks, and strip all attributes.
    private static func sanitizedInlineHTML(_ source: String) -> String {
        var value = escape(source)
        let replacements = [
            ("&lt;strong&gt;", "<strong>"), ("&lt;/strong&gt;", "</strong>"),
            ("&lt;em&gt;", "<em>"), ("&lt;/em&gt;", "</em>"),
            ("&lt;code&gt;", "<code>"), ("&lt;/code&gt;", "</code>"),
            ("&lt;br&gt;", "<br>"), ("&lt;br/&gt;", "<br>")
        ]
        for (encoded, allowed) in replacements {
            value = value.replacingOccurrences(of: encoded, with: allowed, options: .caseInsensitive)
        }
        return value
    }

    fileprivate static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    fileprivate static func escapeAttribute(_ value: String) -> String { escape(value) }
}

struct StudyMathExpressionField: View {
    let title: String
    let prompt: String
    @Binding var latex: String
    var bundle: Bundle = .main

    private var availability: StudyMathRuntimeAvailability {
        .bundled(in: bundle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            if availability.hasMathLive {
                StudyMathLiveWebField(latex: $latex, prompt: prompt, bundle: bundle)
                    .frame(minHeight: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Brand.separator, lineWidth: 1)
                    }
            } else {
                TextField(prompt, text: $latex, axis: .vertical)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Brand.controlFill, in: RoundedRectangle(cornerRadius: 12))
                Text("Math keyboard unavailable in this build. Enter standard notation such as v_0 + at.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !latex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                StudyScientificDocumentView(document: .init(blocks: [
                    .equation(id: "preview", latex: latex, spokenText: latex, number: nil)
                ]), bundle: bundle)
                .frame(maxHeight: 120)
                .accessibilityLabel("Expression preview: \(latex)")
            }
        }
    }
}

private struct StudyMathLiveWebField: UIViewRepresentable {
    @Binding var latex: String
    let prompt: String
    let bundle: Bundle

    func makeCoordinator() -> Coordinator { Coordinator(latex: $latex) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(context.coordinator, name: "studyMathInput")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let scriptURL = StudyScienceRuntimeResources.url(
            named: "mathlive.min",
            extension: "js",
            subdirectory: "ScienceRuntime/mathlive",
            bundle: bundle
        ) else { return }

        if !context.coordinator.hasLoaded {
            context.coordinator.hasLoaded = true
            let cssURL = StudyScienceRuntimeResources.url(
                named: "mathlive-fonts",
                extension: "css",
                subdirectory: "ScienceRuntime/mathlive",
                bundle: bundle
            )
            let html = Self.html(
                scriptName: scriptURL.lastPathComponent,
                cssName: cssURL?.lastPathComponent,
                initialLatex: latex,
                prompt: prompt
            )
            webView.loadHTMLString(html, baseURL: scriptURL.deletingLastPathComponent())
        } else if context.coordinator.lastWebLatex != latex {
            context.coordinator.lastWebLatex = latex
            let encoded = Self.javascriptString(latex)
            webView.evaluateJavaScript("window.studySetLatex(\(encoded));")
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "studyMathInput")
        webView.navigationDelegate = nil
    }

    private static func html(scriptName: String, cssName: String?, initialLatex: String, prompt: String) -> String {
        let stylesheet = cssName.map {
            "<link rel=\"stylesheet\" href=\"\(StudyScientificHTMLRenderer.escapeAttribute($0))\">"
        } ?? ""
        return """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'self' 'unsafe-inline'; font-src 'self' data:; connect-src 'none'; img-src data:; worker-src 'none'; object-src 'none'">
        \(stylesheet)
        <script defer src="\(StudyScientificHTMLRenderer.escapeAttribute(scriptName))"></script>
        <style>:root{color-scheme:light dark}body{margin:0;background:transparent}math-field{width:100%;min-height:64px;padding:12px;border:0;background:transparent;color:CanvasText;font-size:22px}</style>
        </head><body>
        <math-field id="field" aria-label="\(StudyScientificHTMLRenderer.escapeAttribute(prompt))">\(StudyScientificHTMLRenderer.escape(initialLatex))</math-field>
        <script>
          const field = document.getElementById('field');
          let suppress = false;
          field.addEventListener('input', () => {
            if (suppress) return;
            const value = String(field.value || '').slice(0, 4096);
            window.webkit.messageHandlers.studyMathInput.postMessage(value);
          });
          window.studySetLatex = function(value) {
            suppress = true; field.value = String(value || '').slice(0, 4096); suppress = false;
          };
        </script>
        </body></html>
        """
    }

    private static func javascriptString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
        return encoded
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var hasLoaded = false
        var lastWebLatex = ""
        private var latex: Binding<String>

        init(latex: Binding<String>) { self.latex = latex }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "studyMathInput",
                  let value = message.body as? String,
                  value.utf8.count <= 4_096 else { return }
            lastWebLatex = value
            latex.wrappedValue = value
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .other,
                  let url = navigationAction.request.url,
                  url.isFileURL || url.scheme == "about" else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

#Preview("Scientific document") {
    ScrollView {
        StudyScientificDocumentView(document: .init(
            title: "Motion and force",
            blocks: [
                .paragraph(id: "p1", html: "A model connects <strong>observations</strong> with physical laws."),
                .equation(id: "e1", latex: "\\vec{F}_{net}=m\\vec{a}", spokenText: "net force equals mass times acceleration", number: "1.1"),
                .table(id: "t1", caption: "Sample measurements", headers: ["t (s)", "x (m)"], rows: [["0", "0"], ["1", "2.4"]])
            ]
        ))
        .padding()
    }
    .background(ScreenBackground())
}
