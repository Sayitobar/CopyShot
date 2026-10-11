import AppKit
import Combine
import SwiftUI

/// Uses native macOS controls in a separate window, preserving CopyShot's bespoke settings layout.
struct MFRModelDownloadContent: View {
    let state: MFRModelState
    let download: () -> Void
    let cancel: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: state == .installed ? "checkmark.circle.fill" : "square.and.arrow.down")
                    .font(.system(size: 36))
                    .foregroundStyle(state == .installed ? Color.green : Color.accentColor)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text("Pix2Text MFR 1.5 · 120 MB")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text("The model recognizes formulas on your Mac. Only model files are downloaded from Hugging Face; your captures stay on your Mac.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                switch state {
                case .downloading(let received, let total):
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: Double(received), total: Double(total))
                            .progressViewStyle(.linear)
                            .accessibilityLabel("Model download progress")
                        HStack {
                            Text("\(Self.megabytes(received)) of \(Self.megabytes(total))")
                            Spacer()
                            Text("\(Int(Double(received) / Double(max(1, total)) * 100))%")
                        }
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                case .verifying:
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Verifying model files…").font(.subheadline)
                    }
                case .failed(let message):
                    Text(message).font(.subheadline).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                case .installed:
                    Text("Ready for LaTeX captures. Future recognition works offline.")
                        .font(.subheadline).foregroundStyle(.secondary)
                case .notInstalled:
                    Text("A one-time download is required before the first LaTeX capture.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack {
                Link("Model information", destination: URL(string: "https://huggingface.co/breezedeus/pix2text-mfr-1.5")!)
                    .font(.caption)
                Spacer()
                if state == .installed {
                    Button("Done", action: done).keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                    if !state.isBusy {
                        Button(downloadTitle, action: download)
                            .keyboardShortcut(.defaultAction)
                            .accessibilityIdentifier("mfr-download-start")
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var title: String {
        switch state {
        case .downloading: "Downloading LaTeX Model"
        case .verifying: "Preparing LaTeX Model"
        case .installed: "LaTeX Model Installed"
        case .failed: "Download Failed"
        case .notInstalled: "Download LaTeX Model"
        }
    }

    private var downloadTitle: String {
        if case .failed = state { return "Retry" }
        return "Download"
    }

    private static func megabytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal)
    }
}

@MainActor
final class MFRModelDownloadWindow: NSObject, NSWindowDelegate {
    static let shared = MFRModelDownloadWindow()
    private let manager: MFRModelManager
    private var window: NSWindow?
    private var appearanceObserver: AnyCancellable?
    private var waiters: [UUID: (Bool) -> Void] = [:]

    init(manager: MFRModelManager? = nil) { self.manager = manager ?? .shared }

    func show() {
        manager.refreshAvailability()
        if window == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "LaTeX Model"
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
            let content = MFRModelDownloadLiveContent(manager: manager,
                download: { [weak self] in self?.start() },
                close: { [weak self] in self?.close() },
                resize: { [weak self] size in self?.resize(size) })
            let host = NSHostingView(rootView: content)
            window.contentView = host
            window.setContentSize(host.fittingSize)
            appearanceObserver = SettingsManager.shared.$appearance.sink { [weak window] appearance in
                switch appearance {
                case .system: window?.appearance = nil
                case .light: window?.appearance = NSAppearance(named: .aqua)
                case .dark: window?.appearance = NSAppearance(named: .darkAqua)
                }
            }
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Every LaTeX route enters here after its screen selection, sharing any ongoing download.
    func requireModel(cancellation: RecognitionCancellation, completion: @escaping (Bool) -> Void) {
        guard !cancellation.isCancelled else { return }
        guard !manager.isAvailable else { completion(true); return }
        let id = UUID()
        waiters[id] = completion
        cancellation.onCancel { [weak self] in
            Task { @MainActor in self?.waiters.removeValue(forKey: id) }
        }
        show()
    }

    private func resize(_ size: CGSize) {
        guard let window else { return }
        guard window.contentView?.frame.size != size else { return }
        let top = window.frame.maxY
        window.setContentSize(size)
        if window.isVisible { window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height)) }
    }

    private func start() {
        Task { [weak self] in
            guard let self else { return }
            let succeeded = await manager.startDownload().value
            if succeeded, !waiters.isEmpty {
                finishWaiters(true)
                window?.close()
            }
        }
    }

    private func close() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        if manager.state.isBusy { manager.cancelDownload() }
        finishWaiters(false)
        appearanceObserver = nil
        window?.contentView = nil
        window = nil
    }

    private func finishWaiters(_ ready: Bool) {
        let callbacks = Array(waiters.values)
        waiters.removeAll()
        callbacks.forEach { $0(ready) }
    }
}

private struct MFRModelDownloadSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct MFRModelDownloadLiveContent: View {
    @ObservedObject var manager: MFRModelManager
    @ObservedObject private var settings = SettingsManager.shared
    let download: () -> Void
    let close: () -> Void
    let resize: (CGSize) -> Void

    var body: some View {
        MFRModelDownloadContent(state: manager.state, download: download, cancel: close, done: close)
            .preferredColorScheme(settings.appearance.colorScheme)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: MFRModelDownloadSizeKey.self, value: geometry.size)
            })
            .onPreferenceChange(MFRModelDownloadSizeKey.self, perform: resize)
    }
}

struct MFRModelSettingsRow: View {
    @ObservedObject private var manager = MFRModelManager.shared

    var body: some View {
        SettingsRow(label: "MFR Model", tooltip: "Downloads Pix2Text MFR 1.5 once (120 MB). Formula recognition runs locally and works offline after installation.", zIndexValue: 8) {
            HStack(spacing: 10) {
                Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(manager.isAvailable ? "Show in Finder" : manager.state.isBusy ? "View Download…" : "Download…") {
                    if manager.isAvailable {
                        NSWorkspace.shared.activateFileViewerSelecting([manager.directory])
                    } else { MFRModelDownloadWindow.shared.show() }
                }
                .accessibilityIdentifier("settings-mfr-model")
            }
            .frame(width: 200)
        }
        .onAppear { manager.refreshAvailability() }
    }

    private var status: String {
        switch manager.state {
        case .installed: "Installed"
        case .downloading: "Downloading"
        case .verifying: "Verifying"
        case .failed: "Not installed"
        case .notInstalled: "120 MB"
        }
    }
}
