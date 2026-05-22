import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum KidCoinTheme {
    static let background = Color(red: 0.98, green: 0.95, blue: 0.86)
    static let foreground = Color(red: 0.26, green: 0.18, blue: 0.13)
    static let card = Color(red: 1.0, green: 0.98, blue: 0.91)
    static let muted = Color(red: 0.94, green: 0.90, blue: 0.80)
    static let mutedText = Color(red: 0.55, green: 0.46, blue: 0.36)
    static let border = Color(red: 0.89, green: 0.82, blue: 0.67)
    static let primary = Color(red: 0.88, green: 0.34, blue: 0.22)
    static let mint = Color(red: 0.44, green: 0.78, blue: 0.62)
    static let mintText = Color(red: 0.08, green: 0.34, blue: 0.26)
    static let sunshine = Color(red: 0.96, green: 0.76, blue: 0.24)
    static let destructive = Color(red: 0.78, green: 0.14, blue: 0.12)
}

enum KidCoinLayout {
    /// Floating tab bar + home-indicator clearance (matches `KidCoinTabBar` layout).
    static let tabBarReservedHeight: CGFloat = 92
    /// Extra breathing room below the last card inside a scroll view.
    static let scrollBottomPadding: CGFloat = 20
}

enum KidCoinMotion {
    static let quick = Animation.easeOut(duration: 0.18)
    static let gentle = Animation.spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.08)
    static let modal = Animation.spring(response: 0.36, dampingFraction: 0.84, blendDuration: 0.08)
    static let list = Animation.spring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.08)
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.74, blendDuration: 0.04)
    static let tab = Animation.spring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.08)
    static let scroll = Animation.easeInOut(duration: 0.28)
}

extension AnyTransition {
    static var kidCoinModal: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96)),
            removal: .opacity.combined(with: .scale(scale: 0.98))
        )
    }

    static var kidCoinRow: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.98))
        )
    }
}

private struct KidCoinTabBarClearanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var kidCoinTabBarClearance: CGFloat {
        get { self[KidCoinTabBarClearanceKey.self] }
        set { self[KidCoinTabBarClearanceKey.self] = newValue }
    }
}

private struct KidCoinScrollModifier: ViewModifier {
    @Environment(\.kidCoinTabBarClearance) private var tabBarClearance

    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(
                .bottom,
                tabBarClearance + KidCoinLayout.scrollBottomPadding,
                for: .scrollContent
            )
    }
}

struct KidCoinBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(KidCoinTheme.background.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .foregroundStyle(KidCoinTheme.foreground)
    }
}

enum KidCoinKeyboard {
    static func dismiss() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }
}

#if canImport(UIKit)
private final class KeyboardDismissTapCoordinator: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissTapCoordinator()

    private weak var installedWindow: UIWindow?
    private var tapRecognizer: UITapGestureRecognizer?

    func install(on window: UIWindow) {
        guard installedWindow !== window else { return }

        if let tapRecognizer, let installedWindow {
            installedWindow.removeGestureRecognizer(tapRecognizer)
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        tapRecognizer = tap
        installedWindow = window
    }

    @objc private func dismissKeyboard() {
        KidCoinKeyboard.dismiss()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !containsTextInput(touch.view)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    private func containsTextInput(_ view: UIView?) -> Bool {
        var current: UIView? = view
        while let node = current {
            if node is UITextField || node is UITextView || node is UISearchBar {
                return true
            }
            current = node.superview
        }
        return false
    }
}

private struct KeyboardDismissOnTapInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardDismissTapAnchorView {
        let view = KeyboardDismissTapAnchorView()
        view.onWindowChange = { window in
            guard let window else { return }
            KeyboardDismissTapCoordinator.shared.install(on: window)
        }
        return view
    }

    func updateUIView(_ uiView: KeyboardDismissTapAnchorView, context: Context) {}
}

