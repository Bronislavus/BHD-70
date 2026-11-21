// ─────────────────────────────────────────────────────────────
// Wspólny plik serii BH – oryginał: ~/Developer/shared/BHStyle/Lang.swift
// W projektach jest KOPIA (Sources/_shared), nadpisywana przy każdym budowaniu.
// Zmiany wprowadzaj tylko w ~/Developer/shared.
// ─────────────────────────────────────────────────────────────
import Foundation

/// Język programu: polski, gdy system (albo ustawienie tej aplikacji w
/// Ustawieniach systemowych → Język i region → Aplikacje) jest po polsku; w każdym innym razie angielski.
enum Lang {
    static let isPolish: Bool = {
        let bundle = Bundle.main
        if bundle.localizations.contains(where: { $0.hasPrefix("pl") }),
           let first = bundle.preferredLocalizations.first {
            return first.hasPrefix("pl")
        }
        // Uruchomienie bez paczki .app (np. swift run) – bierzemy język systemu
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("pl")
    }()
}

/// Napis w dwóch wersjach: polskiej i angielskiej
@inline(__always)
func tr(_ pl: String, _ en: String) -> String { Lang.isPolish ? pl : en }
