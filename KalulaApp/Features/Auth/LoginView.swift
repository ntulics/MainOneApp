import SwiftUI

// MARK: - Login step

private enum LoginStep { case email, password }

// MARK: - Brand tokens (fixed, scheme-independent)

private extension Color {
    static let m1Primary   = Color(red: 0.075, green: 0.400, blue: 0.937)  // #1366EF
    static let m1PrimaryH  = Color(red: 0.059, green: 0.337, blue: 0.871)  // #0F56DE
    static let m1CTA       = Color(red: 1.000, green: 0.706, blue: 0.000)  // #FFB400
    static let m1Orange    = Color(red: 0.961, green: 0.620, blue: 0.043)  // #F59E0B
    static let m1Green     = Color(red: 0.133, green: 0.773, blue: 0.369)  // #22C55E
    static let m1Grey      = Color(red: 0.380, green: 0.400, blue: 0.450)
}

// MARK: - Adaptive palette (switches with system color scheme)

private struct LoginPalette {
    let colorScheme: ColorScheme

    // Page canvas
    var canvas:   Color { colorScheme == .dark
        ? Color(red: 0.051, green: 0.059, blue: 0.094)   // #0D0F18
        : Color(red: 0.949, green: 0.953, blue: 0.973) } // #F2F3F8

    // Card surface
    var surface:  Color { colorScheme == .dark
        ? Color(red: 0.082, green: 0.094, blue: 0.129)   // #151821
        : Color.white }

    // Secondary surface (passkey btn bg, badge bg)
    var surface2: Color { colorScheme == .dark
        ? Color(red: 0.110, green: 0.125, blue: 0.180)   // #1C202E
        : Color(red: 0.929, green: 0.937, blue: 0.961) } // #EDEFF5

    // Borders
    var border:   Color { colorScheme == .dark
        ? Color(red: 0.165, green: 0.184, blue: 0.259)   // #2A2F42
        : Color(red: 0.878, green: 0.894, blue: 0.941) } // #E0E4F0

    // Input background
    var inputBg:  Color { colorScheme == .dark
        ? Color(red: 0.051, green: 0.059, blue: 0.094)
        : Color(red: 0.961, green: 0.965, blue: 0.980) }

    // Primary text
    var textPrimary: Color { colorScheme == .dark ? .white : Color(red: 0.122, green: 0.141, blue: 0.204) }
    // Secondary text
    var textSecondary: Color { colorScheme == .dark ? Color.white.opacity(0.50) : Color(red: 0.369, green: 0.392, blue: 0.478) }
    // Muted text
    var textMuted: Color { colorScheme == .dark ? Color.white.opacity(0.30) : Color(red: 0.600, green: 0.627, blue: 0.710) }
}

// MARK: - Donut segment shape (exact copy of real dashboard implementation)

private struct MockDonutSegment: Shape {
    let startFraction: Double
    let endFraction:   Double
    let innerRatio:    CGFloat
    let outerRatio:    CGFloat

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, cy = rect.midY
        let r  = min(rect.width, rect.height) / 2
        let ri = r * innerRatio
        let ro = r * outerRatio
        let s  = Angle(degrees: startFraction * 360 - 90)
        let e  = Angle(degrees: endFraction   * 360 - 90)
        var p  = Path()
        p.addArc(center: CGPoint(x: cx, y: cy), radius: ro,
                 startAngle: s, endAngle: e, clockwise: false)
        p.addArc(center: CGPoint(x: cx, y: cy), radius: ri,
                 startAngle: e, endAngle: s, clockwise: true)
        p.closeSubpath()
        return p
    }
}

// MARK: - Financial overview card (mock dashboard)

