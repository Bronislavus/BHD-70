// BHD-70 – panel instrumentu: wierny układ prawdziwego D-70 w kolorach serii BH.
//
// Wszystkie pozycje bierzemy z PanelUklad.swift (przepisanego z emulatora), więc
// przyciski, suwaki i pokrętło stoją dokładnie tam, gdzie na sprzęcie. Nowe jest
// tylko jedno udogodnienie: trójkącik przy nazwie na wyświetlaczu rozwija listę.
//
// Wyświetlacz pokazuje prawdziwe piksele firmware'u (240 × 64), pomalowane
// kolorem akcentu serii na ciemnym tle.

import SwiftUI

// MARK: - Model panelu (wątek główny)

/// Pilnuje obrazu ekranu i diod – odpytuje silnik ponad 30 razy na sekundę.
public final class PanelModel: ObservableObject {
    @Published public private(set) var obraz: [UInt8] = Array(repeating: 0, count: Silnik.ekranBajtow)
    @Published public private(set) var diody: UInt32 = 0
    @Published public private(set) var diodaLearn = false
    @Published public private(set) var learnCel: UInt32 = 0
    /// Co instrument ma wciśnięte i gdzie stoją jego suwaki – także wtedy, gdy
    /// zrobił to kontroler przez MIDI learn, a nie mysz
    @Published public private(set) var przyciski: UInt64 = 0
    @Published public private(set) var suwaki: [UInt8] = Array(repeating: 50, count: 8)
    @Published public private(set) var gotowy = false
    /// Szczyt wyjścia do wskaźnika; odczyt z silnika zeruje licznik, więc trzymamy opadanie
    @Published public private(set) var szczyt: Float = 0
    @Published public private(set) var kolejka: UInt32 = 0
    /// Wgrywanie brzmień z własnego zgrania D-70 (pierwsze uruchomienie)
    @Published public private(set) var wgrywaBrzmienia = false
    @Published public private(set) var postepBrzmien = 0
    private var brzmieniaRuszyly = false

    private let silnik: Silnik?
    private let zapamietuj: Bool
    private var licznik: UInt32 = 0
    private var zegar: Timer?
    private var bufor = [UInt8](repeating: 0, count: Silnik.ekranBajtow)

    /// Poziom wyjścia TEJ kopii instrumentu. Każda wstawiona wtyczka ma własny –
    /// dlatego nie trzymamy go w ustawieniach programu, bo te są wspólne dla
    /// wszystkich kopii w jednym procesie i suwak ruszałby się we wszystkich naraz.
    @Published public var poziomDb: Double = 0 {
        didSet {
            silnik?.poziomDb = Float(poziomDb)
            if zapamietuj { UserDefaults.standard.set(poziomDb, forKey: "poziomDb") }
        }
    }

