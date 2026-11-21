// BHD-70 — silnik instrumentu. Opis w bhd70_engine.h.

#include "bhd70_engine.h"
#include "bh_d70_shm.h"

#include <CoreMIDI/CoreMIDI.h>
#include <CoreFoundation/CoreFoundation.h>

#include <dirent.h>
#include <fcntl.h>
#include <sys/file.h>
#include <signal.h>
#include <spawn.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdarg>
#include <os/log.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <set>
#include <string>
#include <thread>
#include <vector>

extern char **environ;

namespace {

constexpr double kCzestotliwoscUkladu = 32000.0;   // układ dźwiękowy D-70
// Emulator oddaje dźwięk porcjami po jednej klatce ekranu (250 Hz = 128 ramek),
// więc kolejka musi pomieścić całą taką porcję plus to, o co prosi gospodarz,
// plus zapas na nierówności. Przy krótkich buforach (64 próbki) poprzedni zapas
// 128 ramek był za mały i próbek brakowało bez przerwy -- słychać było ciszę.
constexpr uint32_t kPorcjaUkladu = 128;            // ramek na jedną klatkę emulacji
constexpr uint32_t kZapasMin = 320;                // najmniejszy sensowny zapas (10 ms)

std::atomic<unsigned> g_licznik{0};

// Kasuje katalog z zawartością -- używane tylko do kopii roboczych pamięci.
void usun_katalog(std::string const &sciezka)
{
	DIR *d = ::opendir(sciezka.c_str());
	if (!d) return;
	while (dirent *w = ::readdir(d))
	{
		std::string const nazwa = w->d_name;
		if (nazwa == "." || nazwa == "..") continue;
		std::string const pelna = sciezka + "/" + nazwa;
		struct stat st{};
		if (::stat(pelna.c_str(), &st) != 0) continue;
		if (S_ISDIR(st.st_mode)) usun_katalog(pelna);
		else ::unlink(pelna.c_str());
	}
	::closedir(d);
	::rmdir(sciezka.c_str());
}

} // anonymous namespace

struct BHD70Engine
{
	std::string emulator, romy, stan;
	std::string plik_wymiany, nazwa_midi, katalog_nvram, dziennik_sciezka;
	// Nazwa portu MIDI emulatora. Przy każdym włączeniu dostaje inny numer:
	// po zgaszeniu emulatora jego wirtualny port zostaje w CoreMIDI jeszcze
	// chwilę jako martwy wpis, a nowy o tej samej nazwie nie powstaje.
	std::string nazwa_midi_baza;
	int wlaczen = 0;
	// Pamięć brzmień instrumentu: jedna, wspólna i trwała. Bierze ją pierwsza
	// instancja (zamek na pliku); kolejne grają na własnej kopii roboczej,
	// żeby nie nadpisywały sobie nawzajem brzmień.
	std::string katalog_pamieci, katalog_roboczy;
	std::string wersja_firmware;   // np. "v119" -- ktora wersje zgral uzytkownik
	int zamek_fd = -1;
	bool pamiec_trwala = false;

	pid_t dziecko = -1;
	std::thread watek_startu;
	std::thread watek_midi;
	bh_d70::shm_block *blok = nullptr;
	int blok_fd = -1;

	double krok = 1.0, frac = 0.0;
	float poprz[2] = { 0.f, 0.f }, biez[2] = { 0.f, 0.f };
	uint32_t cel = 0;
	int nast_proba = 0, nast_midi = 0;
	uint32_t licznik_diag = 0;
	std::atomic<float> szczyt{0.f};
	float szczyt_diag = 0.f;
	bool zglosil_brak = false;
	// konczymy  = gasimy emulator (wolno go potem wlaczyc na nowo)
	// zamykamy  = koniec calego silnika, wtek MIDI ma wyjsc
	std::atomic<bool> konczymy{false};
	std::atomic<bool> zamykamy{false};

	// Wgrywanie brzmień z pliku SysEx (trwa tyle, co przez prawdziwy kabel MIDI)
	std::thread watek_sysex;
	std::atomic<bool> sysex_idzie{false};
	// Przerwanie wysylki w trakcie (gdy instrument jej nie przyjmuje)
	std::atomic<bool> sysex_stop{false};
	std::atomic<uint32_t> sysex_wyslane{0}, sysex_razem{0};
	// SysEx przychodzący z urządzeń użytkownika (np. zgranie z prawdziwego D-70)
	std::vector<uint8_t> sysex_wejscie;
	bool sysex_wejscie_trwa = false;

	/// Podaje gotowy komunikat SysEx instrumentowi (bez kolejkowania i bez tempa --
	/// ten już przyszedł z zewnątrz w tempie MIDI).
	void podaj_sysex(const uint8_t *dane, uint32_t ile)
	{
		if (!ile || ile > (1u << 20)) return;
		if (!cel_midi) return;      // portu szuka watek MIDI
		std::vector<Byte> bufor(sizeof(MIDIPacketList) + ile + 64);
		auto *pl = reinterpret_cast<MIDIPacketList *>(bufor.data());
		MIDIPacket *p = MIDIPacketListInit(pl);
		p = MIDIPacketListAdd(pl, bufor.size(), p, 0, ile, dane);
		if (p) MIDISend(port, cel_midi, pl);
	}

