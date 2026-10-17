import SwiftUI

/// The only screen while locked: no thumbnails, no names, just the way in.
struct LockView: View {
    @Environment(AppModel.self) private var model
    @State private var password = ""
    @State private var confirm = ""
    @State private var attempts = 0

    private var setup: Bool { model.state == .setup }
    private var canSubmit: Bool {
        !model.busy && (setup ? password.count >= 8 && password == confirm : !password.isEmpty)
    }

    var body: some View {
        VStack(spacing: Theme.space6) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
            VStack(spacing: Theme.space2) {
                Text(setup ? "Crea l'archivio" : "Vault è bloccato").font(Theme.display).foregroundStyle(Theme.ink)
                Text(setup ? "Scegli la master password. Se la dimentichi, i file non si recuperano."
                           : "Cifrato solo su questo Mac")
                    .font(Theme.body).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
            }

            if !setup && TouchID.available {
                Button { Task { await model.unlockWithBiometrics() } } label: {
                    Theme.icon("fingerprint", size: 32).foregroundStyle(Theme.brass)
                        .frame(width: 64, height: 64)
                        .overlay(Circle().strokeBorder(Theme.brass, lineWidth: 1.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sblocca con Touch ID")
                HStack(spacing: Theme.space3) {
                    Rectangle().fill(Theme.line).frame(height: 1)
                    Text("oppure usa la master password").font(Theme.caption).foregroundStyle(Theme.inkMuted).fixedSize()
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
            }

            VStack(spacing: Theme.space3) {
                PasswordField(placeholder: setup ? "Master password (min. 8)" : "Master password",
                              text: $password, error: model.error != nil, autofocus: true, onSubmit: submit)
                if setup {
                    PasswordField(placeholder: "Ripeti la password", text: $confirm, error: false, onSubmit: submit)
                    ProgressView(value: strength(password)).tint(strength(password) < 0.5 ? Theme.danger : Theme.brass)
                }
                if let error = model.error {
                    HStack(spacing: Theme.space1) {
                        Theme.icon("warning", size: 14)
                        Text(error)
                    }
                    .font(Theme.caption).foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(setup ? "Crea archivio" : "Sblocca", action: submit)
                    .buttonStyle(PrimaryButton(large: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
        }
        .frame(width: Theme.lockColumn)
        .padding(Theme.space12)
        .modifier(Shake(animatableData: CGFloat(attempts)))
        .frame(maxWidth: .infinity, maxHeight: .infinity) // fill the window so it stays resizable
        .background(Theme.bg)
        .onChange(of: model.error) { _, error in
            guard error != nil else { return }
            password = ""
            withAnimation(.linear(duration: 0.4)) { attempts += 1 }
        }
        .task {
            #if DEBUG // screenshots of a throwaway vault: VAULT_DIR=… VAULT_TEST_PASSWORD=… Vault
            if let test = ProcessInfo.processInfo.environment["VAULT_TEST_PASSWORD"] { return await model.unlock(password: test, remember: false) }
            #endif
            if NSApp.isActive { await model.unlockWithBiometrics() }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        Task {
            await model.unlock(password: password)
            password = ""
            confirm = ""
        }
    }

    /// Rough guide only: length weighs most, character variety a little.
    private func strength(_ s: String) -> Double {
        let classes: [CharacterSet] = [.lowercaseLetters, .uppercaseLetters, .decimalDigits, .punctuationCharacters.union(.symbols)]
        let used = classes.filter { set in s.unicodeScalars.contains { set.contains($0) } }.count
        return min(1, Double(s.count) / 16 * 0.7 + Double(used) / 4 * 0.3)
    }
}

/// Masked field: `key` icon, `line-strong` border, `brass` when focused, `danger` on error.
struct PasswordField: View {
    let placeholder: String
    @Binding var text: String
    let error: Bool
    var autofocus = false
    let onSubmit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.space2) {
            Theme.icon("key").foregroundStyle(Theme.inkMuted)
            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Theme.headline.weight(.regular))
                .foregroundStyle(Theme.ink)
                .focused($focused)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, Theme.space3)
        .frame(height: Theme.controlHLg)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusMd)
                .strokeBorder(error ? Theme.danger : focused ? Theme.brass : Theme.lineStrong,
                              lineWidth: focused || error ? 2 : 1)
        }
        .onAppear { if autofocus { focused = true } }
    }
}

/// Horizontal shake on a wrong password, instead of a popup.
struct Shake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}