    public init(silnik: Silnik?, zapamietuj: Bool = false) {
        self.silnik = silnik
        self.zapamietuj = zapamietuj
        // Program pamięta poziom między uruchomieniami; wtyczka bierze go z projektu
        // DAW-a (przychodzi do silnika, zanim powstanie panel albo chwilę po nim)
        if zapamietuj, let zapisany = UserDefaults.standard.object(forKey: "poziomDb") as? Double {
            poziomDb = zapisany
            silnik?.poziomDb = Float(poziomDb)
        } else {
            poziomDb = Double(silnik?.poziomDb ?? 0)
        }
        zegar = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.odczyt()
        }
    }

    deinit { zegar?.invalidate() }

    private func odczyt() {
        guard let silnik else { return }
        let nowy = silnik.ekran(&bufor)
        if nowy != licznik {
            licznik = nowy
            obraz = bufor
        }
        let d = silnik.diody
        if d != diody { diody = d }
        let l = silnik.diodaLearn
        if l != diodaLearn { diodaLearn = l }
        let c = silnik.learnCel
        if c != learnCel { learnCel = c }
        let wcis = silnik.przyciski
        if wcis != przyciski { przyciski = wcis }
        var nowe = suwaki
        var zmiana = false
        for i in 0..<8 where silnik.poziomSuwaka(UInt8(i)) != nil {
            let v = silnik.poziomSuwaka(UInt8(i))!
            if nowe[i] != v { nowe[i] = v; zmiana = true }
        }
        if zmiana { suwaki = nowe }
        let g = silnik.gotowy
        if g != gotowy { gotowy = g }
        let sz = silnik.szczyt
        let opadniety = max(sz, szczyt * 0.72)
        if abs(opadniety - szczyt) > 0.0005 { szczyt = opadniety }
        // Poziom mógł przyjść z projektu DAW-a już po otwarciu panelu
        let p = Double(silnik.poziomDb)
        if abs(p - poziomDb) > 0.01 { poziomDb = p }
        kolejka = silnik.kolejkaRamek
        // Instrument właśnie wstał, a pamięć brzmień jest pusta – wgrywamy
        // zgranie z własnego D-70, tak jak wchodzi ze sprzętu kablem MIDI.
        if g && !brzmieniaRuszyly {
            brzmieniaRuszyly = true
            silnik.wgrajBrzmieniaJesliTrzeba()
        }
        let w = silnik.wgrywaBrzmienia
        if w != wgrywaBrzmienia { wgrywaBrzmienia = w }
        if w { postepBrzmien = silnik.postepBrzmien }
    }

    /// Czy instrument trzyma ten przycisk wciśnięty (bez względu na to, kto go nacisnął)
    public func wcisnietyWInstrumencie(port: String, bit: UInt8) -> Bool {
        guard port.hasPrefix("KEY"), let bank = UInt8(port.dropFirst(3)), bank < 8 else { return false }
        let numer = bit.trailingZeroBitCount
        return przyciski & (UInt64(1) << UInt64(Int(bank) * 8 + numer)) != 0
    }

    /// Czy ten przycisk jest w trybie uczenia wskazany
    public func wskazanyPrzycisk(port: String, bit: UInt8) -> Bool {
        guard learnCel >> 24 == 1, port.hasPrefix("KEY"),
              let bank = UInt8(port.dropFirst(3)) else { return false }
        return UInt8((learnCel >> 16) & 0xff) == bank && UInt8((learnCel >> 8) & 0xff) == bit
    }
    /// Czy ten suwak (numer wejścia analogowego) jest wskazany
    public func wskazanySuwak(_ numer: Int) -> Bool {
        learnCel >> 24 == 2 && Int((learnCel >> 16) & 0xff) == numer
    }

    /// Czy świeci dioda o nazwie z układu (LPrc albo learn_led)
    public func swieci(_ nazwa: String) -> Bool {
        if nazwa == "learn_led" { return diodaLearn }
        guard nazwa.count == 4, nazwa.hasPrefix("LP"),
              let bank = nazwa.dropFirst(2).first?.wholeNumberValue,
              let numer = nazwa.last?.wholeNumberValue,
              bank >= 0, bank < 4, numer >= 0, numer < 8 else { return false }
        return diody & (1 << UInt32(bank * 8 + numer)) != 0
    }
}

// MARK: - Panel

public struct PanelView: View {
    /// Sam panel ma stałe proporcje prawdziwego D-70 (1044 × 497 punktów)
    public static let panelRozmiar = CGSize(width: PanelUklad.szerokosc, height: PanelUklad.wysokosc)
    /// Wysokość nagłówka serii i stopki nad/pod panelem
    static let gora: CGFloat = 74
    static let dol: CGFloat = 30
    /// Zalecana wielkość okna wtyczki
    public static let rozmiar = CGSize(width: panelRozmiar.width + 36,
                                       height: panelRozmiar.height + gora + dol)

    private let silnik: Silnik?
    /// Podane tylko w programie na Maca – wtyczka ustawień audio nie ma
    private let ustawieniaAudio: (() -> Void)?
    @StateObject private var model: PanelModel
    /// Wgrywanie plików SysEx – pod przyciskiem SYSEX nad krzyżakiem kursora
    @StateObject private var sysex: WgrywanieSysex
    @State private var wcisniete: Set<String> = []
    @State private var suwaki: [UInt8] = [50, 50, 50, 50]
    /// Który suwak jest właśnie ciągnięty myszą (wtedy panel nie nadpisuje go stanem instrumentu)
    @State private var ciagniety: Int?
    @State private var instrukcja = false
    @State private var okienkoSysex = false
    /// Poziom wyjścia w decybelach – zapamiętywany między uruchomieniami