	MIDIClientRef klient_wy = 0;      // do szukania portu emulatora i wysylki
	MIDIClientRef klient_we = 0;      // nasluch MIDI (programu) -- osobny, zeby odnawianie
	                                  // klienta wyjsciowego go nie kasowalo
	std::chrono::steady_clock::time_point nast_szukanie{};
	MIDIPortRef port = 0;
	MIDIEndpointRef cel_midi = 0;
	MIDIPortRef wejscie = 0;
	std::string zrodlo_midi;
	std::set<MIDIEndpointRef> podlaczone;

	// Dziennik: do pliku obok pamięci brzmień i do konsoli systemowej
	// (w piaskownicy pliku wtyczki nie da się przeczytać z zewnątrz, a konsolę tak:
	//  log stream --predicate 'subsystem == "pl.bronek.bhd70"')
	void dziennik(char const *fmt, ...)
	{
		char tekst[1024];
		va_list ap;
		va_start(ap, fmt);
		std::vsnprintf(tekst, sizeof tekst, fmt, ap);
		va_end(ap);
		os_log(konsola(), "%{public}s", tekst);
		FILE *f = std::fopen(dziennik_sciezka.c_str(), "a");
		if (!f) return;
		std::fputs(tekst, f);
		std::fputc('\n', f);
		std::fclose(f);
	}

	static os_log_t konsola()
	{
		static os_log_t l = os_log_create("pl.bronek.bhd70", "silnik");
		return l;
	}

	// --- kopiowanie pamięci brzmień bez uruchamiania powłoki ------------------
	static void kopiuj_plik(std::string const &z, std::string const &dokad)
	{
		FILE *a = std::fopen(z.c_str(), "rb");
		if (!a) return;
		FILE *b = std::fopen(dokad.c_str(), "wb");
		if (!b) { std::fclose(a); return; }
		char buf[65536];
		size_t n;
		while ((n = std::fread(buf, 1, sizeof(buf), a)) > 0)
			std::fwrite(buf, 1, n, b);
		std::fclose(a);
		std::fclose(b);
	}

	static void kopiuj_katalog(std::string const &z, std::string const &dokad)
	{
		::mkdir(dokad.c_str(), 0755);
		DIR *d = ::opendir(z.c_str());
		if (!d) return;
		while (dirent *e = ::readdir(d))
		{
			std::string const nazwa = e->d_name;
			if (nazwa == "." || nazwa == "..") continue;
			std::string const zrodlo = z + "/" + nazwa;
			std::string const cel2 = dokad + "/" + nazwa;
			struct stat st{};
			if (::stat(zrodlo.c_str(), &st) != 0) continue;
			if (S_ISDIR(st.st_mode)) kopiuj_katalog(zrodlo, cel2);
			else if (::access(cel2.c_str(), F_OK) != 0) kopiuj_plik(zrodlo, cel2);
		}
		::closedir(d);
	}

