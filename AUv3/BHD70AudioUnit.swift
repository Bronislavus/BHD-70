// BHD-70 – wtyczka AUv3 (instrument stereo). Nuty i kontrolery przychodzą z hosta,
// dźwięk liczy emulator prawdziwego firmware'u D-70.
//
// IDENTYFIKATOR (aumu BD70 BHnc) – po pierwszym wydaniu NIE ZMIENIAĆ, także w Xcode/project.yml.

import AVFoundation
import AudioToolbox

/// Bufory renderowania i częstotliwość – wszystko, czego potrzebuje wątek dźwięku.
///
/// Stąd brały się szumy w Logicu. Logic jako jedyny host nie daje wtyczce
/// własnego miejsca na dźwięk, tylko prosi, żeby wtyczka podała swoje. Wcześniej
/// podawaliśmy bufor roboczy, który przy każdym przestawieniu łańcucha (a tak
/// działa wstawienie kolejnego instrumentu) zwalnialiśmy i tworzyliśmy od nowa –
/// Logic czytał wtedy zwolnioną pamięć. Była też druga pułapka: wątek dźwięku
/// mógł zobaczyć stary wskaźnik razem z nowym rozmiarem i wyjść poza bufor.
///
/// Dlatego bufor powstaje RAZ, z zapasem na każdy sensowny blok, nigdy nie jest
/// przenoszony ani zwalniany w trakcie pracy i znika dopiero razem z wtyczką.
/// Wątek dźwięku widzi wtedy coś, co się nie zmienia.
private final class StanRenderowania {
    /// Z zapasem: żaden host nie prosi o dłuższe bloki (Logic przy zgrywaniu bierze do 4096)
    static let maksRamek = 32768
    let bufor: UnsafeMutablePointer<Float>
    let ramek = StanRenderowania.maksRamek
    var czestotliwosc: Double = 48_000
    init() {
        bufor = UnsafeMutablePointer<Float>.allocate(capacity: ramek * 2)
        bufor.initialize(repeating: 0, count: ramek * 2)
    }

    deinit { bufor.deallocate() }
}

public final class BHD70AudioUnit: AUAudioUnit {
    private static func czteroZnaki(_ s: String) -> FourCharCode {
        s.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }

    public static let opisSkladnika = AudioComponentDescription(
        componentType: kAudioUnitType_MusicDevice,
        componentSubType: czteroZnaki("BD70"),
        componentManufacturer: czteroZnaki("BHnc"),
        componentFlags: 0,
        componentFlagsMask: 0)

    public let silnik = Silnik()
    private var wyjscie: AUAudioUnitBus!
    private var tablicaWyjsc: AUAudioUnitBusArray!

    /// Bufory dla wątku dźwięku – patrz StanRenderowania
    private let stan = StanRenderowania()

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        wyjscie = try AUAudioUnitBus(format: format)
        wyjscie.name = "Main"
        wyjscie.maximumChannelCount = 2
        tablicaWyjsc = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [wyjscie])
        maximumFramesToRender = 4096
        silnik?.start()
    }

    public override var outputBusses: AUAudioUnitBusArray { tablicaWyjsc }
    public override var audioUnitShortName: String? { "BHD-70" }
    public override var supportsUserPresets: Bool { false }
    public override var canProcessInPlace: Bool { false }
    public override var tailTime: TimeInterval { 3 }
    /// Bez wejść; wyjście mono albo stereo – niektóre hosty podają kartę o innej liczbie kanałów
    public override var channelCapabilities: [NSNumber]? { [0, 1, 0, 2] }

    public override func shouldChange(to format: AVAudioFormat, for bus: AUAudioUnitBus) -> Bool {
        format.channelCount >= 1 && format.channelCount <= 2 && !renderResourcesAllocated
    }

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        stan.czestotliwosc = wyjscie.format.sampleRate
    }

    public override func deallocateRenderResources() {
        super.deallocateRenderResources()
        // Bufora tu nie zwalniamy: host mógł zapamiętać wskaźnik na niego.
        // Zniknie razem z wtyczką.
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        // Wątek dźwięku dostaje tylko to, co poniżej – żadnego sięgania do wtyczki
        let silnik = self.silnik
        let stan = self.stan
        return { _, _, frameCount, _, outputData, listaZdarzen, _ in
            let n = Int(frameCount)
            let maxF = stan.ramek
            guard n <= maxF else { return kAudioUnitErr_TooManyFramesToProcess }
            let bufor = stan.bufor

            // MIDI od hosta – bez dzielenia bufora: emulator i tak chodzi z własnym opóźnieniem
            var zdarzenie = listaZdarzen
            while let e = zdarzenie {
                if e.pointee.head.eventType == .MIDI {
                    let m = e.pointee.MIDI
                    let status = m.data.0
                    if m.length >= 1, status >= 0x80, status < 0xF0 {
                        silnik?.midi(status,
                                     m.length >= 2 ? m.data.1 & 0x7F : 0,
                                     m.length >= 3 ? m.data.2 & 0x7F : 0)
                    }
                }
                zdarzenie = UnsafePointer(e.pointee.head.next)
            }

            let lewy = bufor
            let prawy = bufor + maxF
            silnik?.render(lewy: lewy, prawy: prawy, ramek: frameCount, czestotliwosc: stan.czestotliwosc)

            let abl = UnsafeMutableAudioBufferListPointer(outputData)
            for (c, i) in abl.indices.enumerated() {
                let zrodlo = c == 0 ? lewy : prawy
                abl[i].mDataByteSize = UInt32(n * MemoryLayout<Float>.size)
                if let d = abl[i].mData {
                    d.assumingMemoryBound(to: Float.self).update(from: zrodlo, count: n)
                } else {
                    abl[i].mData = UnsafeMutableRawPointer(zrodlo)
                }
            }
            return noErr
        }
    }

    // MARK: - Stan w projekcie DAW-a

    /// Poziom wyjścia zapisuje się w projekcie – w każdym może być inny.
    private static let kluczPoziomu = "bhd70.poziomDb"

    public override var fullState: [String: Any]? {
        get {
            var stanProjektu = super.fullState ?? [:]
            stanProjektu[Self.kluczPoziomu] = silnik?.poziomDb ?? 0
            return stanProjektu
        }
        set {
            super.fullState = newValue
            if let p = newValue?[Self.kluczPoziomu] as? Float {
                silnik?.poziomDb = p
            } else if let p = newValue?[Self.kluczPoziomu] as? Double {
                silnik?.poziomDb = Float(p)
            }
        }
    }
}