private final class KeyboardDismissTapAnchorView: UIView {
    var onWindowChange: ((UIWindow?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window)
    }
}
#endif

enum TextFieldFilters {
    static func digitsOnly(_ source: Binding<String>, limit: Int? = nil) -> Binding<String> {
        Binding(
            get: { source.wrappedValue },
            set: { newValue in
                var filtered = newValue.filter(\.isNumber)
                if let limit {
                    filtered = String(filtered.prefix(limit))
                }
                source.wrappedValue = filtered
            }
        )
    }

    static func currencyCode(_ source: Binding<String>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue },
            set: { newValue in
                source.wrappedValue = String(newValue.uppercased().prefix(3))
            }
        )
    }
}

extension View {
    func kidCoinBackground() -> some View {
        modifier(KidCoinBackground())
    }

    func kidCoinScroll() -> some View {
        modifier(KidCoinScrollModifier())
    }

    /// Marks content as sitting under the main tab bar so scroll views reserve bottom space.
    func kidCoinMainTabScreen() -> some View {
        environment(\.kidCoinTabBarClearance, KidCoinLayout.tabBarReservedHeight)
    }

    /// Dismisses the keyboard when tapping outside text fields (including number pads with no Done key).
    func dismissKeyboardOnTapOutside() -> some View {
        #if canImport(UIKit)
        background(KeyboardDismissOnTapInstaller())
        #else
        self
        #endif
    }

    func kidCoinNumericPIN() -> some View {
        keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }

    func kidCoinDecimalEntry() -> some View {
        keyboardType(.decimalPad)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }

    func kidCoinNumberEntry() -> some View {
        keyboardType(.numberPad)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }

    func kidCoinNameEntry() -> some View {
        textInputAutocapitalization(.words)
            .autocorrectionDisabled()
    }

    func tileCard(cornerRadius: CGFloat = 24) -> some View {
        self
            .background(KidCoinTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(KidCoinTheme.border.opacity(0.75), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 10)
    }
}

struct KidCoinPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? scale : 1))
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(reduceMotion ? KidCoinMotion.quick : KidCoinMotion.press, value: configuration.isPressed)
    }
}

struct PageHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    var subtitle: String?
    let trailing: Trailing

    init(
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(KidCoinTheme.mutedText)
                Text(title)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(KidCoinTheme.foreground)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(KidCoinTheme.mutedText)
                }
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(2)
            .foregroundStyle(KidCoinTheme.mutedText)
            .padding(.horizontal, 4)
    }
}

struct MetricTile: View {
    enum Tone {
        case coral
        case mint
    }

