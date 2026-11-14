import SwiftUI
import UIKit

/// Editable prompt with live keyword highlights (tint at 16 % fill + underline), backed by UITextView
/// so the highlights and the caret share one layout.
struct PromptEditor: UIViewRepresentable {
    @Binding var text: String
    var matches: [KeywordMatch]
    var fontSize: CGFloat = 24
    var autoFocus = false

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.delegate = context.coordinator
        view.font = .systemFont(ofSize: fontSize)
        view.textColor = UIColor(Theme.Colors.textPrimary)
        view.tintColor = UIColor(Theme.Colors.textPrimary)
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.autocorrectionType = .default
        view.keyboardType = .default
        view.returnKeyType = .done
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        view.typingAttributes = Self.baseAttributes(fontSize: fontSize)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let attributed = Self.attributed(text: text, matches: matches, fontSize: fontSize)
        if view.attributedText?.string != text || !context.coordinator.lastMatches.elementsEqual(matches, by: { $0.range == $1.range && $0.tint == $1.tint }) {
            let selection = view.selectedRange
            view.attributedText = attributed
            view.typingAttributes = Self.baseAttributes(fontSize: fontSize)
            if selection.location <= attributed.length { view.selectedRange = selection }
            context.coordinator.lastMatches = matches
        }
        if autoFocus, !context.coordinator.didFocus {
            context.coordinator.didFocus = true
            DispatchQueue.main.async { view.becomeFirstResponder() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 80
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(size.height, fontSize * 1.4))
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    static func baseAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        return [.font: UIFont.systemFont(ofSize: fontSize),
                .foregroundColor: UIColor(Theme.Colors.textPrimary),
                .paragraphStyle: paragraph,
                .backgroundColor: UIColor.clear,
                .underlineStyle: 0]
    }

    static func attributed(text: String, matches: [KeywordMatch], fontSize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: baseAttributes(fontSize: fontSize))
        for match in matches {
            let ns = NSRange(match.range, in: text)
            guard ns.location + ns.length <= result.length else { continue }
            result.addAttributes([
                .backgroundColor: UIColor(match.tint.base).withAlphaComponent(0.16),
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: UIColor(match.tint.base),
            ], range: ns)
        }
        return result
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        var lastMatches: [KeywordMatch] = []
        var didFocus = false
        init(text: Binding<String>) { _text = text }

        func textViewDidChange(_ textView: UITextView) {
            textView.typingAttributes = PromptEditor.baseAttributes(fontSize: textView.font?.pointSize ?? 24)
            if text != textView.text { text = textView.text }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            if replacement == "\n" { textView.resignFirstResponder(); return false }
            return true
        }
    }
}
