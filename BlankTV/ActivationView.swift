// ============================================================
// BLANK TV — ActivationView.swift
// Activation gate: device identity, trial/expiry, access control
// iOS 26 Liquid Glass (with graceful fallback)
// ============================================================

import SwiftUI

// MARK: - Legal / App Store compliance strings
enum S8KLegal {
    /// Guideline 4.3 / 5.x — make clear the app is a player only.
    static var disclaimer: String { L("legal.disclaimer") }
    /// Guideline 4.7.1 — content report destination. Lives in `S8KBrand` so a
    /// rebrand is one literal in one place, not a hunt through the tree.
    static var reportEmail: String { S8KBrand.reportEmail }
}

// MARK: - Gate container
// Wraps the app: only renders `content` once the device is allowed.
struct ActivationGate<Content: View>: View {
    @StateObject private var act = ActivationService.shared
    @ViewBuilder var content: () -> Content

    var body: some View {
        // ROOT FIX for "buttons work in demo but not in playlists": content()
        // must sit at the SAME structural position in both modes. Previously demo
        // used the `if` branch while a real (allowed) user used a deeply-nested
        // `else → switch → .allowed` branch, and SwiftUI's .fullScreenCover
        // (attached inside HomeView) fails to present from that nested-conditional
        // position. Here content() is always the FIRST branch (demo OR allowed),
        // so presentations behave identically in both modes.
        ZStack {
            if Store.shared.demoMode || act.gate == .allowed {
                content()
            } else if act.gate == .checking {
                ActivationCheckingView()
            } else {
                ActivationRequiredView()
            }

            // Remote app-control gates — rendered ON TOP (opaque, full-screen) so
            // they block everything WITHOUT changing content()'s structural
            // position (which would risk regressing the home-button presentation).
            // Demo mode is never blocked (protects App Review + demo is offline).
            if !Store.shared.demoMode {
                if act.maintenance {
                    MaintenanceView(message: act.maintenanceMessage) { Task { await act.check() } }
                } else if act.updateRequired {
                    UpdateRequiredView(latest: act.latestVersion, urlString: act.updateURL)
                }
            }
        }
        // Splash already kicks the first check; only re-check here if it is
        // still pending (avoids a redundant call + the "checking" flash).
        .task { if !Store.shared.demoMode && act.gate == .checking { await act.check() } }
    }
}

// MARK: - Checking (brief)
struct ActivationCheckingView: View {
    var body: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            VStack(spacing: S8KSpace.xl) {
                BrandLogo(size: 90)
                    .shadow(color: .s8kGoldHigh.opacity(0.4), radius: 24)
                LoadingDots()
                Text(L("actgate.checking"))
                    .font(S8KFont.footnote).foregroundColor(.s8kTextTertiary)
            }
        }
    }
}

