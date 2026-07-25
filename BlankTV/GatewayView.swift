// ============================================================
// BLANK TV — GatewayView.swift
// The login GATEWAY (muvy-style, owner design ref) — a 3-row animated poster wall
// behind the brand mark + a compact Xtream/M3U login card. Deliberately its OWN
// look (not the Strong8K reference) so the app reads as a distinct product.
//
// Posters are Creative-Commons / open-movie art (Blender / Wikimedia / Internet
// Archive — the SAME safe, free-to-ship source the reference uses for demo art),
// loaded through S8KImage (cached + ThumbHash) so they are legal to distribute.
//
// STEP 8a (isolated): reached via a temporary preview button on the current gate,
// so it never risks the live login until approved, then swapped in.
// ============================================================

import SwiftUI

// CC-safe poster set (verified-200 open-movie / Wikimedia assets). Swap freely —
// this is just data; the gateway code is independent of which posters are used.
private let gatewayPosters: [String] = [
    "https://commons.wikimedia.org/wiki/Special:FilePath/Big_buck_bunny_poster_big.jpg",
    "https://commons.wikimedia.org/wiki/Special:FilePath/Sintel_poster.jpg",
    "https://commons.wikimedia.org/wiki/Special:FilePath/Tos-poster.png",
    "https://commons.wikimedia.org/wiki/Special:FilePath/Sintel_Poster_Paintover_clean.jpg",
    "https://archive.org/services/img/ElephantsDream",
]

// MARK: - One infinite, seamless marquee row (posters repeated ×3, offset loops)
private struct GatewayMarqueeRow: View {
    let posters: [String]
    let reversed: Bool
    let cardW: CGFloat
    let cardH: CGFloat
    let speed: Double        // points per second (calm ≈ 20–26)
    @State private var offset: CGFloat = 0
    private let spacing: CGFloat = 12
    private var setWidth: CGFloat { CGFloat(posters.count) * (cardW + spacing) }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0 ..< (max(posters.count, 1) * 3), id: \.self) { i in
                S8KImage(url: posters[i % max(posters.count, 1)], placeholder: "film", maxPixel: 400)
                    .frame(width: cardW, height: cardH)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
            }
        }
        .offset(x: offset)
        .onAppear {
            offset = reversed ? -setWidth : 0
            withAnimation(.linear(duration: Double(setWidth) / max(speed, 1)).repeatForever(autoreverses: false)) {
                offset = reversed ? 0 : -setWidth
            }
        }
    }
}

// MARK: - The 3-row poster wall (rows drift in ALTERNATING directions, calm)
private struct GatewayPosterWall: View {
    private let cardW: CGFloat = 116
    private let cardH: CGFloat = 174
    var body: some View {
        VStack(spacing: 12) {
            GatewayMarqueeRow(posters: rotate(0), reversed: false, cardW: cardW, cardH: cardH, speed: 22)
            GatewayMarqueeRow(posters: rotate(2), reversed: true,  cardW: cardW, cardH: cardH, speed: 26)
            GatewayMarqueeRow(posters: rotate(4), reversed: false, cardW: cardW, cardH: cardH, speed: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 6)
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

    @State private var loginMode = LoginMode.xtream
    @State private var serverOrCode = ""
    @State private var username = ""
    @State private var password = ""
    @State private var m3uURL = ""
    @State private var showPrivacy = false
    @State private var showTerms = false
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.s8kBlack.ignoresSafeArea()
            GatewayPosterWall().opacity(0.92).ignoresSafeArea(edges: .top)
            // Clear at the top (posters read sharply) → solid black at the bottom
            // (login contrast). Owner: "وضوح في الخلفية" — a light, elegant dim.
            LinearGradient(stops: [
                .init(color: .clear,                       location: 0.0),
                .init(color: Color.s8kBlack.opacity(0.45), location: 0.40),
                .init(color: Color.s8kBlack.opacity(0.92), location: 0.66),
                .init(color: Color.s8kBlack,               location: 1.0),
            ], startPoint: .top, endPoint: .bottom).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 300)   // let the poster wall breathe above
                    brand
                    loginCard
                    footer
                }
                .frame(maxWidth: hSize == .regular ? 520 : .infinity)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
            }
            .scrollBounceBehavior(.basedOnSize)

            if onClose != nil {
                Button { onClose?() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                        .frame(width: 38, height: 38).background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(S8KButtonStyle())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 18).padding(.top, 6)
            }
        }
        .sheet(isPresented: $showPrivacy) { PrivacyView() }
        .sheet(isPresented: $showTerms)   { TermsView() }
    }

    // Brand: the app's OWN logo + wordmark (no tagline — owner spec).
    private var brand: some View {
        VStack(spacing: 12) {
            BrandLogo(size: 72)
            S8KWordmark(size: 30)
        }
        .padding(.bottom, 22)
    }

    // MARK: Login card (Xtream / M3U toggle + fields + button)
    private var loginCard: some View {
        VStack(spacing: 14) {
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

    // A gateway-native segmented toggle (distinct look from the reference form).
    private var modeSwitcher: some View {
        HStack(spacing: 6) {
            modeTab(.xtream, "Xtream Codes", "person.badge.key.fill")
            modeTab(.m3u, L("login.mode_m3u"), "link")
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
    private func modeTab(_ mode: LoginMode, _ title: String, _ icon: String) -> some View {
        let on = loginMode == mode
        return Button { withAnimation(.snappy(duration: 0.25)) { loginMode = mode; auth.error = nil } } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(title).font(S8KFont.subhead.weight(.bold)).lineLimit(1)
            }
            .foregroundColor(on ? .s8kBlack : .s8kTextSecondary)
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                .fill(on ? AnyShapeStyle(S8KGradient.goldFlat) : AnyShapeStyle(Color.clear)))
        }
        .buttonStyle(S8KButtonStyle())
    }

    // MARK: Footer — demo + terms (App Store review needs a demo path)
    private var footer: some View {
        VStack(spacing: 14) {
            Button { auth.enterDemo() } label: {
                Text(L("login.demo"))
                    .font(S8KFont.subhead.weight(.semibold)).foregroundColor(.s8kGoldMid)
            }
            .buttonStyle(S8KButtonStyle())
            .padding(.top, 16)

            HStack(spacing: 4) {
                Button(L("set.terms"))   { showTerms = true }.foregroundColor(.s8kTextTertiary)
                Text("·").foregroundColor(.s8kTextDisabled)
                Button(L("set.privacy")) { showPrivacy = true }.foregroundColor(.s8kTextTertiary)
            }
            .font(S8KFont.caption2)
        }
        .padding(.top, 6).padding(.bottom, 30)
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
