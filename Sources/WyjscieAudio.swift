// BHD-70 – wyjście dźwięku programu na Maca.
//
// We wtyczce dźwięk zabiera DAW i to on wybiera kartę, częstotliwość i wielkość
// bufora. Program musi to zrobić sam – i dać Ci to wybrać.

import AVFoundation
import CoreAudio

public final class WyjscieAudio {
    private let silnik: Silnik
    private var maszyna = AVAudioEngine()
    private var zrodlo: AVAudioSourceNode?
    public private(set) var karta: AudioDeviceID?
    public private(set) var czestotliwosc: Double = 0
    public private(set) var bufor: UInt32 = 0
    public private(set) var blad: String?

    public init(silnik: Silnik) { self.silnik = silnik }

    /// Opóźnienie wyjścia w milisekundach (sam bufor karty)
    public var opoznienieMs: Double {
        czestotliwosc > 0 ? Double(bufor) * 1000 / czestotliwosc : 0
    }

    /// Uruchamia dźwięk na wskazanej karcie. `karta` nil = domyślna systemowa.
    public func start(karta: AudioDeviceID? = nil, czestotliwosc: Double? = nil, bufor: UInt32? = nil) {
        stop()
        blad = nil
        maszyna = AVAudioEngine()
        let urzadzenie = karta ?? Urzadzenia.domyslneWyjscie()
        if let u = urzadzenie {
            if let r = czestotliwosc, r > 0, abs(Urzadzenia.czestotliwosc(u) - r) > 0.5 {
                Urzadzenia.ustawCzestotliwosc(u, r)
            }
            if let b = bufor, b > 0 { Urzadzenia.ustawBufor(u, b) }
            do {
                try maszyna.outputNode.auAudioUnit.setDeviceID(u)
            } catch {
                blad = tr("nie mogę użyć tej karty", "cannot use this device")
            }
        }
        let wyjscie = maszyna.outputNode
        let rate = wyjscie.outputFormat(forBus: 0).sampleRate
        guard rate > 0, let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else {
            blad = tr("karta nie podaje formatu", "the device reports no format")
            return
        }
        self.karta = urzadzenie
        self.czestotliwosc = rate
        self.bufor = urzadzenie.map { Urzadzenia.bufor($0) } ?? 0

        let silnik = self.silnik
        let node = AVAudioSourceNode(format: format) { cisza, _, ramek, bufory -> OSStatus in
            // Bez tego CoreAudio może potraktować nasz blok jako ciszę i nic nie zagra
            cisza.pointee = false
            let abl = UnsafeMutableAudioBufferListPointer(bufory)
            guard abl.count >= 1,
                  let lewy = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let prawy = abl.count >= 2
                ? (abl[1].mData?.assumingMemoryBound(to: Float.self) ?? lewy)
                : lewy
            silnik.render(lewy: lewy, prawy: prawy, ramek: ramek, czestotliwosc: rate)
            return noErr
        }
        zrodlo = node
        maszyna.attach(node)
        maszyna.connect(node, to: maszyna.mainMixerNode, format: format)
        maszyna.prepare()
        do {
            try maszyna.start()
        } catch {
            blad = tr("nie udało się uruchomić dźwięku", "could not start audio")
        }
    }

    public func stop() {
        if maszyna.isRunning { maszyna.stop() }
        if let z = zrodlo { maszyna.detach(z) }
        zrodlo = nil
    }
}
