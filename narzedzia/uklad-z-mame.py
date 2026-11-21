#!/usr/bin/env python3
# Przepisuje układ panelu z emulatora (roland_d70.lay) na tabelę w Swifcie.
# Dzięki temu panel BHD-70 stoi co do punktu tam, gdzie na prawdziwym D-70.
# Uruchamia się raz, po zmianie układu w emulatorze:  python3 narzedzia/uklad-z-mame.py
import html, os, re, sys

LAY = os.path.expanduser("~/mame-d70/src/mame/layout/roland_d70.lay")
CEL = os.path.join(os.path.dirname(__file__), "..", "Sources", "PanelUklad.swift")

s = open(LAY).read()

# 1) napisy: nazwa elementu -> tekst
napisy = {k: html.unescape(v)
          for k, v in re.findall(r'<element name="(\w+)"><text string="([^"]*)"', s)}

v = s[s.index("<view"):]
przyciski, diody, etykiety, kreski, plyty, tlo = [], [], [], [], [], []
nazwa = None
for w in v.split("\n"):
    m = re.search(r"<!--\s*(.+?)\s*-->", w)
    if m: nazwa = m.group(1)
    def b(t=w):
        g = re.search(r'<bounds x="(-?\d+)" y="(-?\d+)"\s+width="(\d+)" height="(\d+)"', t)
        return tuple(int(x) for x in g.groups()) if g else None
    m = re.search(r'<element ref="(button|clickzone)"\s+inputtag="(\w+)"\s+inputmask="(0x[0-9a-fA-F]+)"', w)
    if m and b():
        przyciski.append((nazwa or "?", m.group(2), int(m.group(3), 16)) + b()); continue
    m = re.search(r'<element name="(LP\d\d|learn_led)" ref="red_led"', w)
    if m and b():
        diody.append((m.group(1),) + b()); continue
    m = re.search(r'<element (?:name="\w+" )?ref="(\w+_text)"', w)
    if m and b():
        etykiety.append((napisy.get(m.group(1), ""),) + b()); continue
    m = re.search(r'<element ref="(clear_rect|brown_line|grey_rect|cpanel|lcd_border|lcd_bg)"', w)
    if m and b():
        tlo.append((m.group(1),) + b())
        if m.group(1) in ("cpanel", "lcd_border", "lcd_bg"):
            plyty.append((m.group(1),) + b())
        else:
            kreski.append((m.group(1),) + b())
        continue

# Na sprzecie napisy sa nadrukowane w przerwach kresek, a kresek jest tam
# dokladnie tyle, ile trzeba. U nas napis rysuje sie czcionka ekranowa i
# wychodzi szerszy, wiec kreski konczace sie tuz przy nim wygladaja, jakby go
# dotykaly (ROM PLAY, TONE/ZONE SELECT). Odsuwamy je o `LUZ` punktow.
LUZ = 6


def odsun_kreski(kreski, etykiety):
    wynik = []
    for rodzaj, x, y, w, h in kreski:
        if h > 2:                       # tylko cienkie kreski, nie ramki
            wynik.append((rodzaj, x, y, w, h))
            continue
        for _, nx, ny, nw, nh in etykiety:
            if y + h < ny - 2 or y > ny + nh + 2:
                continue                # kreska nie na wysokosci napisu
            if x < nx and nx - LUZ < x + w <= nx + nw:    # kreska dobiega do napisu z lewej
                w = max(1, nx - LUZ - x)
            elif x + w > nx + nw and nx <= x < nx + nw + LUZ:   # i z prawej
                nowy = nx + nw + LUZ
                w = max(1, x + w - nowy)
                x = nowy
        wynik.append((rodzaj, x, y, w, h))
    return wynik


def pros(t):
    return "pole(%d, %d, %d, %d)" % t

kreski = odsun_kreski(kreski, etykiety)
tlo = [(r, *odsun_kreski([(r, x, y, w, h)], etykiety)[0][1:]) for r, x, y, w, h in tlo]

szer = max((o[3] + o[5]) for o in przyciski) if przyciski else 0
wys = 0
for zbior in (przyciski, diody, etykiety, kreski, plyty):
    for o in zbior:
        szer = max(szer, o[-4] + o[-2])
        wys = max(wys, o[-3] + o[-1])

