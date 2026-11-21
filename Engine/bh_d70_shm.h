// license:GPL-3.0+
// copyright-holders:Bronisław Hońca
/***************************************************************************

    BH D-70: wspólny blok pamięci między emulatorem a wtyczką AU.

    Emulator (ten plik jest w nim kompilowany) pisze próbki do pierścienia,
    wtyczka je odbiera. Gdy pierścień jest pełny, emulator czeka -- i wtedy
    to wtyczka, czyli gospodarz (DAW), wyznacza tempo emulacji.

    Ten plik jest kopiowany do projektu wtyczki przez jej build.sh -- jedyne
    miejsce, w którym się go edytuje, jest tutaj.

***************************************************************************/

#ifndef MAME_ROLAND_BH_D70_SHM_H
#define MAME_ROLAND_BH_D70_SHM_H

#pragma once

#include <atomic>
#include <cstdint>

namespace bh_d70 {

constexpr std::uint32_t SHM_MAGIC = 0x42483730;   // "BH70"
constexpr std::uint32_t SHM_VERSION = 3;

// --- panel: ekran, diody i rozkazy --------------------------------------
// Ekran firmware'u ma 240 x 64 piksele, jeden bit na piksel (zapalony = 1).
constexpr std::uint32_t EKRAN_SZER = 240;
constexpr std::uint32_t EKRAN_WYS = 64;
constexpr std::uint32_t EKRAN_BAJTOW = EKRAN_SZER * EKRAN_WYS / 8;

// Pierścień rozkazów z panelu wtyczki do emulatora (naciśnięcia, suwaki, pokrętło).
constexpr std::uint32_t ROZKAZOW = 256;

// Rodzaje rozkazów: (rodzaj << 24) | (a << 16) | (b << 8) | c
enum : std::uint8_t
{
	ROZKAZ_PRZYCISK = 1,   // a = bank 0-7, b = numer bitu 0-7, c = 1 wcisniety / 0 puszczony
	ROZKAZ_SUWAK    = 2,   // a = numer 0-7, b = wartosc 0-100
	ROZKAZ_POKRETLO = 3,   // a = krokow w gore (0-127), b = krokow w dol (0-127)
	ROZKAZ_POLOWKA  = 4,   // a = 0 w dol / 1 w gore, c = 1 trzymane / 0 puszczone
	ROZKAZ_LEARN    = 5    // a = numer bitu portu LEARN (0 learn, 1 clear, 2 audio/midi), c = stan
};

// Pierścień musi pomieścić co najmniej dwa bloki gospodarza przeliczone na ramki
// układu (przy bloku 1024 próbek i 48 kHz to 683 ramki), z zapasem na nierówności.
// Opóźnieniem jest tylko to, co w nim naprawdę stoi -- a tym steruje `target_frames`.
constexpr std::uint32_t SHM_RING_FRAMES = 4096;

// największy sensowny zapas: powyżej tego pierścień nie miałby miejsca na dopisanie
constexpr std::uint32_t SHM_MAX_TARGET = SHM_RING_FRAMES * 3 / 4;

struct shm_block
{
	std::uint32_t magic;
	std::uint32_t version;
	std::uint32_t rate;                      // częstotliwość próbkowania układu (32000)
	std::uint32_t ring_frames;               // długość pierścienia w ramkach

	std::atomic<std::uint32_t> write_pos;    // pisze emulator
	std::atomic<std::uint32_t> read_pos;     // pisze wtyczka
	std::atomic<std::uint32_t> emu_alive;    // 1 = emulator żyje
	std::atomic<std::uint32_t> host_alive;   // 1 = wtyczka żyje
	std::atomic<std::uint32_t> underruns;    // ile razy wtyczce zabrakło próbek
	std::atomic<std::uint32_t> target_frames;// ile ramek wtyczka chce trzymać w zapasie

	std::int16_t ring[SHM_RING_FRAMES * 2];

	// --- panel (wersja 2) ---
	std::atomic<std::uint32_t> ekran_licznik;  // rosnie po kazdym odrysowaniu ekranu
	std::atomic<std::uint32_t> diody;          // bity LPrc: bit (bank * 8 + numer)
	std::atomic<std::uint32_t> dioda_learn;    // kontrolka MIDI learn
	// Wskazany element w trybie uczenia, zeby panel mogl go podswietlic:
	// (rodzaj << 24) | (port << 16) | (maska << 8); 0 = nic nie wskazano.
	// rodzaj: 1 przycisk (port = KEYn, maska = bit), 2 suwak (port = numer),
	//         3 pokretlo, 4 polowka w dol, 5 polowka w gore
	std::atomic<std::uint32_t> learn_cel;
	std::atomic<std::uint32_t> rozkaz_pisz;    // pisze wtyczka
	std::atomic<std::uint32_t> rozkaz_czytaj;  // pisze emulator
	std::uint32_t rozkazy[ROZKAZOW];
	std::uint8_t ekran[EKRAN_BAJTOW];

	// --- stan panelu (wersja 3) ---
	// Co instrument ma w tej chwili wcisniete i gdzie stoja jego suwaki, niezaleznie
	// od tego, kto to zmienil: reka na panelu, klawiatura czy kontroler przez MIDI
	// learn. Dzieki temu panel pokazuje to, co naprawde dzieje sie w instrumencie.
	std::atomic<std::uint32_t> przyciski_lo;   // banki KEY0-KEY3, po bajcie; bit = wcisniety
	std::atomic<std::uint32_t> przyciski_hi;   // banki KEY4-KEY7
	std::atomic<std::uint32_t> suwaki_lo;      // wejscia analogowe 0-3, po bajcie (0-100)
	std::atomic<std::uint32_t> suwaki_hi;      // wejscia analogowe 4-7
};

inline std::uint32_t shm_queued(const shm_block *b)
{
	std::uint32_t const w = b->write_pos.load(std::memory_order_acquire);
	std::uint32_t const r = b->read_pos.load(std::memory_order_acquire);
	return (w >= r) ? (w - r) : (b->ring_frames - r + w);
}

inline std::uint32_t shm_space(const shm_block *b)
{
	return b->ring_frames - 1 - shm_queued(b);
}

} // namespace bh_d70

#endif // MAME_ROLAND_BH_D70_SHM_H