    /// `poRestarcie` – program musi po ponownym włączeniu instrumentu podłączyć
    /// nasłuch MIDI od nowa; wtyczka nie ma czego podłączać i nic nie podaje.
    public init(silnik: Silnik?, ustawieniaAudio: (() -> Void)? = nil,
                poRestarcie: (() -> Void)? = nil) {
        self.silnik = silnik
        self.ustawieniaAudio = ustawieniaAudio
        _model = StateObject(wrappedValue: PanelModel(silnik: silnik,
                                                      zapamietuj: ustawieniaAudio != nil))
        _sysex = StateObject(wrappedValue: WgrywanieSysex(silnik: silnik,
                                                          poRestarcie: poRestarcie))
    }

    public var body: some View {
        GeometryReader { geo in
            let dostepnaW = max(1, geo.size.width - 36)
            let dostepnaH = max(1, geo.size.height - Self.gora - Self.dol)
            let skala = min(dostepnaW / Self.panelRozmiar.width,
                            dostepnaH / Self.panelRozmiar.height)
            VStack(spacing: 0) {
                naglowek
                    .frame(height: Self.gora)
                    .padding(.horizontal, 18)
                panel
                    .frame(width: Self.panelRozmiar.width, height: Self.panelRozmiar.height)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Theme.line, lineWidth: 1))
                    .shadow(color: .black.opacity(0.55), radius: 10, y: 5)
                    .scaleEffect(skala)
                    .frame(width: Self.panelRozmiar.width * skala,
                           height: Self.panelRozmiar.height * skala)
                Spacer(minLength: 0)
                CreditsFooter()
                    .font(.system(size: 10))
                    .frame(height: Self.dol)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .heroBackground(height: 260)
        .themedWindow()
        // Okno przycisku SYSEX. Tak samo jak instrukcja – nakładką, a nie arkuszem:
        // we wtyczce w DAW-ie osobne okienka systemowe bywają kapryśne.
        .overlay {
            if okienkoSysex {
                ZStack {
                    Theme.bg.opacity(0.75)
                        .ignoresSafeArea()
                        .onTapGesture { if !sysex.pracuje { okienkoSysex = false } }
                    OknoSysex(model: sysex,
                              // Okno wyboru pliku otwiera tylko program; wtyczka
                              // korzysta z plików dołożonych w programie (lista wspólna).
                              moznaWskazac: ustawieniaAudio != nil,
                              zamknij: { okienkoSysex = false })
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bg))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Theme.line, lineWidth: 1))
                        .shadow(color: .black.opacity(0.6), radius: 18, y: 8)
                }
                .transition(.opacity)
            }
        }
        // Instrukcja w oknie instrumentu – we wtyczce nie ma osobnych okien,
        // a w programie to samo otwiera też menu Pomoc.
        .overlay {
            if instrukcja {
                ZStack(alignment: .topTrailing) {
                    Theme.bg.opacity(0.97)
                    HelpView(doc: HelpContent.doc)
                    Button { instrukcja = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.text2)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Theme.surface))
                            .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(14)
                }
                .transition(.opacity)
            }
        }
    }

    /// Nagłówek serii: słupki, hasło, nazwa programu i stan instrumentu
    private var naglowek: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                LevelGlyph()
                Text(Brand.slogan)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(2.2)
                    .foregroundColor(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                BrandName(name: "BHD-70", size: 26)
                // Napis z oryginalnej obudowy D-70
                Text("SUPER LA SYNTHESIZER")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.6)
                    .foregroundColor(Theme.text2)
            }
            Spacer(minLength: 0)
            wskaznik
                .padding(.bottom, 3)
            // W trybie MIDI learn komunikat u góry jest długi i nie zostawia
            // miejsca na suwak głośności – wtedy go chowamy, bo i tak nie da się
            // go przypisać do kontrolera. Po wyjściu z trybu wraca na miejsce.
            if !model.diodaLearn {
                poziomWyjscia
                    .padding(.bottom, 3)
            }
            Button { instrukcja = true } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.text2)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.surface.opacity(0.85)))
                    .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(tr("Instrukcja", "User guide"))
            .padding(.bottom, 3)
            if let ustawieniaAudio {
                Button(action: ustawieniaAudio) {
                    Label(tr("Audio i MIDI", "Audio and MIDI"), systemImage: "slider.horizontal.3")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.text2)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.surface.opacity(0.85)))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 3)
            }
            stanInstrumentu
                .padding(.bottom, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }

    /// Wskaźnik sygnału – od razu widać, czy ta kopia instrumentu w ogóle gra.
    /// Pokazuje poziom PO suwaku, czyli to, co naprawdę wychodzi do DAW-a.
    private var wskaznik: some View {
        let poziom = CGFloat(min(1, max(0, model.szczyt)))
        return HStack(spacing: 2) {
            ForEach(0..<14, id: \.self) { i in
                let prog = CGFloat(i + 1) / 14
                RoundedRectangle(cornerRadius: 1)
                    .fill(poziom >= prog
                          ? (i >= 12 ? Color.red : i >= 10 ? Theme.accentHover : Theme.accent)
                          : Theme.faint.opacity(0.22))
                    .frame(width: 3, height: 4 + CGFloat(i) * 0.9)
            }
        }
        .frame(height: 18, alignment: .bottom)
        .help(tr("Sygnał na wyjściu tej kopii instrumentu",
                 "Output signal of this instrument copy"))
    }

    /// Poziom wyjścia. Prawdziwy D-70 ma suwak głośności za przetwornikiem;
    /// nasz robi to samo, a dodatkowo potrafi dodać, bo instrument z 1990 roku
    /// gra ciszej niż dzisiejsze wtyczki.
    private var poziomWyjscia: some View {
        HStack(spacing: 7) {
            Text("VOLUME")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(Theme.faint)
                .fixedSize()        // nigdy nie łam tego napisu na litery
            Slider(value: $model.poziomDb, in: -24...18, step: 0.5)
                .controlSize(.mini)
                .frame(width: 110)
                .tint(Theme.accent)
            Text(model.poziomDb == 0 ? "0 dB" : String(format: "%+.1f dB", model.poziomDb))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(model.poziomDb == 0 ? Theme.faint : Theme.accent)
                .frame(width: 54, alignment: .leading)
        }
        .help(tr("Poziom wyjścia instrumentu. Dwa kliknięcia na suwaku wracają do zera.",
                 "Instrument output level. Double-click the slider to return to zero."))
        .gesture(TapGesture(count: 2).onEnded { model.poziomDb = 0 })
    }

    private var stanInstrumentu: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.diodaLearn ? Theme.accentHover
                      : model.gotowy ? Theme.accent : Theme.faint.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(model.diodaLearn
                 ? tr("MIDI learn: kliknij element, potem rusz kontrolerem",
                      "MIDI learn: click a control, then move your controller")
                 : model.wgrywaBrzmienia
                 ? tr("wgrywam Twoje brzmienia… \(model.postepBrzmien)%",
                      "loading your sounds… \(model.postepBrzmien)%")
                 : model.gotowy ? tr("gotowy", "ready")
                                : tr("instrument się uruchamia…", "starting up…"))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(model.diodaLearn ? Theme.accentHover
                                 : model.gotowy ? Theme.text2 : Theme.accent.opacity(0.85))
        }
    }

    private var panel: some View {
        ZStack(alignment: .topLeading) {
            Theme.bg
            tlo
            wyswietlacz
            przyciski
            // Opisy nad przyciskami: na D-70 czesc z nich lezy na samym przycisku
            napisy
            strzalki
            diody
            toneSuwaki
            pokretlo
            przyciskSysex
        }
    }

    /// Przycisk SYSEX – nad krzyżakiem kursora. Na prawdziwym D-70 go nie ma:
    /// tam zgranie pamięci wsadza się kablem MIDI po wejściu w tryb serwisowy.
    /// Tutaj robi to za użytkownika program, a przycisk jest drogą do tego.
    ///
    /// Nie ma go w PanelUklad.swift, bo ten plik odtwarza się z układu emulatora
    /// i wpis by przy tym przepadł.
    private static let poleSysex = pole(889, 56, 99, 16)

    private var przyciskSysex: some View {
        // Naciskanie dokładnie tak, jak pozostałe przyciski panelu: zwykły
        // onTapGesture nie dochodził tu do skutku.
        ZStack {
            PrzyciskView(wcisniety: wcisniete.contains("sysex") || okienkoSysex,
                         polowkaPokretla: false)
            Text("SYSEX")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(sysex.pracuje ? Theme.accent : Theme.muted)
        }
        .frame(width: Self.poleSysex.width, height: Self.poleSysex.height)
        .offset(x: Self.poleSysex.minX, y: Self.poleSysex.minY)
        .help(tr("Wgraj do pamięci instrumentu własny plik SysEx (np. brzmienia zgrane z Twojego D-70)",
                 "Load your own SysEx file into the instrument memory (e.g. sounds taken from your D-70)"))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in wcisniete.insert("sysex") }
                .onEnded { _ in
                    wcisniete.remove("sysex")
                    sysex.odswiezListe()
                    okienkoSysex = true
                }
        )
    }

    // MARK: Tło – płyty, ramki i kreski panelu (w kolejności z prawdziwego D-70)

    private var tlo: some View {
        ForEach(Array(PanelUklad.tlo.enumerated()), id: \.offset) { _, e in
            ksztaltTla(e)
                .frame(width: e.pole.width, height: e.pole.height)
                .offset(x: e.pole.minX, y: e.pole.minY)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func ksztaltTla(_ e: PanelUklad.Kreska) -> some View {
        switch e.rodzaj {
        case "cpanel":
            RoundedRectangle(cornerRadius: e.pole.height > 40 ? 6 : 2)
                .fill(Theme.surface)
        case "lcd_border":
            RoundedRectangle(cornerRadius: 4).fill(Theme.surface2)
        case "lcd_bg":
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x06090D))
        case "grey_rect":
            // obwódka wokół napisu (PANIC, ROM PLAY) – wypełnia ją leżący na niej cpanel
            RoundedRectangle(cornerRadius: 2).fill(Theme.line)
        case "brown_line":
            Rectangle().fill(Theme.accent.opacity(0.55))
        default:
            Rectangle().fill(Theme.line)
        }
    }

    /// Strzalki wokol krzyzaka kursora – na sprzecie sa nadrukowane na panelu
    private var strzalki: some View {
        ForEach(Array(PanelUklad.strzalki.enumerated()), id: \.offset) { _, s in
            Strzalka(kierunek: s.kierunek)
                .fill(Theme.muted)
                .frame(width: s.pole.width, height: s.pole.height)
                .offset(x: s.pole.minX, y: s.pole.minY)
                .allowsHitTesting(false)
        }
    }

    private var napisy: some View {
        ForEach(Array(PanelUklad.napisy.enumerated()), id: \.offset) { _, n in
            Text(Self.pomijamy(n) ? "" : n.tekst)
                // Nieco mniejsza czcionka niż pole napisu – napis ma mieć wokół
                // siebie trochę powietrza, tak jak nadruk na panelu
                .font(.system(size: max(6, n.pole.height * 0.78), weight: .medium, design: .monospaced))
                .foregroundColor(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: n.pole.width, height: n.pole.height)
                .offset(x: n.pole.minX, y: n.pole.minY)
                // Napisy leżą na przyciskach – klikać ma się przycisk pod spodem
                .allowsHitTesting(false)
        }
    }

    // MARK: Wyświetlacz

    private var wyswietlacz: some View {
        EkranView(obraz: model.obraz)
            .frame(width: PanelUklad.ekran.width, height: PanelUklad.ekran.height)
            .offset(x: PanelUklad.ekran.minX, y: PanelUklad.ekran.minY)
    }

    // MARK: Przyciski i diody

    private var przyciski: some View {
        ForEach(Array(PanelUklad.przyciski.enumerated()), id: \.offset) { i, p in
            let klucz = "\(i)"
            if !Self.pomijamy(p) {
            PrzyciskView(wcisniety: wcisniete.contains(klucz)
                                     || model.wcisnietyWInstrumencie(port: p.port, bit: p.bit),
                         polowkaPokretla: p.port == "VALUE_BTN",
                         uczenie: model.diodaLearn && p.port.hasPrefix("KEY"),
                         wskazany: model.wskazanyPrzycisk(port: p.port, bit: p.bit))
                .frame(width: p.pole.width, height: p.pole.height)
                .offset(x: p.pole.minX, y: p.pole.minY)
                .help(p.opis)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard !wcisniete.contains(klucz) else { return }
                            wcisniete.insert(klucz)
                            nacisnij(p, true)
                        }
                        .onEnded { _ in
                            wcisniete.remove(klucz)
                            nacisnij(p, false)
                        }
                )
            }
        }
    }

    private var diody: some View {
        ForEach(Array(PanelUklad.diody.enumerated()), id: \.offset) { _, d in
            let swieci = model.swieci(d.nazwa)
            RoundedRectangle(cornerRadius: 1)
                .fill(swieci ? Theme.accent : Theme.accent.opacity(0.10))
                .shadow(color: swieci ? Theme.accent.opacity(0.8) : .clear,
                        radius: swieci ? 3 : 0)
                .frame(width: d.pole.width, height: d.pole.height)
                .offset(x: d.pole.minX, y: d.pole.minY)
                .allowsHitTesting(false)
        }
    }

    /// Przyciski panelu siedzą w macierzy 8 × 8 (KEY0–KEY7), pokrętło i MIDI learn osobno.
    private func nacisnij(_ p: PanelUklad.Przycisk, _ wcisniety: Bool) {
        guard let silnik else { return }
        if p.port.hasPrefix("KEY"), let bank = UInt8(p.port.dropFirst(3)) {
            silnik.przycisk(bank: bank, bit: UInt8(p.bit.trailingZeroBitCount), wcisniety: wcisniety)
        } else if p.port == "VALUE_BTN" {
            silnik.polowka(wGore: p.bit == 0x02, trzymane: wcisniety)
        } else if p.port == "LEARN" {
            silnik.learn(bit: UInt8(p.bit.trailingZeroBitCount), wcisniety: wcisniety)
        }
    }

    /// AUDIO/MIDI otwierał okno poprzedniego programu – we wtyczce i w nowej
    /// aplikacji nie ma czego otwierać, więc tego przycisku nie pokazujemy.
    private static func pomijamy(_ p: PanelUklad.Przycisk) -> Bool {
        p.port == "LEARN" && p.bit == 0x04
    }
    private static func pomijamy(_ n: PanelUklad.Napis) -> Bool {
        n.tekst == "AUDIO/MIDI"
    }

    // MARK: Suwaki Tone Palette

    private var toneSuwaki: some View {
        ForEach(Array(PanelUklad.suwaki.enumerated()), id: \.offset) { i, s in
            SuwakView(wartosc: Binding(
                get: {
                    // Pokazujemy to, co naprawdę ma instrument – także wtedy, gdy
                    // suwakiem ruszył kontroler przez MIDI learn. Tylko w trakcie
                    // ciągnięcia myszą pokazujemy swoją wartość, żeby nie szarpało.
                    ciagniety == i ? suwaki[i] : model.suwaki[4 + i]
                },
                set: { nowa in
                    ciagniety = i
                    suwaki[i] = nowa
                    // Suwaki Tone Palette to wejścia analogowe SLIDER4–SLIDER7
                    silnik?.suwak(UInt8(4 + i), nowa)
                }),
                studzienka: s.studzienka, tor: s.tor,
                uczenie: model.diodaLearn,
                wskazany: model.wskazanySuwak(4 + i),
                koniecCiagniecia: { ciagniety = nil })
                .frame(width: s.studzienka.width, height: s.studzienka.height)
                .offset(x: s.studzienka.minX, y: s.studzienka.minY)
        }
    }

    // MARK: Pokrętło VALUE

    private var pokretlo: some View {
        PokretloView { krokow in silnik?.pokretlo(krokow) }
            .frame(width: PanelUklad.pokretlo.width, height: PanelUklad.pokretlo.height)
            .offset(x: PanelUklad.pokretlo.minX, y: PanelUklad.pokretlo.minY)
    }

}

