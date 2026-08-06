// ============================================================
// BLANK TV — ActivationView.swift
// The admission layer: the one wrapper the whole app lives inside,
// plus the stop screens shown when it will not let the user through.
// ============================================================

import SwiftUI

// MARK: - Mount point: what the rest of the app wraps itself in

// The app's root sits inside this. Everything below is what replaces it, or covers
// it, when admission is withheld.
struct ActivationGate<Gated: View>: View {
    @StateObject private var act = ActivationService.shared
    @ViewBuilder var content: () -> Gated

    var body: some View {
        // Presentation depends on WHERE content() sits in this tree, not merely on
        // whether it is drawn. When the admitted path was buried under a nested
        // else/switch, a .fullScreenCover raised from inside HomeView quietly refused
        // to appear, while the demo path — a plain first branch — kept working. Both
        // admitted paths therefore share one branch, and it is the first one. Do not
        // lift it into a helper, a switch, or a computed property.
        ZStack {
            if act.gate == .allowed || Store.shared.demoMode {
                content()
            } else if act.gate == .checking {
                AdmissionWaitScreen()
            } else {
                AdmissionDeniedScreen()
            }

            // Remotely operated stop screens. They are SIBLINGS painted over the app
            // rather than wrappers placed around it: an opaque full-screen layer
            // blocks input just as effectively and leaves content()'s slot in the
            // tree exactly where it was. Demo is exempt from both — it is the review
            // path and it runs with no server behind it.
            if act.maintenance && !Store.shared.demoMode {
                ServiceHoldCurtain(message: act.maintenanceMessage) { Task { await act.check() } }
            } else if act.updateRequired && !Store.shared.demoMode {
                StoreUpdateCurtain(latest: act.latestVersion, urlString: act.updateURL)
            }
        }
        // The splash already fired the opening check. Repeat it here only while that
        // first answer is still outstanding — otherwise the user pays for a second
        // round trip and a pointless flash of the waiting screen.
        .task {
            guard !Store.shared.demoMode, act.gate == .checking else { return }
            await act.check()
        }
    }
}

// MARK: - Chrome every stop screen shares

// Named once so the three stop screens cannot drift apart the way three hand-copied
// backdrops eventually do.
struct GateBackdrop: View {
    var glow: Bool = false

    var body: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            if glow {
                RadialGradient(colors: [Color.s8kGoldMid.opacity(0.14), .clear],
                               center: .top, startRadius: 0, endRadius: 420)
                    .ignoresSafeArea()
            }
        }
    }
}

// The single large symbol that opens a stop screen.
struct CurtainGlyph: View {
    var symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 46)).foregroundColor(.s8kGoldHigh)
            .shadow(color: .s8kGoldHigh.opacity(0.35), radius: 18)
    }
}

// The shell behind any screen that takes the whole display away from the user.
//
// It scrolls on purpose. The wording on these screens can arrive from the server and
// there is no other way off them, so a rigid stack pushes the only button past the
// bottom edge on a short window or at the largest text sizes and strands whoever
// landed there. Centring short content keeps it off the top edge of an iPad.
struct BlockingCurtain<Panel: View>: View {
    @ViewBuilder var panel: () -> Panel

