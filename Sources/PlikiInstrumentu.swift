// BHD-70 – pliki, których instrument potrzebuje od użytkownika.
//
// BHD-70 nie nosi w sobie oprogramowania Rolanda i nosić go nie może: firmware
// D-70 i jego brzmienia są własnością Rolanda. Żeby instrument zagrał, trzeba
// mieć własny D-70 i zgrać z niego trzy rzeczy:
//
//   1. firmware – dwie kości EPROM (parzysta IC4 i nieparzysta IC9),
//   2. fale – sześć kości z brzmieniami PCM (waverom A–F),
//   3. brzmienia – zgranie pamięci przez MIDI (plik .syx albo .mid).
//
// Ten plik rozpoznaje je po sumach kontrolnych (nie po nazwach – użytkownik
// mógł je nazwać jak chciał), układa tam, gdzie emulator ich szuka, i mówi,
// czego brakuje.

import CryptoKit
import Foundation

public enum PlikiInstrumentu {

    // MARK: - Czego instrument potrzebuje

    public struct Kosc {
        public let nazwa: String       // nazwa, pod jaką emulator jej szuka
        public let sha1: String
        public let bajtow: Int
    }

    /// Wersje firmware'u, które emulator zna. Wystarczy jedna – dowolna.
    public struct Firmware {
        public let wersja: String      // tak nazywa ją emulator: "v119"
        public let opis: String        // tak nazywa ją Roland: "1.19"
        public let parzysta: Kosc
        public let nieparzysta: Kosc
    }

    public static let firmware: [Firmware] = [
        Firmware(wersja: "v119", opis: "1.19",
                 parzysta: Kosc(nazwa: "roland_d70_v1.19_a_even.ic4",
                                sha1: "174962eb42f56aaf936aeca4db77228bf19ec97a", bajtow: 65536),
                 nieparzysta: Kosc(nazwa: "roland_d70_v1.19_b_odd.ic9",
                                   sha1: "9ef2d62b1be5c38b9fa0072a5889b8ab0e47623e", bajtow: 65536)),
        Firmware(wersja: "v116", opis: "1.16",
                 parzysta: Kosc(nazwa: "roland_d70_v1.16_a_even.ic4",
                                sha1: "18bd2c8390d67f1000fae652f51a03322bb088cd", bajtow: 65536),
                 nieparzysta: Kosc(nazwa: "roland_d70_v1.16_b_odd.ic9",
                                   sha1: "530408a8ae8d74786cb8179892b7e3a24db93000", bajtow: 65536)),
        Firmware(wersja: "v114", opis: "1.14",
                 parzysta: Kosc(nazwa: "roland_d70_v1.14_a_even.ic4",
                                sha1: "73ad2d897f51449111064e92b515a4118fee4dad", bajtow: 65536),
                 nieparzysta: Kosc(nazwa: "roland_d70_v1.14_b_odd.ic9",
                                   sha1: "8c2019c20b60d4fbb5f5956bce672a84f515215b", bajtow: 65536)),
        Firmware(wersja: "v112", opis: "1.12",
                 parzysta: Kosc(nazwa: "roland_d70_v1.12_a_even.ic4",
                                sha1: "07e7545c2dae93311f7b5d77b65c548e56391748", bajtow: 65536),
                 nieparzysta: Kosc(nazwa: "roland_d70_v1.12_b_odd.ic9",
                                   sha1: "15cb5ecb956205dc9d6254822178139a228790d8", bajtow: 65536)),
        Firmware(wersja: "v110", opis: "1.10",
                 parzysta: Kosc(nazwa: "roland_d70_v1.10_a_even.ic4",
                                sha1: "15d9249c35c3db6a7d1df6a4f4e42f0ce99f11a5", bajtow: 65536),
                 nieparzysta: Kosc(nazwa: "roland_d70_v1.10_b_odd.ic9",
                                   sha1: "cde358c1ec205f446114f478b43269b01b8be048", bajtow: 65536)),
    ]

