// BHD-70 – karty dźwiękowe i porty MIDI w systemie.
//
// Potrzebuje tego tylko program na Maca: wtyczka w DAW-ie dostaje wyjście,
// częstotliwość i wielkość bufora od gospodarza.

import AVFoundation
import CoreAudio
import CoreMIDI

public struct Karta: Identifiable, Hashable {
    public let id: AudioDeviceID
    public let uid: String
    public let nazwa: String
    public let czestotliwosci: [Double]
    public var czestotliwosc: Double
}

public enum Urzadzenia {
    private static func adres(_ co: AudioObjectPropertySelector,
                             _ zakres: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: co, mScope: zakres, mElement: kAudioObjectPropertyElementMain)
    }

    private static func napis(_ id: AudioObjectID, _ co: AudioObjectPropertySelector) -> String? {
        var a = adres(co)
        var wartosc: Unmanaged<CFString>?
        var ile = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &ile, &wartosc) == noErr,
              let s = wartosc?.takeRetainedValue() else { return nil }
        return s as String
    }

    private static func kanalyWyjscia(_ id: AudioObjectID) -> Int {
        var a = adres(kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeOutput)
        var ile: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &ile) == noErr, ile > 0 else { return 0 }
        let surowe = UnsafeMutableRawPointer.allocate(byteCount: Int(ile), alignment: 16)
        defer { surowe.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &ile, surowe) == noErr else { return 0 }
        let lista = UnsafeMutableAudioBufferListPointer(surowe.assumingMemoryBound(to: AudioBufferList.self))
        return lista.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    public static func czestotliwosc(_ id: AudioDeviceID) -> Double {
        var a = adres(kAudioDevicePropertyNominalSampleRate)
        var r: Float64 = 0
        var ile = UInt32(MemoryLayout<Float64>.size)
        return AudioObjectGetPropertyData(id, &a, 0, nil, &ile, &r) == noErr ? r : 0
    }

    public static func ustawCzestotliwosc(_ id: AudioDeviceID, _ r: Double) {
        var a = adres(kAudioDevicePropertyNominalSampleRate)
        var wartosc = Float64(r)
        AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float64>.size), &wartosc)
    }

    private static func mozliweCzestotliwosci(_ id: AudioDeviceID) -> [Double] {
        var a = adres(kAudioDevicePropertyAvailableNominalSampleRates)
        var ile: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &ile) == noErr, ile > 0 else { return [] }
        var zakresy = [AudioValueRange](repeating: AudioValueRange(), count: Int(ile) / MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &ile, &zakresy) == noErr else { return [] }
        let typowe: [Double] = [44100, 48000, 88200, 96000, 176400, 192000]
        var wynik: Set<Double> = []
        for z in zakresy {
            if z.mMinimum == z.mMaximum { wynik.insert(z.mMinimum) }
            else { for t in typowe where t >= z.mMinimum && t <= z.mMaximum { wynik.insert(t) } }
        }
        return wynik.sorted()
    }

    public static func bufor(_ id: AudioDeviceID) -> UInt32 {
        var a = adres(kAudioDevicePropertyBufferFrameSize, kAudioDevicePropertyScopeOutput)
        var n: UInt32 = 0
        var ile = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &a, 0, nil, &ile, &n) == noErr ? n : 0
    }

    public static func ustawBufor(_ id: AudioDeviceID, _ n: UInt32) {
        var a = adres(kAudioDevicePropertyBufferFrameSize, kAudioDevicePropertyScopeOutput)
        var wartosc = n
        AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &wartosc)
    }

    /// Wszystkie karty, które mają wyjście
    public static func wyjscia() -> [Karta] {
        var a = adres(kAudioHardwarePropertyDevices)
        var ile: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &ile) == noErr else { return [] }
        var id = [AudioDeviceID](repeating: 0, count: Int(ile) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &a, 0, nil, &ile, &id) == noErr else { return [] }
        return id.compactMap { i in
            guard kanalyWyjscia(i) > 0,
                  let nazwa = napis(i, kAudioObjectPropertyName),
                  let uid = napis(i, kAudioDevicePropertyDeviceUID) else { return nil }
            return Karta(id: i, uid: uid, nazwa: nazwa,
                         czestotliwosci: mozliweCzestotliwosci(i), czestotliwosc: czestotliwosc(i))
        }
        .sorted { $0.nazwa.localizedStandardCompare($1.nazwa) == .orderedAscending }
    }

    public static func domyslneWyjscie() -> AudioDeviceID? {
        var a = adres(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var ile = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &ile, &id) == noErr
        else { return nil }
        return id
    }

    /// Woła blok, gdy zmieni się lista kart albo karta domyślna
    public static func pilnujZmian(_ blok: @escaping () -> Void) {
        for co in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var a = adres(co)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a,
                                                DispatchQueue.main) { _, _ in blok() }
        }
    }

    // MARK: - MIDI

    public static func zrodlaMidi() -> [String] {
        (0..<MIDIGetNumberOfSources()).compactMap { i in
            let e = MIDIGetSource(i)
            var s: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(e, kMIDIPropertyDisplayName, &s)
            let nazwa = (s?.takeRetainedValue() as String?) ?? ""
            // własne porty wirtualne instrumentu pomijamy
            return nazwa.hasPrefix("BHD-70") || nazwa.isEmpty ? nil : nazwa
        }
    }
}

/// Powiadomienie o podłączeniu lub odłączeniu urządzenia MIDI
public final class StrazMidi {
    private var klient = MIDIClientRef()

    public init(zmiana: @escaping () -> Void) {
        MIDIClientCreateWithBlock("BHD-70 straz" as CFString, &klient) { wiadomosc in
            if wiadomosc.pointee.messageID == .msgSetupChanged {
                DispatchQueue.main.async { zmiana() }
            }
        }
    }
}
