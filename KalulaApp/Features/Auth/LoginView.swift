import SwiftUI

// MARK: - Login step

private enum LoginStep { case email, password }

// MARK: - LoginView

struct LoginView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.colorScheme) private var colorScheme

    // Two-step flow
    @State private var step: LoginStep = .email
    @State private var email    = ""
    @State private var password = ""

    // Loading / error
    @State private var isCheckingEmail  = false
    @State private var isSigningIn      = false
    @State private var passkeyLoading   = false
    @State private var errorMessage: String?

    // MARK: - Design tokens (MainOne blue palette)

    /// Page canvas: #F0F4FF light / #0D1436 dark
    private var canvas: Color {
        colorScheme == .dark
            ? Color(r: 0.051, g: 0.078, b: 0.212)
            : Color(r: 0.941, g: 0.957, b: 1.000)
    }

    /// Card surface
    private var surface: Color {
        colorScheme == .dark
            ? Color(r: 0.094, g: 0.118, b: 0.259)
            : Color.white
    }

    /// Input background
    private var inputBg: Color {
        colorScheme == .dark
            ? Color(r: 0.122, g: 0.149, b: 0.298)
            : Color(r: 0.929, g: 0.945, b: 1.000)
    }

    /// Card border
    private var border: Color {
        colorScheme == .dark
            ? Color(r: 0.200, g: 0.243, b: 0.431)
            : Color(r: 0.835, g: 0.878, b: 0.980)
    }

    private var primaryText: Color {
        colorScheme == .dark ? Color(r: 0.961, g: 0.973, b: 1.000) : Color(r: 0.051, g: 0.078, b: 0.212)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color(r: 0.639, g: 0.686, b: 0.800) : Color(r: 0.369, g: 0.424, b: 0.600)
    }

    /// MainOne blue #1366EF
    private let brand = Color(r: 0.075, g: 0.400, b: 0.937)

    /// Hero gradient — blue left to indigo-blue right
    private let heroGradient = LinearGradient(
        stops: [
            .init(color: Color(r: 0.047, g: 0.337, b: 0.871), location: 0.00),
            .init(color: Color(r: 0.102, g: 0.396, b: 0.937), location: 0.50),
            .init(color: Color(r: 0.153, g: 0.302, b: 0.820), location: 1.00),
        ],
        startPoint: .init(x: 0, y: 1),
        endPoint:   .init(x: 1, y: 0)
    )

    // MARK: - Body

    var body: some View {
        ZStack {
            canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                logoSection

                heroCard
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                statusBadge
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                formCard
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                if let msg = errorMessage {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(Color(r: 0.863, g: 0.149, b: 0.149))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)
                footerSection.padding(.top, 8).padding(.bottom, 20)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    // MARK: - Logo row

    private var logoSection: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(brand)
                    .frame(width: 38, height: 38)
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: brand.opacity(0.30), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(primaryText)
                Text(headerSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryText)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(step == .email ? "ONE PLATFORM" : contextLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .tracking(2.4)

                Text(step == .email ? "Business workspace\nfor every team" : contextHeadline)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineSpacing(2)
                    .lineLimit(2)
            }

            mockDashboard
        }
        .padding(14)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(heroGradient)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.15), Color.clear],
                        startPoint: .top,
                        endPoint: .init(x: 0.5, y: 0.55)
                    ))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: brand.opacity(0.30), radius: 22, x: 0, y: 10)
    }

    // MARK: - Status badge

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(r: 0.086, g: 0.749, b: 0.337))
                .frame(width: 8, height: 8)
            Text(step == .email ? "Your business, in your pocket." : badgeText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(border, lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Form card

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            if step == .email {
                // ── Step 1: email ─────────────────────────────────────────────
                Text("Sign in")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(primaryText)

                styledField(
                    TextField("Email address", text: $email)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .foregroundStyle(primaryText)
                        .tint(brand)
                        .onSubmit { Task { await continueFromEmail() } }
                )

                // Email continue
                Button { Task { await continueFromEmail() } } label: {
                    Group {
                        if isCheckingEmail {
                            ProgressView().tint(.white).frame(maxWidth: .infinity)
                        } else {
                            Text("Continue →")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 54)
                    .background(buttonGradient)
                }
                .buttonStyle(.plain)
                .disabled(isCheckingEmail || email.trimmingCharacters(in: .whitespaces).isEmpty)

                // ── Passkey divider ───────────────────────────────────────────
                HStack {
                    Rectangle().frame(height: 1).foregroundStyle(border)
                    Text("or").font(.system(size: 12)).foregroundStyle(secondaryText).fixedSize()
                    Rectangle().frame(height: 1).foregroundStyle(border)
                }

                Button { Task { await signInWithPasskey() } } label: {
                    HStack(spacing: 8) {
                        if passkeyLoading {
                            ProgressView().tint(brand)
                        } else {
                            Image(systemName: "person.badge.key.fill").foregroundStyle(brand)
                        }
                        Text(passkeyLoading ? "Authenticating…" : "Sign in with Passkey")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(primaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(inputBg)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(border, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .disabled(passkeyLoading || email.trimmingCharacters(in: .whitespaces).isEmpty)

            } else {
                // ── Step 2: password ──────────────────────────────────────────
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Password")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(secondaryText)
                        Text("Sign in as \(email.split(separator: "@").first.map(String.init) ?? email)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(primaryText)
                    }
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            step = .email
                            password = ""
                            errorMessage = nil
                        }
                    } label: {
                        Text("Change")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(brand)
                    }
                    .buttonStyle(.plain)
                }

                styledField(
                    SecureField("Password", text: $password)
                        .foregroundStyle(primaryText)
                        .tint(brand)
                        .onSubmit { Task { await signIn() } }
                )

                Button { Task { await signIn() } } label: {
                    Group {
                        if isSigningIn {
                            ProgressView().tint(.white).frame(maxWidth: .infinity)
                        } else {
                            Text("Sign in →")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 54)
                    .background(buttonGradient)
                }
                .buttonStyle(.plain)
                .disabled(isSigningIn || password.isEmpty)
            }
        }
        .padding(18)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(border, lineWidth: 1))
        .shadow(
            color: colorScheme == .dark ? Color.black.opacity(0.30) : brand.opacity(0.08),
            radius: 24, x: 0, y: 10
        )
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 3) {
            Text("Connected to MainOne")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(secondaryText)
            Text("MainOne v1.0")
                .font(.system(size: 11))
                .foregroundStyle(secondaryText.opacity(0.6))
        }
    }

    // MARK: - Mock dashboard (inside hero card)

    private var mockDashboard: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                mockShell
                mockMetricRow
            }
            mockBadgeCard.frame(width: 88)
        }
    }

    private var mockShell: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MainOne Business")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(r: 0.05, g: 0.08, b: 0.22))

            Text("Invoices, quotes, expenses and contacts — all in one place.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color(r: 0.35, g: 0.42, b: 0.58))
                .lineLimit(2)

            HStack(spacing: 8) {
                miniRing(value: 74, tint: Color(r: 0.94, g: 0.23, b: 0.37))  // Invoice close rate
                miniRing(value: 62, tint: Color(r: 0.19, g: 0.80, b: 0.38))  // Quote win rate
                miniRing(value: 91, tint: Color(r: 0.24, g: 0.73, b: 0.98))  // Revenue target
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var mockMetricRow: some View {
        HStack(spacing: 8) {
            metricCard(title: leftCardTitle, value: leftCardValue, subtitle: leftCardSub)
            metricCard(title: rightCardTitle, value: rightCardValue, subtitle: rightCardSub)
        }
    }

    private var mockBadgeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WORKSPACE")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.70))
                .tracking(1.6)

            Text("MainOne")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)

            Text("Business Suite")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))

            Text("Invoices · Quotes\nExpenses")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
    }

    private func miniRing(value: Int, tint: Color) -> some View {
        ZStack {
            Circle().stroke(tint.opacity(0.22), lineWidth: 7)
            Circle()
                .trim(from: 0, to: CGFloat(Double(value) / 100.0))
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(value)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color(r: 0.05, g: 0.08, b: 0.22))
        }
        .frame(width: 34, height: 34)
    }

    private func metricCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.80))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Computed copy

    private var headerTitle: String {
        step == .password ? (email.split(separator: "@").first.map(String.init) ?? "MainOne") : "MainOne"
    }
    private var headerSubtitle: String {
        step == .password ? "Business workspace" : "Business workspace"
    }
    private var contextLabel: String { "YOUR ACCOUNT" }
    private var contextHeadline: String { "Invoices, quotes,\nand expenses" }
    private var badgeText: String { "Ready — enter your password." }

    private var leftCardTitle: String  { "Revenue" }
    private var leftCardValue: String  { "R 124k" }
    private var leftCardSub: String    { "This month" }
    private var rightCardTitle: String { "Invoices" }
    private var rightCardValue: String { "12" }
    private var rightCardSub: String   { "Outstanding" }

    // MARK: - Styled field helper

    private func styledField<F: View>(_ field: F) -> some View {
        field
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(inputBg)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(border, lineWidth: 1.5))
    }

    // Button gradient background
    private var buttonGradient: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(r: 0.047, g: 0.337, b: 0.871), Color(r: 0.200, g: 0.490, b: 0.980)],
                    startPoint: .leading, endPoint: .trailing))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.14), Color.clear],
                    startPoint: .top, endPoint: .center))
        }
        .shadow(color: brand.opacity(0.38), radius: 14, x: 0, y: 6)
    }

    // MARK: - Actions

    private func continueFromEmail() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isCheckingEmail = true
        errorMessage = nil
        defer { isCheckingEmail = false }
        // Move to password step — no email lookup needed (backend validates at sign-in)
        withAnimation(.easeInOut(duration: 0.22)) { step = .password }
    }

    private func signIn() async {
        isSigningIn  = true
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            try await auth.login(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password
            )
        } catch let e as APIServiceError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func signInWithPasskey() async {
        passkeyLoading = true
        errorMessage   = nil
        defer { passkeyLoading = false }
        do {
            try await auth.loginWithPasskey(email: email.trimmingCharacters(in: .whitespaces))
        } catch let e as APIServiceError {
            if case .httpError(0, _) = e { return }
            errorMessage = e.errorDescription
        } catch let e as NSError where e.domain == "com.apple.AuthenticationServices.AuthorizationError" {
            errorMessage = "Passkey sign-in is not available. Please use your email and password."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - MFA screen (shown by LoginView root when auth.mfaPending == true)

struct MfaView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.colorScheme) private var colorScheme

    @State private var code        = ""
    @State private var isLoading   = false
    @State private var errorMessage: String?

    private var canvas: Color {
        colorScheme == .dark ? Color(r: 0.051, g: 0.078, b: 0.212) : Color(r: 0.941, g: 0.957, b: 1.000)
    }
    private var surface: Color {
        colorScheme == .dark ? Color(r: 0.094, g: 0.118, b: 0.259) : Color.white
    }
    private var border: Color {
        colorScheme == .dark ? Color(r: 0.200, g: 0.243, b: 0.431) : Color(r: 0.835, g: 0.878, b: 0.980)
    }
    private var primaryText: Color {
        colorScheme == .dark ? Color(r: 0.961, g: 0.973, b: 1.000) : Color(r: 0.051, g: 0.078, b: 0.212)
    }
    private var secondaryText: Color {
        colorScheme == .dark ? Color(r: 0.639, g: 0.686, b: 0.800) : Color(r: 0.369, g: 0.424, b: 0.600)
    }
    private let brand = Color(r: 0.075, g: 0.400, b: 0.937)

    var body: some View {
        ZStack {
            canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(brand).frame(width: 38, height: 38)
                        Image(systemName: "lock.shield.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Two-Factor Auth").font(.system(size: 22, weight: .bold)).foregroundStyle(primaryText)
                        Text("Enter your 6-digit code").font(.system(size: 12, weight: .medium)).foregroundStyle(secondaryText)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)

                Spacer().frame(height: 32)

                VStack(spacing: 20) {
                    Text("Open your authenticator app and enter the 6-digit code shown for MainOne.")
                        .font(.system(size: 14))
                        .foregroundStyle(secondaryText)
                        .multilineTextAlignment(.center)

                    TextField("000 000", text: $code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 20)
                        .background(
                            colorScheme == .dark
                                ? Color(r: 0.122, g: 0.149, b: 0.298)
                                : Color(r: 0.929, g: 0.945, b: 1.000)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(border, lineWidth: 1.5))
                        .onChange(of: code) { new in
                            let digits = new.filter(\.isNumber)
                            code = String(digits.prefix(6))
                            if code.count == 6 { Task { await verify() } }
                        }

                    if let msg = errorMessage {
                        Text(msg).font(.footnote).foregroundStyle(Color(r: 0.863, g: 0.149, b: 0.149)).multilineTextAlignment(.center)
                    }

                    Button { Task { await verify() } } label: {
                        Group {
                            if isLoading {
                                ProgressView().tint(.white).frame(maxWidth: .infinity)
                            } else {
                                Text("Verify →").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 54)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(LinearGradient(
                                        colors: [Color(r: 0.047, g: 0.337, b: 0.871), Color(r: 0.200, g: 0.490, b: 0.980)],
                                        startPoint: .leading, endPoint: .trailing))
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(LinearGradient(colors: [Color.white.opacity(0.14), Color.clear], startPoint: .top, endPoint: .center))
                            }
                            .shadow(color: brand.opacity(0.38), radius: 14, x: 0, y: 6)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading || code.count < 6)

                    Button { auth.cancelMfa() } label: {
                        Text("Use a different account")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(secondaryText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(22)
                .background(surface)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(border, lineWidth: 1))
                .shadow(color: colorScheme == .dark ? Color.black.opacity(0.30) : brand.opacity(0.08), radius: 24, x: 0, y: 10)
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func verify() async {
        guard code.count == 6 else { return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            try await auth.verifyMfa(code: code)
        } catch let e as APIServiceError {
            errorMessage = e.errorDescription; code = ""
        } catch {
            errorMessage = error.localizedDescription; code = ""
        }
    }
}

// MARK: - Root login router (password vs MFA step)

struct LoginRootView: View {
    @EnvironmentObject var auth: AuthService

    var body: some View {
        if auth.mfaPending {
            MfaView().environmentObject(auth)
        } else {
            LoginView().environmentObject(auth)
        }
    }
}

// MARK: - Color convenience init

private extension Color {
    init(r: Double, g: Double, b: Double) { self.init(red: r, green: g, blue: b) }
}
