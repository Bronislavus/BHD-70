// BHD-70 – okno przycisku SYSEX: wgrywanie plików SysEx do pamięci instrumentu.
//
// Na panelu, nad krzyżakiem kursora, jest przycisk SYSEX – takiego na prawdziwym
// D-70 nie ma. Otwiera to okno, a w nim siedzi wszystko, czego potrzeba, żeby
// wsadzić instrumentowi do pamięci własne brzmienia:
//
//   • przełącznik BLOKADY PAMIĘCI – ten, który w sprzęcie jest z tyłu obudowy.
//     Dopóki jest włączony, nic się nie nadpisze;
//   • lista plików SysEx, które już kiedyś wgrywaliśmy – żeby nie szukać ich
//     po dysku za każdym razem;
//   • przycisk, którym dokłada się nowy plik.
//
// Reszta – gaszenie instrumentu, wejście w tryb serwisowy, naciskanie F2 i
// ENTER, tempo wysyłki, wyjście i zapis pamięci – dzieje się sama; opisuje to
// WgrywanieSysex.swift. Użytkownik widzi tylko, co się właśnie dzieje.

import SwiftUI

public struct OknoSysex: View {
    @ObservedObject var model: WgrywanieSysex
    /// Czy w tym miejscu wolno otworzyć okno wyboru pliku. Program – tak;
    /// wtyczka w DAW-ie korzysta z plików dołożonych w programie.
    let moznaWskazac: Bool
    var zamknij: () -> Void

    @State private var wybrany: WgrywanieSysex.Plik?
    @State private var blad: String?

