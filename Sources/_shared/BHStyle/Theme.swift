// ─────────────────────────────────────────────────────────────
// Wspólny plik serii BH – oryginał: ~/Developer/shared/BHStyle/Theme.swift
// W projektach jest KOPIA (Sources/_shared), nadpisywana przy każdym budowaniu.
// Zmiany wprowadzaj tylko w ~/Developer/shared.
// ─────────────────────────────────────────────────────────────
import SwiftUI
import AppKit

// Wspólna paleta i wygląd – zsynchronizowane z bronislawhonca.pl (:root w style.css)

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

enum Theme {
    static let bg          = Color(hex: 0x0F1620)
    static let surface     = Color(hex: 0x17212D)
    static let surface2    = Color(hex: 0x141D28)
    static let line        = Color(hex: 0x243140)
    static let lineSoft    = Color(hex: 0x1F2B38)
    static let text        = Color(hex: 0xE4E9EF)
    static let text2       = Color(hex: 0xC4CDD7)
    static let muted       = Color(hex: 0x9DAAB8)
    static let faint       = Color(hex: 0x7F8D9C)
    static let accent      = Color(hex: 0xE3A54A)
    static let accentHover = Color(hex: 0xF2C27A)
    static let onAccent    = Color(hex: 0x1A1206)

    static let bgNS = NSColor(srgbRed: 0x0F / 255.0, green: 0x16 / 255.0, blue: 0x20 / 255.0, alpha: 1)

    /// Zdjęcie z nagłówka strony (hero.jpg w Contents/Resources) – już w szarości i tonie granatu
    static let heroImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "hero", withExtension: "jpg") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

// MARK: - Panele

// Panel w stylu kart ze strony (surface na tle bg, delikatna ramka)
struct ThemedGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.text2)
            configuration.content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.9))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

extension GroupBoxStyle where Self == ThemedGroupBoxStyle {
    static var themed: ThemedGroupBoxStyle { ThemedGroupBoxStyle() }
}

// MARK: - Tło ze zdjęciem (jak .hero-bg na stronie)

struct HeroBackground: View {
    /// Wysokość pasa ze zdjęciem; niżej jest już jednolite tło
    var height: CGFloat = 300

    var body: some View {
        ZStack {
            Theme.bg
            if let image = Theme.heroImage {
                GeometryReader { geo in
                    // background-size: cover; background-position: 50% 22%
                    let w = geo.size.width, h = geo.size.height
                    let iw = max(image.size.width, 1), ih = max(image.size.height, 1)
                    let scale = max(w / iw, h / ih)
                    let sw = iw * scale, sh = ih * scale
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: sw, height: sh)
                        .offset(x: (w - sw) * 0.5, y: (h - sh) * 0.22)
                }
                .clipped()
            }
            // .hero-bg::after
            LinearGradient(stops: [
                .init(color: Theme.bg.opacity(0.20), location: 0.00),
                .init(color: Theme.bg.opacity(0.55), location: 0.45),
                .init(color: Theme.bg.opacity(0.92), location: 0.78),
                .init(color: Theme.bg,               location: 1.00),
            ], startPoint: .top, endPoint: .bottom)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }
}

// MARK: - Marka

enum Brand {
    /// Hasło serii – zawsze po angielsku, w etykiecie pisane wersalikami
    static let slogan = "ON THE OTHER SIDE"
    /// Przedrostek wszystkich programów: moje inicjały
    static let prefix = "BH"
}

/// Nazwa programu według zasady serii: „BH” w kolorze akcentu (jak słupki), reszta w kolorze tekstu.
/// „BH AU Host” → BH + „ AU Host”,  „BHX-1” → BH + „X-1”.
struct BrandName: View {
    let name: String
    var size: CGFloat = 28
    var weight: Font.Weight = .semibold

    var body: some View {
        styled
            .font(.system(size: size, weight: weight))
    }

    private var styled: Text {
        guard name.hasPrefix(Brand.prefix) else {
            return Text(name).foregroundColor(Theme.text)
        }
        let rest = String(name.dropFirst(Brand.prefix.count))
        return Text(Brand.prefix).foregroundColor(Theme.accent)
             + Text(rest).foregroundColor(Theme.text)
    }
}

// MARK: - Nagłówek (słupki + ON THE OTHER SIDE + nazwa programu)

struct LevelGlyph: View {
    private let lit: [CGFloat]   = [7, 10, 13, 16, 12, 9, 13, 7, 11, 15, 10]
    private let dim: [CGFloat]   = [5, 4, 3, 4, 2.5, 3, 2, 2, 1.5, 1.5, 1.5]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(lit.indices, id: \.self) { i in
                Rectangle().fill(Theme.accent).frame(width: 3.5, height: lit[i])
            }
            ForEach(dim.indices, id: \.self) { i in
                Rectangle().fill(Theme.faint.opacity(0.45)).frame(width: 3.5, height: dim[i])
            }
        }
        .frame(height: 16, alignment: .bottom)
    }
}

struct AppHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LevelGlyph()
                .padding(.bottom, 4)
            Text(Brand.slogan)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(2.2)
                .foregroundColor(Theme.accent)
            BrandName(name: title)
            Text(subtitle)
                .font(.callout)
                .foregroundColor(Theme.text2)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .overlay(alignment: .topTrailing) { HelpButton() }
    }
}

// MARK: - Okno

/// Przezroczysty pasek tytułu – zdjęcie wchodzi pod przyciski okna, jak na stronie
private struct WindowChrome: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.backgroundColor = Theme.bgNS
            w.appearance = NSAppearance(named: .darkAqua)
        }
    }
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// Wygląd głównego okna – ciemne tło + wymuszony dark mode + akcent na kontrolkach
struct ThemedWindow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(Theme.accent)
            .foregroundColor(Theme.text)
            .background(Theme.bg.ignoresSafeArea())
            .background(WindowChrome())
            .preferredColorScheme(.dark)
    }
}

extension View {
    func themedWindow() -> some View { modifier(ThemedWindow()) }

    /// Zdjęcie w tle górnej części okna
    func heroBackground(height: CGFloat = 300) -> some View {
        background(alignment: .top) {
            HeroBackground(height: height).ignoresSafeArea()
        }
    }
}
