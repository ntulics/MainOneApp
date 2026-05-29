import SwiftUI

// MARK: - Login step

private enum LoginStep { case email, password }

// MARK: - Brand tokens

private extension Color {
    /// Primary blue    #1366EF
    static let m1Primary   = Color(red: 0.075, green: 0.400, blue: 0.937)
    /// Blue hover      #0F56DE
    static let m1PrimaryH  = Color(red: 0.059, green: 0.337, blue: 0.871)
    /// CTA amber       #FFB400
    static let m1CTA       = Color(red: 1.000, green: 0.706, blue: 0.000)
    /// Dark canvas     #0D0F18
    static let m1Canvas    = Color(red: 0.051, green: 0.059, blue: 0.094)
    /// Dark surface    #151821
    static let m1Surface   = Color(red: 0.082, green: 0.094, blue: 0.129)
    /// Dark surface 2  #1C202E
    static let m1Surface2  = Color(red: 0.110, green: 0.125, blue: 0.180)
    /// Border          #2A2F42
    static let m1Border    = Color(red: 0.165, green: 0.184, blue: 0.259)
    /// Revenue orange  #F59E0B
    static let m1Orange    = Color(red: 0.961, green: 0.620, blue: 0.043)
    /// Profit green    #22C55E
    static let m1Green     = Color(red: 0.133, green: 0.773, blue: 0.369)
    /// Expenses grey
    static let m1Grey      = Color(red: 0.380, green: 0.400, blue: 0.450)
}

// MARK: - Donut chart helper

private struct DonutSegment {
    let color: Color
    let fraction: Double   // 0…1
}

private struct DonutChart: View {
    let segments: [DonutSegment]
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                    let start = segments.prefix(idx).reduce(0) { $0 + $1.fraction }
                    // 2° gap between segments (0.0055 of full circle)
                    let gap: Double = 0.006
                    Circle()
                        .trim(from: start + gap, to: start + seg.fraction - gap)
                        .stroke(seg.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: seg.color.opacity(0.55), radius: 6, x: 0, y: 3)
                }
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

// MARK: - Financial overview card (mock dashboard)

private struct FinancialOverviewCard: View {

    var body: some View {
        VStack(spacing: 8) {

            // ── Financial Overview ─────────────────────────────────────
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.m1Surface)

                // Orange glow at bottom-left — matches real dashboard card
                Color.m1Orange.opacity(0.18)
                    .blur(radius: 40)
                    .frame(width: 140, height: 80)
                    .offset(x: -10, y: 10)
                    .clipped()

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.m1Border, lineWidth: 0.5)