// MARK: - Wyświetlacz: prawdziwe piksele firmware'u

struct EkranView: View {
    let obraz: [UInt8]

    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: false) { kontekst, rozmiar in
            kontekst.fill(Path(CGRect(origin: .zero, size: rozmiar)),
                          with: .color(Color(hex: 0x06090D)))
            let szer = Silnik.ekranSzerokosc, wys = Silnik.ekranWysokosc
            let px = rozmiar.width / CGFloat(szer)
            let py = rozmiar.height / CGFloat(wys)
            guard obraz.count >= Silnik.ekranBajtow else { return }
            // Rysujemy ciągi zapalonych pikseli w wierszu, nie piksel po pikselu
            var sciezka = Path()
            for y in 0..<wys {
                var x = 0
                while x < szer {
                    let bit = y * szer + x
                    if obraz[bit >> 3] & (1 << (bit & 7)) != 0 {
                        var dlugosc = 1
                        while x + dlugosc < szer {
                            let b2 = y * szer + x + dlugosc
                            if obraz[b2 >> 3] & (1 << (b2 & 7)) == 0 { break }
                            dlugosc += 1
                        }
                        sciezka.addRect(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * py,
                                               width: CGFloat(dlugosc) * px, height: py))
                        x += dlugosc
                    } else {
                        x += 1
                    }
                }
            }
            kontekst.fill(sciezka, with: .color(Theme.accent))
        }
    }
}

