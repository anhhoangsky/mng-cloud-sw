import Foundation
import MNGKit
import SwiftUI
import UIKit
import WebKit

/// The Aurum editor inside a web view.
///
/// Aurum is a browser engine: a WebGL canvas with a DOM overlay. The app
/// embeds it next to the native editor as the "advanced" mode. The edited
/// pixels come back as a blob and are uploaded through the same
/// `POST /items/{id}/edit` route the native export uses, so the server needs
/// no new endpoint.
///
/// The bundle is loaded as a plain script: the IIFE build of Aurum exposes
/// `window.Aurum`, which keeps the web view free of module and CORS rules.
/// The optional AI and face-landmark modules are not bundled, so the editor
/// runs without the 110 MB of ONNX models.
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
    let item: Item
    let onPhase: (AurumEditorView.Phase) -> Void
    let onSave: (Data, String) -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            client: client,
            item: item,
            onPhase: onPhase,
            onSave: onSave,
            onClose: onClose
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let content = WKUserContentController()
        content.add(context.coordinator, name: "aurum")
        if let script = AurumBundle.script() {
            content.addUserScript(
                WKUserScript(
                    source: script,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
        }

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = content

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(AurumBundle.shell(), baseURL: nil)
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
        private let item: Item
        var onPhase: (AurumEditorView.Phase) -> Void
        var onSave: (Data, String) -> Void
        var onClose: () -> Void

        /// The source image has been handed over.
        private var didStart = false

        init(
            client: MNGAPIClient,
            item: Item,
            onPhase: @escaping (AurumEditorView.Phase) -> Void,
            onSave: @escaping (Data, String) -> Void,
            onClose: @escaping () -> Void
        ) {
            self.client = client
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

        /// Fetch the original, hand it to the page and create the editor.
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
                let script = AurumBundle.startScript(source: source, name: item.name)
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
    static func script() -> String? {
        // The resource is `aurum.min.js`, so the name carries the `min` part.
        guard let url = Bundle.main.url(forResource: "aurum.min", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            return nil
        }
        return source
    }

    /// The page the editor is mounted in.
    static func shell() -> String {
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

    /// The call that creates the editor once the source is in place.
    static func startScript(source: String, name: String) -> String {
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
}