                VStack(spacing: 0) {
                    // Header row
                    HStack {
                        Text("FINANCIAL OVERVIEW")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.6)
                            .foregroundStyle(Color.white.opacity(0.40))
                        Spacer()
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(i == 0 ? Color.white.opacity(0.80) : Color.white.opacity(0.20))
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                    // Chart + legend
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            DonutChart(
                                segments: [
                                    DonutSegment(color: .m1Orange, fraction: 0.52),
                                    DonutSegment(color: .m1Grey,   fraction: 0.19),
                                    DonutSegment(color: .m1Green,  fraction: 0.29),
                                ],
                                lineWidth: 19
                            )
                            VStack(spacing: 1) {
                                Text("NET")
                                    .font(.system(size: 7, weight: .semibold))
                                    .tracking(1.2)
                                    .foregroundStyle(Color.white.opacity(0.40))
                                Text("R814k")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Color.m1Green)
                                Text("profit")
                                    .font(.system(size: 7))
                                    .foregroundStyle(Color.white.opacity(0.35))
                            }
                            percentLabel("52%", angle: -90 + 360 * 0.26,  radius: 54)
                            percentLabel("19%", angle: -90 + 360 * 0.595, radius: 54)
                            percentLabel("29%", angle: -90 + 360 * 0.845, radius: 54)
                        }
                        .frame(width: 126, height: 126)

                        VStack(alignment: .leading, spacing: 7) {
                            legendRow(color: .m1Orange, label: "REVENUE",  value: "R1.6M", sub: "52% of total")
                            legendRow(color: .m1Grey,   label: "EXPENSES", value: "R586k", sub: "19% of total")
                            legendRow(color: .m1Green,  label: "PROFIT",   value: "R814k", sub: "29% of total")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
            .frame(height: 194)

            // ── Stat cards ─────────────────────────────────────────────
            HStack(spacing: 8) {
                statCard(dot: Color.m1Primary,
                         label: "OUTSTANDING", value: "R48k",
                         valueColor: Color.m1Primary)
                statCard(dot: Color(red: 0.94, green: 0.27, blue: 0.27),
                         label: "OVERDUE",     value: "R12k",
                         valueColor: Color(red: 0.94, green: 0.27, blue: 0.27))
                statCard(dot: Color.m1CTA,
                         label: "UPCOMING",    value: "R95k",
                         valueColor: Color.m1CTA)
            }

            // ── Top Expenses ───────────────────────────────────────────
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.m1Surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.m1Border, lineWidth: 0.5)
                    )

                // Amber glow at bottom — matches real dashboard
                Color.m1Orange.opacity(0.15)
                    .blur(radius: 30)
                    .frame(height: 24)
                    .frame(maxWidth: .infinity)
                    .offset(y: 28)

                VStack(spacing: 0) {
                    HStack {
                        Text("TOP · EXPENSES")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(Color.white.opacity(0.40))
                        Spacer()
                        Text("VIEW ALL →")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(Color.m1Primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    ForEach(Array(expenseRows.enumerated()), id: \.offset) { idx, row in
                        HStack(spacing: 10) {
                            Text("\(idx + 1)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.30))
                                .frame(width: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.0)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(row.1)
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.white.opacity(0.35))
                            }
                            Spacer()
                            Text(row.2)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.85))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)

                        if idx < expenseRows.count - 1 {
                            Divider()
                                .background(Color.m1Border)
                                .padding(.horizontal, 14)
                        }
                    }

                    Spacer().frame(height: 10)
                }
            }

            // ── Top Customers ──────────────────────────────────────────
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.m1Surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.m1Border, lineWidth: 0.5)
                    )

                VStack(spacing: 0) {
                    HStack {
                        Text("TOP · CUSTOMERS")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(Color.white.opacity(0.40))
                        Spacer()
                        Text("CRM →")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(Color.m1Primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    ForEach(Array(customerRows.enumerated()), id: \.offset) { idx, row in
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(row.2.opacity(0.18))
                                    .frame(width: 26, height: 26)
                                Text(row.0.prefix(2).uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(row.2)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.0)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(row.1)
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.white.opacity(0.35))
                            }
                            Spacer()
                            Text(row.3)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.85))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)

                        if idx < customerRows.count - 1 {
                            Divider()
                                .background(Color.m1Border)
                                .padding(.horizontal, 14)
                        }
                    }

                    Spacer().frame(height: 10)
                }
            }
        }
    }

    // MARK: - Mock data

    private let expenseRows: [(String, String, String)] = [
        ("Scoop Distribution",  "19 May 2026", "R386k"),
        ("Fleet Services SA",   "12 May 2026", "R94k"),
        ("TechPro Solutions",   "08 May 2026", "R47k"),
        ("Office Depot SA",     "02 May 2026", "R28k"),
    ]

    private let customerRows: [(String, String, Color, String)] = [
        ("Nexus Logistics",   "14 invoices",  Color.m1Primary, "R420k"),
        ("BrightEdge Media",  "9 invoices",   Color.m1Green,   "R318k"),
        ("Kibo Industries",   "11 invoices",  Color.m1CTA,     "R275k"),
        ("Apex Retail Group", "7 invoices",   Color(red: 0.68, green: 0.32, blue: 0.98), "R189k"),
    ]

    // MARK: - Helpers

    @ViewBuilder
    private func percentLabel(_ text: String, angle: Double, radius: CGFloat) -> some View {
        let rad = angle * .pi / 180
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .offset(x: radius * CGFloat(cos(rad)),
                    y: radius * CGFloat(sin(rad)))
    }

    @ViewBuilder
    private func legendRow(color: Color, label: String, value: String, sub: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.white.opacity(0.40))
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text(sub)
                    .font(.system(size: 8))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
        }
    }

    @ViewBuilder
    private func statCard(dot: Color, label: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.white.opacity(0.40))
            }
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.m1Surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.m1Border, lineWidth: 0.5)
        )
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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // ── Logo ────────────────────────────────────────────────
                logoSection
                    .padding(.top, 52)
                    .padding(.bottom, 28)

                // ── Mock financial dashboard ────────────────────────────
                FinancialOverviewCard()
                    .padding(.horizontal, 20)

                // ── Status badge ────────────────────────────────────────
                statusBadge
                    .padding(.top, 20)
                    .padding(.bottom, 20)

                // ── Sign-in form card ───────────────────────────────────
                formCard
                    .padding(.horizontal, 20)

                // ── Footer ──────────────────────────────────────────────
                footerSection
                    .padding(.top, 28)
                    .padding(.bottom, 40)
            }
        }
        .background(Color.m1Canvas.ignoresSafeArea())
    }

    // MARK: - Logo

    private var logoSection: some View {
        HStack(spacing: 12) {
            Image("logo-mark")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .environment(\.colorScheme, .dark)

            Image("logo-wordmark")
                .resizable()
                .scaledToFit()
                .frame(height: 22)
                .environment(\.colorScheme, .dark)
        }
    }

    // MARK: - Status badge

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.m1Green).frame(width: 7, height: 7)
                .shadow(color: Color.m1Green.opacity(0.8), radius: 4)
            Text("Your business, in your pocket.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.65))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.m1Surface2, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.m1Border, lineWidth: 0.5))
    }

    // MARK: - Form card

    private var formCard: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text(step == .email ? "Sign in" : "Enter password")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text(step == .email
                     ? "Access your MainOne workspace"
                     : email)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineLimit(1)
            }
            .padding(.top, 22)
            .padding(.bottom, 18)

            // Error
            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.972, green: 0.427, blue: 0.427))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            // Fields
            VStack(spacing: 12) {
                if step == .email {
                    styledField(placeholder: "Email address", text: $email, keyboard: .emailAddress, content: .emailAddress)
                } else {
                    styledSecureField(placeholder: "Password", text: $password)
                }

                // Primary action button
                Button { Task { await primaryAction() } } label: {
                    ZStack {
                        if isCheckingEmail || isSigningIn {
                            ProgressView().tint(.white)
                        } else {
                            Text(step == .email ? "Continue" : "Sign in")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(colors: [Color.m1Primary, Color.m1PrimaryH],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .shadow(color: Color.m1Primary.opacity(0.45), radius: 12, x: 0, y: 6)
                }
                .disabled(isCheckingEmail || isSigningIn || (step == .email ? email.isEmpty : password.isEmpty))

                // Back button (password step)
                if step == .password {
                    Button { withAnimation { step = .email; password = ""; errorMessage = nil } } label: {
                        Text("← Use a different email")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                }
            }
            .padding(.horizontal, 20)

            // Passkey divider + button
            if step == .email {
                HStack(spacing: 10) {
                    Rectangle().fill(Color.m1Border).frame(height: 0.5)
                    Text("or").font(.caption).foregroundStyle(Color.white.opacity(0.30))
                    Rectangle().fill(Color.m1Border).frame(height: 0.5)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                Button { Task { await passkeyAction() } } label: {
                    HStack(spacing: 8) {
                        if passkeyLoading {
                            ProgressView().scaleEffect(0.8).tint(.white)
                        } else {
                            Image(systemName: "touchid")
                                .font(.system(size: 16, weight: .medium))
                            Text("Sign in with Passkey")
                                .font(.system(size: 15, weight: .medium))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.m1Surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.m1Border, lineWidth: 0.8)
                    )
                }
                .disabled(passkeyLoading)
                .padding(.horizontal, 20)
            }

            Spacer().frame(height: 22)
        }
        .background(Color.m1Surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.m1Border, lineWidth: 0.5)
        )
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Circle().fill(Color.m1Green).frame(width: 5, height: 5)
                Text("Connected to MainOne")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            Text("MainOne v1.0")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.20))
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
            .foregroundStyle(.white)
            .tint(Color.m1CTA)
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(Color.m1Canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.m1Border, lineWidth: 0.8)
            )
    }

    @ViewBuilder
    private func styledSecureField(placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .textContentType(.password)
            .foregroundStyle(.white)
            .tint(Color.m1CTA)
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(Color.m1Canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.m1Border, lineWidth: 0.8)
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
    @State private var code = ""
    @State private var isVerifying = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            Image("logo-mark")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .environment(\.colorScheme, .dark)
                .padding(.bottom, 28)

            // Card
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("Two-Factor Auth")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Enter the 6-digit code from your authenticator app")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.50))
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
                    .foregroundStyle(.white)
                    .tint(Color.m1CTA)
                    .padding(.horizontal, 20)
                    .frame(height: 64)
                    .background(Color.m1Canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.m1Border, lineWidth: 0.8)
                    )
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
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
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
                        .foregroundStyle(Color.white.opacity(0.40))
                }
                .padding(.bottom, 22)
            }
            .background(Color.m1Surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.m1Border, lineWidth: 0.5)
            )
            .padding(.horizontal, 24)

            Spacer()
        }
        .background(Color.m1Canvas.ignoresSafeArea())
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