	void uruchom()
	{
		if (dziecko > 0) return;
		// Drugie i każde następne włączenie dostaje port o innej nazwie --
		// patrz nazwa_midi_baza.
		if (++wlaczen > 1)
			nazwa_midi = nazwa_midi_baza + "." + std::to_string(wlaczen);
		if (::access(emulator.c_str(), X_OK) != 0)
		{
			dziennik("brak emulatora: %s", emulator.c_str());
			return;
		}

		// Pamięć brzmień. Pierwsza instancja bierze wspólną, trwałą pamięć na
		// własność -- to ona zapisuje zmiany przy zamknięciu. Kolejne instancje
		// dostają kopię roboczą: grają tym samym, ale nie nadpisują oryginału.
		::mkdir(katalog_pamieci.c_str(), 0755);
		// Gdy wspólna pamięć jest jeszcze pusta, a obok emulatora albo w zasobach
		// leży gotowa -- bierzemy ją na start. Po wyjęciu plików Rolanda z pakietu
		// nie będzie czego brać i instrument wstanie z pustą pamięcią.
		if (::access((katalog_pamieci + "/d70/nvram").c_str(), R_OK) != 0)
		{
			std::string wzor = emulator.substr(0, emulator.find_last_of('/')) + "/nvram";
			if (::access(wzor.c_str(), R_OK) != 0)
				wzor = romy.substr(0, romy.find_last_of('/')) + "/nvram";
			if (::access(wzor.c_str(), R_OK) == 0)
				kopiuj_katalog(wzor, katalog_pamieci);
		}
		zamek_fd = ::open((katalog_pamieci + ".zamek").c_str(), O_CREAT | O_RDWR, 0644);
		pamiec_trwala = (zamek_fd >= 0 && ::flock(zamek_fd, LOCK_EX | LOCK_NB) == 0);
		if (!pamiec_trwala && zamek_fd >= 0) { ::close(zamek_fd); zamek_fd = -1; }
		katalog_nvram = pamiec_trwala ? katalog_pamieci : katalog_roboczy;
		::mkdir(katalog_nvram.c_str(), 0755);
		if (!pamiec_trwala)
			kopiuj_katalog(katalog_pamieci, katalog_nvram);
		dziennik("[%s] pamiec brzmien: %s", nazwa_midi.c_str(),
				pamiec_trwala ? "wspolna, zmiany zostana zapisane"
							  : "kopia robocza, zmiany nie beda zapisane");

		std::string const shmenv = "BH_D70_SHM=" + plik_wymiany;
		// Bez tego SDL rejestruje emulator jako aplikację z oknem i w DAW-ie widać
		// wielki czarny ekran.
		std::string const sdlenv = "SDL_VIDEODRIVER=dummy";
		std::string const midiarg = "virtual:" + nazwa_midi;

		// Użytkownik mógł zgrać inną wersję firmware'u niż domyślna -- mówimy
		// emulatorowi, którą dostał, inaczej szukałby nieistniejącej.
		std::vector<char *> argv = {
			const_cast<char *>(emulator.c_str()), const_cast<char *>("d70"),
		};
		if (!wersja_firmware.empty())
		{
			argv.push_back(const_cast<char *>("-bios"));
			argv.push_back(const_cast<char *>(wersja_firmware.c_str()));
		}
		char *dalej[] = {
			const_cast<char *>("-rompath"), const_cast<char *>(romy.c_str()),
			const_cast<char *>("-video"), const_cast<char *>("none"),
			const_cast<char *>("-skip_gameinfo"),
			const_cast<char *>("-nothrottle"),
			const_cast<char *>("-sound"), const_cast<char *>("none"),
			const_cast<char *>("-midiin"), const_cast<char *>(midiarg.c_str()),
			const_cast<char *>("-nvram_directory"), const_cast<char *>(katalog_nvram.c_str()),
			const_cast<char *>("-cfg_directory"), const_cast<char *>(katalog_nvram.c_str()),
		};
		for (char *a : dalej) argv.push_back(a);
		argv.push_back(nullptr);
		std::vector<char *> env;
		for (char **e = environ; *e; e++) env.push_back(*e);
		env.push_back(const_cast<char *>(shmenv.c_str()));
		env.push_back(const_cast<char *>(sdlenv.c_str()));
		env.push_back(nullptr);

		posix_spawn_file_actions_t akcje;
		posix_spawn_file_actions_init(&akcje);
		std::string const log = stan + "/emulator.log";
		posix_spawn_file_actions_addopen(&akcje, 1, log.c_str(), O_WRONLY | O_CREAT | O_APPEND, 0644);
		posix_spawn_file_actions_adddup2(&akcje, 1, 2);
		pid_t pid = 0;
		int const rc = ::posix_spawn(&pid, emulator.c_str(), &akcje, nullptr, argv.data(), env.data());
		posix_spawn_file_actions_destroy(&akcje);
		if (rc != 0)
		{
			dziennik("nie moge uruchomic emulatora (%d)", rc);
			return;
		}
		dziecko = pid;
		dziennik("[%s] emulator uruchomiony, pid %d", nazwa_midi.c_str(), int(pid));

		// Podłączamy się tutaj, a nie dopiero przy pierwszym bloku dźwięku:
		// panel (ekran, diody) ma działać także wtedy, gdy nikt nie prosi o dźwięk.
		for (int i = 0; i < 400 && !blok && !konczymy.load(); i++)
		{
			nast_proba = 0;
			moze_podlacz();
			if (!blok) std::this_thread::sleep_for(std::chrono::milliseconds(50));
		}
		// Portu emulatora szuka watek MIDI -- on jedyny ma petle zdarzen.
	}

	void moze_podlacz()
	{
		if (blok || dziecko <= 0) return;
		if (nast_proba-- > 0) return;
		nast_proba = 40;
		int fd = ::open(plik_wymiany.c_str(), O_RDWR);
		if (fd < 0) return;
		struct stat st{};
		if (::fstat(fd, &st) != 0 || size_t(st.st_size) < sizeof(bh_d70::shm_block))
		{
			::close(fd);
			return;
		}
		void *mem = ::mmap(nullptr, sizeof(bh_d70::shm_block), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
		::close(fd);
		if (mem == MAP_FAILED) return;
		auto *b = static_cast<bh_d70::shm_block *>(mem);
		if (b->magic != bh_d70::SHM_MAGIC || !b->emu_alive.load())
		{
			::munmap(mem, sizeof(bh_d70::shm_block));
			return;
		}
		b->host_alive.store(1);
		b->target_frames.store(cel ? cel : kZapasMin);
		blok = b;
		dziennik("[%s] podlaczone (%u Hz)", nazwa_midi.c_str(), b->rate);
	}

	// Klient CoreMIDI widzi tylko ten stan systemu, jaki zastał przy utworzeniu,
	// a port emulatora powstaje po jego starcie — przy nieudanym szukaniu zamykamy
	// klienta, żeby następna próba zaczęła od świeżego.
	// Klient CoreMIDI tworzymy raz i z powiadomieniem o zmianach -- bez niego
	// klient widzi tylko porty, ktore istnialy w chwili jego powstania, a nasz
	// emulator tworzy swoj port dopiero kilka sekund po starcie programu.
	// Niszczenie klienta przy ponownej probie kasowalo tez wejscie MIDI.
	// Klient CoreMIDI widzi tylko te porty, ktore istnialy w chwili jego powstania.
	// Powiadomienia o nowych portach dochodza wylacznie na watek z petla zdarzen,
	// a nasz watek startowy jej nie ma -- wiec sie na nich nie opieramy. Zamiast
	// tego, dopoki nie znajdziemy swojego portu, tworzymy klienta od nowa.
	//
	// Wlasnie tego brakowalo, gdy ktos wstawial w DAW-ie kolejna kopie instrumentu
	// po tym, jak pierwsza juz gra: nowa kopia nie widziala swojego emulatora,
	// nuty nie mialy dokad isc i instrument milczal.
	// Watek MIDI: tworzy klienta i KRECI PETLA ZDARZEN.
	//
	// Bez niej caly proces wtyczki widzi tylko te porty, ktore istnialy, gdy pierwszy
	// raz polaczyl sie z systemem MIDI. Porty emulatorow uruchomionych pozniej nie
	// pojawialy sie wcale -- i dlatego w DAW-ie druga i kazda nastepna kopia
	// instrumentu milczala: nuty nie mialy dokad isc. Tworzenie nowego klienta nic
	// nie dawalo, bo ten widok jest wspolny dla procesu, a odswiezaja go wylacznie
	// powiadomienia, ktore przychodza tylko na watek z petla zdarzen.
	void petla_midi()
	{
		// Ten wątek i jego klient CoreMIDI żyją tyle, co cały silnik -- nie tyle,
		// co emulator. Gdy klienta zniszczyć i założyć na nowo, proces przestaje
		// dostawać powiadomienia o portach: po ponownym włączeniu instrumentu w
		// liście zostaje martwy wpis po starym emulatorze, a nowego portu nie
		// widać wcale. Wtedy nic do instrumentu nie dochodzi -- ani nuty, ani
		// SysEx z brzmieniami.
		odnow_klienta_wy();
		while (!zamykamy.load(std::memory_order_relaxed))
		{
			// Przepuszczamy powiadomienia CoreMIDI, potem patrzymy, czy juz jest nasz port
			CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, true);
			if (!cel_midi && dziecko > 0) szukaj_portu();
			else if (!zamykamy.load(std::memory_order_relaxed))
				std::this_thread::sleep_for(std::chrono::milliseconds(200));
		}
	}