    /// Sześć kości z falami – wszystkie są potrzebne.
    public static let fale: [Kosc] = [
        Kosc(nazwa: "roland_d70_waverom-a.bin", sha1: "4872530870d5079776e80e477febe425dc0ec1df", bajtow: 524288),
        Kosc(nazwa: "roland_d70_waverom-b.bin", sha1: "49e55fa672020f95fd9c858ceaae94d6db93df7d", bajtow: 524288),
        Kosc(nazwa: "roland_d70_waverom-c.bin", sha1: "9b6b59ab74e5bf838702abb087c408aaa85b7b1f", bajtow: 524288),
        Kosc(nazwa: "roland_d70_waverom-d.bin", sha1: "3fcbcfd0d8d0fa419c710304c12482e2f79a907f", bajtow: 524288),
        Kosc(nazwa: "roland_d70_waverom-e.bin", sha1: "d378ac89a5963e37f7c157b3c8e71892c334fd7b", bajtow: 524288),
        Kosc(nazwa: "roland_d70_waverom-f.bin", sha1: "acd867d68e49e5f59f1006ed14a7ca197b6dc4af", bajtow: 524288),
    ]

    /// Krój pisma wyświetlacza. Tego Roland nie zgrał nigdy i nikt go nie ma –
    /// jest dorobiony i leży w programie, więc użytkownik go nie szuka.
    public static let krojPisma = "t6963c_0101.bin"

    // MARK: - Gdzie to leży

    /// Katalog, w którym emulator szuka kości (rompath). Wspólny dla programu
    /// i dla wtyczki, bo leży w katalogu grupy aplikacji.
    public static var folderKosci: URL {
        Silnik.folderStanu.appendingPathComponent("kosci", isDirectory: true)
    }

    /// Emulator chce je w podkatalogu o nazwie instrumentu.
    public static var folderD70: URL {
        folderKosci.appendingPathComponent("d70", isDirectory: true)
    }

    /// Brzmienia zgrane z własnego instrumentu – czekają tu na wgranie.
    public static var plikBrzmien: URL {
        Silnik.folderStanu.appendingPathComponent("brzmienia.syx")
    }

    /// Pamięć brzmień instrumentu – jest, gdy instrument już raz grał.
    public static var pamiecBrzmien: URL {
        Silnik.folderStanu.appendingPathComponent("pamiec/d70/nvram")
    }

    // MARK: - Co już mamy

    public struct Stan {
        /// Wersja firmware'u, którą znaleziono ("v119"), albo nil.
        public var wersjaFirmware: String?
        public var opisFirmware: String?
        /// Których fal brakuje (litery A–F).
        public var brakujaceFale: [String] = []
        /// Czy jest plik z brzmieniami do wgrania.
        public var saBrzmienia = false
        /// Czy instrument ma już swoją pamięć (czyli brzmienia raz wgrane).
        public var pamiecZalozona = false

        /// Czy instrument może zagrać.
        public var moznaGrac: Bool { wersjaFirmware != nil && brakujaceFale.isEmpty }
        /// Czy po rozruchu trzeba wgrać brzmienia.
        public var trzebaWgracBrzmienia: Bool { moznaGrac && !pamiecZalozona && saBrzmienia }
    }

    public static func sprawdz() -> Stan {
        var s = Stan()
        let fm = FileManager.default
        for f in firmware {
            if fm.fileExists(atPath: folderD70.appendingPathComponent(f.parzysta.nazwa).path),
               fm.fileExists(atPath: folderD70.appendingPathComponent(f.nieparzysta.nazwa).path) {
                s.wersjaFirmware = f.wersja
                s.opisFirmware = f.opis
                break
            }
        }
        for (i, k) in fale.enumerated() where !fm.fileExists(atPath: folderD70.appendingPathComponent(k.nazwa).path) {
            s.brakujaceFale.append(String(UnicodeScalar(UInt8(65 + i))))
        }
        s.saBrzmienia = fm.fileExists(atPath: plikBrzmien.path)
        s.pamiecZalozona = fm.fileExists(atPath: pamiecBrzmien.path)
        return s
    }

    // MARK: - Wkładanie plików użytkownika

