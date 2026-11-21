// BHD-70 – okno pierwszego uruchomienia: prośba o własne pliki z D-70.
//
// BHD-70 nie nosi w sobie oprogramowania Rolanda. Zanim instrument zagra,
// użytkownik musi wskazać folder ze zgraniem własnego D-70. To okno tłumaczy,
// czego potrzeba i skąd to wziąć, a potem sprawdza, czy komplet się zgadza.
//
// Wtyczka w DAW-ie swojego okna wyboru pliku mieć nie może, więc korzysta z
// tego, co wskazano w programie – patrz WidokBrakPlikow na dole.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Program: okno powitalne

public struct OknoPlikow: View {
    /// Wołane, gdy komplet jest już na miejscu i można uruchomić instrument.
    public var gotowe: () -> Void

    @State private var stan = PlikiInstrumentu.sprawdz()
    @State private var raport: PlikiInstrumentu.Raport?
    @State private var blad: String?
    @State private var szuka = false

    public init(gotowe: @escaping () -> Void) { self.gotowe = gotowe }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AppHeader(title: "BHD-70",
                          subtitle: tr("Zanim zagra, potrzebuje oprogramowania z Twojego D-70",
                                       "Before it can play, it needs the software from your own D-70"))

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tr("Dźwięk w BHD-70 liczy prawdziwe oprogramowanie Rolanda D-70. Tego oprogramowania nie wolno nam rozpowszechniać – należy do Rolanda. Dlatego instrument prosi o zgranie z Twojego własnego egzemplarza.",
                                "The sound in BHD-70 is computed by the real Roland D-70 software. We are not allowed to distribute that software – it belongs to Roland. So the instrument asks for a copy taken from your own unit."))
                        .foregroundColor(Theme.text2)
                        Text(tr("Wskaż folder, w którym leżą te pliki. Mogą być w podfolderach i nazywać się jak chcą – rozpoznaję je po zawartości.",
                                "Point to the folder where those files are. They may sit in subfolders and be named anything – I recognise them by their content."))
                        .foregroundColor(Theme.text2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .groupBoxStyle(.themed)

                GroupBox(label: Text(tr("Czego potrzebuję", "What I need"))) {
                    VStack(alignment: .leading, spacing: 12) {
                        pozycja(numer: "1",
                                tytul: tr("Firmware – dwie kości", "Firmware – two chips"),
                                opis: tr("Zgranie kości EPROM z płyty głównej: parzystej (IC4) i nieparzystej (IC9), po 64 kB każda. Wystarczy jedna wersja: 1.19, 1.16, 1.14, 1.12 albo 1.10.",
                                         "Dumps of the EPROMs on the main board: even (IC4) and odd (IC9), 64 kB each. One version is enough: 1.19, 1.16, 1.14, 1.12 or 1.10."),
                                stanOpis: stan.wersjaFirmware != nil
                                    ? tr("jest, wersja \(stan.opisFirmware ?? "")", "present, version \(stan.opisFirmware ?? "")")
                                    : tr("brak", "missing"),
                                dobre: stan.wersjaFirmware != nil)
                        pozycja(numer: "2",
                                tytul: tr("Fale – sześć kości", "Waves – six chips"),
                                opis: tr("Zgranie kości z brzmieniami PCM, oznaczonych A, B, C, D, E i F, po 512 kB każda. Potrzebne są wszystkie sześć.",
                                         "Dumps of the PCM wave chips, marked A, B, C, D, E and F, 512 kB each. All six are needed."),
                                stanOpis: stan.brakujaceFale.isEmpty
                                    ? tr("wszystkie sześć", "all six")
                                    : tr("brakuje: \(stan.brakujaceFale.joined(separator: ", "))",
                                         "missing: \(stan.brakujaceFale.joined(separator: ", "))"),
                                dobre: stan.brakujaceFale.isEmpty)
                        pozycja(numer: "3",
                                tytul: tr("Brzmienia – wgrasz je później", "Sounds – you load them later"),
                                opis: tr("Instrument wstanie z pustą pamięcią, jak sprzęt po wyjęciu baterii: zagra, ale nazwy brzmień będą śmieciami. Wgrasz je przyciskiem SYSEX na panelu: wskażesz plik .syx zgrany ze swojego D-70, a resztę program zrobi sam. Wgrywa się raz i zostaje – krok po kroku opisuje to instrukcja pod „?”.",
                                         "The instrument starts with empty memory, like the hardware with a flat battery: it plays, but the patch names are garbage. You load them with the SYSEX button on the panel: point to a .syx file dumped from your own D-70 and the program does the rest. Loaded once, it stays – the guide under “?” walks you through it."),
                                stanOpis: tr("osobny krok", "a separate step"),
                                dobre: false, wazne: false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .groupBoxStyle(.themed)

                if let r = raport { podsumowanie(r) }
                if let b = blad {
                    Text(b)
                        .font(.callout)
                        .foregroundColor(Theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Przycisk stoi tu, nad objaśnieniami – ma być widoczny od razu,
                // bez przewijania okna.
                HStack(spacing: 12) {
                    Button(szuka ? tr("Szukam…", "Looking…") : tr("Wskaż folder z plikami…", "Choose the folder…")) {
                        wskaz()
                    }
                    .disabled(szuka)
                    .keyboardShortcut(.defaultAction)

                    if stan.moznaGrac {
                        Button(tr("Uruchom instrument", "Start the instrument")) { gotowe() }
                    }
                    Spacer()
                    if stan.moznaGrac || stan.saBrzmienia {
                        Button(tr("Zacznij od nowa", "Start over")) {
                            PlikiInstrumentu.zapomnij()
                            raport = nil; blad = nil
                            stan = PlikiInstrumentu.sprawdz()
                        }
                        .foregroundColor(Theme.faint)
                    }
                }

                GroupBox(label: Text(tr("Skąd to wziąć", "Where to get it"))) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Text(.init(...)) – inaczej SwiftUI pokaże gwiazdki zamiast pogrubienia
                        Text(.init(tr("**Kości** wyjmuje się z instrumentu i odczytuje programatorem EPROM – robi to serwis albo ktoś, kto ma sprzęt do programowania kości. Plików musi być dokładnie tyle i takich, jakie są w prawdziwym D-70.",
                                      "**The chips** are taken out of the instrument and read with an EPROM programmer – a service shop does this, or anyone with chip-reading equipment. The files must be exactly those found in a real D-70.")))
                        Text(.init(tr("**Brzmienia** zgrasz sam, bez rozkręcania: podłącz D-70 do komputera kablem MIDI, nagraj Bulk Dump dowolnym programem do SysEx i zapisz jako plik .syx. Ten plik wgrywa się potem przyciskiem SYSEX na panelu.",
                                      "**The sounds** you can dump yourself, without opening anything: connect the D-70 to your computer with a MIDI cable, record a Bulk Dump with any SysEx utility and save it as a .syx file. You then load that file with the SYSEX button on the panel.")))
                        Text(tr("Jeśli masz fabryczną dyskietkę D-70, plik .mid z niej też się nada.",
                                "If you have the factory D-70 disk, the .mid file from it works too."))
                    }
                    .font(.callout)
                    .foregroundColor(Theme.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .groupBoxStyle(.themed)

                Text(tr("Pliki, które wskażesz, zostają na Twoim komputerze. BHD-70 nigdzie ich nie wysyła i nie dołącza ich do siebie.",
                        "The files you point to stay on your computer. BHD-70 never sends them anywhere and never bundles them."))
                    .font(.footnote)
                    .foregroundColor(Theme.faint)

                CreditsFooter()
            }
            .padding(22)
        }
        .frame(minWidth: 560, minHeight: 560)
        .themedWindow()
    }

    // MARK: - Kawałki

    @ViewBuilder
    private func pozycja(numer: String, tytul: String, opis: String,
                         stanOpis: String, dobre: Bool, wazne: Bool = true) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(numer)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(dobre ? Theme.accent : Theme.faint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(tytul).font(.headline).foregroundColor(Theme.text)
                    Text(stanOpis)
                        .font(.caption)
                        .foregroundColor(dobre ? Theme.accent : (wazne ? Theme.text2 : Theme.faint))
                }
                Text(opis).font(.callout).foregroundColor(Theme.text2)
            }
        }
    }

    @ViewBuilder
    private func podsumowanie(_ r: PlikiInstrumentu.Raport) -> some View {
        GroupBox(label: Text(tr("Co znalazłem", "What I found"))) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Przejrzałem \(r.przejrzanych) plików.", "I looked through \(r.przejrzanych) files."))
                    .foregroundColor(Theme.text2)
                if !r.rozpoznane.isEmpty {
                    Text(tr("Rozpoznane kości: \(r.rozpoznane.count).", "Chips recognised: \(r.rozpoznane.count)."))
                        .foregroundColor(Theme.text2)
                }
                if let z = r.brzmieniaZ {
                    Text(tr("Brzmienia wzięte z pliku \(z) (\(r.bajtowBrzmien / 1024) kB).",
                            "Sounds taken from \(z) (\(r.bajtowBrzmien / 1024) kB)."))
                        .foregroundColor(Theme.text2)
                }
                if r.stan.moznaGrac {
                    Text(tr("Komplet się zgadza – instrument może grać.",
                            "The set is complete – the instrument can play."))
                        .foregroundColor(Theme.accent)
                } else {
                    Text(tr("To jeszcze nie komplet. Wskaż folder, w którym leży reszta – to, co już mam, zostaje.",
                            "Not complete yet. Point to the folder with the rest – what I already have stays."))
                        .foregroundColor(Theme.text2)
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .groupBoxStyle(.themed)
    }

    private func wskaz() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = tr("Przejrzyj", "Scan")
        panel.message = tr("Wskaż folder ze zgraniem Twojego D-70 – przejrzę go razem z podfolderami.",
                           "Choose the folder with your D-70 dump – I will scan it with its subfolders.")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        szuka = true; blad = nil
        DispatchQueue.global(qos: .userInitiated).async {
            var wynik: PlikiInstrumentu.Raport?
            var opisBledu: String?
            do { wynik = try PlikiInstrumentu.wezZFolderu(folder) }
            catch { opisBledu = error.localizedDescription }
            DispatchQueue.main.async {
                szuka = false
                raport = wynik
                blad = opisBledu
                stan = PlikiInstrumentu.sprawdz()
            }
        }
    }
}