	void odnow_klienta_wy()
	{
		if (port) { MIDIPortDispose(port); port = 0; }
		if (klient_wy) { MIDIClientDispose(klient_wy); klient_wy = 0; }
		cel_midi = 0;
		if (MIDIClientCreate(CFSTR("BHD-70 wy"), nullptr, nullptr, &klient_wy) != noErr) return;
		if (MIDIOutputPortCreate(klient_wy, CFSTR("out"), &port) != noErr)
		{
			MIDIClientDispose(klient_wy);
			klient_wy = 0;
		}
	}

	// Szuka portu emulatora. Wolane wylacznie z watku MIDI, ktory ma petle zdarzen.
	void szukaj_portu()
	{
		if (cel_midi) return;
		if (!klient_wy) { odnow_klienta_wy(); if (!klient_wy) return; }
		ItemCount const n = MIDIGetNumberOfDestinations();
		for (ItemCount i = 0; i < n; i++)
		{
			MIDIEndpointRef e = MIDIGetDestination(i);
			CFStringRef nm = nullptr;
			MIDIObjectGetStringProperty(e, kMIDIPropertyDisplayName, &nm);
			if (!nm) continue;
			char buf[256] = "";
			CFStringGetCString(nm, buf, sizeof(buf), kCFStringEncodingUTF8);
			CFRelease(nm);
			if (nazwa_midi == buf)
			{
				cel_midi = e;
				dziennik("[%s] port MIDI znaleziony", buf);
				return;
			}
		}
		if (!zglosil_brak)
		{
			zglosil_brak = true;
			std::string lista;
			for (ItemCount i = 0; i < n; i++)
			{
				CFStringRef nm = nullptr;
				MIDIObjectGetStringProperty(MIDIGetDestination(i), kMIDIPropertyDisplayName, &nm);
				char buf[256] = "?";
				if (nm) { CFStringGetCString(nm, buf, sizeof(buf), kCFStringEncodingUTF8); CFRelease(nm); }
				lista += (i ? ", " : ""); lista += buf;
			}
			dziennik("[%s] nie widze jeszcze swojego portu MIDI; widze %u: %s",
					nazwa_midi.c_str(), unsigned(n), lista.c_str());
		}
	}

};

// --- interfejs C -----------------------------------------------------------

BHD70Engine *bhd70_utworz(const char *emulator, const char *romy, const char *stan)
{
	auto *e = new BHD70Engine();
	e->emulator = emulator ? emulator : "";
	e->romy = romy ? romy : "";
	e->stan = stan ? stan : "/tmp";
	::mkdir(e->stan.c_str(), 0755);
	unsigned const n = ++g_licznik;
	char buf[64];
	std::snprintf(buf, sizeof(buf), "BHD-70 %d-%u", int(::getpid()), n);
	e->nazwa_midi = buf;
	e->nazwa_midi_baza = buf;
	e->plik_wymiany = e->stan + "/wymiana-" + std::to_string(::getpid()) + "-" + std::to_string(n) + ".bin";
	e->katalog_pamieci = e->stan + "/pamiec";
	e->katalog_roboczy = e->stan + "/pamiec-robocza-" + std::to_string(::getpid()) + "-" + std::to_string(n);
	e->katalog_nvram = e->katalog_roboczy;
	e->dziennik_sciezka = e->stan + "/wtyczka.log";
	e->dziennik("[%s] nowa instancja", e->nazwa_midi.c_str());
	return e;
}

void bhd70_start(BHD70Engine *e)
{
	if (!e || e->watek_startu.joinable() || e->dziecko > 0) return;
	// Po bhd70_stop flaga „kończymy" została ustawiona. Zerujemy ją, bo inaczej
	// ponowne włączenie instrumentu (wejście w tryb serwisowy) natychmiast by się
	// poddało. Dzięki temu stop/start wolno wołać wiele razy na tym samym silniku.
	e->konczymy.store(false);
	e->sysex_stop.store(false);
	e->zglosil_brak = false;
	e->cel_midi = 0;
	// Gospodarz woła to na swoim głównym wątku — nie wolno go blokować.
	e->watek_startu = std::thread([e] { e->uruchom(); });
	// Wątek MIDI zakładamy tylko raz na cały silnik -- patrz petla_midi().
	if (!e->watek_midi.joinable())
		e->watek_midi = std::thread([e] { e->petla_midi(); });
}