    public struct Raport {
        public var rozpoznane: [String] = []        // nazwy kości, które weszły
        public var brzmieniaZ: String?              // z jakiego pliku wzięto brzmienia
        public var bajtowBrzmien = 0
        public var stan = Stan()
        public var przejrzanych = 0
    }

    public enum Blad: LocalizedError {
        case nicNieZnaleziono
        case niemaDostepu

        public var errorDescription: String? {
            switch self {
            case .nicNieZnaleziono:
                return tr("W tym folderze nie ma żadnego pliku D-70, który bym rozpoznał.",
                          "This folder has no D-70 file I could recognise.")
            case .niemaDostepu:
                return tr("Nie mogę zajrzeć do tego folderu.", "I cannot look inside this folder.")
            }
        }
    }

    /// Przegląda folder (razem z podfolderami), rozpoznaje pliki D-70 po sumach
    /// kontrolnych i układa je tam, gdzie emulator ich szuka. Nazwy plików nie
    /// mają znaczenia – liczy się zawartość.
    public static func wezZFolderu(_ folder: URL) throws -> Raport {
        let fm = FileManager.default
        var r = Raport()

        // Czego szukamy, po sumie kontrolnej
        var poSha: [String: String] = [:]           // sha1 -> nazwa docelowa
        for f in firmware {
            poSha[f.parzysta.sha1] = f.parzysta.nazwa
            poSha[f.nieparzysta.sha1] = f.nieparzysta.nazwa
        }
        for k in fale { poSha[k.sha1] = k.nazwa }
        let rozmiary = Set(firmware.flatMap { [$0.parzysta.bajtow] } + fale.map(\.bajtow) + [65536])

        try? fm.createDirectory(at: folderD70, withIntermediateDirectories: true)

        guard let chodz = fm.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            throw Blad.niemaDostepu
        }

        var kandydaciNaBrzmienia: [(URL, Int)] = []
        while let url = chodz.nextObject() as? URL {
            guard let w = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  w.isRegularFile == true, let rozmiar = w.fileSize else { continue }
            r.przejrzanych += 1
            if r.przejrzanych > 20000 { break }      // ktoś wskazał cały dysk

            // Brzmienia: plik SysEx albo MIDI. Tych nie da się sprawdzić sumą –
            // każdy ma swoje własne brzmienia w instrumencie.
            let koncowka = url.pathExtension.lowercased()
            if (koncowka == "syx" || koncowka == "mid" || koncowka == "midi"),
               rozmiar > 256, rozmiar < 4_000_000 {
                kandydaciNaBrzmienia.append((url, rozmiar))
                continue
            }

            // Kości: rozpoznajemy po zawartości, nie po nazwie.
            guard rozmiary.contains(rozmiar), let dane = try? Data(contentsOf: url) else { continue }
            let suma = Insecure.SHA1.hash(data: dane).map { String(format: "%02x", $0) }.joined()
            guard let nazwa = poSha[suma] else { continue }
            let cel = folderD70.appendingPathComponent(nazwa)
            try? fm.removeItem(at: cel)
            try fm.copyItem(at: url, to: cel)
            if !r.rozpoznane.contains(nazwa) { r.rozpoznane.append(nazwa) }
        }

        // Z brzmień bierzemy ten plik, w którym jest ich najwięcej.
        var najlepsze: (URL, Data)?
        for (url, _) in kandydaciNaBrzmienia {
            guard let dane = try? Data(contentsOf: url) else { continue }
            let wyjete = url.pathExtension.lowercased() == "syx" ? wytnijSysex(dane) : sysexZMidi(dane)
            guard wyjete.count > (najlepsze?.1.count ?? 0) else { continue }
            najlepsze = (url, wyjete)
        }
        if let (url, dane) = najlepsze, !dane.isEmpty {
            try? dane.write(to: plikBrzmien)
            r.brzmieniaZ = url.lastPathComponent
            r.bajtowBrzmien = dane.count
        }

