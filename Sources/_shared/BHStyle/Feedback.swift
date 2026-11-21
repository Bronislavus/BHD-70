// ─────────────────────────────────────────────────────────────
// Wspólny plik serii BH – oryginał: ~/Developer/shared/BHStyle/Feedback.swift
// W projektach jest KOPIA (Sources/_shared), nadpisywana przy każdym budowaniu.
// Zmiany wprowadzaj tylko w ~/Developer/shared.
//
// Okno „Zgłoś błąd lub pomysł” (PL/EN): zachęca do napisania na adres z Credits.email,
// otwiera gotowy e-mail (mailto:) z danymi technicznymi i niczego nie wysyła samo.
//
// Podłączenie w App:
//   Window(tr("Zgłoś błąd lub pomysł", "Report a Problem or Idea"), id: FeedbackWindow.id) {
//       FeedbackView(extraInfo: { … opcjonalne dane programu … }).themedWindow()
//   }
//   .windowResizability(.contentSize)
//   w głównym oknie:  .feedbackAtLaunch(releases: ["1.0"])
//                     – okno wyskakuje tylko przy pierwszym uruchomieniu wymienionych wersji (X.Y);
//                       każdy program sam decyduje, czy w ogóle go chce (bez parametru się nie skompiluje)
//   w menu Pomoc:     FeedbackMenuItem()
// ─────────────────────────────────────────────────────────────
import SwiftUI
import AppKit

enum FeedbackWindow {
    static let id = "feedback"
}

enum Feedback {
    static let skipKey = "feedback.skipAtLaunch"
    static let lastShownKey = "feedback.lastShownVersion"

    private static func info(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
    }

    static var appName: String {
        let display = info("CFBundleDisplayName")
        if !display.isEmpty { return display }
        let name = info("CFBundleName")
        return name.isEmpty ? "BH" : name
    }

    static var version: String {
        let v = info("CFBundleShortVersionString")
        return v.isEmpty ? "?" : v
    }

    static var build: String { info("CFBundleVersion") }

    /// „1.0.3” → „1.0”: okno wraca przy nowej wersji głównej lub pomocniczej, nie przy każdej łatce
    static var releaseLine: String {
        version.split(separator: ".").prefix(2).joined(separator: ".")
    }

    /// Tylko dla wymienionych wersji (np. ["1.0"]), raz, i o ile użytkownik tego nie wyłączył
    static func shouldShowAtLaunch(releases: [String]) -> Bool {
        guard releases.contains(releaseLine) else { return false }
        let d = UserDefaults.standard
        if d.bool(forKey: skipKey) { return false }
        return d.string(forKey: lastShownKey) != releaseLine
    }

    static func markShown() {
        UserDefaults.standard.set(releaseLine, forKey: lastShownKey)
    }

