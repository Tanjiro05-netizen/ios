import PDFKit
import SwiftData
import SwiftUI

struct StudyCourseSourceScreen: View {
    let courseID: String
    let resourceName: String
    let resourceFirstSourcePage: Int
    let firstPage: Int
    let lastPage: Int

    @Environment(AuthStore.self) private var auth
    @Environment(StudyCourseLibrary.self) private var library
    @Query private var entitlements: [StudyScienceEntitlementRecord]

    private var resourceURL: URL? {
        let url = URL(fileURLWithPath: resourceName)
        let extensionName = url.pathExtension
        let baseName = url.deletingPathExtension().lastPathComponent
        return Bundle.main.url(
            forResource: baseName,
            withExtension: extensionName.isEmpty ? nil : extensionName
        )
    }

    var body: some View {
        Group {
            if let course = library.course(id: courseID),
               !StudyScienceCourseUnlockPolicy.permitsAccess(
                course: course,
                subjectID: auth.userId,
                entitlements: entitlements
               ) {
                StudyScienceLockedContentView(
                    title: "Course access required",
                    message: "Return to the course home and check your account access before opening source pages."
                )
            } else if let resourceURL {
                StudyPDFSourceView(
                    url: resourceURL,
                    firstDocumentPageIndex: max(firstPage - resourceFirstSourcePage, 0),
                    lastDocumentPageIndex: max(lastPage - resourceFirstSourcePage, 0)
                )
            } else {
                ContentUnavailableView(
                    "Source pages unavailable",
                    systemImage: "doc.questionmark",
                    description: Text("The bundled course edition could not be opened.")
                )
            }
        }
        .navigationTitle(firstPage == lastPage ? "Source page \(firstPage)" : "Source pages \(firstPage)–\(lastPage)")
        .navigationBarTitleDisplayMode(.inline)
        .background(ScreenBackground())
    }
}

private struct StudyPDFSourceView: UIViewRepresentable {
    let url: URL
    let firstDocumentPageIndex: Int
    let lastDocumentPageIndex: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.pageShadowsEnabled = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
        guard context.coordinator.lastPageIndex != firstDocumentPageIndex,
              let page = view.document?.page(at: firstDocumentPageIndex) else { return }
        context.coordinator.lastPageIndex = firstDocumentPageIndex
        view.go(to: page)
        view.accessibilityLabel = firstDocumentPageIndex == lastDocumentPageIndex
            ? "Course source page"
            : "Course source pages"
        view.accessibilityValue = "Pages \(firstDocumentPageIndex + 1) through \(lastDocumentPageIndex + 1) in the bundled excerpt"
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastPageIndex: Int?
    }
}
