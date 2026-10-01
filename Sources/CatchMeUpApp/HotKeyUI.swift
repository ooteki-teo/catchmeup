import SwiftUI
import AppKit
import Carbon.HIToolbox
import CatchMeUpCore

/// Captures a key combination from the user.
struct HotKeyRecorder: NSViewRepresentable {
    @Binding var recording: Bool
    var onCapture: (UInt32, UInt32) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator {
        var parent: HotKeyRecorder
        init(_ parent: HotKeyRecorder) { self.parent = parent }
    }

    func makeNSView(context: Context) -> HotKeyRecorderNSView {
        let view = HotKeyRecorderNSView()
        view.onCapture = { keyCode, modifiers in
            DispatchQueue.main.async {
                context.coordinator.parent.recording = false
                context.coordinator.parent.onCapture(keyCode, modifiers)
            }
        }
        view.onCancel = {
            DispatchQueue.main.async {
                context.coordinator.parent.recording = false
                context.coordinator.parent.onCancel()
            }
        }
        return view
    }

    func updateNSView(_ nsView: HotKeyRecorderNSView, context: Context) {
        context.coordinator.parent = self
        if recording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

final class HotKeyRecorderNSView: NSView {
    var onCapture: ((UInt32, UInt32) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { onCancel?(); return }
        handle(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        if event.keyCode == UInt16(kVK_Escape) { onCancel?(); return true }
        handle(event)
        return true
    }

    private func handle(_ event: NSEvent) {
        let modifiers = carbonModifiers(from: event.modifierFlags)
        // Require a modifier, except for bare function keys (F1–F12).
        guard modifiers != 0 || GlobalHotKey.isFunctionKey(UInt32(event.keyCode)) else {
            NSSound.beep()
            return
        }
        guard event.keyCode != UInt16(kVK_Escape) else { onCancel?(); return }
        onCapture?(UInt32(event.keyCode), modifiers)
    }
}

/// A settings row that shows the current shortcut and lets the user re-record it.
struct HotKeyField: View {
    let display: String
    @Binding var recording: Bool
    var onCapture: (UInt32, UInt32) -> Void
    var onReset: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                HotKeyRecorder(recording: $recording, onCapture: onCapture, onCancel: {})
                Text(recording ? L.t("请按下组合键（Esc 取消）") : display)
                    .font(.body.monospaced())
                    .foregroundStyle(recording ? Color.accentColor : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .allowsHitTesting(false)
            }
            .frame(minWidth: 170, minHeight: 28)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(recording ? Color.accentColor : Color.primary.opacity(0.15),
                            lineWidth: recording ? 2 : 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { recording = true }

            if recording {
                Button(L.t("取消")) { recording = false }
            } else {
                Button(L.t("修改")) { recording = true }
                Button(L.t("默认"), action: onReset)
            }
        }
    }
}
