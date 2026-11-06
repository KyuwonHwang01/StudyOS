import SwiftUI

private func adaptive(_ light: UInt, _ dark: UInt) -> Color {
    func ui(_ value: UInt) -> UIColor {
        UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
}
enum Water {
    static let background = adaptive(0xF5F5F1, 0x131A1C)
    static let surface = adaptive(0xFFFFFF, 0x253134)
    static let soft = adaptive(0xEBEFEC, 0x1D282B)
    static let ink = adaptive(0x20292B, 0xF0F4F1)
    static let secondary = adaptive(0x58676A, 0xAFBCB9)
    static let accent = adaptive(0x476C70, 0xB0CDCB)
    static let mist = adaptive(0xA9C4C2, 0x6C9291)
    static let glass = adaptive(0x8BAEA6, 0x9BC2B4)
    static let warning = adaptive(0x976047, 0xDBA28A)
    static let motion = Animation.smooth(duration: 0.55, extraBounce: 0)
}
struct WaterCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(Water.surface, in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Water.mist.opacity(0.18), lineWidth: 1))
    }
}
struct FlowButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16).padding(.horizontal, 20)
            .foregroundStyle(Water.background).background(Water.accent.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .opacity(isEnabled ? 1 : 0.45)
    }
}
struct LiquidProgressBar: View {
    var progress: Double
    private var fraction: Double { progress.isFinite ? min(1, max(0, progress)) : 0 }
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        GeometryReader { geo in
            Capsule().fill(Water.soft).overlay(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: [Water.mist, Water.accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: (geo.size.width.isFinite ? max(0, geo.size.width) : 0) * fraction)
            }
        }.frame(height: 8).animation(reduce ? nil : Water.motion, value: progress)
            .accessibilityLabel("Progress").accessibilityValue("\(Int(fraction * 100)) percent")
    }
}
struct DropletBadge: View {
    var count: Int
    var body: some View { Label("\(count) drops", systemImage: "drop.fill").font(.subheadline.weight(.medium)).foregroundStyle(Water.accent).fixedSize(horizontal: true, vertical: false) }
}
struct DeadlineChip: View {
    var date: Date
    var body: some View { Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "clock").font(.caption).foregroundStyle(date < Date() ? Water.warning : Water.secondary) }
}
struct PriorityChip: View {
    var priority: Int
    var body: some View { Label(priority == 3 ? "High" : priority == 2 ? "Normal" : "Low", systemImage: priority == 3 ? "flag.fill" : "flag").font(.caption).foregroundStyle(Water.secondary) }
}
struct EmptyStateView: View {
    var title: String
    var message: String
    var symbol = "drop"
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 32, weight: .ultraLight)).foregroundStyle(Water.accent).accessibilityHidden(true)
            Text(title).font(.title3.weight(.medium))
            Text(message).font(.subheadline).foregroundStyle(Water.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 28)
    }
}
struct SectionHeading: View {
    var title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Water.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct RippleCompletionEffect: ViewModifier {
    var trigger: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var expanded = false
    func body(content: Content) -> some View {
        content.overlay {
            Circle().stroke(Water.mist.opacity(expanded ? 0 : 0.7), lineWidth: 1)
                .scaleEffect(expanded ? 1.6 : 0.6).opacity(expanded ? 0 : 1).allowsHitTesting(false)
                .accessibilityHidden(true)
        }.onChange(of: trigger) { _, new in
            guard new, !reduce else { return }
            expanded = false
            withAnimation(.easeOut(duration: 0.3)) { expanded = true }
        }.onAppear { expanded = true }
    }
}
private struct WaveShape: Shape {
    var phase: Double
    var level: Double
    func path(in rect: CGRect) -> Path {
        var p = Path(); let base = rect.height * (1 - level)
        p.move(to: CGPoint(x: 0, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: base))
        for x in stride(from: 0.0, through: Double(rect.width), by: 4) {
            let y = base + sin(x / Double(max(1, rect.width)) * .pi * 2 + phase) * 5
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: rect.width, y: rect.height)); p.closeSubpath(); return p
    }
}
struct WaterSurfaceView: View {
    var progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.scenePhase) private var scene
    @State private var visible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: reduce || scene != .active || !visible || lowPower)) { timeline in
            let phase = reduce || lowPower ? 0 : timeline.date.timeIntervalSinceReferenceDate / 5
            ZStack {
                Water.soft
                WaveShape(phase: phase + 1.4, level: 0.25 + min(1, progress) * 0.5).fill(Water.mist.opacity(0.5))
                WaveShape(phase: phase, level: 0.22 + min(1, progress) * 0.5)
                    .fill(LinearGradient(colors: [Water.glass.opacity(0.8), Water.accent.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                Ellipse().stroke(Water.mist.opacity(0.4), lineWidth: 1).padding(20)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 80)).frame(height: 190)
            .onAppear { visible = true }.onDisappear { visible = false }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
            .accessibilityHidden(true)
    }
}
struct FocusTransition: ViewModifier {
    var id: UUID
    var namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduce
    @ViewBuilder func body(content: Content) -> some View {
        if reduce { content } else { content.navigationTransition(.zoom(sourceID: id, in: namespace)) }
    }
}
extension View {
    func waterPage() -> some View { self.background(Water.background).foregroundStyle(Water.ink) }
}

private struct FocusNamespaceKey: EnvironmentKey { static let defaultValue: Namespace.ID? = nil }
extension EnvironmentValues {
    var focusNamespace: Namespace.ID? {
        get { self[FocusNamespaceKey.self] }
        set { self[FocusNamespaceKey.self] = newValue }
    }
}
struct FocusSource: ViewModifier {
    var id: UUID
    @Environment(\.focusNamespace) private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduce
    @ViewBuilder func body(content: Content) -> some View {
        if let namespace, !reduce { content.matchedTransitionSource(id:id,in:namespace) } else { content }
    }
}
struct FocusPresentation: ViewModifier {
    var id: UUID?
    var namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduce
    @ViewBuilder func body(content: Content) -> some View {
        if let id, !reduce { content.navigationTransition(.zoom(sourceID:id,in:namespace)) } else { content }
    }
}
