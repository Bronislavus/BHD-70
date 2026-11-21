// ─────────────────────────────────────────────────────────────
// Wspólny plik serii BH – oryginał: ~/Developer/shared/BHStyle/Help.swift
// W projektach jest KOPIA (Sources/_shared), nadpisywana przy każdym budowaniu.
// Zmiany wprowadzaj tylko w ~/Developer/shared.
// ─────────────────────────────────────────────────────────────
import SwiftUI

// Okno z instrukcją – treść w HelpContent.swift (osobna dla każdej aplikacji)

enum HelpWindow {
    static let id = "help"
}

struct HelpDoc {
    let title: String
    let lead: String
    let sections: [HelpSection]
}

struct HelpSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [HelpItem]
}

enum HelpItem {
    case step(String)                         // punkt numerowany
    case bullet(String)                       // punkt zwykły
    case note(String)                         // akapit
    case keys([(keys: String, action: String)]) // tabela skrótów; klawisze oddzielone spacjami
}

// MARK: - Widok

struct HelpView: View {
    let doc: HelpDoc

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    LevelGlyph().padding(.bottom, 4)
                    Text(tr("INSTRUKCJA", "USER GUIDE"))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(2.2)
                        .foregroundColor(Theme.accent)
                    BrandName(name: doc.title, size: 26)
                    Text(md(doc.lead))
                        .foregroundColor(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(doc.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title.uppercased())
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .tracking(1.6)
                            .foregroundColor(Theme.accent)
                        items(section.items)
                    }
                }

                Divider().overlay(Theme.line)
                CreditsFooter()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 420, idealHeight: 720)
    }

    @ViewBuilder
    private func items(_ list: [HelpItem]) -> some View {
        let numbers = stepNumbers(list)
        VStack(alignment: .leading, spacing: 7) {
            ForEach(list.indices, id: \.self) { i in
                switch list[i] {
                case .step(let text):
                    row(marker: "\(numbers[i]).", text: text, markerColor: Theme.accent)
                case .bullet(let text):
                    row(marker: "•", text: text, markerColor: Theme.faint)
                case .note(let text):
                    Text(md(text))
                        .font(.callout)
                        .foregroundColor(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                case .keys(let rows):
                    KeyTable(rows: rows)
                }
            }
        }
    }

    private func row(marker: String, text: String, markerColor: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Numer nigdy się nie łamie (na iPadzie większa czcionka nie mieściła „1.” w 20 pkt)
            Text(marker)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(markerColor)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 20, alignment: .trailing)
            Text(md(text))
                .foregroundColor(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepNumbers(_ list: [HelpItem]) -> [Int] {
        var n = 0
        return list.map { item in
            if case .step = item { n += 1 }
            return n
        }
    }
}

/// Pogrubienia i kursywy w stylu **tak** / *tak*
func md(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(s)
}

private struct KeyTable: View {
    let rows: [(keys: String, action: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(alignment: .center, spacing: 12) {
                    HStack(spacing: 4) {
                        ForEach(tokens(rows[i].keys).indices, id: \.self) { j in
                            let t = tokens(rows[i].keys)[j]
                            if t == "/" || t == "…" || t == "–" {
                                Text(t).foregroundColor(Theme.faint)
                            } else {
                                KeyCap(label: t)
                            }
                        }
                    }
                    .frame(width: 270, alignment: .leading)
                    Text(md(rows[i].action))
                        .foregroundColor(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.lineSoft).frame(height: 1)
                }
            }
        }
    }

    private func tokens(_ s: String) -> [String] {
        s.split(separator: " ").map(String.init)
    }
}

private struct KeyCap: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(Theme.text)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .frame(minWidth: 18)
            .background(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.line, lineWidth: 1))
            .cornerRadius(4)
    }
}

// MARK: - Otwieranie

/// Przycisk „?” (w nagłówku okna)
struct HelpButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button {
            openWindow(id: HelpWindow.id)
        } label: {
            Image(systemName: "questionmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.text2)
                .frame(width: 24, height: 24)
                .background(Theme.surface.opacity(0.85))
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(tr("Instrukcja", "User guide"))
    }
}

/// Pozycja w menu Pomoc (Cmd+?)
struct HelpMenuItem: View {
    let appName: String
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button(tr("Instrukcja \(appName)", "\(appName) User Guide")) {
            openWindow(id: HelpWindow.id)
        }
        .keyboardShortcut("?", modifiers: .command)
    }
}