// MARK: - Maintenance gate (remote App Control)
struct MaintenanceView: View {
    var message: String?
    var onRetry: () -> Void
    var body: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            // SCROLLABLE: the message is server-supplied and unbounded — on a short
            // window (landscape / Mac) or at large text sizes a fixed stack would push
            // "Retry" off-screen and trap the user in the gate with no way out.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: S8KSpace.xl) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 46)).foregroundColor(.s8kGoldHigh)
                        .shadow(color: .s8kGoldHigh.opacity(0.35), radius: 18)
                    Text(L("maintenance.title"))
                        .font(S8KFont.title2).foregroundColor(.s8kTextPrimary)
                    Text(message?.isEmpty == false ? message! : L("maintenance.message"))
                        .font(S8KFont.callout).foregroundColor(.s8kTextSecondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 36)
                    OutlineButton(title: L("common.retry"), icon: "arrow.clockwise", action: onRetry)
                        .frame(maxWidth: 200)
                }
                .padding(.vertical, 32)
                // Capped and centred. This view sits OUTSIDE S8KMetricsRoot, so it has
                // no layout metrics of its own — unbounded, its buttons stretched to
                // 1326pt on a 12.9" iPad and 1960pt in a Mac window. 460 is the same
                // order as the gateway's own 400pt login card.
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            // CENTRES content that is shorter than the screen (iOS 17+) — without this
            // the ScrollView would top-align it and leave a screen of dead black below.
            .defaultScrollAnchor(.center)
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: - Forced-update gate (remote App Control)
struct UpdateRequiredView: View {
    var latest: String?
    var urlString: String?
    var body: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            // SCROLLABLE for the same reason as MaintenanceView: this gate is the only
            // UI on screen, so the Update button must be reachable on every device.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: S8KSpace.xl) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 46)).foregroundColor(.s8kGoldHigh)
                        .shadow(color: .s8kGoldHigh.opacity(0.35), radius: 18)
                    Text(L("update.title"))
                        .font(S8KFont.title2).foregroundColor(.s8kTextPrimary)
                    Text(L("update.message"))
                        .font(S8KFont.callout).foregroundColor(.s8kTextSecondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 36)
                    if let v = latest, !v.isEmpty {
                        Text("\(L("update.latest")) \(v)")
                            .font(S8KFont.caption1).foregroundColor(.s8kTextTertiary)
                    }
                    GoldButton(title: L("update.button"), icon: "arrow.up.forward.app") {
                        // Without a configured URL this button was DISABLED — and this
                        // screen offers no other control, no dismiss and no re-check, so
                        // anyone who reached it was locked in for good. Unreachable today
                        // (`updateRequired` is hardcoded false), but it costs two lines to
                        // make sure it can never become a trap if force-update returns.
                        let raw = urlString ?? ""
                        if let u = URL(string: raw.isEmpty ? "itms-apps://apps.apple.com" : raw) {
                            UIApplication.shared.open(u)
                        }
                    }
                    .frame(maxWidth: 220)
                }
                .padding(.vertical, 32)
                // Capped and centred. This view sits OUTSIDE S8KMetricsRoot, so it has
                // no layout metrics of its own — unbounded, its buttons stretched to
                // 1326pt on a 12.9" iPad and 1960pt in a Mac window. 460 is the same
                // order as the gateway's own 400pt login card.
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            // Centre when it fits (see MaintenanceView) — this gate is the whole screen.
            .defaultScrollAnchor(.center)
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: - Access required / denied
struct ActivationRequiredView: View {
    @StateObject private var act  = ActivationService.shared
    @StateObject private var auth = AuthService.shared
    @State private var copied = false
    @State private var refreshing = false

    var body: some View {
        ZStack {
            // Ambient black + gold glow backdrop
            Color.s8kBlack.ignoresSafeArea()
            RadialGradient(colors: [Color.s8kGoldMid.opacity(0.14), .clear],
                           center: .top, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: S8KSpace.xxl) {
                    header

                    // Device identity glass card
                    GlassCard(tinted: true) {
                        VStack(spacing: S8KSpace.lg) {
                            Label(L("actgate.device_id"), systemImage: "number")
                                .font(S8KFont.caption1.weight(.bold))
                                .foregroundColor(.s8kGoldMid)
                                .frame(maxWidth: .infinity, alignment: .center)

                            Text(act.deviceID)
                                .font(.system(size: 22, weight: .black, design: .monospaced))
                                .foregroundStyle(S8KGradient.goldFlat)
                                .textSelection(.enabled)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)

                            Button(action: copy) {
                                Label(copied ? L("actgate.copied") : L("actgate.copy_id"),
                                      systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .font(S8KFont.subhead)
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .background(S8KGradient.goldFlat)
                                    .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous))
                            }
                            .buttonStyle(S8KButtonStyle())
                        }
                    }
                    .padding(.horizontal, S8KSpace.xl)

                    statusBlock

                    // Refresh
                    Button(action: refresh) {
                        HStack(spacing: 8) {
                            if refreshing {
                                ProgressView().tint(.s8kGoldMid).scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(L("actgate.recheck"))
                        }
                        .font(S8KFont.subhead)
                        .foregroundColor(.s8kGoldMid)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .overlay(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
                            .strokeBorder(Color.s8kGoldHigh.opacity(0.4), lineWidth: 1.5))
                    }
                    .buttonStyle(S8KButtonStyle())
                    .padding(.horizontal, S8KSpace.xl)
                    .disabled(refreshing)

                    // Support / activation help — a CONTACT link (no prices),
                    // compliant with Apple 3.1.1. Driven by the activation server.
                    if let support = act.supportURL, let u = URL(string: support) {
                        Button(action: { UIApplication.shared.open(u) }) {
                            HStack(spacing: 8) {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                Text(L("actgate.contact"))
                            }
                            .font(S8KFont.subhead).foregroundColor(.black)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(S8KGradient.goldFlat)
                            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous))
                            .shadow(color: .s8kGoldMid.opacity(0.4), radius: 8, y: 3)
                        }
                        .buttonStyle(S8KButtonStyle())
                        .padding(.horizontal, S8KSpace.xl)
                        .padding(.top, S8KSpace.sm)
                    }

