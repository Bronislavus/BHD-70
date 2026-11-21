// BHD-70 – wgrywanie plików SysEx do pamięci instrumentu.
//
// Prawdziwy D-70 nie przyjmuje zgrania pamięci w zwykłym trybie gry. Roland
// zrobił do tego osobny tryb serwisowy („Extend Product Mode”): instrument
// włącza się z przytrzymanym klawiszem [5], a w jego menu F.2 to „Bulk Load
// All Memory from MIDI”. Dopiero tam firmware przyjmuje cały zrzut i zapisuje
// go do swojej pamięci – a ta jest podtrzymywana, dokładnie jak bateryjka
// w sprzęcie. Wgrywa się raz i zostaje.
//
// Ten plik robi to wszystko za użytkownika: gasi instrument, włącza go z
// przytrzymanym [5], naciska F2 i ENTER, wysyła plik w tempie kabla MIDI
// (3125 bajtów na sekundę – szybciej firmware nie przyjmie), naciska EXIT
// i włącza instrument na nowo, już z nowymi brzmieniami.
//
// Kolejność i czasy nie są zgadnięte: tak przeszła próba, po której w pamięci
// stanęły nazwy brzmień fabrycznych („D Piano+ 1”, „Grandioso”, „Rhodes 1”…).

import Foundation

@MainActor
public final class WgrywanieSysex: ObservableObject {

    // MARK: - Plik na liście

    /// Plik SysEx, który użytkownik już kiedyś wgrywał – leży w katalogu grupy,
    /// więc widzi go i program, i wtyczka, i nie trzeba go wskazywać od nowa.
    public struct Plik: Identifiable, Hashable {
        public let url: URL
        public var id: String { url.lastPathComponent }
        public var nazwa: String { url.deletingPathExtension().lastPathComponent }
        public var bajtow: Int
        public var data: Date
    }

    /// Gdzie trzymamy kopie wgranych plików.
    public static var folder: URL {
        Silnik.folderStanu.appendingPathComponent("sysex", isDirectory: true)
    }

    // MARK: - Stan dla okna

    public enum Etap: Equatable {
        case bezczynny
        case gaszenie, rozruch, menu, wysylka, zapis
        case gotowe, blad
    }

    @Published public private(set) var etap: Etap = .bezczynny
    /// Co się właśnie dzieje – jednym zdaniem, dla użytkownika.
    @Published public private(set) var opis = ""
    /// Postęp wysyłki w procentach (tylko w etapie `wysylka`).
    @Published public private(set) var postep = 0
    /// Wynik: co się udało albo na czym stanęło.
    @Published public private(set) var wynik: String?
    /// Blokada pamięci – przełącznik z tyłu obudowy. Dopóki włączona, nic nie wgramy.
    /// Po zamknięciu okna wraca sama, żeby nie dało się nadpisać brzmień przypadkiem.
    @Published public var ochronaPamieci = true
    /// Pliki, które już kiedyś wgrywaliśmy.
    @Published public private(set) var pliki: [Plik] = []

    public var pracuje: Bool {
        switch etap {
        case .bezczynny, .gotowe, .blad: return false
        default: return true
        }
    }

    private let silnik: Silnik?
    /// Co zrobić po ponownym włączeniu instrumentu (program musi na nowo
    /// podłączyć nasłuch MIDI – przy gaszeniu silnik zwalnia porty).
    private let poRestarcie: (() -> Void)?
    private var zadanie: Task<Void, Never>?

    /// Powstaje razem z panelem, więc bez sięgania do dysku – listę plików
    /// czyta dopiero `odswiezListe()`, kiedy okno się otwiera.
    public nonisolated init(silnik: Silnik?, poRestarcie: (() -> Void)? = nil) {
        self.silnik = silnik
        self.poRestarcie = poRestarcie
    }

    // MARK: - Lista plików

