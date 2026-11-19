#if os(iOS)
import SwiftUI
import UIKit

/// Sizes the actual editable control, not only its surrounding SwiftUI layout.
struct StudioURLField: UIViewRepresentable {
    @Binding var text: String
    @Environment(\.isEnabled) private var enabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.borderStyle = .roundedRect
        field.placeholder = "https://…"
        field.accessibilityLabel = "Video link"
        field.accessibilityIdentifier = "local-video-url"
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.keyboardType = .URL
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.returnKeyType = .done
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        context.coordinator.field = field
        let toolbar = UIToolbar()
        toolbar.items = [UIBarButtonItem(systemItem: .flexibleSpace),
                         UIBarButtonItem(title: "Done", style: .done, target: context.coordinator, action: #selector(Coordinator.done))]
        toolbar.sizeToFit()
        field.inputAccessoryView = toolbar
        return field
    }
    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        field.isEnabled = enabled
        field.font = .preferredFont(forTextStyle: .body)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: max(48, (uiView.font?.lineHeight ?? 20) + 20))
    }
    @MainActor final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: StudioURLField
        weak var field: UITextField?
        init(_ parent: StudioURLField) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        @objc func done() { field?.resignFirstResponder() }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder(); return true }
    }
}

/// Native explicit paste keeps iOS paste authorization semantics and a real48pt target.
struct StudioPasteButton: UIViewRepresentable {
    @Environment(\.isEnabled) private var enabled
    let onPaste: ([String]) -> Void
    func makeUIView(context: Context) -> PasteHost { PasteHost() }
    func updateUIView(_ host: PasteHost, context: Context) {
        host.onPaste = onPaste
        host.allowsPaste = enabled
        host.control.appAllowsPaste = enabled
        host.control.isUserInteractionEnabled = enabled
        host.control.alpha = enabled ? 1 : 0.5
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PasteHost, context: Context) -> CGSize? {
        let natural = uiView.control.intrinsicContentSize
        return CGSize(width: min(proposal.width ?? .greatestFiniteMagnitude, max(110, natural.width)),
                      height: max(48, natural.height))
    }
    static func dismantleUIView(_ host: PasteHost, coordinator: ()) {
        host.cancelPendingPaste()
        host.onPaste = { _ in }
        host.control.target = nil
    }
    @MainActor final class PasteControl: UIPasteControl {
        var appAllowsPaste = true
        override var accessibilityTraits: UIAccessibilityTraits {
            get {
                var traits = super.accessibilityTraits
                if !appAllowsPaste { traits.insert(.notEnabled) }
                return traits
            }
            set { super.accessibilityTraits = newValue }
        }
    }
    @MainActor final class PasteHost: UIView {
        let control: PasteControl
        var onPaste: ([String]) -> Void = { _ in }
        private var generation = UUID()
        var allowsPaste = true {
            didSet { if oldValue != allowsPaste { cancelPendingPaste() } }
        }
        func cancelPendingPaste() { generation = UUID() }
        override init(frame: CGRect) {
            let configuration = UIPasteControl.Configuration()
            configuration.displayMode = .iconAndLabel
            configuration.cornerStyle = .medium
            configuration.baseBackgroundColor = UIColor(StudioPalette.action)
            configuration.baseForegroundColor = .white
            control = PasteControl(configuration: configuration)
            super.init(frame: frame)
            pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
            control.target = self
            control.accessibilityIdentifier = "local-video-paste"
            control.accessibilityLabel = "Paste video URL from Clipboard"
            control.translatesAutoresizingMaskIntoConstraints = false
            addSubview(control)
            NSLayoutConstraint.activate([
                control.leadingAnchor.constraint(equalTo: leadingAnchor),
                control.trailingAnchor.constraint(equalTo: trailingAnchor),
                control.topAnchor.constraint(equalTo: topAnchor),
                control.bottomAnchor.constraint(equalTo: bottomAnchor),
                control.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
            ])
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func paste(itemProviders: [NSItemProvider]) {
            guard allowsPaste else { return }
            cancelPendingPaste()
            guard itemProviders.count == 1, let provider = itemProviders.first,
                  provider.canLoadObject(ofClass: NSString.self) else { onPaste([]); return }
            let request = generation
            _ = provider.loadObject(ofClass: NSString.self) { [weak self] value, _ in
                let text = value as? String
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.allowsPaste, self.generation == request else { return }
                    self.onPaste(text.map { [$0] } ?? [])
                }
            }
        }
    }
}
#endif
