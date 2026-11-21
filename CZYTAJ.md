# BHD-70 — jak to jest zbudowane

Instrument BHD-70 to **aplikacja na Maca z wtyczką AUv3 w środku**, zbudowana tak samo
jak BHX-1. Dźwięk liczy prawdziwy firmware Rolanda D-70 w emulatorze — nie przybliżenie,
nie model, tylko ten sam program, który chodzi w sprzęcie.

**Oprogramowania Rolanda w pakiecie nie ma i być nie może.** Firmware D-70, kości z falami
i fabryczna pamięć brzmień należą do Rolanda. Użytkownik wskazuje zgranie własnego
egzemplarza przy pierwszym uruchomieniu programu — patrz „Pliki użytkownika" niżej.

## Co z czego się składa

| Folder | Co tam jest |
|---|---|
| `Engine/` | silnik: uruchamia emulator, odbiera dźwięk i obraz, wysyła MIDI i naciśnięcia (C/C++, widziany ze Swifta) |
| `AUv3/` | wtyczka AUv3 (`aumu BD70 BHnc`, „Bronisław Hońca: BHD-70”) i jej okno |
| `Sources/` | panel: `PanelView.swift` (wygląd i obsługa), `PanelUklad.swift` (pozycje), `Silnik.swift` (silnik po stronie Swifta) |
| `App/` | aplikacja na Maca — ten sam panel bez DAW-a |
| `Xcode/project.yml` | opis projektu; plik `.xcodeproj` odtwarza `build.sh`, **nie edytuj go ręcznie** |
| `narzedzia/uklad-z-mame.py` | przepisuje układ panelu z emulatora do `Sources/PanelUklad.swift` |
| `Poprzedni-program/` | pierwsza wersja (uruchamiała emulator osobno) — już nie budowana |

## Budowanie

```bash
bash build.sh          # buduje i instaluje w ~/Applications (z wtyczką)
bash build.sh sync     # tylko odświeża wspólne pliki i emulator w Zasoby/
bash build.sh xcode    # odtwarza projekt i otwiera w Xcode
```

Emulator bierze się z `~/mame-d70` (gałąź `d70`) i **wchodzi do środka wtyczki** — sam
emulator, biblioteka SDL i krój pisma wyświetlacza, **bez niczego, co należy do Rolanda**.
`build.sh` pilnuje tego sam: gdyby w `Zasoby/` znalazł pliki Rolanda, zatrzymuje budowanie.
Po zmianie w emulatorze: `make SOURCES=src/mame/roland/roland_d70.cpp SUBTARGET=d70 -j10`,
potem `bash build.sh` tutaj.

## Pliki użytkownika

`Sources/PlikiInstrumentu.swift` zna komplet, którego instrument potrzebuje, i rozpoznaje
pliki **po sumach kontrolnych SHA-1, nie po nazwach** — użytkownik mógł je nazwać dowolnie.

| Co | Ile plików | Rozmiar każdego | Czyje |
|---|---|---|---|
| firmware (EPROM IC4 + IC9) | 2 (jedna z wersji 1.19, 1.16, 1.14, 1.12, 1.10) | 65 536 B | Rolanda |
| fale PCM (waverom A–F) | 6, wszystkie | 524 288 B | Rolanda |
| brzmienia (Bulk Dump) | 1 plik `.syx` albo `.mid`, nieobowiązkowy | ok. 69 kB | użytkownika |
| krój pisma `t6963c_0101.bin` | 1 | 1024 B | **nie Rolanda** — dorobiony, bo oryginału nikt nie zgrał; leży w pakiecie |

Gdzie co ląduje (wszystko w katalogu grupy aplikacji, `Silnik.folderStanu`):

- `kosci/d70/` — kości wskazane przez użytkownika plus krój pisma; to jest `rompath` emulatora;
- `brzmienia.syx` — wyjęte komunikaty SysEx (z `.mid` wyjmuje je `sysexZMidi`);
- `sysex/` — pliki SysEx z listy przycisku SYSEX (patrz niżej); `brzmienia.syx` kopiuje się
  tu samo przy pierwszym otwarciu okna, pod nazwą „Brzmienia z Twojego D-70";
- `pamiec/` — pamięć brzmień instrumentu (patrz niżej);
- `pamiec-kopia-RRRR-MM-DD-GGMM/` — kopia pamięci sprzed wgrywania SysEx.

Wersję firmware'u rozpoznaje program i podaje emulatorowi przez `-bios` (`bhd70_wersja_firmware`),
bo domyślna to `v119` — gdyby użytkownik miał tylko 1.16, emulator szukałby nie tego pliku.

