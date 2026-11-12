import Foundation
import MNGKit
import SwiftUI
import UIKit
import WebKit

/// The Aurum editor inside a web view.
///
/// Aurum is a browser engine: a WebGL canvas with a DOM overlay. The
/// editor page lives on the server, so the app and the web shell run the
/// very same editor, with the same AI.
///
/// The session of the app is a token and not a cookie of the origin, so
/// the photo, the faces of it and the capabilities of the deployment are
/// handed over in `window.__aurumConfig`. The edited pixels come back as a
/// blob and are uploaded through the same
/// `POST /items/{id}/edit` route the native export uses, so the server
/// needs no new endpoint.
struct AurumEditorView: View {
    let model: ShellModel
    let item: Item

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading

    enum Phase: Equatable {
        case loading
        case ready
        case saving
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                AurumWebView(
                    client: model.client,
                    server: model.server,
                    item: item,
                    onPhase: { phase = $0 },
                    onSave: { data, name in
                        Task { await save(data: data, name: name) }
                    },
                    onClose: { dismiss() }
                )
                .ignoresSafeArea()

                switch phase {
                case .loading, .saving:
                    ProgressView()
                        .tint(.white)
                case .failed(let message):
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(Font.mng(26))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(message)
                            .font(Font.mng(13))
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.8))
                case .ready:
                    EmptyView()
                }
            }
            .navigationTitle(Strings.editorAurumTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Strings.editorCancel) { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    /// Upload the pixels Aurum produced.
    private func save(data: Data, name: String) async {
        phase = .saving
        let format = AurumEditorView.exportFormat(for: data, item: item)
        // The container decides the extension: the name Aurum hands back is
        // the name of the source, which may be a HEIC the server cannot take.
        let base = (name as NSString).deletingPathExtension
        let filename = base.isEmpty
            ? "edit.\(format.fileExtension)"
            : "\(base).\(format.fileExtension)"
        let saved = await model.editor.saveExternal(
            item: item,
            data: format.data,
            filename: filename,
            mime: format.mime
        )
        if saved {
            dismiss()
        } else {
            phase = .failed(Strings.editorSaveFailed)
        }
    }

    /// The container the server expects.
    ///
    /// A HEIC photo is uploaded as JPEG and converted back on the server, so
    /// a PNG result has to be re-encoded before it goes up.
    static func exportFormat(
        for data: Data,
        item: Item
    ) -> (data: Data, mime: String, fileExtension: String) {
        let isPNG = data.starts(with: Data([0x89, 0x50, 0x4E, 0x47]))
        if isPNG, item.isHeif, let image = UIImage(data: data),
           let jpeg = image.jpegData(compressionQuality: 0.95) {
            return (jpeg, "image/jpeg", "jpg")
        }
        if isPNG {
            return (data, "image/png", "png")
        }
        return (data, "image/jpeg", "jpg")
    }
}

/// The web view that hosts the Aurum editor.
private struct AurumWebView: UIViewRepresentable {
    let client: MNGAPIClient
    let server: MNGServer
    let item: Item
    let onPhase: (AurumEditorView.Phase) -> Void
    let onSave: (Data, String) -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            client: client,
            server: server,
            item: item,
            onPhase: onPhase,
            onSave: onSave,
            onClose: onClose
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let content = WKUserContentController()
        content.add(context.coordinator, name: "aurum")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = content

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        // The editor page lives on the server, so the app and the web shell
        // run the same editor with the same AI. A server without the page
        // falls back to the editor inside the app.
        if let url = server.editorPageURL {
            webView.load(URLRequest(url: url))
        } else {
            context.coordinator.loadLocalEditor(in: webView)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onPhase = onPhase
        context.coordinator.onSave = onSave
        context.coordinator.onClose = onClose
    }

