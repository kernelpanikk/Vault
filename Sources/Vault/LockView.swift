import SwiftUI

struct LockView: View {
    @Environment(AppModel.self) private var model
    @State private var password = ""
    @State private var confirm = ""
    @State private var attempts = 0
    @FocusState private var focused: Bool

    private var setup: Bool { model.state == .setup }
    private var canSubmit: Bool {
        !model.busy && (setup ? password.count >= 8 && password == confirm : !password.isEmpty)
    }

    var body: some View {
        VStack(spacing: Theme.gap) {
            Image(systemName: "lock.fill").font(Theme.lockIcon).foregroundStyle(.secondary)
            Text(setup ? "Crea l'archivio" : "Archivio bloccato").font(Theme.title)

            SecureField(setup ? "Master password (min. 8)" : "Password", text: $password)
                .focused($focused)
                .onSubmit(submit)
            if setup {
                SecureField("Conferma", text: $confirm).onSubmit(submit)
                ProgressView(value: strength(password)).tint(strength(password) < 0.5 ? .orange : .green)
                Text("Se la dimentichi, i file non si recuperano.")
                    .font(Theme.caption).foregroundStyle(.secondary)
            }
            if let error = model.error {
                Text(error).font(Theme.caption).foregroundStyle(Theme.error)
            }

            Button(setup ? "Crea archivio" : "Sblocca", action: submit)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            if !setup && Biometrics.available {
                Button("Usa Touch ID") { Task { await model.unlockWithBiometrics() } }
                    .buttonStyle(.link)
            }
        }
        .textFieldStyle(.roundedBorder)
        .frame(width: Theme.lockWidth)
        .padding(Theme.padding * 1.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity) // fill the window so it stays resizable
        .modifier(Shake(animatableData: CGFloat(attempts)))
        .onChange(of: model.error) { _, error in
            guard error != nil else { return }
            password = ""
            withAnimation(.linear(duration: 0.4)) { attempts += 1 }
        }
        .task {
            focused = true
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

/// Horizontal shake on a wrong password, instead of a popup.
struct Shake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}