// MARK: - Wtyczka: sam napis, bez wyboru pliku

/// Wtyczka w DAW-ie nie otwiera własnego okna wyboru pliku – korzysta z tego,
/// co wskazano w programie. Gdy nic nie wskazano, mówi, co zrobić.
public struct WidokBrakPlikow: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 14) {
            Text(Brand.slogan)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(2.2)
                .foregroundColor(Theme.accent)
            BrandName(name: "BHD-70")
            Text(tr("Instrument nie ma jeszcze oprogramowania z Twojego D-70.",
                    "The instrument does not yet have the software from your D-70."))
                .font(.headline)
                .foregroundColor(Theme.text)
            Text(.init(tr("Otwórz program **BHD-70** (w folderze Programy), wskaż w nim folder ze zgraniem swojego instrumentu, a potem wstaw wtyczkę jeszcze raz. Wtyczka korzysta z tego samego, co program.",
                          "Open the **BHD-70** app (in your Applications folder), point it to the folder with your instrument's dump, then insert the plug-in again. The plug-in uses the same files as the app.")))
                .font(.callout)
                .foregroundColor(Theme.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Text(tr("Oprogramowanie Rolanda D-70 jest własnością Rolanda i nie jest częścią BHD-70.",
                    "The Roland D-70 software belongs to Roland and is not part of BHD-70."))
                .font(.footnote)
                .foregroundColor(Theme.faint)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }
}