// MARK: - Przycisk panelu

struct PrzyciskView: View {
    let wcisniety: Bool
    let polowkaPokretla: Bool
    /// W trybie MIDI learn panel podświetla to, co można przypisać
    var uczenie = false
    var wskazany = false
    /// Woła się, gdy użytkownik puści suwak – wtedy panel wraca do pokazywania
    /// tego, co naprawdę ma instrument
    var koniecCiagniecia: () -> Void = {}

    var body: some View {
        if polowkaPokretla {
            // Klikalne połówki pokrętła nie mają własnego wyglądu – tylko reagują
            Rectangle().fill(Color.clear).contentShape(Rectangle())
        } else {
            // Lekki połysk od góry – żeby przycisk wyglądał jak przycisk, a nie jak prostokąt
            RoundedRectangle(cornerRadius: 2)
                .fill(LinearGradient(
                    colors: wcisniety
                        ? [Theme.line, Color(hex: 0x1A2633)]
                        : [Color(hex: 0x2A3747), Color(hex: 0x16202B)],
                    startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(wcisniety ? Theme.accent.opacity(0.7) : Color(hex: 0x33434F),
                                      lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(wskazany ? Theme.accent : Theme.accent.opacity(0.45),
                                      lineWidth: wskazany ? 2 : 1)
                        .opacity(uczenie ? 1 : 0)
                )
                .shadow(color: wskazany ? Theme.accent.opacity(0.9)
                                        : .black.opacity(wcisniety ? 0 : 0.45),
                        radius: wskazany ? 4 : 1, y: wskazany ? 0 : 1)
                .contentShape(Rectangle())
        }
    }
}

// MARK: - Suwak Tone Palette

struct SuwakView: View {
    @Binding var wartosc: UInt8
    let studzienka: Pole
    let tor: Pole
    var uczenie = false
    var wskazany = false
    /// Woła się, gdy użytkownik puści suwak – wtedy panel wraca do pokazywania
    /// tego, co naprawdę ma instrument
    var koniecCiagniecia: () -> Void = {}

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.surface2)
                .overlay(RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(uczenie ? (wskazany ? Theme.accent : Theme.accent.opacity(0.45)) : Theme.line,
                                  lineWidth: uczenie && wskazany ? 2 : 1))
                .shadow(color: wskazany ? Theme.accent.opacity(0.9) : .clear, radius: wskazany ? 4 : 0)
            // tor suwaka
            let torX = tor.minX - studzienka.minX
            let torY = tor.minY - studzienka.minY
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: 0x0A1018))
                .frame(width: tor.width, height: tor.height)
                .offset(x: torX, y: torY)
            // gałka: 0 na dole, 100 u góry
            let zakres = tor.height - 14
            let dol = torY + tor.height - 14

            // Znacznik połowy – prawdziwy D-70 ma w tym miejscu wyczuwalny zatrzask
            let srodek = dol - zakres / 2 + 7
            ForEach([torX - 9, torX + tor.width + 4], id: \.self) { x in
                Rectangle()
                    .fill(Theme.faint.opacity(0.75))
                    .frame(width: 5, height: 1)
                    .offset(x: x, y: srodek)
            }

            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.accent.opacity(0.85))
                .frame(width: tor.width + 8, height: 14)
                .offset(x: torX - 4, y: dol - zakres * CGFloat(wartosc) / 100)

            // Odczyt 0–100 w wolnym pasku na górze studzienki
            Text("\(wartosc)")
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundColor(wartosc == 50 ? Theme.faint : Theme.accent)
                .frame(width: studzienka.width, height: torY, alignment: .center)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { ruch in
                    let torY = tor.minY - studzienka.minY
                    let t = (ruch.location.y - torY - 7) / max(1, tor.height - 14)
                    wartosc = UInt8(max(0, min(100, (1 - t) * 100)))
                }
                .onEnded { _ in koniecCiagniecia() }
        )
    }
}

