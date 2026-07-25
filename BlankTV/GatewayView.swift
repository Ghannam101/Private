// ============================================================
// BLANK TV — GatewayView.swift
// The login GATEWAY (owner-approved muvy-style design, distinct from the Strong8K
// reference for App Store distinctiveness): a full-bleed 3-row poster wall that
// scrolls SEAMLESSLY in alternating directions, behind the app's own logo/wordmark
// and a compact Xtream/M3U login card. Responsive across iPhone / iPad / Mac.
//
// Posters are BUNDLED (Assets: gwposter1…6) so they paint instantly (no network).
// Reuses the proven LoginView auth logic verbatim.
// ============================================================

import SwiftUI

// Bundled poster asset names (owner-supplied art). Swap freely — just data.
private let gatewayPosters = ["gwposter1", "gwposter2", "gwposter3", "gwposter4", "gwposter5", "gwposter6"]

private let gwCardW: CGFloat = 112
private let gwCardH: CGFloat = 168
private let gwSpacing: CGFloat = 12
private var gwBaseWidth: CGFloat { CGFloat(gatewayPosters.count) * (gwCardW + gwSpacing) }

// MARK: - One SEAMLESS infinite marquee row
// The base 6-poster set is repeated `reps` times; the offset animates by EXACTLY
// one base-set width (gwBaseWidth). Because poster[6] is identical to poster[0] and
// the item stride is uniform (cardW+spacing), the loop is perfectly seamless — no
// jump, no gap, never ends. `reps` is sized to the screen so wide screens stay full.
private struct GatewayMarqueeRow: View {
    let posters: [String]
    let reversed: Bool
    let reps: Int
    let speed: Double            // points per second (calm ≈ 16–24)
    @State private var offset: CGFloat = 0

    var body: some View {
        HStack(spacing: gwSpacing) {
            // Explicit [Int] (NOT a variable-count Range ForEach, which traps when
            // `reps` changes on resize/rotation — see the launch-crash guardrail).
            ForEach(Array(0 ..< (posters.count * reps)), id: \.self) { i in
                Image(posters[i % posters.count])
                    .resizable()
                    .scaledToFill()
                    .frame(width: gwCardW, height: gwCardH)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }
        }
        .offset(x: offset)
        .onAppear {
            offset = reversed ? -gwBaseWidth : 0
            withAnimation(.linear(duration: Double(gwBaseWidth) / max(speed, 1)).repeatForever(autoreverses: false)) {
                offset = reversed ? 0 : -gwBaseWidth
            }
        }
    }
}

// MARK: - 3-row poster wall (alternating directions, seamless)
private struct GatewayPosterWall: View {
    // Fixed repeat count — 6 base-sets (~4400pt) fills any screen from iPhone→Mac
    // and keeps the seamless loop simple (no GeometryReader / width dependency).
    private let reps = 6
    var body: some View {
        VStack(spacing: gwSpacing) {
            GatewayMarqueeRow(posters: rotate(0), reversed: false, reps: reps, speed: 20)
            GatewayMarqueeRow(posters: rotate(2), reversed: true,  reps: reps, speed: 16)
            GatewayMarqueeRow(posters: rotate(4), reversed: false, reps: reps, speed: 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 30)
    }
    private func rotate(_ n: Int) -> [String] {
        let a = gatewayPosters
        guard !a.isEmpty else { return a }
        let k = n % a.count
        return Array(a[k...] + a[..<k])
    }
}

// MARK: - Gateway
struct GatewayView: View {
    var onClose: (() -> Void)? = nil
    @StateObject private var auth = AuthService.shared
    @StateObject private var activation = ActivationService.shared
    @StateObject private var loc = LocalizationManager.shared

    @State private var loginMode = LoginMode.xtream
    @State private var serverOrCode = ""
    @State private var username = ""
    @State private var password = ""
    @State private var m3uURL = ""
    @State private var showPrivacy = false
    @State private var showTerms = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.s8kBlack.ignoresSafeArea()

            // Full-bleed poster wall (rows pinned to the top), seamless.
            GatewayPosterWall().ignoresSafeArea()

            // Scrim — the bottom ~half is fully dark so the login area reads clean on
            // EVERY screen, regardless of the posters behind it.
            LinearGradient(stops: [
                .init(color: .clear,                       location: 0.00),
                .init(color: Color.s8kBlack.opacity(0.15), location: 0.26),
                .init(color: Color.s8kBlack.opacity(0.55), location: 0.40),
                .init(color: Color.s8kBlack.opacity(0.90), location: 0.49),
                .init(color: Color.s8kBlack,               location: 0.56),
                .init(color: Color.s8kBlack,               location: 1.00),
            ], startPoint: .top, endPoint: .bottom).ignoresSafeArea()

            // Foreground — bottom-anchored, width-capped + centered on iPad/Mac,
            // with real breathing room. Keyboard avoidance shifts it up.
            VStack(spacing: 20) {
                brand
                loginCard
                footer
            }
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .overlay(alignment: .top) { topBar }   // respects the safe area (below the notch)
        .sheet(isPresented: $showPrivacy) { PrivacyView() }
        .sheet(isPresented: $showTerms)   { TermsView() }
    }