void bhd70_stop(BHD70Engine *e)
{
	if (!e) return;
	e->konczymy.store(true);
	if (e->watek_startu.joinable()) e->watek_startu.join();
	if (e->watek_sysex.joinable()) e->watek_sysex.join();
	// Wyzerowanie host_alive to dla emulatora prośba o zakończenie. Musi wyjść sam,
	// a nie zginąć od sygnału -- tylko wtedy MAME zapisze pamięć brzmień na dysk.
	// Blok wymiany zostaje odwzorowany, dopóki emulator żyje: emulacja pisze do
	// niego do ostatniej chwili i odmapowanie za wcześnie kończy się jego awarią.
	if (e->blok) e->blok->host_alive.store(0);
	if (e->dziecko > 0)
	{
		auto czekaj = [&](int prob) {
			for (int i = 0; i < prob; i++)
			{
				int st = 0;
				if (::waitpid(e->dziecko, &st, WNOHANG) == e->dziecko) return true;
				std::this_thread::sleep_for(std::chrono::milliseconds(20));
			}
			return false;
		};
		// Zwykle wychodzi w ułamku sekundy; 5 s to zapas na zapis pamięci.
		if (czekaj(250))
			e->dziennik("[%s] emulator zamkniety, pamiec zapisana", e->nazwa_midi.c_str());
		else
		{
			// Nie posłuchał -- wtedy trudno, ubijamy. Pamięć brzmień przepadnie.
			::kill(e->dziecko, SIGTERM);
			czekaj(100);
			e->dziennik("[%s] emulator nie wyszedl sam, ubity", e->nazwa_midi.c_str());
		}
		e->dziecko = -1;
	}
	if (e->blok)
	{
		::munmap(e->blok, sizeof(bh_d70::shm_block));
		e->blok = nullptr;
	}
	::unlink(e->plik_wymiany.c_str());
	// Kopia robocza była tylko na czas grania -- sprzątamy, żeby się nie zbierały.
	if (!e->pamiec_trwala && !e->katalog_roboczy.empty())
		usun_katalog(e->katalog_roboczy);
	if (e->zamek_fd >= 0) { ::flock(e->zamek_fd, LOCK_UN); ::close(e->zamek_fd); e->zamek_fd = -1; }
	e->pamiec_trwala = false;
	// Port emulatora zniknął razem z nim; klient i wątek MIDI zostają, bo bez
	// nich proces nie zobaczyłby portu po ponownym włączeniu instrumentu.
	e->cel_midi = 0;
}

void bhd70_zniszcz(BHD70Engine *e)
{
	if (!e) return;
	bhd70_stop(e);
	// Teraz, i tylko teraz, zwijamy CoreMIDI -- patrz petla_midi().
	e->zamykamy.store(true);
	if (e->watek_midi.joinable()) e->watek_midi.join();
	if (e->port) { MIDIPortDispose(e->port); e->port = 0; }
	if (e->klient_wy) { MIDIClientDispose(e->klient_wy); e->klient_wy = 0; }
	if (e->wejscie) { MIDIPortDispose(e->wejscie); e->wejscie = 0; }
	if (e->klient_we) { MIDIClientDispose(e->klient_we); e->klient_we = 0; }
	e->podlaczone.clear();
	delete e;
}

int bhd70_gotowy(const BHD70Engine *e) { return (e && e->blok) ? 1 : 0; }

// --- nasłuch MIDI (aplikacja na Maca) ------------------------------------

static void bhd70_odbior(const MIDIPacketList *lista, void *ref, void *)
{
	auto *e = static_cast<BHD70Engine *>(ref);
	const MIDIPacket *p = &lista->packet[0];
	for (unsigned i = 0; i < lista->numPackets; i++)
	{
		for (unsigned k = 0; k + 1 <= p->length; k++)
		{
			uint8_t const st = p->data[k];
			// Komunikat systemowy (SysEx) -- tędy wchodzą brzmienia zgrywane na
			// żywo z prawdziwego D-70. Potrafi iść przez kilka paczek, więc
			// zbieramy go do końca (F7) i dopiero wtedy podajemy instrumentowi.
			if (st == 0xf0 || e->sysex_wejscie_trwa)
			{
				for (; k < p->length; k++)
				{
					uint8_t const b = p->data[k];
					if (b == 0xf0) { e->sysex_wejscie.clear(); e->sysex_wejscie_trwa = true; }
					if (!e->sysex_wejscie_trwa) break;
					if (e->sysex_wejscie.size() < 1u << 20) e->sysex_wejscie.push_back(b);
					if (b == 0xf7)
					{
						e->sysex_wejscie_trwa = false;
						e->podaj_sysex(e->sysex_wejscie.data(), uint32_t(e->sysex_wejscie.size()));
						e->sysex_wejscie.clear();
						break;
					}
				}
				continue;
			}
			if (st < 0x80 || st >= 0xf0) continue;
			int const dl = ((st & 0xf0) == 0xc0 || (st & 0xf0) == 0xd0) ? 2 : 3;
			if (k + dl > p->length) break;
			bhd70_midi(e, st, p->data[k + 1], dl >= 3 ? p->data[k + 2] : 0);
			k += dl - 1;
		}
		p = MIDIPacketNext(p);
	}
}

