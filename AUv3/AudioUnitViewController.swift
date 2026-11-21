// BHD-70 – rozszerzenie AUv3: tworzy wtyczkę i jej okno w hoście (Logic Pro, Ableton Live…)

import CoreAudioKit
import SwiftUI
import AppKit

public final class AudioUnitViewController: AUViewController, AUAudioUnitFactory {
    private var wtyczka: BHD70AudioUnit?
    private var okno: NSViewController?

    public override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: PanelView.rozmiar))
        // Zawsze ciemny wygląd serii – niezależnie od tego, czy okno DAW jest jasne
        view.appearance = NSAppearance(named: .darkAqua)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = PanelView.rozmiar
        if let wtyczka { podlacz(wtyczka) }
    }

    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let au = try BHD70AudioUnit(componentDescription: componentDescription, options: [])
        wtyczka = au
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isViewLoaded else { return }
            self.podlacz(au)
        }
        return au
    }

    private func podlacz(_ au: BHD70AudioUnit) {
        guard okno == nil else { return }
        // Wtyczka w DAW-ie nie otwiera własnego okna wyboru pliku – gdy nie ma
        // oprogramowania z D-70 użytkownika, mówi tylko, co zrobić w programie.
        let kontroler: NSViewController = au.silnik == nil
            ? NSHostingController(rootView: WidokBrakPlikow())
            : NSHostingController(rootView: PanelView(silnik: au.silnik))
        addChild(kontroler)
        kontroler.view.appearance = NSAppearance(named: .darkAqua)
        kontroler.view.frame = view.bounds
        kontroler.view.autoresizingMask = [.width, .height]
        view.addSubview(kontroler.view)
        okno = kontroler
    }
}