private struct FinancialOverviewCard: View {
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    // Card background adapts to system mode
    private var cardBg: AnyShapeStyle {
        if isDark {
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.09, green: 0.11, blue: 0.17),
                         Color(red: 0.07, green: 0.08, blue: 0.13)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        } else {
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.95, green: 0.97, blue: 1.00),
                         Color(red: 0.91, green: 0.94, blue: 0.99)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
    private var holeColor: Color { isDark
        ? Color(red: 0.07, green: 0.08, blue: 0.13)
        : Color(red: 0.93, green: 0.95, blue: 0.99) }
    private var labelColor: Color  { isDark ? Color.white.opacity(0.45) : Color(red: 0.3, green: 0.35, blue: 0.5) }
    private var valueColor: Color  { isDark ? .white : Color(red: 0.12, green: 0.14, blue: 0.20) }
    private var subColor:   Color  { isDark ? Color.white.opacity(0.38) : Color(red: 0.5, green: 0.55, blue: 0.65) }
    private var borderColor: Color { isDark
        ? Color(red: 0.165, green: 0.184, blue: 0.259)
        : Color(red: 0.84, green: 0.88, blue: 0.95) }

    private let colors:      [Color]   = [Color.m1Primary, Color.m1Grey, Color.m1Green]
    private let outerRatios: [CGFloat] = [0.98, 1.03, 1.01]
    private let labels:      [String]  = ["REVENUE", "EXPENSES", "PROFIT"]
    private let values:      [String]  = ["R1.6M",   "R586k",   "R814k"]
    private let icons:       [String]  = ["icon-revenue-wallet", "icon-expenses-arrow", "icon-profit-up"]
    private let percents:    [Int]     = [50, 19, 31]
    private let st: [Double] = [0.00, 0.50, 0.69]
    private let en: [Double] = [0.50, 0.69, 1.00]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(cardBg)