    let title: String
    let value: Int
    var systemImage: String?
    let tone: Tone
    var showsDisclosure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title.uppercased())
                Spacer(minLength: 0)
                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KidCoinTheme.mutedText)
                }
            }
            .font(.caption2.weight(.semibold))
            .tracking(1.8)
            .foregroundStyle(KidCoinTheme.mutedText)

            Text("\(value)")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
                .animation(KidCoinMotion.gentle, value: value)
            Text("points")
                .font(.caption2)
                .foregroundStyle(KidCoinTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 14, x: 0, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var background: LinearGradient {
        switch tone {
        case .coral:
            LinearGradient(
                colors: [KidCoinTheme.primary.opacity(0.16), KidCoinTheme.sunshine.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .mint:
            LinearGradient(
                colors: [KidCoinTheme.mint.opacity(0.34), KidCoinTheme.mint.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct RoundIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(KidCoinTheme.primary)
                .clipShape(Circle())
                .shadow(color: KidCoinTheme.primary.opacity(0.35), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(KidCoinPressButtonStyle(scale: 0.94))
    }
}

struct PillButton: View {
    enum Tone {
        case primary
        case mint
        case subtle
    }

    let title: String
    let systemImage: String?
    let tone: Tone
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                if let systemImage {
                    Image(systemName: systemImage)
                }
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
            .shadow(color: shadowColor, radius: disabled ? 0 : 12, x: 0, y: disabled ? 0 : 6)
            .opacity(disabled ? 0.42 : 1)
        }
        .buttonStyle(KidCoinPressButtonStyle())
        .disabled(disabled)
    }

    private var background: Color {
        switch tone {
        case .primary:
            KidCoinTheme.primary
        case .mint:
            KidCoinTheme.mint
        case .subtle:
            KidCoinTheme.mint.opacity(0.22)
        }
    }

    private var foreground: Color {
        switch tone {
        case .primary:
            .white
        case .mint, .subtle:
            KidCoinTheme.mintText
        }
    }

    private var shadowColor: Color {
        switch tone {
        case .primary:
            KidCoinTheme.primary.opacity(0.28)
        case .mint, .subtle:
            KidCoinTheme.mint.opacity(0.24)
        }
    }
}

/// A fully animated segmented control that replaces `.pickerStyle(.segmented)`.
/// The active selection slides via `matchedGeometryEffect`; tapping triggers a spring transition.
struct SegmentedPickerRow<Item: Hashable>: View {
    @Binding var selection: Item
    let items: [Item]
    let label: (Item) -> String
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items, id: \.self) { item in
                let isSelected = item == selection
                Button {
                    withAnimation(KidCoinMotion.tab) {
                        selection = item
                    }
                } label: {
                    Text(label(item))
                        .font(.caption.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(KidCoinTheme.primary)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .foregroundStyle(isSelected ? Color.white : KidCoinTheme.mutedText)
                        .contentShape(Rectangle())
                }
                .buttonStyle(KidCoinPressButtonStyle(scale: 0.98))
            }
        }
        .padding(4)
        .background(KidCoinTheme.muted)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct CounterControl: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(KidCoinMotion.gentle) {
                    value = max(range.lowerBound, value - 1)
                }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 36, height: 36)
            }
            .disabled(value <= range.lowerBound)

            Text("\(value)")
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .frame(minWidth: 42)
                .contentTransition(.numericText(value: Double(value)))

            Button {
                withAnimation(KidCoinMotion.gentle) {
                    value = min(range.upperBound, value + 1)
                }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 36, height: 36)
            }
            .disabled(value >= range.upperBound)
        }
        .buttonStyle(KidCoinPressButtonStyle(scale: 0.94))
        .foregroundStyle(KidCoinTheme.foreground.opacity(0.75))
        .background(KidCoinTheme.muted)
        .clipShape(Capsule())
    }
}

struct SettingsField<Content: View>: View {
    let label: String
    let hint: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(KidCoinTheme.mutedText)
            }
            Spacer()
            content
        }
    }
}

extension View {
    func fieldPill() -> some View {
        self
            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(KidCoinTheme.muted)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct EmptyStatePanel: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(KidCoinTheme.primary)
                .frame(width: 58, height: 58)
                .background(KidCoinTheme.primary.opacity(0.1))
                .clipShape(Circle())
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(KidCoinTheme.mutedText)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(KidCoinTheme.primary)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .buttonStyle(KidCoinPressButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(KidCoinTheme.border, style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
        }
    }
}

// MARK: - Transaction rows

enum TransactionPillStyle {
    static func background(for kind: RewardTransaction.Kind) -> Color {
        switch kind {
        case .cashedOut, .goalCashedOut:
            return KidCoinTheme.destructive.opacity(0.12)
        case .deposited:
            return KidCoinTheme.mint.opacity(0.25)
        case .goalDeposited:
            return KidCoinTheme.primary.opacity(0.12)
        case .withdrawn:
            return KidCoinTheme.primary.opacity(0.2)
        case .goalWithdrawn:
            return KidCoinTheme.primary.opacity(0.15)
        case .earned, .interest, .adjusted, .goalInterest:
            return KidCoinTheme.primary.opacity(0.12)
        }
    }