    public func odswiezListe() {
        let fm = FileManager.default
        dolozZOknaPowitalnego()
        let klucze: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let znalezione = (try? fm.contentsOfDirectory(at: Self.folder,
                                                      includingPropertiesForKeys: klucze,
                                                      options: [.skipsHiddenFiles])) ?? []
        pliki = znalezione
            .filter { $0.pathExtension.lowercased() == "syx" }
            .map { u in
                let w = try? u.resourceValues(forKeys: Set(klucze))
                return Plik(url: u, bajtow: w?.fileSize ?? 0,
                            data: w?.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.data > $1.data }
    }

    /// W oknie powitalnym użytkownik wskazuje folder ze zgraniem swojego D-70;
    /// jeśli leżał tam plik z brzmieniami, czeka pod nazwą brzmienia.syx.
    /// Przenosimy go na listę, żeby po pierwszym uruchomieniu wystarczyło
    /// otworzyć SYSEX i kliknąć „Wgraj”.
    private func dolozZOknaPowitalnego() {
        let fm = FileManager.default
        let zrodlo = PlikiInstrumentu.plikBrzmien
        guard let dane = try? Data(contentsOf: zrodlo), dane.count >= 10 else { return }
        let cel = Self.folder
            .appendingPathComponent(tr("Brzmienia z Twojego D-70", "Sounds from your D-70"))
            .appendingPathExtension("syx")
        guard !fm.fileExists(atPath: cel.path) else { return }
        try? fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? dane.write(to: cel, options: .atomic)
    }

    public func usun(_ p: Plik) {
        try? FileManager.default.removeItem(at: p.url)
        odswiezListe()
    }

    /// Bierze plik wskazany przez użytkownika: wyjmuje z niego komunikaty SysEx
    /// (działa i dla .syx, i dla .mid – fabryczna dyskietka D-70 to plik MIDI),
    /// odkłada kopię do katalogu grupy i oddaje ją jako pozycję listy.
    public func dolozPlik(_ zrodlo: URL) throws -> Plik {
        let dane = try Data(contentsOf: zrodlo)
        let sysex = PlikiInstrumentu.sysexZMidi(dane)
        guard sysex.count >= 10 else {
            throw Blad.brakSysex(zrodlo.lastPathComponent)
        }
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        var nazwa = zrodlo.deletingPathExtension().lastPathComponent
        if nazwa.isEmpty { nazwa = "sysex" }
        var cel = Self.folder.appendingPathComponent(nazwa).appendingPathExtension("syx")
        var n = 2
        while fm.fileExists(atPath: cel.path) {
            // Ten sam plik wgrywany drugi raz – nadpisujemy, gdy treść ta sama
            if let stary = try? Data(contentsOf: cel), stary == sysex { break }
            cel = Self.folder.appendingPathComponent("\(nazwa) \(n)").appendingPathExtension("syx")
            n += 1
        }
        try sysex.write(to: cel, options: .atomic)
        odswiezListe()
        return pliki.first { $0.url == cel }
            ?? Plik(url: cel, bajtow: sysex.count, data: Date())
    }

    public enum Blad: LocalizedError {
        case brakSysex(String), brakSilnika, ochrona, kopiaRobocza, nieWchodzi, pustaPamiec

        public var errorDescription: String? {
            switch self {
            case .brakSysex(let nazwa):
                return tr("W pliku „\(nazwa)” nie ma żadnego komunikatu SysEx.",
                          "File “\(nazwa)” contains no SysEx message.")
            case .brakSilnika:
                return tr("Instrument nie jest uruchomiony.", "The instrument is not running.")
            case .ochrona:
                return tr("Blokada pamięci jest włączona.", "Memory protect is on.")
            case .kopiaRobocza:
                return tr("Ta kopia instrumentu gra na pamięci roboczej – wgrane brzmienia nie zostałyby zapisane. Zamknij pozostałe kopie BHD-70 i spróbuj jeszcze raz.",
                          "This instrument copy runs on a scratch memory – loaded sounds would not be saved. Close the other BHD-70 copies and try again.")
            case .nieWchodzi:
                return tr("Instrument nie przyjmuje danych – nie udało się wejść w tryb serwisowy. Pamięć brzmień została nietknięta.",
                          "The instrument is not taking the data – entering service mode failed. The sound memory was left untouched.")
            case .pustaPamiec:
                return tr("Wysyłka doszła do końca, ale pamięć instrumentu została pusta.",
                          "The transfer finished, but the instrument memory stayed empty.")
            }
        }
    }

    // MARK: - Wgrywanie

    public func wgraj(_ p: Plik) {
        guard !pracuje else { return }
        wynik = nil
        guard let silnik else { zakonczBledem(Blad.brakSilnika); return }
        guard !ochronaPamieci else { zakonczBledem(Blad.ochrona); return }
        guard silnik.pamiecTrwala else { zakonczBledem(Blad.kopiaRobocza); return }
        guard let dane = try? Data(contentsOf: p.url), dane.count >= 10 else {
            zakonczBledem(Blad.brakSysex(p.nazwa)); return
        }
        zadanie = Task { await przeprowadz(dane: dane, nazwa: p.nazwa, silnik: silnik) }
    }

    public func przerwij() {
        silnik?.przerwijWgrywanie()
        zadanie?.cancel()
    }

    private func zakonczBledem(_ b: Error) {
        etap = .blad
        opis = ""
        wynik = b.localizedDescription
    }

    // MARK: - Cała droga, krok po kroku

    /// Czasy wzięte z próby, która się udała. Nie skracać na oko: [5] musi być
    /// trzymane przez cały rozruch procesora, a menu trybu serwisowego pojawia
    /// się dopiero po pełnym rozruchu firmware'u.
    private enum Czas {
        static let trzymanie: Double = 8
        static let rozruch: Double = 24
        static let przycisk: Double = 0.3
        static let poPrzycisku: Double = 1.2
        /// Po tym czasie wysyłki sprawdzamy, czy na wyświetlaczu cokolwiek drgnęło.
        static let sprawdzenie: Double = 2.5
        static let poWysylce: Double = 2
        static let poWyjsciu: Double = 3
    }

    private func przeprowadz(dane: Data, nazwa: String, silnik: Silnik) async {
        func krok(_ e: Etap, _ t: String) {
            etap = e
            opis = t
        }

        // 1. Kopia pamięci na wszelki wypadek – gdyby wgrywanie poszło nie tak,
        //    poprzednie brzmienia zostają na dysku.
        krok(.gaszenie, tr("Odkładam kopię dotychczasowej pamięci…",
                           "Backing up the current memory…"))
        await wTle { silnik.stop() }
        let kopia = zrobKopiePamieci()

        // 2. Włączamy instrument z przytrzymanym [5] – to wejście w tryb serwisowy.
        krok(.rozruch, tr("Włączam instrument z przytrzymanym [5] (tryb serwisowy)…",
                          "Powering up with [5] held (service mode)…"))
        await wTle { silnik.start() }
        poRestarcie?()
        let doKiedy = Date().addingTimeInterval(Czas.trzymanie)
        while Date() < doKiedy {
            if Task.isCancelled { return przerwane(silnik) }
            // Przycisk trzeba dociskać bez przerwy: emulator łapie rozkazy dopiero,
            // gdy wstanie, a klawisz musi być wciśnięty, kiedy firmware go czyta.
            silnik.przycisk(bank: 2, bit: 3, wcisniety: true)
            try? await Task.sleep(nanoseconds: 33_000_000)
        }
        silnik.przycisk(bank: 2, bit: 3, wcisniety: false)

        krok(.rozruch, tr("Czekam, aż instrument wejdzie w menu trybu serwisowego…",
                          "Waiting for the service menu to come up…"))
        if !(await odczekaj(Czas.rozruch)) { return przerwane(silnik) }

        // 3. F.2 = Bulk Load All Memory from MIDI, potem ENTER.
        krok(.menu, tr("Wybieram F.2 – Bulk Load All Memory from MIDI…",
                       "Choosing F.2 – Bulk Load All Memory from MIDI…"))
        if !(await nacisnij(silnik, bank: 4, bit: 3)) { return przerwane(silnik) }
        if !(await nacisnij(silnik, bank: 0, bit: 0)) { return przerwane(silnik) }

        // Obraz ekranu sprzed wysyłki – po pierwszych komunikatach firmware
        // zacznie na nim odliczać adresy, i to jest nasz dowód, że przyjmuje.
        var przed = [UInt8](repeating: 0, count: Silnik.ekranBajtow)
        _ = silnik.ekran(&przed)

        // 4. Wysyłka w tempie kabla MIDI.
        krok(.wysylka, tr("Wysyłam „\(nazwa)” – \(dane.count / 1024) kB w tempie kabla MIDI…",
                          "Sending “\(nazwa)” – \(dane.count / 1024) kB at MIDI cable speed…"))
        postep = 0
        silnik.wgrajBrzmienia(dane)
        if !(await odczekaj(Czas.sprawdzenie)) { return przerwane(silnik) }

        var teraz = [UInt8](repeating: 0, count: Silnik.ekranBajtow)
        _ = silnik.ekran(&teraz)
        if teraz == przed {
            // Instrument nie liczy adresów, czyli nie jest w trybie wczytywania.
            // Przerywamy od razu: do pamięci weszło najwyżej kilka kilobajtów,
            // a kopia sprzed wgrywania leży na dysku.
            silnik.przerwijWgrywanie()
            await wTle { silnik.stop() }
            przywrocKopie(kopia)
            await wTle { silnik.start() }
            poRestarcie?()
            zakonczBledem(Blad.nieWchodzi)
            return
        }

        while silnik.wgrywaBrzmienia {
            if Task.isCancelled { return przerwane(silnik) }
            postep = silnik.postepBrzmien
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        postep = 100
        if !(await odczekaj(Czas.poWysylce)) { return przerwane(silnik) }

        // 5. EXIT – wyjście z trybu serwisowego.
        krok(.zapis, tr("Wychodzę z trybu serwisowego…", "Leaving service mode…"))
        if !(await nacisnij(silnik, bank: 4, bit: 7)) { return przerwane(silnik) }
        if !(await odczekaj(Czas.poWyjsciu)) { return przerwane(silnik) }

        // 6. Gaszenie zapisuje pamięć na dysk, włączenie wraca do trybu gry.
        krok(.zapis, tr("Zapisuję pamięć i włączam instrument na nowo…",
                        "Saving the memory and powering the instrument back up…"))
        await wTle { silnik.stop() }
        let bajtow = niezerowychWPamieci()
        await wTle { silnik.start() }
        poRestarcie?()

        if bajtow < 1000 {
            zakonczBledem(Blad.pustaPamiec)
            return
        }
        etap = .gotowe
        opis = ""
        wynik = tr("Gotowe. Brzmienia z „\(nazwa)” siedzą w pamięci instrumentu i zostaną tam także po zamknięciu programu.",
                   "Done. The sounds from “\(nazwa)” are in the instrument memory and will stay there after you quit.")
        // Blokada pamięci wraca sama – tak jak przełącznik, którego nie zostawia się otwartym.
        ochronaPamieci = true
    }

    /// Przerwane przez użytkownika: instrument musi wrócić do grania.
    private func przerwane(_ silnik: Silnik) {
        silnik.przerwijWgrywanie()
        etap = .bezczynny
        opis = ""
        postep = 0
        wynik = tr("Przerwane.", "Cancelled.")
    }

    private func nacisnij(_ silnik: Silnik, bank: UInt8, bit: UInt8) async -> Bool {
        silnik.przycisk(bank: bank, bit: bit, wcisniety: true)
        guard await odczekaj(Czas.przycisk) else { return false }
        silnik.przycisk(bank: bank, bit: bit, wcisniety: false)
        return await odczekaj(Czas.poPrzycisku)
    }

    /// Gaszenie instrumentu czeka, aż emulator wyjdzie sam (zapisuje wtedy pamięć),
    /// a to trwa chwilę – robimy to poza wątkiem okna, żeby panel się nie zacinał.
    private func wTle(_ co: @escaping () -> Void) async {
        await withCheckedContinuation { dalej in
            DispatchQueue.global(qos: .userInitiated).async {
                co()
                dalej.resume()
            }
        }
    }

    /// Czeka, oddając wątek główny. Zwraca false, gdy użytkownik przerwał.
    private func odczekaj(_ sekund: Double) async -> Bool {
        let koniec = Date().addingTimeInterval(sekund)
        while Date() < koniec {
            if Task.isCancelled { return false }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return !Task.isCancelled
    }

    // MARK: - Pamięć na dysku

    private var folderPamieci: URL {
        Silnik.folderStanu.appendingPathComponent("pamiec", isDirectory: true)
    }

    /// Kopia pamięci sprzed wgrywania. Zwraca jej katalog albo nil, gdy nie było
    /// czego kopiować (pierwsze wgrywanie na świeżym instrumencie).
    private func zrobKopiePamieci() -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: PlikiInstrumentu.pamiecBrzmien.path) else { return nil }
        let stempel = DateFormatter()
        stempel.dateFormat = "yyyy-MM-dd-HHmm"
        let cel = Silnik.folderStanu
            .appendingPathComponent("pamiec-kopia-" + stempel.string(from: Date()), isDirectory: true)
        try? fm.removeItem(at: cel)
        guard (try? fm.copyItem(at: folderPamieci, to: cel)) != nil else { return nil }
        return cel
    }

    private func przywrocKopie(_ kopia: URL?) {
        guard let kopia else { return }
        let fm = FileManager.default
        try? fm.removeItem(at: folderPamieci)
        try? fm.copyItem(at: kopia, to: folderPamieci)
    }

    /// Ile w pamięci instrumentu jest niezerowych bajtów – po wgrywaniu powinno
    /// być ich kilkadziesiąt tysięcy, a w pustej pamięci jest kilka.
    private func niezerowychWPamieci() -> Int {
        guard let d = try? Data(contentsOf: PlikiInstrumentu.pamiecBrzmien) else { return 0 }
        return d.reduce(into: 0) { suma, b in if b != 0 { suma += 1 } }
    }
}