static std::string nazwa_punktu(MIDIEndpointRef e)
{
	CFStringRef s = nullptr;
	if (MIDIObjectGetStringProperty(e, kMIDIPropertyDisplayName, &s) != noErr || !s) return {};
	char buf[256] = { 0 };
	CFStringGetCString(s, buf, sizeof buf, kCFStringEncodingUTF8);
	CFRelease(s);
	return buf;
}

void bhd70_sluchaj_midi(BHD70Engine *e, int wlacz, const char *zrodlo)
{
	if (!e) return;
	if (!wlacz)
	{
		if (e->wejscie) { MIDIPortDispose(e->wejscie); e->wejscie = 0; }
		e->podlaczone.clear();
		return;
	}
	// Nasłuch ma własnego klienta: klient wyjściowy bywa odnawiany przy szukaniu
	// portu emulatora i zabrałby ze sobą otwarte wejście.
	if (!e->klient_we
	    && MIDIClientCreate(CFSTR("BHD-70 we"), nullptr, nullptr, &e->klient_we) != noErr)
		return;
	std::string const chciane = zrodlo ? zrodlo : "";
	if (chciane != e->zrodlo_midi)
	{
		// zmiana wyboru: zaczynamy od nowa
		if (e->wejscie) { MIDIPortDispose(e->wejscie); e->wejscie = 0; }
		e->podlaczone.clear();
		e->zrodlo_midi = chciane;
	}
	if (!e->wejscie)
	{
		CFStringRef nazwa = CFStringCreateWithCString(nullptr, "BHD-70 wejscie", kCFStringEncodingUTF8);
		OSStatus const rc = MIDIInputPortCreate(e->klient_we, nazwa, bhd70_odbior, e, &e->wejscie);
		CFRelease(nazwa);
		if (rc != noErr) { e->dziennik("nie moge otworzyc wejscia MIDI (%d)", int(rc)); return; }
	}
	ItemCount const n = MIDIGetNumberOfSources();
	unsigned ile = 0;
	for (ItemCount i = 0; i < n; i++)
	{
		MIDIEndpointRef const p = MIDIGetSource(i);
		std::string const nz = nazwa_punktu(p);
		if (nz.rfind("BHD-70", 0) == 0) continue;            // własne porty wirtualne
		if (!chciane.empty() && nz != chciane) continue;
		if (e->podlaczone.count(p)) { ile++; continue; }
		if (MIDIPortConnectSource(e->wejscie, p, nullptr) == noErr)
		{
			e->podlaczone.insert(p);
			ile++;
			e->dziennik("nasluch MIDI: podlaczone \"%s\"", nz.c_str());
		}
	}
	if (!ile) e->dziennik("nasluch MIDI: nie ma czego sluchac");
}

// --- panel ---------------------------------------------------------------

uint32_t bhd70_ekran(const BHD70Engine *e, uint8_t *bajty)
{
	if (!e || !e->blok || e->blok->version < 2) return 0;
	std::memcpy(bajty, e->blok->ekran, sizeof e->blok->ekran);
	return e->blok->ekran_licznik.load(std::memory_order_acquire);
}

uint32_t bhd70_diody(const BHD70Engine *e)
{
	if (!e || !e->blok || e->blok->version < 2) return 0;
	return e->blok->diody.load(std::memory_order_relaxed);
}

int bhd70_dioda_learn(const BHD70Engine *e)
{
	if (!e || !e->blok || e->blok->version < 2) return 0;
	return int(e->blok->dioda_learn.load(std::memory_order_relaxed));
}

uint64_t bhd70_przyciski(const BHD70Engine *e)
{
	if (!e || !e->blok || e->blok->version < 3) return 0;
	return uint64_t(e->blok->przyciski_lo.load(std::memory_order_relaxed))
	     | (uint64_t(e->blok->przyciski_hi.load(std::memory_order_relaxed)) << 32);
}

int bhd70_poziom_suwaka(const BHD70Engine *e, uint8_t numer)
{
	if (!e || !e->blok || e->blok->version < 3 || numer > 7) return -1;
	uint32_t const slowo = (numer < 4 ? e->blok->suwaki_lo : e->blok->suwaki_hi)
			.load(std::memory_order_relaxed);
	return int((slowo >> ((numer % 4) * 8)) & 0xff);
}

uint32_t bhd70_learn_cel(const BHD70Engine *e)
{
	if (!e || !e->blok || e->blok->version < 2) return 0;
	return e->blok->learn_cel.load(std::memory_order_relaxed);
}

float bhd70_szczyt(BHD70Engine *e)
{
	if (!e) return 0.f;
	return e->szczyt.exchange(0.f, std::memory_order_relaxed);
}

// Wklada rozkaz do pierscienia. Gdy pierscien jest pelny, rozkaz przepada --
// panel i tak wysle nastepny stan, a lepiej zgubic jedno nacisniecie niz
// zatrzymac okno wtyczki.
static void rozkaz(BHD70Engine *e, uint8_t rodzaj, uint8_t a, uint8_t b, uint8_t c)
{
	if (!e || !e->blok || e->blok->version < 2) return;
	auto *blok = e->blok;
	uint32_t const pisz = blok->rozkaz_pisz.load(std::memory_order_relaxed);
	uint32_t const nast = (pisz + 1) % bh_d70::ROZKAZOW;
	if (nast == blok->rozkaz_czytaj.load(std::memory_order_acquire)) return;
	blok->rozkazy[pisz] = (uint32_t(rodzaj) << 24) | (uint32_t(a) << 16) | (uint32_t(b) << 8) | c;
	blok->rozkaz_pisz.store(nast, std::memory_order_release);
}

