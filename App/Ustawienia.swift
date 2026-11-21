// BHD-70 – okno Audio/MIDI programu na Maca.
//
// Wtyczka tego nie ma i nie potrzebuje: w DAW-ie kartę, częstotliwość i
// wielkość bufora wybiera gospodarz.

import SwiftUI

/// Ustawienia zapamiętywane między uruchomieniami
final class Ustawienia: ObservableObject {
    @AppStorage("wyjscieUID") var wyjscieUID = ""
    @AppStorage("czestotliwosc") var czestotliwosc = 0.0      // 0 = jak karta
    @AppStorage("bufor") var bufor = 0                        // 0 = jak karta
    @AppStorage("wejscieMidi") var wejscieMidi = ""           // puste = wszystkie
}

struct UstawieniaView: View {
    @ObservedObject var instrument: Instrument
    @ObservedObject var ustawienia: Ustawienia
    @Environment(\.dismiss) private var zamknij

    @State private var karty: [Karta] = []
    @State private var zrodla: [String] = []
    private static let bufory = [64, 128, 256, 512, 1024]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(tr("Audio i MIDI", "Audio and MIDI"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                Button(tr("Gotowe", "Done")) { zamknij() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 14)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    etykieta(tr("Wyjście", "Output"))
                    Picker("", selection: $ustawienia.wyjscieUID) {
                        Text(tr("domyślne systemowe", "system default")).tag("")
                        ForEach(karty) { k in Text(k.nazwa).tag(k.uid) }
                    }
                    .labelsHidden()
                    .frame(width: 280)
                }
                GridRow {
                    etykieta(tr("Częstotliwość", "Sample rate"))
                    Picker("", selection: $ustawienia.czestotliwosc) {
                        Text(tr("jak karta", "as the device")).tag(0.0)
                        ForEach(mozliweCzestotliwosci, id: \.self) { r in
                            Text("\(Int(r)) Hz").tag(r)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 280)
                }
                GridRow {
                    etykieta(tr("Bufor", "Buffer"))
                    Picker("", selection: $ustawienia.bufor) {
                        Text(tr("jak karta", "as the device")).tag(0)
                        ForEach(Self.bufory, id: \.self) { b in
                            Text("\(b) " + tr("próbek", "samples")).tag(b)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 280)
                }
                GridRow {
                    etykieta(tr("Wejście MIDI", "MIDI input"))
                    Picker("", selection: $ustawienia.wejscieMidi) {
                        Text(tr("wszystkie urządzenia", "all devices")).tag("")
                        ForEach(zrodla, id: \.self) { z in Text(z).tag(z) }
                    }
                    .labelsHidden()
                    .frame(width: 280)
                }
            }

            Divider().padding(.vertical, 14)

            VStack(alignment: .leading, spacing: 5) {
                stan
                Text(tr("Instrument liczy dźwięk w 32 kHz, tak jak prawdziwy D-70, i przelicza go na częstotliwość karty.",
                        "The instrument runs at 32 kHz, like the real D-70, and resamples to the device rate."))
                    .font(.system(size: 10))
                    .foregroundColor(Theme.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(width: 460)
        .background(Theme.bg)
        .onAppear(perform: odswiez)
        .onChange(of: ustawienia.wyjscieUID) { _ in zastosuj() }
        .onChange(of: ustawienia.czestotliwosc) { _ in zastosuj() }
        .onChange(of: ustawienia.bufor) { _ in zastosuj() }
        .onChange(of: ustawienia.wejscieMidi) { nowe in instrument.ustawMidi(nowe) }
    }

    private var mozliweCzestotliwosci: [Double] {
        let k = karty.first { $0.uid == ustawienia.wyjscieUID } ?? karty.first { $0.id == instrument.wyjscie?.karta }
        return k?.czestotliwosci ?? [44100, 48000, 96000]
    }

    private var stan: some View {
        let w = instrument.wyjscie
        let opoznienie = w?.opoznienieMs ?? 0
        return HStack(spacing: 6) {
            Circle()
                .fill(w?.blad == nil ? Theme.accent : Color.red)
                .frame(width: 7, height: 7)
            if let b = w?.blad {
                Text(b).foregroundColor(.red)
            } else if let w, w.czestotliwosc > 0 {
                Text(String(format: tr("gra: %d Hz, bufor %d próbek – opóźnienie %.1f ms",
                                       "playing: %d Hz, buffer %d samples – latency %.1f ms"),
                            Int(w.czestotliwosc), Int(w.bufor), opoznienie))
                    .foregroundColor(Theme.text2)
            } else {
                Text(tr("dźwięk nie działa", "audio is not running")).foregroundColor(Theme.muted)
            }
        }
        .font(.system(size: 11, design: .monospaced))
    }

    private func etykieta(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 12))
            .foregroundColor(Theme.text2)
            .frame(width: 110, alignment: .trailing)
    }

    private func odswiez() {
        karty = Urzadzenia.wyjscia()
        zrodla = Urzadzenia.zrodlaMidi()
    }

    private func zastosuj() {
        odswiez()
        instrument.ustawWyjscie(uid: ustawienia.wyjscieUID,
                                czestotliwosc: ustawienia.czestotliwosc,
                                bufor: UInt32(ustawienia.bufor))
    }
}
