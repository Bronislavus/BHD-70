// BHD-70 – silnik widziany ze Swifta: ścieżki, start, dźwięk, MIDI.
//
// Dźwięk liczy prawdziwy firmware D-70 w emulatorze, który chodzi jako osobny program.
// Ten plik tylko mówi mu, gdzie leżą ROM-y i gdzie ma zapisywać pamięć brzmień.

import Foundation

public final class Silnik {
    private var uchwyt: OpaquePointer?

    /// Folder na pamięć brzmień i plik wymiany – wspólny dla aplikacji i wtyczki.
    public static var folderStanu: URL {
        let grupa = Bundle.main.object(forInfoDictionaryKey: "BHAppGroup") as? String
        if let grupa,
           let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grupa) {
            return url.appendingPathComponent("BHD70", isDirectory: true)
        }
        // Zapas: gdy nie ma grupy aplikacji (np. narzędzia pomocnicze)
        return FileManager.default.temporaryDirectory.appendingPathComponent("BHD70", isDirectory: true)
    }

    /// Emulator leży w pakiecie (w pracy nad programem – w ~/mame-d70).
    /// Program i wtyczka sięgają po tę samą kopię, żeby nie nosić dwóch.
    public static func emulatorWPakiecie() -> String? {
        let pakiet = Bundle.main.bundleURL
        let kandydaci = [
            pakiet.appendingPathComponent("Contents/MacOS/d70"),
            pakiet.appendingPathComponent("Contents/PlugIns/BHD70AU.appex/Contents/MacOS/d70"),
        ]
        for emu in kandydaci where FileManager.default.isExecutableFile(atPath: emu.path) {
            return emu.path
        }
        let e = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("mame-d70/d70")
        return FileManager.default.isExecutableFile(atPath: e.path) ? e.path : nil
    }

    /// Krój pisma wyświetlacza – jedyna kość, którą wolno nam nosić, bo nie
    /// jest Rolanda: oryginału nikt nie zgrał, ten jest dorobiony.
    public static func krojPismaWPakiecie() -> [URL] {
        let pakiet = Bundle.main.bundleURL
        var lista: [URL] = []
        if let u = Bundle.main.url(forResource: "t6963c_0101", withExtension: "bin") { lista.append(u) }
        lista.append(pakiet.appendingPathComponent("Contents/Resources/t6963c_0101.bin"))
        lista.append(pakiet.appendingPathComponent("Contents/PlugIns/BHD70AU.appex/Contents/Resources/t6963c_0101.bin"))
        lista.append(FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("mame-d70/roms/d70/t6963c_0101.bin"))
        return lista
    }

    /// Kości D-70: te, które wskazał użytkownik. W pracy nad programem – gdy
    /// użytkownik nic nie wskazał – bierzemy je z ~/mame-d70, żeby testowanie
    /// nie wymagało za każdym razem przechodzenia przez okno powitalne.
    public static func zasoby() -> (emulator: String, romy: String, wersja: String?)? {
        guard let emu = Silnik.emulatorWPakiecie() else { return nil }
        let stan = PlikiInstrumentu.sprawdz()
        if stan.moznaGrac {
            PlikiInstrumentu.dolozKrojPisma()
            return (emu, PlikiInstrumentu.folderKosci.path, stan.wersjaFirmware)
        }
        // Moja wersja (bash build.sh): kości leżą w pakiecie. Wtyczka siedzi
        // w piaskownicy i poza swój pakiet nie wyjrzy, więc to jedyna droga,
        // żeby grała bez pytania o cokolwiek.
        if let wPakiecie = Silnik.kosciWPakiecie() { return (emu, wPakiecie, nil) }
        #if BH_MOJA_WERSJA
        // Praca nad programem bez DAW-a: program (nie wtyczka) sięga do ~/mame-d70.
        // Tej furtki NIE MA w wersji na stronę – tam program ma zachowywać się
        // u mnie dokładnie tak samo jak u kogoś obcego.
        let robocze = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("mame-d70/roms")
        if FileManager.default.fileExists(atPath: robocze.appendingPathComponent("d70").path) {
            return (emu, robocze.path, nil)
        }
        #endif
        return nil
    }

    /// Kości w pakiecie – są tylko w mojej wersji, wersja na stronę ich nie ma.
    public static func kosciWPakiecie() -> String? {
        let pakiet = Bundle.main.bundleURL
        let kandydaci = [
            pakiet.appendingPathComponent("Contents/Resources/roms"),
            pakiet.appendingPathComponent("Contents/PlugIns/BHD70AU.appex/Contents/Resources/roms"),
        ]
        for r in kandydaci where FileManager.default.fileExists(atPath: r.appendingPathComponent("d70").path) {
            return r.path
        }
        return nil
    }

    /// Czy instrument ma wszystko, czego potrzebuje, żeby zagrać.
    public static var maPliki: Bool { zasoby() != nil }

    public init?() {
        guard let z = Silnik.zasoby() else { return nil }
        let stan = Silnik.folderStanu
        try? FileManager.default.createDirectory(at: stan, withIntermediateDirectories: true)
        guard let u = bhd70_utworz(z.emulator, z.romy, stan.path) else { return nil }
        uchwyt = u
        if let w = z.wersja { bhd70_wersja_firmware(u, w) }
    }

    // MARK: - Brzmienia z własnego instrumentu

    /// Wgrywa brzmienia z pliku SysEx tak, jak wchodzą ze sprzętu kablem MIDI.
    /// Trwa to tyle, co na sprzęcie – stąd postęp.
    public func wgrajBrzmienia(_ dane: Data) {
        guard let w = wsk, !dane.isEmpty else { return }
        dane.withUnsafeBytes { bufor in
            if let p = bufor.bindMemory(to: UInt8.self).baseAddress {
                bhd70_sysex(w, p, UInt32(dane.count))
            }
        }
    }

    /// Czy samoczynne wgrywanie brzmień po rozruchu jest włączone.
    ///
    /// WYŁĄCZONE, i to nie jest przeoczenie. D-70 nie przyjmuje zgrania pamięci
    /// w zwykłym trybie gry -- Roland zrobił do tego osobny tryb serwisowy
    /// („Extend Product Mode”): instrument trzeba włączyć z przytrzymanym
    /// klawiszem [5] i wybrać F.2 „Bulk Load All Memory from MIDI”. Dopiero tam
    /// firmware przyjmuje cały zrzut i zapisuje go do pamięci.
    ///
    /// Tego nie da się zrobić „po cichu” przy rozruchu, bo trzeba instrument
    /// zgasić i włączyć na nowo. Robi to przycisk SYSEX na panelu -- patrz
    /// WgrywanieSysex.swift. Tam cała droga jest przejechana i sprawdzona:
    /// po wgraniu w pamięci stoją nazwy brzmień („D Piano+ 1”, „Grandioso”…).
    ///
    /// Sama wysyłka (`wgrajBrzmienia`) jest sprawna; brakowało tylko
    /// przygotowania instrumentu, i to właśnie dokłada przycisk SYSEX.
    public static let samoWgrywanieBrzmien = false

    /// Wgrywa brzmienia wskazane przez użytkownika, jeśli instrument ich jeszcze
    /// nie ma. Wołane raz, po rozruchu.
    @discardableResult
    public func wgrajBrzmieniaJesliTrzeba() -> Bool {
        guard Silnik.samoWgrywanieBrzmien else { return false }
        let s = PlikiInstrumentu.sprawdz()
        guard s.trzebaWgracBrzmienia,
              let dane = try? Data(contentsOf: PlikiInstrumentu.plikBrzmien) else { return false }
        wgrajBrzmienia(dane)
        return true
    }

    public var wgrywaBrzmienia: Bool { wsk.map { bhd70_sysex_idzie($0) != 0 } ?? false }
    public var postepBrzmien: Int { wsk.map { Int(bhd70_sysex_postep($0)) } ?? 0 }

    /// Przerywa wysyłkę w trakcie – gdy widać, że instrument jej nie przyjmuje.
    public func przerwijWgrywanie() { if let w = wsk { bhd70_sysex_przerwij(w) } }

    /// Czy TA kopia instrumentu trzyma wspólną, trwałą pamięć brzmień. Pierwsza
    /// uruchomiona kopia bierze ją na własność i tylko ona zapisuje zmiany;
    /// kolejne grają na kopii roboczej, więc wgrywanie z nich nic by nie dało.
    public var pamiecTrwala: Bool { wsk.map { bhd70_pamiec_trwala($0) != 0 } ?? false }

    deinit { if let u = uchwyt { bhd70_zniszcz(u) } }

    private var wsk: OpaquePointer? { uchwyt }

    public func start() { if let w = wsk { bhd70_start(w) } }
    public func stop()  { if let w = wsk { bhd70_stop(w) } }
    public var gotowy: Bool { wsk.map { bhd70_gotowy($0) != 0 } ?? false }
    public var kolejkaRamek: UInt32 { wsk.map { bhd70_kolejka_ramek($0) } ?? 0 }
    public var brakow: UInt32 { wsk.map { bhd70_brakow($0) } ?? 0 }

    /// Jeden blok dźwięku – wołane z wątku audio.
    /// Poziom wyjścia w decybelach (0 = jak instrument, bez zmiany).
    /// Prawdziwy D-70 ma suwak głośności za przetwornikiem – tu robi to samo,
    /// tylko potrafi też dodać, bo instrument z 1990 roku gra ciszej niż dzisiejsze wtyczki.
    public var poziomDb: Float = 0 {
        didSet { wzmocnienie = poziomDb == 0 ? 1 : powf(10, poziomDb / 20) }
    }
    private var wzmocnienie: Float = 1

    public func render(lewy: UnsafeMutablePointer<Float>, prawy: UnsafeMutablePointer<Float>,
                       ramek: UInt32, czestotliwosc: Double) {
        guard let w = wsk else { return }
        bhd70_render(w, lewy, prawy, ramek, czestotliwosc)
        let g = wzmocnienie
        guard g != 1 else { return }
        for k in 0..<Int(ramek) {
            lewy[k] *= g
            if prawy != lewy { prawy[k] *= g }
        }
    }

    public func midi(_ status: UInt8, _ d1: UInt8, _ d2: UInt8) {
        if let w = wsk { bhd70_midi(w, status, d1, d2) }
    }

    // MARK: - Panel

    /// Rozmiar ekranu firmware'u
    public static let ekranSzerokosc = Int(BHD70_EKRAN_SZER)
    public static let ekranWysokosc = Int(BHD70_EKRAN_WYS)
    public static let ekranBajtow = Int(BHD70_EKRAN_BAJTOW)

    /// Przepisuje obraz ekranu do `bajty` (jeden bit na piksel, zapalony = 1).
    /// Zwraca licznik odrysowania – gdy ten sam, obraz się nie zmienił.
    public func ekran(_ bajty: inout [UInt8]) -> UInt32 {
        guard let w = wsk else { return 0 }
        return bajty.withUnsafeMutableBufferPointer { bufor in
            bhd70_ekran(w, bufor.baseAddress)
        }
    }

    /// Diody panelu: bit (bank * 8 + numer), czyli LP00 = bit 0, LP37 = bit 31
    public var diody: UInt32 { wsk.map { bhd70_diody($0) } ?? 0 }
    public var diodaLearn: Bool { wsk.map { bhd70_dioda_learn($0) != 0 } ?? false }
    /// Co instrument ma wciśnięte: bit (bank * 8 + numer bitu). Obejmuje także to,
    /// co wywołał kontroler przez MIDI learn — dzięki temu panel to pokazuje.
    public var przyciski: UInt64 { wsk.map { bhd70_przyciski($0) } ?? 0 }
    /// Gdzie stoi wejście analogowe (0–7): 0–100, albo nil, gdy nie wiadomo
    public func poziomSuwaka(_ numer: UInt8) -> UInt8? {
        guard let w = wsk else { return nil }
        let v = bhd70_poziom_suwaka(w, numer)
        return v < 0 ? nil : UInt8(v)
    }

    /// Element wskazany w trybie uczenia (patrz bhd70_learn_cel)
    public var learnCel: UInt32 { wsk.map { bhd70_learn_cel($0) } ?? 0 }
    /// Szczyt z ostatniego bloku – do miernika; odczyt zeruje licznik
    /// Szczyt PO suwaku głośności – wskaźnik ma pokazywać to, co naprawdę
    /// wychodzi do DAW-a. Silnik liczy go przed wzmocnieniem, więc dokładamy je tu.
    public var szczyt: Float { (wsk.map { bhd70_szczyt($0) } ?? 0) * wzmocnienie }

    public func przycisk(bank: UInt8, bit: UInt8, wcisniety: Bool) {
        if let w = wsk { bhd70_przycisk(w, bank, bit, wcisniety ? 1 : 0) }
    }
    public func suwak(_ numer: UInt8, _ wartosc: UInt8) {
        if let w = wsk { bhd70_suwak(w, numer, wartosc) }
    }
    public func pokretlo(_ krokow: Int) {
        if let w = wsk { bhd70_pokretlo(w, Int32(krokow)) }
    }
    /// Przyciski MIDI learn: bit 0 = LEARN, bit 1 = CLEAR
    public func learn(bit: UInt8, wcisniety: Bool) {
        if let w = wsk { bhd70_learn(w, bit, wcisniety ? 1 : 0) }
    }

    /// Nasłuch MIDI ze wszystkich urządzeń – tylko aplikacja; we wtyczce nuty podaje DAW.
    /// `zrodlo` puste = wszystkie urządzenia. Wolno wołać wielokrotnie –
    /// podłącza to, co pojawiło się później.
    public func sluchajMidi(_ wlacz: Bool, zrodlo: String = "") {
        if let w = wsk { bhd70_sluchaj_midi(w, wlacz ? 1 : 0, zrodlo.isEmpty ? nil : zrodlo) }
    }

    public func polowka(wGore: Bool, trzymane: Bool) {
        if let w = wsk { bhd70_polowka(w, wGore ? 1 : 0, trzymane ? 1 : 0) }
    }
}