out = ['''// Układ panelu BHD-70 – przepisany z emulatora (roland_d70.lay) przez
// narzedzia/uklad-z-mame.py. NIE EDYTUJ RĘCZNIE: uruchom narzędzie po zmianie układu.
//
// Współrzędne są dokładnie takie, jak na prawdziwym D-70: panel 1044 × 497 punktów.

import CoreGraphics

/// Prostokąt w układzie panelu (lewy górny róg, szerokość, wysokość)
public typealias Pole = CGRect

@inline(__always) func pole(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> Pole {
    CGRect(x: x, y: y, width: w, height: h)
}

public enum PanelUklad {
    public static let szerokosc: CGFloat = %SZER%
    public static let wysokosc: CGFloat = %WYS%
    /// Ekran firmware'u: 240 × 64 piksele rysowane w tym prostokącie
    public static let ekran = pole(258, 52, 480, 128)

    /// Przycisk panelu: opis, port i bit w macierzy 8×8, miejsce
    public struct Przycisk {
        public let opis: String, port: String, bit: UInt8, pole: Pole
    }
    /// Dioda: nazwa LPrc (r = bank, c = bit) albo learn_led
    public struct Dioda {
        public let nazwa: String, pole: Pole
    }
    public struct Napis {
        public let tekst: String, pole: Pole
    }
    public struct Kreska {
        public let rodzaj: String, pole: Pole
    }
''']
out.append("    public static let przyciski: [Przycisk] = [")
for o in przyciski:
    out.append('        Przycisk(opis: %s, port: "%s", bit: 0x%02x, pole: %s),' % (
        '"%s"' % o[0].replace('"', '\\"'), o[1], o[2], pros(o[3:])))
out.append("    ]\n")
out.append("    public static let diody: [Dioda] = [")
for o in diody:
    out.append('        Dioda(nazwa: "%s", pole: %s),' % (o[0], pros(o[1:])))
out.append("    ]\n")
out.append("    public static let napisy: [Napis] = [")
for o in etykiety:
    out.append('        Napis(tekst: "%s", pole: %s),' % (o[0].replace('"', '\\"'), pros(o[1:])))
out.append("    ]\n")
out.append("""    /// Płyty, ramki i kreski w kolejności z panelu – rysować po kolei
    public static let tlo: [Kreska] = [""")
for o in tlo:
    out.append('        Kreska(rodzaj: "%s", pole: %s),' % (o[0], pros(o[1:])))
out.append("    ]\n")
out.append("    public static let kreski: [Kreska] = [")
for o in kreski:
    out.append('        Kreska(rodzaj: "%s", pole: %s),' % (o[0], pros(o[1:])))
out.append("    ]\n")
out.append("    public static let plyty: [Kreska] = [")
for o in plyty:
    out.append('        Kreska(rodzaj: "%s", pole: %s),' % (o[0], pros(o[1:])))
out.append("    ]\n")
# suwaki Tone Palette
out.append("""    /// Suwaki Tone Palette: studzienka i tor (Lower 1, Lower 2, Upper 3, Upper 4)
    public static let suwaki: [(studzienka: Pole, tor: Pole, numer: Int)] = [""")
for i, x in enumerate((200, 269, 337, 405)):
    out.append("        (pole(%d, 349, 43, 97), pole(%d, 357, 10, 82), %d)," % (x, x + 17, i + 1))
out.append("    ]\n")
out.append("""    /// Strzałki wokół krzyżaka kursora (z rysunku `grey_arrows`):
    /// kierunek 0 = w górę, 1 = w dół, 2 = w lewo, 3 = w prawo
    public static let strzalki: [(kierunek: Int, pole: Pole)] = [
        (0, pole(930, 89, 18, 14)),
        (1, pole(930, 185, 18, 14)),
        (2, pole(894, 137, 14, 16)),
        (3, pole(970, 137, 14, 16)),
    ]

    /// Pokrętło VALUE: tarcza, palec i dwie klikalne połówki
    public static let pokretlo = pole(919, 363, 106, 106)
    public static let pokretloPalec = pole(931, 381, 32, 32)
}
""")
tekst = "\n".join(out).replace("%SZER%", str(szer)).replace("%WYS%", str(wys))
open(os.path.normpath(CEL), "w").write(tekst)
print("panel %d x %d; przyciski %d, diody %d, napisy %d, kreski %d, płyty %d"
      % (szer, wys, len(przyciski), len(diody), len(etykiety), len(kreski), len(plyty)))
