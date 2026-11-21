// ─────────────────────────────────────────────────────────────
// Wspólny plik serii BH – oryginał: ~/Developer/shared/BHStyle/Credits.swift
// W projektach jest KOPIA (Sources/_shared), nadpisywana przy każdym budowaniu.
// Zmiany wprowadzaj tylko w ~/Developer/shared.
// ─────────────────────────────────────────────────────────────
import SwiftUI
import AppKit

/// Informacja o autorze i wersji – w stopce okna i w „O programie…”
enum Credits {
    static let author = "Bronisław Hońca"
    static let year = "2026"
    static let email = "kontakt@bronislawhonca.pl"

    /// Wersja z Info.plist (VERSION w build.sh / MARKETING_VERSION w Xcode)
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// Numer kompilacji – pokazywany tylko, gdy różni się od wersji
    static var build: String? {
        guard let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              b != version else { return nil }
        return b
    }

    static var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? ProcessInfo.processInfo.processName
    }

    /// Tekst do zgłoszeń błędów, np. „BH AU Host 1.1 (12) · macOS 27.0.1 · Apple Silicon”
    static var versionReport: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osText = os.patchVersion > 0
            ? "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
            : "\(os.majorVersion).\(os.minorVersion)"
        #if arch(arm64)
        let chip = "Apple Silicon"
        #else
        let chip = "Intel"
        #endif
        let ver = version + (build.map { " (\($0))" } ?? "")
        return "\(appName) \(ver) · macOS \(osText) · \(chip)"
    }

    static func copyVersionReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(versionReport, forType: .string)
    }

    static func showAboutPanel() {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center

        let credits = NSMutableAttributedString(
            string: tr("Pomysł i koncepcja", "Idea and concept") + ": \(author), \(year)\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.labelColor])
        if let mail = URL(string: "mailto:\(email)") {
            credits.append(NSAttributedString(
                string: email,
                attributes: [.font: NSFont.systemFont(ofSize: 11), .link: mail]))
        }
        credits.addAttribute(.paragraphStyle, value: centered,
                             range: NSRange(location: 0, length: credits.length))

        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Stan przycisku wersji (bez @State – makra SwiftUI nie działają przy samych narzędziach wiersza poleceń)
final class VersionBadgeState: ObservableObject {
    @Published var hovering = false
    @Published var copied = false
}

/// Stopka w głównym oknie: „© 2026 Bronisław Hońca · kontakt@… · v1.1”
/// Kliknięcie w wersję kopiuje do schowka informację do zgłoszeń błędów.
struct CreditsFooter: View {
    @StateObject private var badge = VersionBadgeState()

    var body: some View {
        HStack(spacing: 4) {
            Text("© \(Credits.year) \(Credits.author)")
                .foregroundColor(Theme.faint)
            Text("·").foregroundColor(Theme.faint)
            if let mail = URL(string: "mailto:\(Credits.email)") {
                Link(Credits.email, destination: mail)
                    .foregroundColor(Theme.accent)
            }
            Text("·").foregroundColor(Theme.faint)
            Button {
                Credits.copyVersionReport()
                badge.copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { badge.copied = false }
            } label: {
                Text(badge.copied ? tr("skopiowano ✓", "copied ✓") : "v\(Credits.version)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(badge.copied || badge.hovering ? Theme.accent : Theme.faint)
            }
            .buttonStyle(.plain)
            .onHover { badge.hovering = $0 }
            .help(tr("Kliknij, aby skopiować informacje o wersji (do zgłoszenia błędu)",
                     "Click to copy version info (for bug reports)"))
        }
        .font(.caption2)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
