#!/usr/bin/env python3
"""Ikona BHD-70 w stylu serii BH (zasady: ~/Developer/shared/design/STYLE.md).

Ciemny granatowy kafelek z gradientem, symbol w kremie i bursztynie, pod spodem
słupki poziomu – znak serii. BHD-70 nie jest sprzedawany (licencja GPL-3 silnika),
więc kafelek ma rozjaśniony środek, tak jak programy darmowe.

Uruchomienie:  python3 narzedzia/ikona.py        → narzedzia/ikony/*.png
Po wyborze:    cp narzedzia/ikony/<wariant>.png icon.png
"""
import os
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

TU = os.path.dirname(os.path.abspath(__file__))
WYJ = os.path.join(TU, "ikony")
K = 2
S = 1024 * K
GORA, DOL = (33, 45, 61), (15, 22, 33)
KREM = (241, 234, 218)
BURSZTYN = (227, 165, 74)
CIEMNY = (6, 9, 13)
BLADY = (64, 80, 98)

KROJ = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
KROJ_W = "/System/Library/Fonts/Supplemental/Arial Narrow Bold.ttf"


def p(v):
    return int(v * K)


def czcionka(sciezka, rozmiar):
    return ImageFont.truetype(sciezka, p(rozmiar))


def kafelek(poswiata=True):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cien = Image.new("L", (S, S), 0)
    ImageDraw.Draw(cien).rounded_rectangle([p(100), p(118), p(924), p(942)], p(185), fill=150)
    cien = cien.filter(ImageFilter.GaussianBlur(p(18)))
    img.paste((0, 0, 0, 255), (0, 0), cien)

    grad = Image.new("RGBA", (S, S))
    gd = ImageDraw.Draw(grad)
    for y in range(p(100), p(925)):
        t = (y - p(100)) / p(824)
        c = tuple(int(GORA[i] + (DOL[i] - GORA[i]) * t) for i in range(3))
        gd.line([(0, y), (S, y)], fill=c + (255,))
    maska = Image.new("L", (S, S), 0)
    ImageDraw.Draw(maska).rounded_rectangle([p(100), p(100), p(924), p(924)], p(185), fill=255)
    img.paste(grad, (0, 0), maska)

    if poswiata:
        g = Image.new("L", (S, S), 0)
        r = int(S * 0.42)
        ImageDraw.Draw(g).ellipse([S // 2 - r, int(S * 0.47) - r, S // 2 + r, int(S * 0.47) + r],
                                  fill=int(255 * 0.85))
        g = g.filter(ImageFilter.GaussianBlur(S * 0.13))
        g = ImageChops.multiply(g, maska)
        img.paste((92, 110, 132, 255), (0, 0), g)

    ImageDraw.Draw(img).rounded_rectangle([p(100), p(100), p(924), p(924)], p(185),
                                          outline=(255, 255, 255, 22), width=p(3))
    return img


def slupki(d, cx, podstawa, skala=1.0):
    """Słupki poziomu – znak serii BH"""
    wys = [12, 18, 24, 26, 16, 22, 20, 12, 20, 26, 18, 14]
    sz, odstep = 11 * skala, 8 * skala
    kropek = 8
    calosc = len(wys) * (sz + odstep) + kropek * 15 * skala
    x = cx - calosc / 2
    for h in wys:
        d.rectangle([p(x), p(podstawa - h * 2.2 * skala), p(x + sz), p(podstawa)], fill=BURSZTYN)
        x += sz + odstep
    for i in range(kropek):
        a = 1 - i / (kropek + 3)
        c = tuple(int(CIEMNY[k] + (BLADY[k] - CIEMNY[k]) * a) for k in range(3))
        d.rectangle([p(x), p(podstawa - 6 * skala), p(x + 8 * skala), p(podstawa)], fill=c)
        x += 15 * skala


def srodek(d, tekst, kroj, cx, cy, kolor):
    l, t, r, b = d.textbbox((0, 0), tekst, font=kroj)
    d.text((p(cx) - (r - l) / 2 - l, p(cy) - (b - t) / 2 - t), tekst, font=kroj, fill=kolor)


# --- A: złoty napis BHD-70 na kafelku -------------------------------------
def wariant_napis():
    img = kafelek()
    d = ImageDraw.Draw(img)
    srodek(d, "BHD", czcionka(KROJ, 210), 512, 400, KREM)
    srodek(d, "D-70", czcionka(KROJ, 210), 512, 400, BURSZTYN)  # nadpisane niżej
    img = kafelek()
    d = ImageDraw.Draw(img)
    srodek(d, "BH", czcionka(KROJ, 230), 512, 390, BURSZTYN)
    srodek(d, "D-70", czcionka(KROJ_W, 190), 512, 590, KREM)
    slupki(d, 512, 790, 1.35)
    return img


# --- B: wyświetlacz D-70 ze złotym napisem --------------------------------
def wariant_wyswietlacz():
    img = kafelek()
    d = ImageDraw.Draw(img)
    # obudowa wyświetlacza
    d.rounded_rectangle([p(190), p(270), p(834), p(610)], p(34), outline=BURSZTYN, width=p(16))
    d.rounded_rectangle([p(226), p(306), p(798), p(574)], p(16), fill=CIEMNY)
    srodek(d, "D-70", czcionka(KROJ, 190), 512, 440, BURSZTYN)
    slupki(d, 512, 790, 1.45)
    return img


# --- C: suwaki Tone Palette ------------------------------------------------
def wariant_suwaki():
    img = kafelek()
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([p(206), p(250), p(818), p(640)], p(34), outline=BURSZTYN, width=p(16))
    pozycje = [0.72, 0.42, 0.58, 0.30]
    for i, poz in enumerate(pozycje):
        x = 290 + i * 148
        d.rounded_rectangle([p(x - 14), p(300), p(x + 14), p(590)], p(14), fill=CIEMNY)
        y = 300 + (590 - 300 - 56) * poz
        d.rounded_rectangle([p(x - 44), p(y), p(x + 44), p(y + 56)], p(12), fill=KREM)
    slupki(d, 512, 800, 1.45)
    return img


def zapisz(img, nazwa):
    os.makedirs(WYJ, exist_ok=True)
    out = img.resize((1024, 1024), Image.LANCZOS)
    out.save(os.path.join(WYJ, nazwa + ".png"))
    return out


if __name__ == "__main__":
    warianty = [("A-napis", wariant_napis()),
                ("B-wyswietlacz", wariant_wyswietlacz()),
                ("C-suwaki", wariant_suwaki())]
    male = []
    for nazwa, img in warianty:
        duza = zapisz(img, nazwa)
        male.append((nazwa, duza))
    # porównanie: duże obok siebie i rządek małych (tak je widać w Docku)
    por = Image.new("RGBA", (1024 * 3 + 80, 1024 + 220), (15, 22, 32, 255))
    for i, (_, duza) in enumerate(male):
        por.paste(duza, (i * (1024 + 40), 0), duza)
    d = ImageDraw.Draw(por)
    x = 60
    for nazwa, duza in male:
        for rozmiar in (128, 64, 32):
            m = duza.resize((rozmiar, rozmiar), Image.LANCZOS)
            por.paste(m, (x, 1024 + 60 + (128 - rozmiar) // 2), m)
            x += rozmiar + 24
        d.text((x, 1024 + 110), nazwa, fill=(200, 210, 220))
        x += 220
    por.save(os.path.join(WYJ, "_porownanie.png"))
    print("gotowe:", WYJ)