    static func foreground(for kind: RewardTransaction.Kind) -> Color {
        switch kind {
        case .cashedOut, .goalCashedOut:
            return KidCoinTheme.destructive
        case .deposited:
            return KidCoinTheme.mintText
        case .goalDeposited, .goalInterest:
            return KidCoinTheme.primary
        case .withdrawn, .goalWithdrawn:
            return KidCoinTheme.primary
        case .earned, .interest, .adjusted:
            return KidCoinTheme.primary
        }
    }
}

enum RewardTransactionRowVariant {
    case household(kidName: String)
    case parent(onCorrect: () -> Void, onDelete: () -> Void)
    case child
}

struct RewardTransactionRow: View {
    let transaction: RewardTransaction
    let currencyCode: String
    let variant: RewardTransactionRowVariant

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.note)
                    .font(titleFont)
                    .foregroundStyle(titleColor)
                    .lineLimit(variantLineLimit)
                Text(subtitleText)
                    .font(.caption2)
                    .foregroundStyle(KidCoinTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(transaction.pointsDisplayLabel)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(TransactionPillStyle.background(for: transaction.kind))
                .foregroundStyle(TransactionPillStyle.foreground(for: transaction.kind))
                .clipShape(Capsule())

            if case .parent(let onCorrect, let onDelete) = variant {
                Button(action: onCorrect) {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KidCoinTheme.primary)
                        .frame(width: 32, height: 32)
                        .background(KidCoinTheme.primary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(KidCoinPressButtonStyle(scale: 0.94))
                .accessibilityLabel("Correct transaction")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KidCoinTheme.destructive)
                        .frame(width: 32, height: 32)
                        .background(KidCoinTheme.destructive.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(KidCoinPressButtonStyle(scale: 0.94))
                .accessibilityLabel("Delete transaction")
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .modifier(TransactionRowChrome(variant: variant))
        .accessibilityElement(children: accessibilityCombinesChildren ? .combine : .ignore)
        .accessibilityLabel(accessibilityLabelText)
    }

    private var titleFont: Font {
        switch variant {
        case .child:
            return .caption.weight(.semibold)
        case .household, .parent:
            return .subheadline.weight(.semibold)
        }
    }

    private var titleColor: Color {
        KidCoinTheme.foreground
    }

    private var variantLineLimit: Int? {
        switch variant {
        case .child:
            return 2
        case .household, .parent:
            return 1
        }
    }

    private var horizontalPadding: CGFloat {
        switch variant {
        case .child:
            return 12
        case .household, .parent:
            return 14
        }
    }

    private var verticalPadding: CGFloat {
        switch variant {
        case .child:
            return 10
        case .household, .parent:
            return 11
        }
    }

    private var accessibilityCombinesChildren: Bool {
        if case .child = variant { return true }
        return false
    }

    private var accessibilityLabelText: String {
        switch variant {
        case .child:
            return "\(transaction.note), \(transaction.pointsDisplayLabel)"
        case .household, .parent:
            return ""
        }
    }

    private var subtitleText: String {
        let formattedDate = transaction.date.formatted(date: .abbreviated, time: .omitted)
        let dateAndAmount: String
        if let amount = transaction.currencyAmount {
            dateAndAmount = "\(formattedDate) · \(Formatters.currency(amount, code: currencyCode))"
        } else {
            dateAndAmount = formattedDate
        }
        switch variant {
        case .household(let kidName):
            return "\(kidName) · \(dateAndAmount)"
        case .parent, .child:
            return dateAndAmount
        }
    }
}

private struct TransactionRowChrome: ViewModifier {
    let variant: RewardTransactionRowVariant

    func body(content: Content) -> some View {
        switch variant {
        case .child:
            content
                .background(KidCoinTheme.muted.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .household, .parent:
            content.tileCard(cornerRadius: 14)
        }
    }
}