    // MARK: - Dane techniczne

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    /// Wersja programu i systemu, model komputera, język; `extra` – dane specyficzne dla programu
    static func diagnostics(extra: String = "") -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let model = sysctlString("hw.model") ?? "?"
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        var lines = [
            "\(appName) \(version) (\(build))",
            "macOS: \(os)",
            tr("Komputer", "Mac") + ": \(model) · \(arch)",
            tr("Język programu", "App language") + ": " + (Lang.isPolish ? "pl" : "en"),
        ]
        let more = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !more.isEmpty { lines.append(more) }
        return lines.joined(separator: "\n")
    }

    // MARK: - E-mail

    static var subject: String {
        "\(appName) \(version) – " + tr("zgłoszenie", "feedback")
    }

    static func mailBody(extra: String) -> String {
        let intro = tr(
            "Opisz, co się stało: jaka czynność poprzedziła problem i co miało się wydarzyć.\nJeśli to możliwe, napisz też, jakich urządzeń używasz.",
            "Please describe what happened: what you were doing before the problem and what you expected to happen.\nIf you can, also tell me which devices you use.")
        let marker = tr("— Dane techniczne (możesz je usunąć) —", "— Technical info (you can delete it) —")
        return intro + "\n\n\n\n" + marker + "\n" + diagnostics(extra: extra) + "\n"
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func mailURL(extra: String) -> URL? {
        func enc(_ s: String) -> String {
            s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
        }
        return URL(string: "mailto:\(Credits.email)?subject=\(enc(subject))&body=\(enc(mailBody(extra: extra)))")
    }

    /// Otwiera domyślny program pocztowy z gotowym szkicem. false = nie udało się (brak programu pocztowego).
    @discardableResult
    static func compose(extra: String = "") -> Bool {
        guard let url = mailURL(extra: extra) else { return false }
        return NSWorkspace.shared.open(url)
    }

    static func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Okno

struct FeedbackView: View {
    /// Dane specyficzne dla programu (np. lista portów MIDI); wywoływane w chwili kliknięcia
    var extraInfo: () -> String = { "" }

    @AppStorage(Feedback.skipKey) private var skipAtLaunch = false
    @State private var message = ""
    @State private var messageIsWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                LevelGlyph().padding(.bottom, 4)
                Text(tr("ZGŁOSZENIA I POMYSŁY", "FEEDBACK & IDEAS"))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(2.2)
                    .foregroundColor(Theme.accent)
                BrandName(name: Feedback.appName, size: 26)
                Text(tr("Wersja \(Feedback.version)", "Version \(Feedback.version)"))
                    .font(.callout)
                    .foregroundColor(Theme.text2)
            }

            Text(md(tr(
                "To nowy program – u mnie działa dobrze, ale każdy komputer i każdy zestaw sprzętu jest inny. Jeśli coś nie działa, program się zawiesza, brakuje Ci jakiejś funkcji albo masz pomysł, **napisz do mnie**. Każda wiadomość pomaga.",
                "This is a new app – it works well here, but every computer and every setup is different. If something doesn't work, the app freezes, a feature is missing or you have an idea, **please write to me**. Every message helps.")))
                .foregroundColor(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox(tr("Co napisać", "What to include")) {
                VStack(alignment: .leading, spacing: 6) {
                    bullet(tr("co robiłeś, zanim coś poszło nie tak, i co miało się wydarzyć",
                              "what you were doing before it went wrong and what you expected"))
                    bullet(tr("jakich urządzeń używasz (marka i model)",
                              "which devices you use (make and model)"))
                    Text(tr("W wiadomości znajdziesz podstawowe dane techniczne (wersja programu i systemu, model komputera). Możesz je usunąć przed wysłaniem. Program niczego nie wysyła sam – to zwykły e-mail.",
                            "The message contains basic technical info (app and system version, Mac model). You can delete it before sending. The app never sends anything by itself – it is a plain e-mail."))
                        .font(.callout)
                        .foregroundColor(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "envelope")
                    .foregroundColor(Theme.faint)
                Text(Credits.email)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(Theme.accent)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                Button {
                    if Feedback.compose(extra: extraInfo()) {
                        message = ""
                    } else {
                        message = tr("Nie udało się otworzyć programu pocztowego. Skopiuj adres i napisz z dowolnej poczty, także w przeglądarce.",
                                     "Could not open a mail app. Copy the address and write from any mail service, also in a browser.")
                        messageIsWarning = true
                    }
                } label: {
                    Label(tr("Napisz e-mail", "Write an e-mail"), systemImage: "envelope.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

                Button(tr("Kopiuj adres", "Copy address")) {
                    Feedback.copyToPasteboard(Credits.email)
                    message = tr("Adres skopiowany.", "Address copied.")
                    messageIsWarning = false
                }
                Button(tr("Kopiuj dane techniczne", "Copy technical info")) {
                    Feedback.copyToPasteboard(Feedback.diagnostics(extra: extraInfo()))
                    message = tr("Dane techniczne skopiowane – wklej je do wiadomości.",
                                 "Technical info copied – paste it into your message.")
                    messageIsWarning = false
                }

                Spacer()

                Button(tr("Zamknij", "Close")) { NSApp.keyWindow?.close() }
                    .keyboardShortcut(.cancelAction)
            }

            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundColor(messageIsWarning ? .orange : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(Theme.line)

            VStack(alignment: .leading, spacing: 8) {
                Toggle(tr("Nie pokazuj tego okna przy starcie", "Don't show this window at launch"),
                       isOn: $skipAtLaunch)
                    .toggleStyle(.checkbox)
                Text(tr("Zawsze znajdziesz je w menu Pomoc → Zgłoś błąd lub pomysł…",
                        "You can always find it in the Help menu → Report a Problem or Idea…"))
                    .font(.caption)
                    .foregroundColor(Theme.faint)
                CreditsFooter().padding(.top, 4)
            }
        }
        .padding(24)
        .frame(width: 560)
        .groupBoxStyle(.themed)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(Theme.accent)
            Text(text)
                .foregroundColor(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Otwieranie

/// Pozycja w menu Pomoc
struct FeedbackMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button(tr("Zgłoś błąd lub pomysł…", "Report a Problem or Idea…")) {
            openWindow(id: FeedbackWindow.id)
        }
    }
}

/// Pokazuje okno przy pierwszym uruchomieniu wybranych wersji (X.Y), o ile użytkownik tego nie wyłączył
struct FeedbackAtLaunch: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    let releases: [String]

    func body(content: Content) -> some View {
        content.task {
            guard Feedback.shouldShowAtLaunch(releases: releases) else { return }
            Feedback.markShown()
            // chwila, żeby najpierw pojawiło się główne okno
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            openWindow(id: FeedbackWindow.id)
        }
    }
}

extension View {
    func feedbackAtLaunch(releases: [String]) -> some View { modifier(FeedbackAtLaunch(releases: releases)) }
}
