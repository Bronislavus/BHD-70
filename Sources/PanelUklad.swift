// Układ panelu BHD-70 – przepisany z emulatora (roland_d70.lay) przez
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
    public static let szerokosc: CGFloat = 1044
    public static let wysokosc: CGFloat = 516
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

    public static let przyciski: [Przycisk] = [
        Przycisk(opis: "MIDI learn + Audio/MIDI window (top left)", port: "LEARN", bit: 0x01, pole: pole(20, 34, 70, 16)),
        Przycisk(opis: "MIDI learn + Audio/MIDI window (top left)", port: "LEARN", bit: 0x04, pole: pole(100, 34, 70, 16)),
        Przycisk(opis: "MIDI learn + Audio/MIDI window (top left)", port: "LEARN", bit: 0x02, pole: pole(20, 62, 70, 14)),
        Przycisk(opis: "click/hold the left or right half of the VALUE dial to turn it", port: "VALUE_BTN", bit: 0x01, pole: pole(900, 363, 72, 106)),
        Przycisk(opis: "click/hold the left or right half of the VALUE dial to turn it", port: "VALUE_BTN", bit: 0x02, pole: pole(972, 363, 72, 106)),
        Przycisk(opis: "PERFORMANCE", port: "KEY0", bit: 0x80, pole: pole(505, 379, 37, 9)),
        Przycisk(opis: "PATCH", port: "KEY0", bit: 0x40, pole: pole(553, 379, 37, 9)),
        Przycisk(opis: "TONE", port: "KEY0", bit: 0x20, pole: pole(602, 379, 37, 9)),
        Przycisk(opis: "A/B", port: "KEY0", bit: 0x10, pole: pole(650, 379, 37, 9)),
        Przycisk(opis: "INT/CARD", port: "KEY0", bit: 0x08, pole: pole(698, 379, 37, 9)),
        Przycisk(opis: "COMMAND", port: "KEY0", bit: 0x04, pole: pole(747, 379, 37, 9)),
        Przycisk(opis: "WRITE", port: "KEY0", bit: 0x02, pole: pole(795, 379, 37, 9)),
        Przycisk(opis: "ENTER", port: "KEY0", bit: 0x01, pole: pole(843, 379, 37, 9)),
        Przycisk(opis: "Bank 1", port: "KEY1", bit: 0x80, pole: pole(505, 439, 37, 9)),
        Przycisk(opis: "Bank 2", port: "KEY1", bit: 0x40, pole: pole(553, 439, 37, 9)),
        Przycisk(opis: "Bank 3", port: "KEY1", bit: 0x20, pole: pole(602, 439, 37, 9)),
        Przycisk(opis: "Bank 4", port: "KEY1", bit: 0x10, pole: pole(650, 439, 37, 9)),
        Przycisk(opis: "Bank 5", port: "KEY1", bit: 0x08, pole: pole(698, 439, 37, 9)),
        Przycisk(opis: "Bank 6", port: "KEY1", bit: 0x04, pole: pole(747, 439, 37, 9)),
        Przycisk(opis: "Bank 7", port: "KEY1", bit: 0x02, pole: pole(795, 439, 37, 9)),
        Przycisk(opis: "Bank 8", port: "KEY1", bit: 0x01, pole: pole(843, 439, 37, 9)),
        Przycisk(opis: "Number 1", port: "KEY2", bit: 0x80, pole: pole(505, 469, 37, 9)),
        Przycisk(opis: "Number 2", port: "KEY2", bit: 0x40, pole: pole(553, 469, 37, 9)),
        Przycisk(opis: "Number 3", port: "KEY2", bit: 0x20, pole: pole(602, 469, 37, 9)),
        Przycisk(opis: "Number 4", port: "KEY2", bit: 0x10, pole: pole(650, 469, 37, 9)),
        Przycisk(opis: "Number 5", port: "KEY2", bit: 0x08, pole: pole(698, 469, 37, 9)),
        Przycisk(opis: "Number 6", port: "KEY2", bit: 0x04, pole: pole(747, 469, 37, 9)),
        Przycisk(opis: "Number 7", port: "KEY2", bit: 0x02, pole: pole(795, 469, 37, 9)),
        Przycisk(opis: "Number 8", port: "KEY2", bit: 0x01, pole: pole(843, 469, 37, 9)),
        Przycisk(opis: "DEC/DEL", port: "KEY3", bit: 0x80, pole: pole(871, 252, 59, 13)),
        Przycisk(opis: "INC/INS", port: "KEY3", bit: 0x40, pole: pole(947, 252, 59, 13)),
        Przycisk(opis: "Down", port: "KEY3", bit: 0x20, pole: pole(909, 204, 59, 13)),
        Przycisk(opis: "Left", port: "KEY3", bit: 0x10, pole: pole(871, 157, 59, 13)),
        Przycisk(opis: "Right", port: "KEY3", bit: 0x08, pole: pole(947, 157, 59, 13)),
        Przycisk(opis: "Up", port: "KEY3", bit: 0x04, pole: pole(909, 108, 59, 13)),
        Przycisk(opis: "MIDI OUT", port: "KEY3", bit: 0x02, pole: pole(53, 157, 59, 13)),
        Przycisk(opis: "TONE DISPLAY", port: "KEY3", bit: 0x01, pole: pole(53, 108, 59, 13)),
        Przycisk(opis: "EXIT", port: "KEY4", bit: 0x80, pole: pole(751, 252, 59, 13)),
        Przycisk(opis: "F5", port: "KEY4", bit: 0x40, pole: pole(645, 252, 59, 13)),
        Przycisk(opis: "F4", port: "KEY4", bit: 0x20, pole: pole(555, 252, 59, 13)),
        Przycisk(opis: "F3", port: "KEY4", bit: 0x10, pole: pole(465, 252, 59, 13)),
        Przycisk(opis: "F2", port: "KEY4", bit: 0x08, pole: pole(375, 252, 59, 13)),
        Przycisk(opis: "F1", port: "KEY4", bit: 0x04, pole: pole(285, 252, 59, 13)),
        Przycisk(opis: "USER", port: "KEY4", bit: 0x02, pole: pole(177, 252, 59, 13)),
        Przycisk(opis: "PART", port: "KEY4", bit: 0x01, pole: pole(53, 252, 59, 13)),
        Przycisk(opis: "EDIT", port: "KEY5", bit: 0x80, pole: pole(79, 467, 37, 9)),
        Przycisk(opis: "PORTAMENTO", port: "KEY5", bit: 0x40, pole: pole(79, 438, 37, 9)),
        Przycisk(opis: "RESONANCE", port: "KEY5", bit: 0x20, pole: pole(79, 408, 37, 9)),
        Przycisk(opis: "PAN", port: "KEY5", bit: 0x10, pole: pole(79, 378, 37, 9)),
        Przycisk(opis: "TUNING", port: "KEY5", bit: 0x08, pole: pole(127, 378, 37, 9)),
        Przycisk(opis: "ATTACK", port: "KEY5", bit: 0x04, pole: pole(127, 408, 37, 9)),
        Przycisk(opis: "RELEASE", port: "KEY5", bit: 0x02, pole: pole(127, 438, 37, 9)),
        Przycisk(opis: "PCM CARD", port: "KEY5", bit: 0x01, pole: pole(127, 467, 37, 9)),
        Przycisk(opis: "PLAY", port: "KEY6", bit: 0x80, pole: pole(30, 467, 37, 9)),
        Przycisk(opis: "SOLO", port: "KEY6", bit: 0x40, pole: pole(30, 438, 37, 9)),
        Przycisk(opis: "CUTOFF", port: "KEY6", bit: 0x20, pole: pole(30, 408, 37, 9)),
        Przycisk(opis: "LEVEL", port: "KEY6", bit: 0x10, pole: pole(30, 378, 37, 9)),
        Przycisk(opis: "UPPER (4)", port: "KEY6", bit: 0x08, pole: pole(407, 467, 37, 9)),
        Przycisk(opis: "UPPER (3)", port: "KEY6", bit: 0x04, pole: pole(339, 467, 37, 9)),
        Przycisk(opis: "LOWER (2)", port: "KEY6", bit: 0x02, pole: pole(271, 467, 37, 9)),
        Przycisk(opis: "LOWER (1)", port: "KEY6", bit: 0x01, pole: pole(203, 467, 37, 9)),
        Przycisk(opis: "EFFECT/CTRL", port: "KEY7", bit: 0x01, pole: pole(53, 204, 59, 13)),
    ]

    public static let diody: [Dioda] = [
        Dioda(nazwa: "learn_led", pole: pole(47, 54, 16, 4)),
        Dioda(nazwa: "LP26", pole: pole(518, 380, 10, 3)),
        Dioda(nazwa: "LP31", pole: pole(566, 380, 10, 3)),
        Dioda(nazwa: "LP32", pole: pole(615, 380, 10, 3)),
        Dioda(nazwa: "LP33", pole: pole(663, 380, 10, 3)),
        Dioda(nazwa: "LP34", pole: pole(711, 380, 10, 3)),
        Dioda(nazwa: "LP35", pole: pole(760, 380, 10, 3)),
        Dioda(nazwa: "LP36", pole: pole(808, 380, 10, 3)),
        Dioda(nazwa: "LP37", pole: pole(856, 380, 10, 3)),
        Dioda(nazwa: "LP03", pole: pole(75, 158, 15, 5)),
        Dioda(nazwa: "LP02", pole: pole(75, 109, 15, 5)),
        Dioda(nazwa: "LP00", pole: pole(199, 253, 15, 5)),
        Dioda(nazwa: "LP01", pole: pole(75, 253, 15, 5)),
        Dioda(nazwa: "LP04", pole: pole(92, 468, 10, 3)),
        Dioda(nazwa: "LP05", pole: pole(92, 439, 10, 3)),
        Dioda(nazwa: "LP06", pole: pole(92, 409, 10, 3)),
        Dioda(nazwa: "LP07", pole: pole(92, 379, 10, 3)),
        Dioda(nazwa: "LP13", pole: pole(140, 379, 10, 3)),
        Dioda(nazwa: "LP12", pole: pole(140, 409, 10, 3)),
        Dioda(nazwa: "LP11", pole: pole(140, 439, 10, 3)),
        Dioda(nazwa: "LP10", pole: pole(140, 468, 10, 3)),
        Dioda(nazwa: "LP20", pole: pole(43, 468, 10, 3)),
        Dioda(nazwa: "LP21", pole: pole(43, 439, 10, 3)),
        Dioda(nazwa: "LP22", pole: pole(43, 409, 10, 3)),
        Dioda(nazwa: "LP23", pole: pole(43, 379, 10, 3)),
        Dioda(nazwa: "LP16", pole: pole(420, 468, 10, 3)),
        Dioda(nazwa: "LP17", pole: pole(352, 468, 10, 3)),
        Dioda(nazwa: "LP15", pole: pole(284, 468, 10, 3)),
        Dioda(nazwa: "LP14", pole: pole(216, 468, 10, 3)),
        Dioda(nazwa: "LP24", pole: pole(75, 205, 15, 5)),
    ]

    public static let napisy: [Napis] = [
        Napis(tekst: "MIDI LEARN", pole: pole(20, 20, 150, 9)),
        Napis(tekst: "LEARN", pole: pole(20, 37, 70, 9)),
        Napis(tekst: "AUDIO/MIDI", pole: pole(102, 37, 66, 9)),
        Napis(tekst: "CLEAR", pole: pole(20, 64, 70, 9)),
        Napis(tekst: "", pole: pole(96, 64, 78, 9)),
        Napis(tekst: "TONE DISPLAY", pole: pole(39, 92, 69, 10)),
        Napis(tekst: "MIDI OUT", pole: pole(51, 140, 47, 10)),
        Napis(tekst: "EFFECT/CTRL", pole: pole(45, 188, 64, 10)),
        Napis(tekst: "PART", pole: pole(62, 236, 25, 10)),
        Napis(tekst: "USER", pole: pole(194, 236, 26, 10)),
        Napis(tekst: "F1", pole: pole(309, 236, 11, 10)),
        Napis(tekst: "F2", pole: pole(399, 236, 11, 10)),
        Napis(tekst: "F3", pole: pole(489, 236, 11, 10)),
        Napis(tekst: "F4", pole: pole(579, 236, 11, 10)),
        Napis(tekst: "F5", pole: pole(669, 236, 11, 10)),
        Napis(tekst: "EXIT", pole: pole(770, 236, 22, 10)),
        Napis(tekst: "DEC", pole: pole(891, 236, 19, 10)),
        Napis(tekst: "DEL", pole: pole(891, 273, 18, 10)),
        Napis(tekst: "INC", pole: pole(968, 236, 16, 10)),
        Napis(tekst: "INS", pole: pole(968, 273, 16, 10)),
        Napis(tekst: "TONE PALETTE", pole: pole(206, 331, 62, 9)),
        Napis(tekst: "LOWER", pole: pole(242, 341, 29, 9)),
        Napis(tekst: "UPPER", pole: pole(379, 341, 27, 9)),
        Napis(tekst: "1", pole: pole(220, 455, 6, 10)),
        Napis(tekst: "2", pole: pole(287, 455, 6, 10)),
        Napis(tekst: "3", pole: pole(355, 455, 6, 10)),
        Napis(tekst: "4", pole: pole(423, 455, 6, 10)),
        Napis(tekst: "TONE/ZONE SELECT", pole: pole(281, 480, 87, 9)),
        Napis(tekst: "MODE", pole: pole(86, 450, 21, 8)),
        Napis(tekst: "LEVEL", pole: pole(40, 368, 19, 8)),
        Napis(tekst: "CUTOFF", pole: pole(37, 398, 24, 8)),
        Napis(tekst: "SOLO", pole: pole(41, 428, 16, 8)),
        Napis(tekst: "PLAY", pole: pole(42, 458, 15, 8)),
        Napis(tekst: "PAN", pole: pole(91, 368, 12, 8)),
        Napis(tekst: "RESONANCE", pole: pole(78, 398, 38, 8)),
        Napis(tekst: "PORTAMENTO", pole: pole(76, 428, 43, 8)),
        Napis(tekst: "EDIT", pole: pole(91, 458, 14, 8)),
        Napis(tekst: "TUNING", pole: pole(128, 368, 23, 8)),
        Napis(tekst: "ATTACK", pole: pole(134, 398, 24, 8)),
        Napis(tekst: "RELEASE", pole: pole(132, 428, 27, 8)),
        Napis(tekst: "PCM CARD", pole: pole(130, 458, 33, 8)),
        Napis(tekst: "ROM PLAY", pole: pole(82, 489, 32, 8)),
        Napis(tekst: "PANIC", pole: pole(65, 481, 20, 8)),
        Napis(tekst: "PERFORMANCE", pole: pole(500, 366, 47, 8)),
        Napis(tekst: "PATCH", pole: pole(562, 366, 19, 8)),
        Napis(tekst: "TONE", pole: pole(612, 366, 17, 8)),
        Napis(tekst: "A/", pole: pole(663, 366, 6, 8)),
        Napis(tekst: "B", pole: pole(670, 366, 4, 8)),
        Napis(tekst: "INT/", pole: pole(702, 366, 12, 8)),
        Napis(tekst: "CARD", pole: pole(714, 366, 17, 8)),
        Napis(tekst: "COMMAND", pole: pole(748, 366, 33, 8)),
        Napis(tekst: "WRITE", pole: pole(804, 366, 20, 8)),
        Napis(tekst: "ENTER", pole: pole(852, 366, 20, 8)),
        Napis(tekst: "CAPS", pole: pole(515, 389, 16, 8)),
        Napis(tekst: "SPACE", pole: pole(562, 389, 19, 8)),
        Napis(tekst: "A   B", pole: pole(625, 389, 14, 8)),
        Napis(tekst: "C   D", pole: pole(673, 389, 14, 8)),
        Napis(tekst: "E   F", pole: pole(722, 389, 13, 8)),
        Napis(tekst: "G   H", pole: pole(769, 389, 14, 8)),
        Napis(tekst: "I   J", pole: pole(821, 389, 9, 8)),
        Napis(tekst: "K   L", pole: pole(867, 389, 13, 8)),
        Napis(tekst: "BANK", pole: pole(682, 418, 20, 9)),
        Napis(tekst: "1", pole: pole(522, 428, 4, 8)),
        Napis(tekst: "2", pole: pole(570, 428, 4, 8)),
        Napis(tekst: "3", pole: pole(619, 428, 4, 8)),
        Napis(tekst: "4", pole: pole(667, 428, 4, 8)),
        Napis(tekst: "5", pole: pole(715, 428, 4, 8)),
        Napis(tekst: "6", pole: pole(763, 428, 4, 8)),
        Napis(tekst: "7", pole: pole(812, 428, 4, 8)),
        Napis(tekst: "8", pole: pole(860, 428, 4, 8)),
        Napis(tekst: "M   N", pole: pole(527, 449, 15, 8)),
        Napis(tekst: "O   P", pole: pole(576, 449, 14, 8)),
        Napis(tekst: "Q   R", pole: pole(625, 449, 15, 8)),
        Napis(tekst: "S   T", pole: pole(674, 449, 13, 8)),
        Napis(tekst: "U   V", pole: pole(722, 449, 14, 8)),
        Napis(tekst: "-   W", pole: pole(770, 449, 14, 8)),
        Napis(tekst: "9   X", pole: pole(819, 449, 14, 8)),
        Napis(tekst: "0   Y", pole: pole(867, 449, 14, 8)),
        Napis(tekst: "1", pole: pole(522, 458, 4, 8)),
        Napis(tekst: "2", pole: pole(570, 458, 4, 8)),
        Napis(tekst: "3", pole: pole(619, 458, 4, 8)),
        Napis(tekst: "4", pole: pole(667, 458, 4, 8)),
        Napis(tekst: "5", pole: pole(715, 458, 4, 8)),
        Napis(tekst: "6", pole: pole(763, 458, 4, 8)),
        Napis(tekst: "7", pole: pole(812, 458, 4, 8)),
        Napis(tekst: "8", pole: pole(860, 458, 4, 8)),
        Napis(tekst: "1   Z", pole: pole(529, 479, 13, 8)),
        Napis(tekst: "2   /", pole: pole(578, 479, 11, 8)),
        Napis(tekst: "3   +", pole: pole(625, 479, 14, 8)),
        Napis(tekst: "4   *", pole: pole(674, 479, 12, 8)),
        Napis(tekst: "5   #", pole: pole(722, 479, 14, 8)),
        Napis(tekst: "6   .", pole: pole(771, 479, 11, 8)),
        Napis(tekst: "7   ,", pole: pole(820, 479, 11, 8)),
        Napis(tekst: "8   !", pole: pole(868, 479, 11, 8)),
        Napis(tekst: "NUMBER", pole: pole(674, 486, 38, 9)),
        Napis(tekst: "VALUE", pole: pole(960, 352, 24, 9)),
        Napis(tekst: "◄", pole: pole(903, 410, 12, 12)),
        Napis(tekst: "►", pole: pole(1029, 410, 12, 12)),
    ]

    /// Płyty, ramki i kreski w kolejności z panelu – rysować po kolei
    public static let tlo: [Kreska] = [
        Kreska(rodzaj: "cpanel", pole: pole(8, 8, 1032, 300)),
        Kreska(rodzaj: "lcd_border", pole: pole(178, 16, 632, 200)),
        Kreska(rodzaj: "lcd_bg", pole: pole(254, 48, 488, 136)),
        Kreska(rodzaj: "cpanel", pole: pole(8, 316, 464, 200)),
        Kreska(rodzaj: "cpanel", pole: pole(480, 316, 560, 200)),
        Kreska(rodzaj: "clear_rect", pole: pole(497, 363, 244, 13)),
        Kreska(rodzaj: "cpanel", pole: pole(498, 364, 242, 11)),
        Kreska(rodzaj: "clear_rect", pole: pole(743, 363, 138, 13)),
        Kreska(rodzaj: "cpanel", pole: pole(744, 364, 136, 11)),
        Kreska(rodzaj: "clear_rect", pole: pole(555, 365, 132, 1)),
        Kreska(rodzaj: "brown_line", pole: pole(31, 336, 169, 1)),
        Kreska(rodzaj: "brown_line", pole: pole(274, 336, 174, 1)),
        Kreska(rodzaj: "brown_line", pole: pole(200, 346, 36, 1)),
        Kreska(rodzaj: "brown_line", pole: pole(277, 346, 35, 1)),
        Kreska(rodzaj: "brown_line", pole: pole(337, 346, 36, 1)),
        Kreska(rodzaj: "brown_line", pole: pole(412, 346, 36, 1)),
        Kreska(rodzaj: "clear_rect", pole: pole(200, 481, 75, 1)),
        Kreska(rodzaj: "clear_rect", pole: pole(374, 481, 74, 1)),
        Kreska(rodzaj: "clear_rect", pole: pole(30, 455, 50, 1)),
        Kreska(rodzaj: "clear_rect", pole: pole(113, 455, 51, 1)),
        Kreska(rodzaj: "grey_rect", pole: pole(48, 477, 99, 15)),
        Kreska(rodzaj: "cpanel", pole: pole(49, 476, 97, 15)),
        Kreska(rodzaj: "cpanel", pole: pole(80, 487, 36, 8)),
        Kreska(rodzaj: "grey_rect", pole: pole(48, 477, 50, 7)),
        Kreska(rodzaj: "cpanel", pole: pole(49, 476, 48, 7)),
        Kreska(rodzaj: "cpanel", pole: pole(63, 480, 24, 8)),
        Kreska(rodzaj: "clear_rect", pole: pole(506, 423, 170, 1)),
        Kreska(rodzaj: "clear_rect", pole: pole(708, 423, 172, 1)),
        Kreska(rodzaj: "clear_rect", pole: pole(506, 488, 162, 1)),
        Kreska(rodzaj: "clear_rect", pole: pole(718, 488, 162, 1)),
    ]

    public static let kreski: [Kreska] = [
        Kreska(rodzaj: "clear_rect", pole: pole(497, 363, 244, 13)),
        Kreska(rodzaj: "clear_rect", pole: pole(743, 363, 138, 13)),
        Kreska(rodzaj: "clear_rect", pole: pole(555, 365, 132, 1)),
        Kreska(rodzaj: "brown_line", pole: pole(31, 336, 169, 1)),
        Kreska(rodzaj: "brown_line", pole: pole(274, 336, 174, 1)),
        Kreska(rodzaj: "brown_line", pole: pole(200, 346, 36, 1)),
        Kreska(rodzaj: "brown_line", pole: pole(277, 346, 35, 1)),
        Kreska(rodzaj: "brown_line", pole: pole(337, 346, 36, 1)),
        Kreska(rodzaj: "brown_line", pole: pole(412, 346, 36, 1)),
        Kreska(rodzaj: "clear_rect", pole: pole(200, 481, 75, 1)),
        Kreska(rodzaj: "clear_rect", pole: pole(374, 481, 74, 1)),
        Kreska(rodzaj: "clear_rect", pole: pole(30, 455, 50, 1)),
        Kreska(rodzaj: "clear_rect", pole: pole(113, 455, 51, 1)),
        Kreska(rodzaj: "grey_rect", pole: pole(48, 477, 99, 15)),
        Kreska(rodzaj: "grey_rect", pole: pole(48, 477, 50, 7)),
        Kreska(rodzaj: "clear_rect", pole: pole(506, 423, 170, 1)),
        Kreska(rodzaj: "clear_rect", pole: pole(708, 423, 172, 1)),
        Kreska(rodzaj: "clear_rect", pole: pole(506, 488, 162, 1)),
        Kreska(rodzaj: "clear_rect", pole: pole(718, 488, 162, 1)),
    ]

    public static let plyty: [Kreska] = [
        Kreska(rodzaj: "cpanel", pole: pole(8, 8, 1032, 300)),
        Kreska(rodzaj: "lcd_border", pole: pole(178, 16, 632, 200)),
        Kreska(rodzaj: "lcd_bg", pole: pole(254, 48, 488, 136)),
        Kreska(rodzaj: "cpanel", pole: pole(8, 316, 464, 200)),
        Kreska(rodzaj: "cpanel", pole: pole(480, 316, 560, 200)),
        Kreska(rodzaj: "cpanel", pole: pole(498, 364, 242, 11)),
        Kreska(rodzaj: "cpanel", pole: pole(744, 364, 136, 11)),
        Kreska(rodzaj: "cpanel", pole: pole(49, 476, 97, 15)),
        Kreska(rodzaj: "cpanel", pole: pole(80, 487, 36, 8)),
        Kreska(rodzaj: "cpanel", pole: pole(49, 476, 48, 7)),
        Kreska(rodzaj: "cpanel", pole: pole(63, 480, 24, 8)),
    ]

    /// Suwaki Tone Palette: studzienka i tor (Lower 1, Lower 2, Upper 3, Upper 4)
    public static let suwaki: [(studzienka: Pole, tor: Pole, numer: Int)] = [
        (pole(200, 349, 43, 97), pole(217, 357, 10, 82), 1),
        (pole(269, 349, 43, 97), pole(286, 357, 10, 82), 2),
        (pole(337, 349, 43, 97), pole(354, 357, 10, 82), 3),
        (pole(405, 349, 43, 97), pole(422, 357, 10, 82), 4),
    ]

    /// Strzałki wokół krzyżaka kursora (z rysunku `grey_arrows`):
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