    /// The message handler is retained by the user content controller, so it
    /// has to be released with the web view.
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController
            .removeScriptMessageHandler(forName: "aurum")
    }

    /// WebKit calls its delegates on the main thread. The class stays
    /// unisolated so it can satisfy the delegate protocols in every Swift
    /// language mode, and every state change hops to the main actor.
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let client: MNGAPIClient
        private let server: MNGServer
        private let item: Item
        var onPhase: (AurumEditorView.Phase) -> Void
        var onSave: (Data, String) -> Void
        var onClose: () -> Void

        /// The source image has been handed over.
        private var didStart = false
        /// The page of the server is used; a server without it falls back to
        /// the editor inside the app.
        private var usesRemotePage = true

        init(
            client: MNGAPIClient,
            server: MNGServer,
            item: Item,
            onPhase: @escaping (AurumEditorView.Phase) -> Void,
            onSave: @escaping (Data, String) -> Void,
            onClose: @escaping () -> Void
        ) {
            self.client = client
            self.server = server
            self.item = item
            self.onPhase = onPhase
            self.onSave = onSave
            self.onClose = onClose
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor [weak self] in
                self?.start(webView: webView)
            }
        }

        /// The page of the server is missing: fall back to the editor inside
        /// the app, which has the engine but no AI.
        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.usesRemotePage = false
                self.loadLocalEditor(in: webView)
            }
        }

        /// Mount the editor inside the app.
        ///
        /// The engine is loaded as a plain script, so the web view stays free
        /// of the module and cross-origin rules.
        @MainActor
        func loadLocalEditor(in webView: WKWebView) {
            if let script = AurumBundle.script() {
                webView.configuration.userContentController.addUserScript(
                    WKUserScript(
                        source: script,
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: true
                    )
                )
            }
            webView.loadHTMLString(AurumBundle.localShell(), baseURL: nil)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            let body = message.body
            Task { @MainActor [weak self] in
                self?.handle(body)
            }
        }

        @MainActor
        private func handle(_ body: Any) {
            guard let body = body as? [String: Any],
                  let kind = body["type"] as? String
            else {
                return
            }
            switch kind {
            case "ready":
                onPhase(.ready)
            case "error":
                onPhase(.failed(body["message"] as? String ?? Strings.editorSaveFailed))
            case "save", "saveCopy":
                let payload = body["data"] as? String ?? ""
                // The payload is a data URL: strip the prefix before decoding.
                let base64 = payload.split(separator: ",").last.map { String($0) } ?? payload
                guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
                else {
                    return
                }
                onSave(data, body["name"] as? String ?? "")
            case "close":
                onClose()
            default:
                break
            }
        }

        /// Fetch the original and the capabilities, then hand them over.
        @MainActor
        private func start(webView: WKWebView) {
            guard !didStart else { return }
            didStart = true
            Task { @MainActor in
                guard let source = await AurumBundle.source(
                    for: item,
                    client: client
                ) else {
                    onPhase(.failed(Strings.editorUnsupported))
                    return
                }
                // The faces and the parts of the AI that the server has
                // installed decide what the editor offers.
                let capabilities = try? await client.editorConfig(id: item.id)
                let script = usesRemotePage
                    ? AurumBundle.startScript(
                        source: source,
                        name: item.name,
                        item: item,
                        capabilities: capabilities
                    )
                    : AurumBundle.localStartScript(source: source, name: item.name)
                webView.evaluateJavaScript(script) { _, error in
                    guard let error else { return }
                    Task { @MainActor in
                        self.onPhase(.failed("\(error)"))
                    }
                }
            }
        }
    }
}

/// The Aurum bundle and the small page that hosts it.
enum AurumBundle {
    /// The IIFE build of Aurum, injected before the page runs.
    ///
    /// It is the fallback for a server without the editor page: the engine
    /// works, but the AI of the deployment does not.
    static func script() -> String? {
        // The resource is `aurum.min.js`, so the name carries the `min` part.
        guard let url = Bundle.main.url(forResource: "aurum.min", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            return nil
        }
        return source
    }