                    // The reseller-code entry lived here. It called resolveCode, which
                    // returns false unconditionally since the resolver was removed — a
                    // button that could only ever fail. Removed rather than left to
                    // advertise a feature the binary cannot deliver (Guideline 2.1).

                    // Demo Mode entry (App Review, Guideline 2.1)
                    Button(L("actgate.demo")) { auth.enterDemo() }
                        .font(S8KFont.callout.weight(.semibold))
                        .foregroundColor(.s8kTextSecondary)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .overlay(RoundedRectangle(cornerRadius: S8KRadius.md)
                            .strokeBorder(Color.s8kBorder, lineWidth: 1))
                        .padding(.horizontal, S8KSpace.xl)
                        .padding(.top, S8KSpace.sm)

                    // Apple-required disclaimer (Guideline 4.3 / 5.x)
                    Text(S8KLegal.disclaimer)
                        .font(S8KFont.caption2)
                        .foregroundColor(.s8kTextDisabled)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, S8KSpace.h)
                        .padding(.top, S8KSpace.xxl)

                    Spacer(minLength: 40)
                }
                .padding(.top, 70)
                // Capped like the other two gates. This is the screen an Apple reviewer
                // sees on an unactivated device, and uncapped its buttons ran to 1326pt
                // on a 12.9" iPad.
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)   // literal: this gate renders OUTSIDE S8KMetricsRoot, so metrics.safeTop would be 0
            }
        }
    }


    private var header: some View {
        VStack(spacing: S8KSpace.lg) {
            BrandLogo(size: 96)
                .shadow(color: .s8kGoldHigh.opacity(0.4), radius: 26)
            Text(S8KBrand.name)
                .font(.system(size: 26, weight: .black)).tracking(6)
                .foregroundStyle(S8KGradient.goldFlat)
        }
    }

    @ViewBuilder
    private var statusBlock: some View {
        let isBlocked = act.status == "blocked"
        VStack(spacing: S8KSpace.md) {
            Image(systemName: isBlocked ? "lock.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 34))
                .foregroundColor(isBlocked ? .s8kRed : .s8kOrange)

            Text(isBlocked ? L("actgate.blocked.title")
                 : act.gate == .offline ? L("actgate.offline.title")
                 : L("actgate.notactive.title"))
                .font(S8KFont.title3).foregroundColor(.s8kTextPrimary)

            Text(displayMessage)
                .font(S8KFont.callout).foregroundColor(.s8kTextSecondary)
                .multilineTextAlignment(.center).lineSpacing(4)
                .padding(.horizontal, S8KSpace.xl)
        }
        .padding(.horizontal, S8KSpace.xl)
    }

    private var displayMessage: String {
        if act.gate == .offline {
            return L("actgate.offline.msg")
        }
        if act.status == "blocked" {
            return L("actgate.blocked.msg")
        }
        return L("actgate.notactive.msg")
    }

    private func copy() {
        UIPasteboard.general.string = act.deviceID
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { copied = false }
        }
    }

    private func refresh() {
        refreshing = true
        Task {
            await act.check()
            refreshing = false
        }
    }
}

// MARK: - Loading dots
struct LoadingDots: View {
    @State private var phase = 0.0
    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.s8kGoldMid)
                    .frame(width: 7, height: 7)
                    .opacity(0.3 + 0.7 * abs(sin(phase + Double(i) * 0.6)))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}