void bhd70_przycisk(BHD70Engine *e, uint8_t bank, uint8_t bit, int wcisniety)
{
	rozkaz(e, bh_d70::ROZKAZ_PRZYCISK, bank, bit, wcisniety ? 1 : 0);
}

void bhd70_suwak(BHD70Engine *e, uint8_t numer, uint8_t wartosc)
{
	rozkaz(e, bh_d70::ROZKAZ_SUWAK, numer, wartosc > 100 ? 100 : wartosc, 0);
}

void bhd70_pokretlo(BHD70Engine *e, int krokow)
{
	int const w_gore = krokow > 0 ? (krokow > 127 ? 127 : krokow) : 0;
	int const w_dol = krokow < 0 ? (-krokow > 127 ? 127 : -krokow) : 0;
	rozkaz(e, bh_d70::ROZKAZ_POKRETLO, uint8_t(w_gore), uint8_t(w_dol), 0);
}

void bhd70_learn(BHD70Engine *e, uint8_t bit, int wcisniety)
{
	rozkaz(e, bh_d70::ROZKAZ_LEARN, bit, 0, wcisniety ? 1 : 0);
}

void bhd70_polowka(BHD70Engine *e, int wGore, int trzymane)
{
	rozkaz(e, bh_d70::ROZKAZ_POLOWKA, wGore ? 1 : 0, 0, trzymane ? 1 : 0);
}

uint32_t bhd70_kolejka_ramek(const BHD70Engine *e)
{
	return (e && e->blok) ? bh_d70::shm_queued(e->blok) : 0;
}

uint32_t bhd70_brakow(const BHD70Engine *e)
{
	return (e && e->blok) ? e->blok->underruns.load() : 0;
}

void bhd70_render(BHD70Engine *e, float *lewy, float *prawy, uint32_t ramek, double czestotliwosc)
{
	if (!e) return;
	if (!e->blok)
	{
		e->moze_podlacz();
		if (lewy) std::memset(lewy, 0, ramek * sizeof(float));
		if (prawy && prawy != lewy) std::memset(prawy, 0, ramek * sizeof(float));
		return;
	}
	auto *b = e->blok;
	// Emulator zniknął (zamknął się sam albo go zabrakło) -- w pierścieniu zostaje
	// to, co ostatnio zdążył napisać, i bez tego sprawdzenia gospodarz czytałby
	// te resztki w kółko. Słychać to jako szum. Oddajemy ciszę.
	if (!b->emu_alive.load(std::memory_order_acquire))
	{
		if (lewy) std::memset(lewy, 0, ramek * sizeof(float));
		if (prawy && prawy != lewy) std::memset(prawy, 0, ramek * sizeof(float));
		e->szczyt.store(0.f, std::memory_order_relaxed);
		return;
	}
	if (czestotliwosc > 0) e->krok = kCzestotliwoscUkladu / czestotliwosc;

	// Zapas musi pomieścić co najmniej jeden blok gospodarza przeliczony na 32 kHz,
	// inaczej przy każdym wywołaniu brakuje próbek, a emulacja jest duszona.
	uint32_t const trzeba = uint32_t(std::ceil(double(ramek) * e->krok));
	uint32_t nowy_cel = std::max<uint32_t>(kZapasMin, trzeba * 2 + kPorcjaUkladu + 64);
	if (nowy_cel > bh_d70::SHM_MAX_TARGET) nowy_cel = bh_d70::SHM_MAX_TARGET;
	if (nowy_cel != e->cel)
	{
		e->cel = nowy_cel;
		b->target_frames.store(nowy_cel, std::memory_order_relaxed);
	}

	float szczyt_bloku = 0.f;
	for (uint32_t i = 0; i < ramek; i++)
	{
		e->frac += e->krok;
		while (e->frac >= 1.0)
		{
			e->frac -= 1.0;
			e->poprz[0] = e->biez[0];
			e->poprz[1] = e->biez[1];
			if (bh_d70::shm_queued(b) > 0)
			{
				uint32_t r = b->read_pos.load(std::memory_order_relaxed);
				e->biez[0] = b->ring[size_t(r) * 2 + 0] / 32768.0f;
				e->biez[1] = b->ring[size_t(r) * 2 + 1] / 32768.0f;
				b->read_pos.store((r + 1) % b->ring_frames, std::memory_order_release);
			}
			else
			{
				b->underruns.fetch_add(1, std::memory_order_relaxed);
			}
		}
		float const t = float(e->frac);
		float const l = e->poprz[0] + (e->biez[0] - e->poprz[0]) * t;
		float const p = e->poprz[1] + (e->biez[1] - e->poprz[1]) * t;
		if (lewy) lewy[i] = l;
		if (prawy) prawy[i] = (prawy == lewy) ? (l + p) * 0.5f : p;
		float const a = std::fabs(l) > std::fabs(p) ? std::fabs(l) : std::fabs(p);
		if (a > szczyt_bloku) szczyt_bloku = a;
	}
	{
		float poprzedni = e->szczyt.load(std::memory_order_relaxed);
		while (szczyt_bloku > poprzedni
		       && !e->szczyt.compare_exchange_weak(poprzedni, szczyt_bloku, std::memory_order_relaxed)) {}
	}

	// Co dwie sekundy wpis do konsoli – inaczej w piaskownicy nie widać, co się dzieje
	if (szczyt_bloku > e->szczyt_diag) e->szczyt_diag = szczyt_bloku;
	e->licznik_diag += ramek;
	if (e->licznik_diag >= uint32_t(czestotliwosc > 0 ? czestotliwosc * 2 : 96000))
	{
		e->licznik_diag = 0;
		e->dziennik("[%s] kolejka %u, cel %u, brakow %u, emulator %u, gospodarz %u, szczyt %.1f dB",
			e->nazwa_midi.c_str(), bh_d70::shm_queued(b), e->cel,
			b->underruns.load(std::memory_order_relaxed),
			b->emu_alive.load(std::memory_order_relaxed),
			b->host_alive.load(std::memory_order_relaxed),
			e->szczyt_diag > 0 ? 20.0 * std::log10(e->szczyt_diag) : -200.0);
		e->szczyt_diag = 0.f;
	}
}