            // Glow blobs (more subtle in light mode)
            Circle().fill(Color.m1Primary)
                .frame(width: 140, height: 140).blur(radius: 50)
                .offset(x: 30, y: -45).opacity(isDark ? 0.26 : 0.08)
            Circle().fill(Color(red: 0.0, green: 0.48, blue: 1.0))
                .frame(width: 100, height: 100).blur(radius: 55)
                .offset(x: -90, y: 50).opacity(isDark ? 0.16 : 0.06)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.5)

            VStack(alignment: .leading, spacing: 0) {
                Text("FINANCIAL OVERVIEW")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(labelColor)
                    .padding(.bottom, 8)

                HStack(alignment: .center, spacing: 14) {
                    // ── Donut ──────────────────────────────────────────
                    GeometryReader { proxy in
                        let size        = min(proxy.size.width, proxy.size.height)
                        let center      = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        let labelRadius = size * 0.39

                        ZStack {
                            ForEach(0..<3, id: \.self) { k in
                                let mid   = (st[k] + en[k]) / 2
                                let angle = (mid * 360 - 90) * .pi / 180
                                let lp    = CGPoint(
                                    x: center.x + CGFloat(cos(angle)) * labelRadius,
                                    y: center.y + CGFloat(sin(angle)) * labelRadius)

                                MockDonutSegment(startFraction: st[k], endFraction: en[k],
                                                 innerRatio: 0.48, outerRatio: outerRatios[k])
                                    .fill(colors[k])
                                    .shadow(color: .black.opacity(isDark ? 0.42 : 0.18), radius: 9, x: 0, y: 6)

                                Text("\(percents[k])%")
                                    .font(.system(size: 10, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                    .minimumScaleFactor(0.65).lineLimit(1)
                                    .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
                                    .frame(width: 48, height: 28).position(lp)
                            }

                            Circle()
                                .fill(holeColor)
                                .frame(width: size * 0.50, height: size * 0.50)
                                .shadow(color: .black.opacity(isDark ? 0.78 : 0.12), radius: 14, x: 0, y: 8)
                                .shadow(color: .black.opacity(isDark ? 0.34 : 0.06), radius: 4,  x: 0, y: 2)

                            VStack(spacing: 2) {
                                Text("NET").font(.system(size: 8, weight: .black)).tracking(0.5)
                                    .foregroundStyle(labelColor)
                                Text("R814k").font(.system(size: 15, weight: .black, design: .rounded))
                                    .foregroundStyle(Color.m1Green).minimumScaleFactor(0.6).lineLimit(1)
                                Text("profit").font(.system(size: 8))
                                    .foregroundStyle(subColor)
                            }
                        }
                    }
                    .frame(width: 172, height: 172)

                    // ── Legend ─────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(0..<3, id: \.self) { k in
                            HStack(alignment: .center, spacing: 8) {
                                RoundedRectangle(cornerRadius: 2).fill(colors[k]).frame(width: 3, height: 34)
                                Image(icons[k]).resizable().renderingMode(.template)
                                    .foregroundStyle(colors[k]).frame(width: 24, height: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(labels[k])
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundStyle(labelColor)
                                    Text(values[k])
                                        .font(.system(size: 15, weight: .black, design: .rounded))
                                        .foregroundStyle(valueColor)
                                        .minimumScaleFactor(0.65).lineLimit(1)
                                    Text("\(percents[k])% of total")
                                        .font(.system(size: 8.5, weight: .medium))
                                        .foregroundStyle(subColor).lineLimit(1)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxHeight: .infinity)

            // Bottom accent line
            VStack {
                Spacer()
                LinearGradient(colors: [Color.m1Primary, Color.m1Primary.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .frame(height: 246)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - LoginView

struct LoginView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.colorScheme) private var colorScheme

    @State private var step: LoginStep = .email
    @State private var email    = ""
    @State private var password = ""

    @State private var isCheckingEmail = false
    @State private var isSigningIn     = false
    @State private var passkeyLoading  = false
    @State private var errorMessage: String?

    private var p: LoginPalette { LoginPalette(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            logoSection
                .padding(.bottom, 20)

            FinancialOverviewCard()
                .padding(.horizontal, 20)

            statusBadge
                .padding(.top, 16)
                .padding(.bottom, 16)

            // Form: biometric only when session exists, otherwise email/passkey
            formCard
                .padding(.horizontal, 20)

            Spacer(minLength: 0)

            footerSection
                .padding(.bottom, 28)
        }
        .padding(.top, 52)
        .background(p.canvas.ignoresSafeArea())
    }

    // MARK: - Logo (wordmark only, no icon mark)

    private var logoSection: some View {
        Image("logo-wordmark")
            .resizable()
            .scaledToFit()
            .frame(height: 32)    // slightly bigger than before (was 22)
    }

    // MARK: - Status badge

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.m1Green).frame(width: 7, height: 7)
                .shadow(color: Color.m1Green.opacity(0.8), radius: 4)
            Text("Your business, in your pocket.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(p.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(p.surface2, in: Capsule())
        .overlay(Capsule().strokeBorder(p.border, lineWidth: 0.5))
    }

    // MARK: - Form card

    private var biometricIcon: String {
        auth.biometricType == .faceID ? "faceid" : "touchid"
    }
    private var biometricLabel: String {
        auth.biometricType == .faceID ? "Face ID" : "Touch ID"
    }

    private var formCard: some View {
        VStack(spacing: 0) {
            if auth.hasSavedSession {
                // ── Biometric-only card (no email/passkey needed) ──────
                VStack(spacing: 14) {
                    VStack(spacing: 4) {
                        Text("Welcome back")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(p.textPrimary)
                        Text("Use \(biometricLabel) to sign in")
                            .font(.system(size: 13))
                            .foregroundStyle(p.textSecondary)
                    }
                    .padding(.top, 20)

                    if let err = auth.biometricError {
                        Text(err).font(.caption)
                            .foregroundStyle(Color(red: 0.972, green: 0.427, blue: 0.427))
                            .multilineTextAlignment(.center).padding(.horizontal, 16)
                    }

                    biometricSection.padding(.horizontal, 20)
                }
                .padding(.bottom, 20)

            } else {
                // ── Email / password form ──────────────────────────────
                VStack(spacing: 4) {
                    Text(step == .email ? "Sign in" : "Enter password")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(p.textPrimary)
                    Text(step == .email ? "Access your MainOne workspace" : email)
                        .font(.system(size: 13)).foregroundStyle(p.textSecondary).lineLimit(1)
                }
                .padding(.top, 20).padding(.bottom, 16)

                if let err = errorMessage {
                    Text(err).font(.caption)
                        .foregroundStyle(Color(red: 0.972, green: 0.427, blue: 0.427))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16).padding(.bottom, 10)
                }

                VStack(spacing: 12) {
                    if step == .email {
                        styledField(placeholder: "Email address", text: $email,
                                    keyboard: .emailAddress, content: .emailAddress)
                    } else {
                        styledSecureField(placeholder: "Password", text: $password)
                    }

                    Button { Task { await primaryAction() } } label: {
                        ZStack {
                            if isCheckingEmail || isSigningIn { ProgressView().tint(.white) }
                            else {
                                Text(step == .email ? "Continue" : "Sign in")
                                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(
                            LinearGradient(colors: [Color.m1Primary, Color.m1PrimaryH],
                                           startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: Color.m1Primary.opacity(0.45), radius: 12, x: 0, y: 6)
                    }
                    .disabled(isCheckingEmail || isSigningIn ||
                              (step == .email ? email.isEmpty : password.isEmpty))

                    if step == .password {
                        Button { withAnimation { step = .email; password = ""; errorMessage = nil } } label: {
                            Text("← Use a different email").font(.system(size: 13))
                                .foregroundStyle(p.textMuted)
                        }
                    }
                }
                .padding(.horizontal, 20)

                if step == .email {
                    HStack(spacing: 10) {
                        Rectangle().fill(p.border).frame(height: 0.5)
                        Text("or").font(.caption).foregroundStyle(p.textMuted)
                        Rectangle().fill(p.border).frame(height: 0.5)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14)

                    Button { Task { await passkeyAction() } } label: {
                        HStack(spacing: 8) {
                            if passkeyLoading { ProgressView().scaleEffect(0.8).tint(p.textPrimary) }
                            else {
                                Image(systemName: "touchid").font(.system(size: 16, weight: .medium))
                                Text("Sign in with Passkey").font(.system(size: 15, weight: .medium))
                            }
                        }
                        .foregroundStyle(p.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(p.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(p.border, lineWidth: 0.8))
                    }
                    .disabled(passkeyLoading).padding(.horizontal, 20)
                }

                Spacer().frame(height: 20)
            }
        }
        .background(p.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(p.border, lineWidth: 0.5))
    }

    // MARK: - Biometric section

    @State private var biometricLoading = false

    private var biometricSection: some View {
        VStack(spacing: 12) {
            // Face ID / Touch ID button
            Button {
                Task { await triggerBiometric() }
            } label: {
                HStack(spacing: 10) {
                    if biometricLoading {
                        ProgressView().tint(.white).scaleEffect(0.85)
                    } else {
                        Image(systemName: biometricIcon)
                            .font(.system(size: 18, weight: .medium))
                        Text("Sign in with \(biometricLabel)")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(colors: [Color.m1Primary, Color.m1PrimaryH],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .shadow(color: Color.m1Primary.opacity(0.40), radius: 10, x: 0, y: 5)
            }
            .disabled(biometricLoading)

            // Biometric error
            if let err = auth.biometricError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.972, green: 0.427, blue: 0.427))
                    .multilineTextAlignment(.center)
            }

            // Divider between biometric and password form
            HStack(spacing: 10) {
                Rectangle().fill(p.border).frame(height: 0.5)
                Text("or sign in with password")
                    .font(.system(size: 11))
                    .foregroundStyle(p.textMuted)
                    .fixedSize()
                Rectangle().fill(p.border).frame(height: 0.5)
            }
        }
    }

    private func triggerBiometric() async {
        biometricLoading = true
        await auth.authenticateWithBiometrics()
        biometricLoading = false
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Circle().fill(Color.m1Green).frame(width: 5, height: 5)
                Text("Connected to MainOne")
                    .font(.system(size: 11))
                    .foregroundStyle(p.textMuted)
            }
            Text("MainOne v1.0")
                .font(.system(size: 10))
                .foregroundStyle(p.textMuted.opacity(0.6))
        }
    }

    // MARK: - Styled inputs

    @ViewBuilder
    private func styledField(placeholder: String, text: Binding<String>,
                             keyboard: UIKeyboardType = .default,
                             content: UITextContentType? = nil) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .textContentType(content)
            .autocapitalization(.none)
            .autocorrectionDisabled()
            .foregroundStyle(p.textPrimary)
            .tint(Color.m1Primary)
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(p.inputBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(p.border, lineWidth: 0.8)
            )
    }

    @ViewBuilder
    private func styledSecureField(placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .textContentType(.password)
            .foregroundStyle(p.textPrimary)
            .tint(Color.m1Primary)
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(p.inputBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(p.border, lineWidth: 0.8)
            )
    }

    // MARK: - Actions

    private func primaryAction() async {
        errorMessage = nil
        if step == .email {
            guard !email.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            withAnimation { step = .password }
        } else {
            isSigningIn = true
            do {
                try await auth.login(email: email, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSigningIn = false
        }
    }

    private func passkeyAction() async {
        errorMessage = nil
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Enter your email first"
            return
        }
        passkeyLoading = true
        do {
            try await auth.loginWithPasskey(email: email)
        } catch let e as NSError
            where e.domain == "com.apple.AuthenticationServices.AuthorizationError" {
            if e.code != 1001 {   // 1001 = user cancelled — ignore silently
                errorMessage = "Passkey sign-in failed. Try password instead."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        passkeyLoading = false
    }
}

// MARK: - MfaView

struct MfaView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.colorScheme) private var colorScheme
    @State private var code = ""
    @State private var isVerifying = false
    @State private var errorMessage: String?

    private var p: LoginPalette { LoginPalette(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Wordmark only — no icon mark
            Image("logo-wordmark")
                .resizable()
                .scaledToFit()
                .frame(height: 28)
                .padding(.bottom, 28)

            // Card
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("Two-Factor Auth")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(p.textPrimary)
                    Text("Enter the 6-digit code from your authenticator app")
                        .font(.system(size: 13))
                        .foregroundStyle(p.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 22)

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.972, green: 0.427, blue: 0.427))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                TextField("000000", text: $code)
                    .keyboardType(.numberPad)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(p.textPrimary)
                    .tint(Color.m1Primary)
                    .padding(.horizontal, 20)
                    .frame(height: 64)
                    .background(p.inputBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(p.border, lineWidth: 0.8))
                    .onChange(of: code) { newValue in
                        let digits = newValue.filter(\.isNumber)
                        if digits.count > 6 { code = String(digits.prefix(6)); return }
                        code = digits
                        if code.count == 6 { Task { await verify() } }
                    }
                    .padding(.horizontal, 20)

                Button { Task { await verify() } } label: {
                    ZStack {
                        if isVerifying {
                            ProgressView().tint(.white)
                        } else {
                            Text("Verify")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(
                        LinearGradient(colors: [Color.m1Primary, Color.m1PrimaryH],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .shadow(color: Color.m1Primary.opacity(0.45), radius: 12, x: 0, y: 6)
                }
                .disabled(code.count < 6 || isVerifying)
                .padding(.horizontal, 20)

                Button { auth.cancelMfa() } label: {
                    Text("Cancel")
                        .font(.system(size: 13))
                        .foregroundStyle(p.textMuted)
                }
                .padding(.bottom, 22)
            }
            .background(p.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(p.border, lineWidth: 0.5))
            .padding(.horizontal, 24)

            Spacer()
        }
        .background(p.canvas.ignoresSafeArea())
    }

    private func verify() async {
        guard code.count == 6 else { return }
        isVerifying = true; errorMessage = nil
        do {
            try await auth.verifyMfa(code: code)
        } catch {
            errorMessage = error.localizedDescription
            code = ""
        }
        isVerifying = false
    }
}

// MARK: - LoginRootView

struct LoginRootView: View {
    @EnvironmentObject var auth: AuthService

    var body: some View {
        Group {
            if auth.mfaPending {
                MfaView()
                    .transition(.asymmetric(
                        insertion:  .move(edge: .trailing),
                        removal:    .move(edge: .leading)
                    ))
            } else {
                LoginView()
                    .transition(.asymmetric(
                        insertion:  .move(edge: .leading),
                        removal:    .move(edge: .trailing)
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: auth.mfaPending)
    }
}