    // MARK: Top bar — close (preview only) + a CLEARLY-VISIBLE language toggle
    private var topBar: some View {
        HStack {
            if onClose != nil {
                Button { onClose?() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                        .frame(width: 40, height: 40).background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(S8KButtonStyle())
            }
            Spacer()
            langMenu
        }
        .padding(.horizontal, 16).padding(.top, 6)
    }

    // A high-contrast GOLD pill so the user always sees the language switch before login.
    private var langMenu: some View {
        Menu {
            ForEach(AppLang.allCases) { l in
                Button { loc.set(l) } label: {
                    if loc.lang == l { Label(l.display, systemImage: "checkmark") } else { Text(l.display) }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "globe").font(.system(size: 14, weight: .bold))
                Text(loc.lang.display).font(S8KFont.subhead.weight(.heavy))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.s8kBlack)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Capsule().fill(S8KGradient.goldFlat))
            .shadow(color: .black.opacity(0.4), radius: 9, y: 3)
        }
    }

    // MARK: Brand — the app's OWN logo + wordmark (no tagline)
    private var brand: some View {
        VStack(spacing: 12) {
            BrandLogo(size: 66)
            S8KWordmark(size: 30)
        }
        .padding(.bottom, 2)
    }

    // MARK: Login card
    private var loginCard: some View {
        VStack(spacing: 11) {
            modeSwitcher
            if loginMode == .xtream {
                if Store.shared.resellerHost?.isEmpty != false {
                    S8KTextField(placeholder: L("login.server_or_code"), icon: "server.rack", text: $serverOrCode,
                                 ltr: true, keyboard: .URL, contentType: .URL, disableAutocorrect: true, capitalization: .never)
                }
                S8KTextField(placeholder: L("login.username"), icon: "person.fill", text: $username,
                             ltr: true, contentType: .username, disableAutocorrect: true, capitalization: .never)
                S8KTextField(placeholder: L("login.password"), icon: "lock.fill", text: $password,
                             isSecure: true, disableAutocorrect: true, capitalization: .never)
            } else {
                S8KTextField(placeholder: "http://server.com/playlist.m3u", icon: "link", text: $m3uURL,
                             ltr: true, keyboard: .URL, contentType: .URL, disableAutocorrect: true, capitalization: .never)
            }

            if let err = auth.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 13))
                    Text(err.errorDescription ?? L("common.error")).font(S8KFont.caption1)
                }
                .foregroundColor(.s8kRed).padding(12).frame(maxWidth: .infinity, alignment: .trailing)
                .background(Color.s8kRed.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm))
                .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm).strokeBorder(Color.s8kRed.opacity(0.2), lineWidth: 1))
                .transition(.opacity)
            }

            GoldButton(title: loginMode == .xtream ? L("login.signin") : L("login.load_playlist"),
                       icon: "play.fill", isLoading: auth.isLoading,
                       isDisabled: loginMode == .xtream ? (username.isEmpty || password.isEmpty) : m3uURL.isEmpty) {
                submit()
            }
        }
    }

    private var modeSwitcher: some View {
        HStack(spacing: 0) {
            modeTab(.xtream, "Xtream Codes", "person.badge.key.fill")
            modeTab(.m3u, L("login.mode_m3u"), "link")
        }
        .padding(5)
        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }
    private func modeTab(_ mode: LoginMode, _ title: String, _ icon: String) -> some View {
        let on = loginMode == mode
        return Button { withAnimation(.snappy(duration: 0.28)) { loginMode = mode; auth.error = nil } } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(title).font(S8KFont.subhead.weight(.bold)).lineLimit(1).minimumScaleFactor(0.85)
            }
            .foregroundColor(on ? .s8kBlack : .s8kTextSecondary)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(on ? AnyShapeStyle(S8KGradient.goldFlat) : AnyShapeStyle(Color.clear))
                    .shadow(color: on ? Color.s8kGoldMid.opacity(0.45) : .clear, radius: 8, y: 2)
            )
        }
        .buttonStyle(S8KButtonStyle())
    }

    // MARK: Footer — demo + legal
    private var footer: some View {
        VStack(spacing: 13) {
            Button { auth.enterDemo() } label: {
                Text(L("login.demo")).font(S8KFont.subhead.weight(.semibold)).foregroundColor(.s8kGoldMid)
            }
            .buttonStyle(S8KButtonStyle()).padding(.top, 14)
            HStack(spacing: 5) {
                Button(L("set.terms"))   { showTerms = true }.foregroundColor(.s8kTextTertiary)
                Text("·").foregroundColor(.s8kTextDisabled)
                Button(L("set.privacy")) { showPrivacy = true }.foregroundColor(.s8kTextTertiary)
            }
            .font(S8KFont.caption2)
        }
        .padding(.bottom, 22)
    }

    // MARK: Login action (faithful to the proven LoginView logic)
    private func submit() {
        Task {
            if loginMode == .xtream {
                let typed = serverOrCode.trimmingCharacters(in: .whitespacesAndNewlines)
                if looksLikeResellerCode(typed) {
                    auth.error = nil; auth.isLoading = true
                    let ok = await activation.resolveCode(typed)
                    guard ok, let host = Store.shared.resellerHost, !host.isEmpty else {
                        auth.isLoading = false; auth.error = .server(L("code.invalid")); return
                    }
                    auth.isLoading = false
                    await auth.loginXtream(host: host, username: username, password: password)
                } else {
                    let host = !typed.isEmpty ? typed : (Store.shared.resellerHost ?? "")
                    await auth.loginXtream(host: host, username: username, password: password)
                }
            } else {
                await auth.loginM3U(urlString: m3uURL)
            }
        }
    }

    private func looksLikeResellerCode(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        if t.contains("://") || t.contains(".") || t.contains(":") || t.contains("/") { return false }
        return t.range(of: "^[A-Za-z0-9_-]{1,40}$", options: .regularExpression) != nil
    }
}
