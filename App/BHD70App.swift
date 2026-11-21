// BHD-70 – program na Maca: pełnoprawny instrument, nie podgląd.
// Uruchamia własny emulator, słucha MIDI i wypuszcza dźwięk na wybraną kartę.
// Wtyczka AUv3 siedzi w jego środku; tam kartę, częstotliwość i bufor daje DAW.

import SwiftUI

@main
struct BHD70App: App {
    @StateObject private var instrument = Instrument()
    @StateObject private var ustawienia = Ustawienia()

    var body: some Scene {
        WindowGroup("BHD-70") {
            // Dopóki nie ma oprogramowania z własnego D-70, instrument nie ma
            // czego grać – zamiast panelu pokazujemy, czego potrzeba i skąd.
            if instrument.brakPlikow {
                OknoPlikow { instrument.sprobujJeszczeRaz(ustawienia) }
                    .frame(minWidth: 560, minHeight: 560)
            } else {
                PanelView(silnik: instrument.silnik,
                          ustawieniaAudio: { instrument.pokazUstawienia = true },
                          poRestarcie: { instrument.poRestarcie(ustawienia) })
                    .frame(minWidth: 620, idealWidth: PanelView.rozmiar.width,
                           maxWidth: .infinity,
                           minHeight: 360, idealHeight: PanelView.rozmiar.height,
                           maxHeight: .infinity)
                    .onAppear { instrument.start(ustawienia) }
                    .sheet(isPresented: $instrument.pokazUstawienia) {
                        UstawieniaView(instrument: instrument, ustawienia: ustawienia)
                    }
                    // Beta: okno „Zgłoś błąd lub pomysł” przy pierwszym uruchomieniu
                    // wersji 0.9. Raz, z możliwością wyłączenia; potem tylko z menu Pomoc.
                    .feedbackAtLaunch(releases: ["0.9"])
            }
        }
        .defaultSize(width: PanelView.rozmiar.width, height: PanelView.rozmiar.height)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(tr("O programie BHD-70", "About BHD-70")) { Credits.showAboutPanel() }
            }
            CommandGroup(after: .appSettings) {
                Button(tr("Audio i MIDI…", "Audio and MIDI…")) { instrument.pokazUstawienia = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                HelpMenuItem(appName: "BHD-70")
                FeedbackMenuItem()
            }
        }

        Window(tr("Instrukcja – BHD-70", "BHD-70 User Guide"), id: HelpWindow.id) {
            HelpView(doc: HelpContent.doc)
                .themedWindow()
        }
        .defaultSize(width: 640, height: 780)

        // Zgłoszenia od testerów: gotowy e-mail z wersją programu, systemu i tym,
        // jakie oprogramowanie D-70 ma u siebie użytkownik.
        Window(tr("Zgłoś błąd lub pomysł", "Report a Problem or Idea"), id: FeedbackWindow.id) {
            FeedbackView(extraInfo: { BHD70App.daneDoZgloszenia() })
                .themedWindow()
        }
        .windowResizability(.contentSize)
    }

    /// Dane techniczne dopisywane do zgłoszenia – bez nich trudno zgadnąć,
    /// z jakim D-70 ktoś pracuje.
    static func daneDoZgloszenia() -> String {
        let stan = PlikiInstrumentu.sprawdz()
        let firmware = stan.opisFirmware ?? stan.wersjaFirmware ?? tr("brak", "none")
        var linie = ["Firmware D-70: \(firmware)"]
        if !stan.brakujaceFale.isEmpty {
            linie.append(tr("Brakujące fale", "Missing waves") + ": " + stan.brakujaceFale.joined(separator: ", "))
        }
        linie.append(tr("Pamięć brzmień", "Sound memory") + ": "
                     + (stan.pamiecZalozona ? tr("założona", "set up") : tr("pusta", "empty")))
        return linie.joined(separator: "\n")
    }
}

/// Silnik programu razem z dźwiękiem i MIDI
final class Instrument: ObservableObject {
    @Published private(set) var silnik: Silnik?
    /// Instrument nie ma jeszcze oprogramowania z D-70 użytkownika.
    @Published private(set) var brakPlikow: Bool
    @Published var pokazUstawienia = false
    private(set) var wyjscie: WyjscieAudio?
    private var straz: StrazMidi?
    private var ustawienia: Ustawienia?
    private var ruszyl = false

    init() {
        let s = Silnik()
        silnik = s
        brakPlikow = (s == nil)
    }

    /// Po wskazaniu plików w oknie powitalnym – budujemy silnik od nowa.
    func sprobujJeszczeRaz(_ u: Ustawienia) {
        guard brakPlikow else { return }
        silnik = Silnik()
        guard silnik != nil else { return }
        brakPlikow = false
        ruszyl = false
        start(u)
    }

    func start(_ u: Ustawienia) {
        guard !ruszyl, let silnik else { return }
        ruszyl = true
        ustawienia = u
        silnik.start()
        wyjscie = WyjscieAudio(silnik: silnik)
        ustawWyjscie(uid: u.wyjscieUID, czestotliwosc: u.czestotliwosc, bufor: UInt32(u.bufor))
        ustawMidi(u.wejscieMidi)
        // Urządzenia podłączone później też mają być słyszane
        straz = StrazMidi { [weak self] in self?.ustawMidi(self?.ustawienia?.wejscieMidi ?? "") }
        Urzadzenia.pilnujZmian { [weak self] in
            guard let self, let u = self.ustawienia, u.wyjscieUID.isEmpty else { return }
            self.ustawWyjscie(uid: "", czestotliwosc: u.czestotliwosc, bufor: UInt32(u.bufor))
        }
    }

    func ustawWyjscie(uid: String, czestotliwosc: Double, bufor: UInt32) {
        let karta = uid.isEmpty ? nil : Urzadzenia.wyjscia().first { $0.uid == uid }?.id
        wyjscie?.start(karta: karta,
                       czestotliwosc: czestotliwosc > 0 ? czestotliwosc : nil,
                       bufor: bufor > 0 ? bufor : nil)
        objectWillChange.send()
    }

    /// Wgrywanie SysEx gasi instrument i włącza go na nowo – przy gaszeniu silnik
    /// zwalnia porty CoreMIDI, więc nasłuch trzeba podłączyć od początku.
    func poRestarcie(_ u: Ustawienia) {
        ustawienia = u
        ustawMidi(u.wejscieMidi)
    }

    func ustawMidi(_ zrodlo: String) {
        silnik?.sluchajMidi(true, zrodlo: zrodlo)
    }
}
