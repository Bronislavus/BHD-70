// BHD-70 — silnik instrumentu, interfejs dla Swifta.
//
// Silnik uruchamia emulator D-70 jako osobny proces, odbiera od niego dźwięk
// przez plik odwzorowany w pamięci i wysyła mu MIDI wirtualnym portem CoreMIDI.
// Gdy w kolejce stoi tyle próbek, ile gospodarz chce trzymać w zapasie, emulator
// czeka — czyli tempo emulacji wyznacza DAW.
//
// Wszystkie ścieżki podaje się z zewnątrz, żeby ten sam kod działał i wtedy, gdy
// emulator leży w pakiecie wtyczki (piaskownica), i wtedy, gdy leży w ~/mame-d70.

#ifndef BHD70_ENGINE_H
#define BHD70_ENGINE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct BHD70Engine BHD70Engine;

// emulator  – pełna ścieżka do programu d70
// romy      – katalog z ROM-ami
// stan      – katalog na pamięć brzmień, dziennik i plik wymiany (musi być zapisywalny)
BHD70Engine *bhd70_utworz(const char *emulator, const char *romy, const char *stan);
void bhd70_zniszcz(BHD70Engine *e);

// Uruchamia emulator w tle; wraca natychmiast. Do czasu gotowości render oddaje ciszę.
void bhd70_start(BHD70Engine *e);
void bhd70_stop(BHD70Engine *e);

// 1 = emulator podłączony i oddaje dźwięk
int bhd70_gotowy(const BHD70Engine *e);

// Jeden blok dźwięku. `lewy` i `prawy` mogą być tym samym wskaźnikiem (mono).
void bhd70_render(BHD70Engine *e, float *lewy, float *prawy, uint32_t ramek, double czestotliwosc);

// Komunikat MIDI do instrumentu (status, dane 1, dane 2).
void bhd70_midi(BHD70Engine *e, uint8_t status, uint8_t d1, uint8_t d2);

// Ktora wersje firmware'u zgral uzytkownik ("v119", "v116", ...). Wolac przed
// bhd70_start; puste = wersja domyslna emulatora.
void bhd70_wersja_firmware(BHD70Engine *e, const char *wersja);

// Wgrywa brzmienia z pliku SysEx -- tak samo, jak przez kabel MIDI ze sprzetu,
// wiec trwa to tyle, co na sprzecie (okolo 20 sekund na 64 kB). Wraca od razu,
// wysylka idzie w tle.
void bhd70_sysex(BHD70Engine *e, const uint8_t *dane, uint32_t ile);
// 1 = wgrywanie trwa
int bhd70_sysex_idzie(const BHD70Engine *e);
// Postep wgrywania w procentach (0-100)
uint32_t bhd70_sysex_postep(const BHD70Engine *e);
// Przerywa wysylke w trakcie -- gdy widac, ze instrument jej nie przyjmuje.
void bhd70_sysex_przerwij(BHD70Engine *e);

// 1 = ta kopia instrumentu trzyma wspolna, trwala pamiec brzmien (czyli to, co
// do niej wgramy, zostanie zapisane). 0 = gra na kopii roboczej.
int bhd70_pamiec_trwala(const BHD70Engine *e);

// --- panel: ekran, diody, rozkazy ---------------------------------------
// Rozmiar ekranu firmware'u (240 x 64 piksele, bit na piksel).
enum {
	BHD70_EKRAN_SZER = 240,
	BHD70_EKRAN_WYS = 64,
	BHD70_EKRAN_BAJTOW = 240 * 64 / 8
};

// Kopiuje obraz ekranu do `bajty` (BHD70_EKRAN_BAJTOW bajtow). Zwraca licznik
// odrysowania -- gdy nie zmienil sie od ostatniego razu, obraz jest ten sam
// i nie trzeba go rysowac ponownie.
uint32_t bhd70_ekran(const BHD70Engine *e, uint8_t *bajty);

// Diody panelu: bit (bank * 8 + numer), czyli LP00 = bit 0, LP37 = bit 31.
uint32_t bhd70_diody(const BHD70Engine *e);
int bhd70_dioda_learn(const BHD70Engine *e);
// Element wskazany w trybie uczenia: (rodzaj << 24) | (port << 16) | (maska << 8).
// rodzaj: 1 przycisk, 2 suwak, 3 pokretlo, 4 polowka w dol, 5 polowka w gore; 0 = nic.
uint32_t bhd70_learn_cel(const BHD70Engine *e);
// Szczyt z ostatniego bloku dzwieku (0..1) -- do miernika w oknie.
float bhd70_szczyt(BHD70Engine *e);

// Naciskanie i puszczanie przyciskow panelu (bank i bit z macierzy 8 x 8).
void bhd70_przycisk(BHD70Engine *e, uint8_t bank, uint8_t bit, int wcisniety);
// Suwak Tone Palette (numer 0-7, wartosc 0-100).
void bhd70_suwak(BHD70Engine *e, uint8_t numer, uint8_t wartosc);
// Pokretlo VALUE: tyle krokow w gore (ujemne = w dol).
void bhd70_pokretlo(BHD70Engine *e, int krokow);
// Przyciski MIDI learn (nie ma ich na prawdziwym D-70):
// bit 0 = LEARN, bit 1 = CLEAR.
void bhd70_learn(BHD70Engine *e, uint8_t bit, int wcisniety);
// Trzymana polowka pokretla: wGore = 1 w gore, 0 w dol.
void bhd70_polowka(BHD70Engine *e, int wGore, int trzymane);

// Nasłuch MIDI ze wszystkich urządzeń w systemie – dla aplikacji na Maca.
// We wtyczce tego nie włączamy: tam nuty podaje DAW.
// `zrodlo` puste albo NULL = wszystkie urzadzenia; inaczej tylko to o tej nazwie.
// Wolanie powtorne podlacza urzadzenia, ktore pojawily sie pozniej.
void bhd70_sluchaj_midi(BHD70Engine *e, int wlacz, const char *zrodlo);

// Co instrument ma w tej chwili wcisniete: bit (bank * 8 + numer bitu),
// niezaleznie od tego, czy zrobila to mysz, klawiatura czy kontroler MIDI.
uint64_t bhd70_przyciski(const BHD70Engine *e);
// Gdzie stoi wejscie analogowe `numer` (0-7): 0-100. Zwraca -1, gdy nie wiadomo.
int bhd70_poziom_suwaka(const BHD70Engine *e, uint8_t numer);

// Diagnostyka dla okna wtyczki.
uint32_t bhd70_kolejka_ramek(const BHD70Engine *e);
uint32_t bhd70_brakow(const BHD70Engine *e);

#ifdef __cplusplus
}
#endif

#endif // BHD70_ENGINE_H