void bhd70_midi(BHD70Engine *e, uint8_t status, uint8_t d1, uint8_t d2)
{
	if (!e) return;
	if (!e->cel_midi) return;      // portu szuka watek MIDI, nie watek dzwieku
	Byte msg[3] = { status, d1, d2 };
	int const dlugosc = ((status & 0xf0) == 0xc0 || (status & 0xf0) == 0xd0) ? 2 : 3;
	MIDIPacketList pl;
	MIDIPacket *p = MIDIPacketListInit(&pl);
	p = MIDIPacketListAdd(&pl, sizeof(pl), p, 0, dlugosc, msg);
	if (p) MIDISend(e->port, e->cel_midi, &pl);
}

void bhd70_wersja_firmware(BHD70Engine *e, const char *wersja)
{
	if (e && e->dziecko < 0) e->wersja_firmware = wersja ? wersja : "";
}

void bhd70_sysex(BHD70Engine *e, const uint8_t *dane, uint32_t ile)
{
	if (!e || !dane || !ile || e->sysex_idzie.load()) return;
	std::vector<uint8_t> kopia(dane, dane + ile);
	if (e->watek_sysex.joinable()) e->watek_sysex.join();
	e->sysex_stop.store(false);
	e->sysex_wyslane.store(0);
	e->sysex_razem.store(ile);
	e->sysex_idzie.store(true);
	e->watek_sysex = std::thread([e, kopia = std::move(kopia)] {
		// Brzmienia wchodzą do instrumentu tak samo jak ze sprzętu: zwykłym
		// kablem MIDI. Dlatego wysyłamy w tempie MIDI (31250 bodów, czyli
		// 3125 bajtów na sekundę) -- firmware nie przyjmie tego szybciej.
		//
		// WAŻNE: wysyłamy KOMUNIKAT PO KOMUNIKACIE, od F0 do F7. Wcześniej szło
		// to równymi porcjami po 256 bajtów, co tnie komunikaty w pół (dump D-70
		// ma po 138 bajtów na komunikat) -- instrument dostawał połówki i nic
		// z nich nie zapisywał.
		constexpr double kBajtowNaSekunde = 3125.0;
		constexpr size_t kNajwiekszy = 4096;
		auto chwila = std::chrono::steady_clock::now();
		size_t i = 0;
		while (i < kopia.size() && !e->konczymy.load() && !e->sysex_stop.load())
		{
			if (kopia[i] != 0xF0) { i++; continue; }           // śmieci między komunikatami
			size_t k = i + 1;
			while (k < kopia.size() && kopia[k] != 0xF7) k++;
			if (k >= kopia.size()) break;                      // urwany komunikat na końcu
			size_t const dlugosc = k - i + 1;
			if (dlugosc <= kNajwiekszy)
			{
				if (e->cel_midi)
				{
					Byte bufor[sizeof(MIDIPacketList) + kNajwiekszy + 64];
					auto *pl = reinterpret_cast<MIDIPacketList *>(bufor);
					MIDIPacket *p = MIDIPacketListInit(pl);
					p = MIDIPacketListAdd(pl, sizeof(bufor), p, 0, dlugosc, kopia.data() + i);
					if (p) MIDISend(e->port, e->cel_midi, pl);
				}
			}
			i = k + 1;
			e->sysex_wyslane.store(uint32_t(i));
			chwila += std::chrono::microseconds(uint64_t(1000000.0 * dlugosc / kBajtowNaSekunde));
			std::this_thread::sleep_until(chwila);
		}
		e->sysex_wyslane.store(uint32_t(kopia.size()));
		// Instrument zapisuje przyjęte brzmienia do pamięci jeszcze chwilę po
		// ostatnim bajcie -- nie wolno go w tym momencie zamknąć.
		for (int i = 0; i < 30 && !e->konczymy.load() && !e->sysex_stop.load(); i++)
			std::this_thread::sleep_for(std::chrono::milliseconds(100));
		e->sysex_idzie.store(false);
	});
}

int bhd70_sysex_idzie(const BHD70Engine *e) { return (e && e->sysex_idzie.load()) ? 1 : 0; }

void bhd70_sysex_przerwij(BHD70Engine *e)
{
	if (e) e->sysex_stop.store(true);
}

int bhd70_pamiec_trwala(const BHD70Engine *e) { return (e && e->pamiec_trwala) ? 1 : 0; }

uint32_t bhd70_sysex_postep(const BHD70Engine *e)
{
	if (!e) return 0;
	uint32_t const razem = e->sysex_razem.load();
	if (!razem) return 0;
	return uint32_t(100.0 * e->sysex_wyslane.load() / razem);
}