    var body: some View {
        ZStack {
            GateBackdrop()
            ScrollView(.vertical, showsIndicators: false) {
                // Mounted above S8KMetricsRoot, so there are no layout metrics to read
                // and the ceiling has to be a literal. Unbounded, a lone button ran the
                // full width of a 12.9" iPad and wider again in a desktop window; 460 is
                // the same order as the gateway's own sign-in card. The sequence matters:
                // pad, cap, then re-expand, so the capped column ends up centred.
                panel()
                    .padding(.vertical, 32)
                    .frame(maxWidth: 460)
                    .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.center)
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// Three dots breathing out of phase with one another.
struct WaitPulse: View {
    @State private var wave = 0.0

    var body: some View {
        HStack(spacing: 7) {
            pip(0)
            pip(1)
            pip(2)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                wave = .pi * 2
            }
        }
    }

    private func pip(_ slot: Int) -> some View {
        Circle()
            .fill(Color.s8kGoldMid)
            .frame(width: 7, height: 7)
            .opacity(0.3 + 0.7 * abs(sin(wave + Double(slot) * 0.6)))
    }
}

// MARK: - Stop: the app is held by remote control

// Service is paused from the operator's side. The retry hands control back to the
// activation service and nothing else on the screen does anything.
struct ServiceHoldCurtain: View {
    var message: String?
    var onRetry: () -> Void

    var body: some View {
        BlockingCurtain {
            VStack(spacing: S8KSpace.xl) {
                CurtainGlyph(symbol: "wrench.and.screwdriver.fill")
                Text(L("maintenance.title"))
                    .font(S8KFont.title2).foregroundColor(.s8kTextPrimary)
                Text(message?.isEmpty == false ? message! : L("maintenance.message"))
                    .font(S8KFont.callout).foregroundColor(.s8kTextSecondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 36)
                OutlineButton(title: L("common.retry"), icon: "arrow.clockwise", action: onRetry)
                    .frame(maxWidth: 200)
            }
        }
    }
}

// This build is too old to keep running. The only way forward is the store listing.
struct StoreUpdateCurtain: View {
    var latest: String?
    var urlString: String?

    var body: some View {
        BlockingCurtain {
            VStack(spacing: S8KSpace.xl) {
                CurtainGlyph(symbol: "arrow.down.circle.fill")
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
                    // An earlier revision switched this button off whenever no URL had
                    // been configured — on a screen that offers no dismiss, no re-check
                    // and nothing else to press, which locked the user in permanently.
                    // Unreachable while `updateRequired` is pinned false, but falling
                    // back to the store's own scheme costs two lines and makes sure the
                    // trap cannot reappear if remote force-update is ever switched on.
                    let raw = urlString ?? ""
                    if let u = URL(string: raw.isEmpty ? "itms-apps://apps.apple.com" : raw) {
                        UIApplication.shared.open(u)
                    }
                }
                .frame(maxWidth: 220)
            }
        }
    }
}

// MARK: - Stop: entry is still being decided

// The only transient state here. Deliberately not built on BlockingCurtain: it holds
// a short, fixed line of text, so it needs neither the scroll shell nor the width cap.
struct AdmissionWaitScreen: View {
    var body: some View {
        ZStack {
            GateBackdrop()
            VStack(spacing: S8KSpace.xl) {
                BrandLogo(size: 90)
                    .shadow(color: .s8kGoldHigh.opacity(0.4), radius: 24)
                WaitPulse()
                Text(L("actgate.checking"))
                    .font(S8KFont.footnote).foregroundColor(.s8kTextTertiary)
            }
        }
    }
}

// MARK: - Stop: entry was refused

// Eight slots, one named child each, so the stack reads top to bottom in one screen.
// The panels are grouped below; the things the user can still press after them; the
// wording rules and the two side effects last.
struct AdmissionDeniedScreen: View {
    @StateObject private var act  = ActivationService.shared
    @StateObject private var auth = AuthService.shared
    @State private var copied = false
    @State private var refreshing = false

    // How long the copy button stays in its confirmed state.
    private static let copiedFlash: TimeInterval = 1.8