    public init(model: WgrywanieSysex, moznaWskazac: Bool, zamknij: @escaping () -> Void) {
        self.model = model
        self.moznaWskazac = moznaWskazac
        self.zamknij = zamknij
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            naglowek

            if model.pracuje {
                przebieg
            } else {
                przelacznik
                lista
                przyciski
            }

            if let w = model.wynik {
                Text(w)
                    .font(.callout)
                    .foregroundColor(model.etap == .blad ? Theme.accentHover : Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let b = blad {
                Text(b)
                    .font(.callout)
                    .foregroundColor(Theme.accentHover)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
            objasnienie
        }
        .padding(22)
        .frame(width: 560, height: 580)
    }

    // MARK: - Nagłówek

    private var naglowek: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SYSEX")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(2.4)
                    .foregroundColor(Theme.accent)
                Text(tr("Wgrywanie do pamięci instrumentu",
                        "Loading into the instrument memory"))
                    .font(.headline)
                    .foregroundColor(Theme.text)
            }
            Spacer()
            Button { zamknij() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.text2)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Theme.surface))
                    .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(model.pracuje)
            .opacity(model.pracuje ? 0.3 : 1)
        }
    }

    // MARK: - Blokada pamięci

    private var przelacznik: some View {
        GroupBox {
            HStack(alignment: .center, spacing: 16) {
                PrzelacznikOchrony(chroniona: $model.ochronaPamieci)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Blokada pamięci", "Memory protect"))
                        .font(.headline)
                        .foregroundColor(Theme.text)
                    Text(model.ochronaPamieci
                         ? tr("Włączona – brzmienia w instrumencie są bezpieczne i nic ich nie nadpisze.",
                              "On – the sounds in the instrument are safe and nothing can overwrite them.")
                         : tr("Wyłączona – wgranie pliku nadpisze całą pamięć brzmień.",
                              "Off – loading a file will overwrite the whole sound memory."))
                        .font(.callout)
                        .foregroundColor(model.ochronaPamieci ? Theme.text2 : Theme.accentHover)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .groupBoxStyle(.themed)
    }

    // MARK: - Lista plików

    private var lista: some View {
        GroupBox(label: Text(tr("Pliki SysEx", "SysEx files"))) {
            VStack(alignment: .leading, spacing: 0) {
                if model.pliki.isEmpty {
                    Text(moznaWskazac
                         ? tr("Nie ma jeszcze żadnego. Wskaż plik .syx albo .mid – odłożę go tutaj i następnym razem będzie pod ręką.",
                              "None yet. Choose a .syx or .mid file – I will keep it here, ready next time.")
                         : tr("Nie ma jeszcze żadnego. Pliki dokłada się w programie BHD-70; wtyczka widzi tę samą listę.",
                              "None yet. Files are added in the BHD-70 application; the plug-in sees the same list."))
                        .font(.callout)
                        .foregroundColor(Theme.text2)
                        .padding(.vertical, 6)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(model.pliki) { p in
                                wiersz(p)
                            }
                        }
                    }
                    .frame(height: 150)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .groupBoxStyle(.themed)
    }

    private func wiersz(_ p: WgrywanieSysex.Plik) -> some View {
        let ten = wybrany?.url == p.url
        return HStack(spacing: 10) {
            Image(systemName: ten ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 11))
                .foregroundColor(ten ? Theme.accent : Theme.faint)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.nazwa)
                    .font(.callout)
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                Text("\(p.bajtow / 1024) kB · \(p.data.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(Theme.faint)
            }
            Spacer(minLength: 0)
            Button {
                if ten { wybrany = nil }
                model.usun(p)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.faint)
            }
            .buttonStyle(.plain)
            .help(tr("Usuń z listy (pamięci instrumentu to nie rusza)",
                     "Remove from the list (this does not touch the instrument memory)"))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 4)
            .fill(ten ? Theme.accent.opacity(0.10) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { wybrany = ten ? nil : p }
    }

    // MARK: - Przyciski

    private var przyciski: some View {
        HStack(spacing: 12) {
            Button(tr("Wgraj do instrumentu", "Load into the instrument")) {
                blad = nil
                if let w = wybrany { model.wgraj(w) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(wybrany == nil || model.ochronaPamieci)

            if moznaWskazac {
                Button(tr("Wskaż plik…", "Choose a file…")) { wskaz() }
            }
            Spacer()
        }
    }

    private func wskaz() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["syx", "mid", "midi", "bin", "dmp"]
        panel.prompt = tr("Dołóż", "Add")
        panel.message = tr("Wskaż plik SysEx zgrany z Twojego D-70 (.syx) albo plik MIDI z fabrycznej dyskietki (.mid).",
                           "Choose a SysEx file taken from your D-70 (.syx) or a MIDI file from the factory disk (.mid).")
        guard panel.runModal() == .OK, let plik = panel.url else { return }
        blad = nil
        do { wybrany = try model.dolozPlik(plik) }
        catch { blad = error.localizedDescription }
    }

    // MARK: - Przebieg wgrywania

    private var przebieg: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.opis)
                        .font(.callout)
                        .foregroundColor(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.etap == .wysylka {
                    ProgressView(value: Double(model.postep), total: 100)
                        .tint(Theme.accent)
                    Text("\(model.postep)%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.accent)
                }
                Text(tr("Instrument gasi się i włącza na nowo – to normalne. Przez tę chwilę nie graj i nie zamykaj okna; całość zajmuje około minuty.",
                        "The instrument powers down and back up – that is normal. Do not play and do not close this window meanwhile; the whole thing takes about a minute."))
                    .font(.footnote)
                    .foregroundColor(Theme.faint)
                    .fixedSize(horizontal: false, vertical: true)
                Button(tr("Przerwij", "Cancel")) { model.przerwij() }
                    .foregroundColor(Theme.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .groupBoxStyle(.themed)
    }

    // MARK: - Objaśnienie

    private var objasnienie: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(.init(tr("Pamięć brzmień instrumentu jest **podtrzymywana** – zupełnie jak bateryjka w prawdziwym D-70. Plik wgrywa się **raz** i zostaje tam na zawsze, także po zamknięciu programu i DAW-a.",
                          "The instrument sound memory is **kept** – just like the battery in a real D-70. A file is loaded **once** and stays there for good, also after you quit the application and the DAW.")))
            Text(tr("Przed wgraniem odkładam kopię dotychczasowej pamięci, więc nic nie przepada bezpowrotnie.",
                    "Before loading I put aside a copy of the current memory, so nothing is lost for good."))
            Text(tr("Działa to dla każdego pliku SysEx dla D-70, nie tylko dla brzmień fabrycznych.",
                    "This works for any D-70 SysEx file, not only the factory sounds."))
            if !moznaWskazac {
                // Przez cały czas wgrywania DAW musi przetwarzać dźwięk, bo to on
                // napędza emulację. Gdy zatrzyma wtyczkę w pół drogi, instrument stanie.
                Text(tr("We wtyczce rób to przy włączonym odtwarzaniu albo wcale nie dotykaj transportu – przez cały czas DAW musi przetwarzać dźwięk, bo to on napędza instrument. Najspokojniej wgrać brzmienia raz, w programie BHD-70; wtyczka ma potem tę samą pamięć.",
                        "In the plug-in do this with the DAW processing audio and do not touch the transport – the DAW drives the instrument the whole time. The calmest way is to load the sounds once in the BHD-70 application; the plug-in then has the same memory."))
                    .foregroundColor(Theme.text2)
            }
        }
        .font(.footnote)
        .foregroundColor(Theme.faint)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Przełącznik blokady pamięci (jak z tyłu obudowy)

/// Suwaczek dwupozycyjny – taki, jaki Roland umieścił z tyłu D-70.
/// Górna pozycja (PROTECT) chroni brzmienia, dolna pozwala je nadpisać.
struct PrzelacznikOchrony: View {
    @Binding var chroniona: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text("PROTECT")
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundColor(chroniona ? Theme.accent : Theme.faint)
            ZStack(alignment: chroniona ? .top : .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: 0x0A1018))
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(chroniona ? Theme.line : Theme.accentHover.opacity(0.8),
                                      lineWidth: 1))
                    .frame(width: 26, height: 48)
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Color(hex: 0x3A4858), Color(hex: 0x1A2633)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color(hex: 0x4A5A6A), lineWidth: 1))
                    .frame(width: 22, height: 22)
                    .padding(2)
            }
            .frame(width: 26, height: 48)
            Text("OFF")
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundColor(chroniona ? Theme.faint : Theme.accentHover)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.12)) { chroniona.toggle() }
        }
        .help(tr("Blokada pamięci – tak jak przełącznik z tyłu obudowy D-70",
                 "Memory protect – like the switch on the back of a D-70"))
    }
}