Brzmienia wysyła `bhd70_sysex` zwykłym portem MIDI, **w tempie prawdziwego MIDI**
(3125 bajtów na sekundę, czyli fabryczny komplet idzie jakieś 23 sekundy), komunikat po
komunikacie od F0 do F7. `bhd70_odbior` przepuszcza też SysEx **przychodzący**, więc zgranie
wysłane na żywo z prawdziwego D-70 dochodzi do instrumentu.

## Wgrywanie brzmień: przycisk SYSEX

**D-70 nie przyjmuje zgrania pamięci w zwykłym trybie gry.** Roland zrobił do tego osobny tryb
serwisowy („Extend Product Mode"): instrument włącza się z przytrzymanym klawiszem **[5]**, a w
jego menu **F.2** to „Bulk Load All Memory from MIDI". Dopiero tam firmware przyjmuje cały zrzut
i zapisuje go do pamięci. Opisuje to `presety/CZYTAJ.md`.

Robi to za użytkownika przycisk **SYSEX** na panelu (`Sources/OknoSysex.swift` — okno,
`Sources/WgrywanieSysex.swift` — przebieg). Kolejność i czasy nie są zgadnięte, tak przeszła próba:

1. kopia dotychczasowej pamięci na dysk;
2. `Silnik.stop()`;
3. `Silnik.start()` i **dociskanie [5] przez 8 s** (KEY2 bit 3, 30 razy na sekundę — emulator łapie
   rozkazy dopiero, gdy wstanie, a klawisz musi być wciśnięty, kiedy firmware go czyta);
4. 24 s na rozruch firmware'u i menu trybu serwisowego;
5. **F2** = KEY4 bit 3 (uwaga: bit 6 to F5, nie F2), potem **ENTER** = KEY0 bit 0;
6. `bhd70_sysex` — po 2,5 s porównanie obrazu ekranu: firmware odlicza na nim adresy, więc
   **niezmieniony ekran = instrument nie przyjmuje**. Wtedy `bhd70_sysex_przerwij`, przywrócenie
   kopii pamięci i komunikat; do pamięci weszło najwyżej kilka kilobajtów;
7. **EXIT** = KEY4 bit 7;
8. `Silnik.stop()` (czyste zamknięcie zapisuje nvram), odczyt liczby niezerowych bajtów,
   `Silnik.start()` — instrument wraca do trybu gry z nowymi brzmieniami.

Okno ma **przełącznik blokady pamięci** (ten, który w sprzęcie jest z tyłu obudowy): dopóki jest
włączony, przycisk „Wgraj" jest nieczynny. Po udanym wgraniu blokada wraca sama. Wgrywanie jest
też odmawiane, gdy ta kopia instrumentu nie trzyma trwałej pamięci (`bhd70_pamiec_trwala`) —
inaczej wgrane brzmienia i tak by przepadły.

Lista plików to po prostu zawartość `<grupa>/BHD70/sysex` — widzi ją i program, i wtyczka.
Okno wyboru pliku otwiera tylko program (`moznaWskazac`); wtyczka korzysta z tej samej listy.

Samą wysyłkę robi `bhd70_sysex` zwykłym portem MIDI, **w tempie prawdziwego MIDI**
(3125 bajtów na sekundę, czyli fabryczny komplet idzie jakieś 23 sekundy), komunikat po
komunikacie od F0 do F7. `bhd70_odbior` przepuszcza też SysEx **przychodzący**.

`Silnik.samoWgrywanieBrzmien` zostaje `false`: samoczynnie przy rozruchu tego zrobić nie można,
bo trzeba instrument zgasić i włączyć na nowo.

Sprawdzone na pustej pamięci: po przejściu całej drogi **22 835 niezerowych bajtów z 32 768**,
a w pamięci stoją nazwy brzmień (`D Piano+ 1`, `Grandioso`, `Rhodes 1`, `BellRhodes`,
`Tack Piano`, `MIDI Piano`, `Stirrings`).

### Pułapka, która to blokowała

Wcześniejszy wniosek, że „firmware nie przyjmuje danych, bo ma wyłączone Exclusive Rx", był
**błędny** i wziął się z błędu pomiaru: zgranie fabryczne wgrywano do pamięci, która już je
zawierała, więc nic się nie zmieniało. Porównywać trzeba z przebiegiem **bez** wysyłki albo na
pustej pamięci.

Druga pułapka była w silniku: `bhd70_stop` niszczył klienta CoreMIDI, a po tym proces przestawał
dostawać powiadomienia o portach — po ponownym włączeniu instrumentu w liście zostawał martwy wpis
po starym emulatorze, a nowego portu nie było widać wcale. Dlatego **klient i wątek MIDI żyją tyle,
co cały silnik** (`zamykamy`, nie `konczymy`), a port emulatora dostaje przy każdym włączeniu inną
nazwę (`nazwa_midi_baza` + numer włączenia). `bhd70_start` wolno teraz wołać wiele razy.

W pracy nad programem, gdy użytkownik nic nie wskazał, `Silnik.zasoby()` sięga do `~/mame-d70/roms`,
żeby testowanie nie wymagało za każdym razem przechodzenia przez okno powitalne.

## Pamięć brzmień

Jedna, wspólna i trwała: `<grupa>/BHD70/pamiec`. Pierwsza uruchomiona instancja bierze ją na
własność (zamek `flock` na `pamiec.zamek`) i to ona zapisuje zmiany; kolejne dostają kopię
roboczą, która znika przy zamknięciu. Zapis działa tylko przy **czystym** zamknięciu emulatora:
`bhd70_stop` zeruje `host_alive`, czeka do 5 s, aż emulator wyjdzie sam, i dopiero w ostateczności
wysyła SIGTERM. Blok wymiany odmapowujemy **po** wyjściu emulatora — za wczesne odmapowanie
kończyło się jego awarią (naprawione też po stronie `~/mame-d70`, commit `beef1383`).

## Jak panel rozmawia z emulatorem

Jeden plik odwzorowany w pamięci w katalogu grupy aplikacji
(`~/Library/Group Containers/QU6ZS8MFVX.pl.bronek.bhd70/BHD70/`):

- **dźwięk** — pierścień 4096 ramek po 32 kHz; gdy jest pełny, emulator czeka, więc
  tempo emulacji wyznacza DAW;
- **ekran** — 240 × 64 piksele po bicie na piksel, oddawane ponad 30 razy na sekundę;
- **diody** — 32 bity (LP00–LP37);
- **rozkazy** — naciśnięcia przycisków, suwaki Tone Palette, pokrętło VALUE.

MIDI idzie osobno, wirtualnym portem CoreMIDI o nazwie `BHD-70 <pid>-<numer>`.
Każda wstawiona wtyczka ma własny emulator, więc instancji może być ile się chce.

## Co działa, a co jeszcze nie

Działa: dźwięk w Logicu, Abletonie i AU Hoście, `auval` przechodzi, panel 1:1,
wyświetlacz z prawdziwymi pikselami, przyciski, suwaki, pokrętło, lista miejsc
pod trójkącikiem.

Zostaje:

1. **Diody nie nadążają za zmianami.** Firmware wysyła ich stan do panelu raz, przy
   rozruchu (paczka 8 bajtów w fazie zapisu, bajty 4–7 to banki LP0–LP3, stan aktywny
   niski). Po włączeniu świecą poprawnie: PLAY, LEVEL i cztery strefy Tone. Przy
   zmianie trybu nic nowego nie przychodzi — prawdziwy panel prawdopodobnie odpowiada
   na linii ACK, a nasz tego nie robi, więc firmware przestaje wysyłać.
   Podgląd strumienia: `BH_DIODY=1` przy uruchomieniu emulatora.
2. **Lista brzmień pokazuje miejsca (11–88), nie nazwy.** Nazwy trzeba wyjąć z pamięci
   brzmień (plik `nvram`) albo odczytać z wyświetlacza po przełączeniu.
3. **Rozruch trwa około 18 sekund** — tyle potrzebuje firmware. Do skrócenia: zapisany
   stan emulacji (MAME save state) ładowany zamiast rozruchu.
4. **Zgranie offline (bounce) daje ciszę** — emulator chodzi w tempie czasu
   rzeczywistego, a zgranie leci szybciej.

## Licencja — ważne

Emulator D-70 używa układów z projektu gearmulator na licencji **GPL-3.0**. To znaczy,
że BHD-70 **nie może być sprzedawany jako program zamknięty** — jest darmowy i rozdawany
razem z kodem źródłowym.

Druga, osobna sprawa: **firmware i brzmienia D-70 są własnością Rolanda.** Nie wolno ich
dołączać ani do pakietu, ani do repozytorium, ani do DMG. Instrument opisujemy jako
„dopracowaną rekreację instrumentu Roland D-70 Super LA Synthesizer w oparciu o oryginalne
oprogramowanie z własnego egzemplarza", z jasną informacją, że plików firmware'u się nie
dołącza i trzeba je mieć z własnego instrumentu.