        dolozKrojPisma()
        r.stan = sprawdz()
        if r.rozpoznane.isEmpty && r.brzmieniaZ == nil { throw Blad.nicNieZnaleziono }
        return r
    }

    /// Krój pisma wyświetlacza leży w programie – dokładamy go do kości.
    public static func dolozKrojPisma() {
        let fm = FileManager.default
        let cel = folderD70.appendingPathComponent(krojPisma)
        guard !fm.fileExists(atPath: cel.path) else { return }
        try? fm.createDirectory(at: folderD70, withIntermediateDirectories: true)
        for zrodlo in Silnik.krojPismaWPakiecie() where fm.fileExists(atPath: zrodlo.path) {
            try? fm.copyItem(at: zrodlo, to: cel)
            return
        }
    }

    /// Kasuje wszystko, co użytkownik wskazał – żeby mógł zacząć od nowa.
    public static func zapomnij() {
        let fm = FileManager.default
        try? fm.removeItem(at: folderKosci)
        try? fm.removeItem(at: plikBrzmien)
        try? fm.removeItem(at: Silnik.folderStanu.appendingPathComponent("pamiec"))
    }

    // MARK: - Wyjmowanie SysEx

    /// Zostawia z pliku tylko całe komunikaty SysEx (od F0 do F7).
    static func wytnijSysex(_ dane: Data) -> Data {
        var wynik = Data()
        var i = dane.startIndex
        while i < dane.endIndex {
            guard dane[i] == 0xF0 else { i = dane.index(after: i); continue }
            var k = dane.index(after: i)
            while k < dane.endIndex, dane[k] != 0xF7 { k = dane.index(after: k) }
            guard k < dane.endIndex else { break }
            wynik.append(contentsOf: dane[i...k])
            i = dane.index(after: k)
        }
        return wynik
    }

    /// Wyjmuje komunikaty SysEx z pliku MIDI (tak wygląda fabryczna dyskietka D-70).
    static func sysexZMidi(_ dane: Data) -> Data {
        let b = [UInt8](dane)
        guard b.count > 14, b[0] == 0x4D, b[1] == 0x54, b[2] == 0x68, b[3] == 0x64 else {
            return wytnijSysex(dane)        // to jednak zwykły SysEx
        }
        var wynik = Data()
        var i = 14                           // za nagłówkiem MThd
        while i + 8 <= b.count {
            let znacznik = (UInt32(b[i]) << 24) | (UInt32(b[i + 1]) << 16) | (UInt32(b[i + 2]) << 8) | UInt32(b[i + 3])
            let dlugosc = Int((UInt32(b[i + 4]) << 24) | (UInt32(b[i + 5]) << 16) | (UInt32(b[i + 6]) << 8) | UInt32(b[i + 7]))
            let poczatek = i + 8
            let koniec = min(poczatek + dlugosc, b.count)
            i = poczatek + dlugosc
            guard znacznik == 0x4D54726B else { continue }     // MTrk

            var k = poczatek
            var ostatniStatus: UInt8 = 0
            func zmienna() -> Int {
                var w = 0
                while k < koniec {
                    let bajt = b[k]; k += 1
                    w = (w << 7) | Int(bajt & 0x7F)
                    if bajt & 0x80 == 0 { break }
                }
                return w
            }
            while k < koniec {
                _ = zmienna()                                   // czas – nieistotny
                guard k < koniec else { break }
                let status = b[k]
                if status == 0xFF {                             // zdarzenie porządkowe
                    k += 2
                    let dl = zmienna(); k += dl
                } else if status == 0xF0 || status == 0xF7 {    // SysEx
                    k += 1
                    let dl = zmienna()
                    let kon = min(k + dl, koniec)
                    if status == 0xF0 { wynik.append(0xF0) }
                    wynik.append(contentsOf: b[k..<kon])
                    k = kon
                } else if status & 0x80 != 0 {                  // zwykła nuta itp.
                    ostatniStatus = status; k += 1
                    k += ((status & 0xF0) == 0xC0 || (status & 0xF0) == 0xD0) ? 1 : 2
                } else {                                        // status biegnący
                    k += ((ostatniStatus & 0xF0) == 0xC0 || (ostatniStatus & 0xF0) == 0xD0) ? 1 : 2
                }
            }
        }
        return wynik
    }
}