// MARK: - Pokrętło VALUE

struct PokretloView: View {
    /// Oddaje liczbę kroków (dodatnie = w prawo)
    let obrot: (Int) -> Void
    @State private var ostatniKat: Double?

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(colors: [Theme.surface, Color(hex: 0x0D131B)],
                                   center: .init(x: 0.35, y: 0.3),
                                   startRadius: 2, endRadius: 60)
                )
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
            // palec: zagłębienie, za które kręci się tarczą
            Circle()
                .fill(Color(hex: 0x0A1018))
                .overlay(Circle().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
                .frame(width: PanelUklad.pokretloPalec.width,
                       height: PanelUklad.pokretloPalec.height)
                .offset(x: PanelUklad.pokretloPalec.midX - PanelUklad.pokretlo.midX,
                        y: PanelUklad.pokretloPalec.midY - PanelUklad.pokretlo.midY)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { ruch in
                    let srodek = CGPoint(x: PanelUklad.pokretlo.width / 2,
                                         y: PanelUklad.pokretlo.height / 2)
                    let kat = atan2(ruch.location.y - srodek.y, ruch.location.x - srodek.x)
                    if let poprz = ostatniKat {
                        var roznica = kat - poprz
                        if roznica > .pi { roznica -= 2 * .pi }
                        if roznica < -.pi { roznica += 2 * .pi }
                        // jeden krok na około 12 stopni obrotu
                        let kroki = Int((roznica * 180 / .pi) / 12)
                        if kroki != 0 {
                            obrot(kroki)
                            ostatniKat = kat
                        }
                    } else {
                        ostatniKat = kat
                    }
                }
                .onEnded { _ in ostatniKat = nil }
        )
    }
}

// MARK: - Strzałka krzyżaka kursora

struct Strzalka: Shape {
    /// 0 = w górę, 1 = w dół, 2 = w lewo, 3 = w prawo
    let kierunek: Int

    func path(in r: CGRect) -> Path {
        var p = Path()
        switch kierunek {
        case 0: p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        case 1: p.move(to: CGPoint(x: r.midX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        case 2: p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        default: p.move(to: CGPoint(x: r.maxX, y: r.midY)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        }
        p.closeSubpath()
        return p
    }
}