    var body: some View {
        ZStack {
            GateBackdrop(glow: true)

            ScrollView(showsIndicators: false) {
                VStack(spacing: S8KSpace.xxl) {
                    brandMark
                    deviceIdentityCard
                    denialNotice
                    recheckButton
                    supportLink
                    demoEntry
                    legalFootnote
                    Spacer(minLength: 40)
                }
                .padding(.top, 70)
                // Same ceiling as the other stop screens, and for the same reason: this
                // one renders outside S8KMetricsRoot, so it has no metrics of its own and
                // uncapped its buttons stretched the whole width of a large iPad. This is
                // also the screen an unactivated review device lands on.
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Refused screen · the panels it stacks

extension AdmissionDeniedScreen {

    private var brandMark: some View {
        VStack(spacing: S8KSpace.lg) {
            BrandLogo(size: 96)
                .shadow(color: .s8kGoldHigh.opacity(0.4), radius: 26)
            Text(S8KBrand.name)
                .font(.system(size: 26, weight: .black)).tracking(6)
                .foregroundStyle(S8KGradient.goldFlat)
        }
    }

    // The identifier support will ask for, presented so it can be read aloud over a
    // phone, selected by hand, or copied in one tap.
    private var deviceIdentityCard: some View {
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

                copyIDButton
            }
        }
        .padding(.horizontal, S8KSpace.xl)
    }

    private var copyIDButton: some View {
        Button(action: copyIdentity) {
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

    // Why the device was turned away. Wording comes from the rules further down.
    private var denialNotice: some View {
        VStack(spacing: S8KSpace.md) {
            Image(systemName: noticeSymbol)
                .font(.system(size: 34))
                .foregroundColor(noticeTint)

            Text(noticeTitle)
                .font(S8KFont.title3).foregroundColor(.s8kTextPrimary)

            Text(noticeBody)
                .font(S8KFont.callout).foregroundColor(.s8kTextSecondary)
                .multilineTextAlignment(.center).lineSpacing(4)
                .padding(.horizontal, S8KSpace.xl)
        }
        .padding(.horizontal, S8KSpace.xl)
    }
}

// MARK: - Refused screen · what the user can still do

extension AdmissionDeniedScreen {

    // Ask again. Disabled for the duration so the request cannot be stacked.
    private var recheckButton: some View {
        Button(action: runRecheck) {
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
    }

    // A route to a person, and nothing more: it quotes no tariff, sells nothing, and
    // does not hand the user off to a checkout, which is what keeps it inside Apple
    // 3.1.1. The destination is supplied by the activation server, so the button
    // exists only when the server named one AND that name parses as a URL — a visible
    // button that leads nowhere is worse than no button at all.
    @ViewBuilder
    private var supportLink: some View {
        if let u = S8KBrand.supportURL {
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
    }

    // A reseller-code field used to sit between the contact link and this button. It
    // called a resolver that had already been removed, so it could only ever report
    // failure — an advertised feature the binary could not perform. It was taken out
    // rather than left to mislead (Guideline 2.1).

    // The unauthenticated way in, so a reviewer is never stuck behind this screen
    // (Guideline 2.1).
    private var demoEntry: some View {
        Button(L("actgate.demo")) { auth.enterDemo() }
            .font(S8KFont.callout.weight(.semibold))
            .foregroundColor(.s8kTextSecondary)
            .frame(maxWidth: .infinity, minHeight: 46)
            .overlay(RoundedRectangle(cornerRadius: S8KRadius.md)
                .strokeBorder(Color.s8kBorder, lineWidth: 1))
            .padding(.horizontal, S8KSpace.xl)
            .padding(.top, S8KSpace.sm)
    }

    // States plainly that this is a player and the content is not ours (4.3 / 5.x).
    private var legalFootnote: some View {
        Text(S8KLegal.disclaimer)
            .font(S8KFont.caption2)
            .foregroundColor(.s8kTextDisabled)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .padding(.horizontal, S8KSpace.h)
            .padding(.top, S8KSpace.xxl)
    }
}

// MARK: - Refused screen · wording rules and side effects

extension AdmissionDeniedScreen {

    private var isBlocked: Bool { act.status == "blocked" }

    private var noticeSymbol: String {
        isBlocked ? "lock.fill" : "exclamationmark.shield.fill"
    }

    private var noticeTint: Color {
        isBlocked ? .s8kRed : .s8kOrange
    }

    // ⚠ The heading and the paragraph resolve their three cases in DIFFERENT orders,
    // and that is deliberate — do not fold them into one rule, one enum or one switch.
    // A device that is both blocked and offline should be TITLED as blocked, because
    // that is the fact that will not change when the network returns; but it should be
    // TOLD about the network first, because that is the part it can act on.

    private var noticeTitle: String {
        if isBlocked { return L("actgate.blocked.title") }
        return act.gate == .offline ? L("actgate.offline.title") : L("actgate.notactive.title")
    }

    private var noticeBody: String {
        if act.gate == .offline { return L("actgate.offline.msg") }
        return isBlocked ? L("actgate.blocked.msg") : L("actgate.notactive.msg")
    }

    private func copyIdentity() {
        UIPasteboard.general.string = act.deviceID
        withAnimation { copied = true }
        // Not a Task: a Task started from a view dies with the view, and the label
        // would then be left reading "copied" if this screen were rebuilt mid-flash.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.copiedFlash) {
            withAnimation { copied = false }
        }
    }

    private func runRecheck() {
        // The button is disabled while this runs, so the guard should never fire; it is
        // here so a second entry point added later cannot start two checks at once.
        guard !refreshing else { return }
        refreshing = true
        Task {
            await act.check()
            refreshing = false
        }
    }
}

// MARK: - Compliance strings other screens read

// Not a view — a small table of wording that the settings and gateway screens read as
// well. Its natural home is beside the rest of the identity kit; it stays here for now
// because moving it is a separate, cross-file change.
enum S8KLegal {
    /// Says out loud that this is a player and the streams are the user's own —
    /// Guideline 4.3 / 5.x.
    static var disclaimer: String { L("legal.disclaimer") }
    /// Where takedown requests go (Guideline 4.7.1). Forwarded from `S8KBrand` so a
    /// re-skin changes one literal rather than several.
    static var reportEmail: String { S8KBrand.reportEmail }
}
