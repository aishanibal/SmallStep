import SwiftUI
import UIKit

// MARK: Colour tokens (asset catalog, light + dark). Contrast is checked by scripts/gen_colors.py.

extension Color {
    static let ssBackground = Color("Background")
    static let ssSurface = Color("Surface")
    static let ssText = Color("TextPrimary")
    static let ssTextSecondary = Color("TextSecondary")
    static let ssSage = Color("Sage")
    static let ssOnSage = Color("OnSage")
    static let ssSageSoft = Color("SageSoft")
    static let ssBlue = Color("MutedBlue")
    static let ssBlueSoft = Color("BlueSoft")
    static let ssTaupe = Color("Taupe")        // skipped / unfinished: a muted tone, never red
    static let ssTaupeSoft = Color("TaupeSoft")
    static let ssHairline = Color("Hairline")
}

// MARK: Type. Text styles, so everything scales with Dynamic Type.

extension Font {
    static let ssTitle = Font.system(.largeTitle, design: .rounded).weight(.semibold)
    static let ssHeading = Font.system(.title2, design: .rounded).weight(.semibold)
    static let ssCardTitle = Font.system(.title3, design: .rounded).weight(.semibold)
    static let ssButton = Font.system(.headline, design: .rounded)
    static let ssBody = Font.body
    static let ssCaption = Font.subheadline
}

extension View {
    /// Body copy: generous line spacing.
    func ssBodyText() -> some View { font(.ssBody).foregroundStyle(Color.ssText).lineSpacing(6) }
    func ssSecondaryText() -> some View { font(.ssCaption).foregroundStyle(Color.ssTextSecondary).lineSpacing(5) }
    func ssHeadingText() -> some View { font(.ssHeading).foregroundStyle(Color.ssText).accessibilityAddTraits(.isHeader) }
}

// MARK: Motion. Slow and gentle; none at all when Reduce Motion is on.

struct GentleAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: V
    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.9), value: value)
    }
}

extension View {
    func gentle<V: Equatable>(value: V) -> some View { modifier(GentleAnimation(value: value)) }
}

/// A slow fade for screen content appearing.
struct FadeIn: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    func body(content: Content) -> some View {
        content.opacity(shown || reduceMotion ? 1 : 0)
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.9)) { shown = true } }
    }
}
extension View { func fadeIn() -> some View { modifier(FadeIn()) } }

enum Haptics {
    /// A soft tap for finishing something. Silent if the device has no haptics.
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
}

// MARK: Screen and card containers

struct ScreenScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) { content }
                .padding(.horizontal, 24).padding(.vertical, 28)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.ssBackground.ignoresSafeArea())
    }
}

struct SoftCard: ViewModifier {
    var selected = false
    var tint: Color = .ssSurface
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.ssSageSoft : tint, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(selected ? Color.ssSage : Color.ssHairline, lineWidth: selected ? 2.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
extension View {
    func softCard(selected: Bool = false, tint: Color = .ssSurface) -> some View { modifier(SoftCard(selected: selected, tint: tint)) }
}

// MARK: Buttons: one primary action per screen, quiet text buttons for the rest.

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ssButton)
            .foregroundStyle(Color.ssOnSage)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 20)
            .background(Color.ssSage, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: configuration.isPressed)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ssButton)
            .foregroundStyle(Color.ssBlue)
            .frame(maxWidth: .infinity, minHeight: 48)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: Chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (i, origin) in result.origins.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func layout(in maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return (CGSize(width: width, height: y + rowHeight), origins)
    }
}

/// A selectable chip. Selection shows a check mark and a heavier border, never colour alone.
struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected { Image(systemName: "checkmark").font(.footnote.weight(.bold)).accessibilityHidden(true) }
                Text(title).font(.system(.body, design: .rounded))
            }
            .foregroundStyle(Color.ssText)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(selected ? Color.ssSageSoft : Color.ssSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.ssSage : Color.ssHairline, lineWidth: selected ? 2.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A wrapping row of chips for picking one value (tap the selected one again to clear it if `clearable`).
struct ChipGroup<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T?
    var clearable = false

    var body: some View {
        FlowLayout {
            ForEach(options, id: \.value) { option in
                Chip(title: option.label, selected: selection == option.value) {
                    selection = (clearable && selection == option.value) ? nil : option.value
                }
            }
        }
        .gentle(value: selection)
    }
}

// MARK: Progress

struct StepProgress: View {
    let step: Int
    let of: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Step \(step) of \(of)").ssSecondaryText()
            ProgressView(value: Double(step), total: Double(of)).tint(Color.ssSage)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step) of \(of)")
    }
}