    /// The page the editor is mounted in, when the server has no page.
    static func localShell() -> String {
        """
        <!DOCTYPE html>
        <html lang="vi">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>
          html, body { margin: 0; padding: 0; height: 100%; background: #08080a; }
          #aurumHost { position: absolute; inset: 0; }
        </style>
        </head>
        <body>
        <div id="aurumHost"></div>
        </body>
        </html>
        """
    }

    /// The call that creates the editor once the source is in place.
    static func localStartScript(source: String, name: String) -> String {
        let fileName = name.isEmpty ? "aurum" : name
        let safeName = fileName.replacingOccurrences(of: "'", with: "")
        return """
        (function () {
          if (!window.Aurum || !window.Aurum.createEditor) {
            window.webkit.messageHandlers.aurum.postMessage({
              type: 'error',
              message: 'Aurum không tải được.'
            });
            return;
          }
          var editor;
          try {
            editor = window.Aurum.createEditor({
              container: '#aurumHost',
              image: '\(source)',
              fileName: '\(safeName)',
              colorSpace: 'auto',
              locale: 'vi',
              title: 'Chỉnh sửa ảnh',
              startTab: 'adjust',
              exportTypes: ['image/jpeg', 'image/png'],
              onSave: function (blob, fileName) {
                var reader = new FileReader();
                reader.onloadend = function () {
                  window.webkit.messageHandlers.aurum.postMessage({
                    type: 'save',
                    data: reader.result,
                    name: fileName
                  });
                };
                reader.readAsDataURL(blob);
              },
              onSaveCopy: function (blob, fileName) {
                var reader = new FileReader();
                reader.onloadend = function () {
                  window.webkit.messageHandlers.aurum.postMessage({
                    type: 'saveCopy',
                    data: reader.result,
                    name: fileName
                  });
                };
                reader.readAsDataURL(blob);
              },
              onClose: function () {
                window.webkit.messageHandlers.aurum.postMessage({ type: 'close' });
              }
            });
          } catch (error) {
            window.webkit.messageHandlers.aurum.postMessage({
              type: 'error',
              message: String(error)
            });
            return;
          }
          editor.on('ready', function () {
            window.webkit.messageHandlers.aurum.postMessage({ type: 'ready' });
          });
        })();
        """
    }

    /// The configuration the page of the editor waits for.
    static func startScript(
        source: String,
        name: String,
        item: Item,
        capabilities: EditorConfig?
    ) -> String {
        let fileName = name.isEmpty ? "aurum" : name
        let safeName = fileName.replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "'", with: "")
        let itemJSON = """
        {"id": \(item.id), "type": "\(item.mediaType)", "mime": "\(item.mime)",
         "name": "\(safeName)", "edit": "", "media": "",
         "width": \(item.width), "height": \(item.height)}
        """
        let faces = capabilities?.faces ?? []
        let faceJSON = faces
            .map {
                "{\"x\": \($0.x), \"y\": \($0.y), \"w\": \($0.w), \"h\": \($0.h), " +
                    "\"confidence\": \($0.confidence)}"
            }
            .joined(separator: ",")
        let ai = capabilities?.ai == true
        return """
        (function () {
          window.__aurumConfig = {
            item: \(itemJSON),
            mediaUrl: '\(source)',
            uploadName: '\(safeName)',
            config: { faces: [\(faceJSON)], ai: \(ai ? "true" : "false") }
          };
          window.dispatchEvent(new Event('mng-editor-config'));
        })();
        """
    }

    /// Read the original file as a JPEG data URL.
    ///
    /// Browsers cannot decode HEIC, so the original is decoded with ImageIO
    /// and re-encoded as JPEG before it enters the web view.
    static func source(for item: Item, client: MNGAPIClient) async -> String? {
        do {
            let file = try await client.mediaFile(
                path: item.mediaPath(),
                suggestedName: item.name
            )
            defer {
                try? FileManager.default.removeItem(
                    at: file.url.deletingLastPathComponent()
                )
            }
            let data = try Data(contentsOf: file.url)
            guard let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.95)
            else {
                return nil
            }
            return "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        } catch {
            return nil
        }
    }
}
