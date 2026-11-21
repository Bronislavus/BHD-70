#!/bin/bash
# BHD-70 – budowanie: aplikacja na Maca + wtyczka AUv3 (projekt Xcode z Xcode/project.yml)
#   bash build.sh            → MOJA wersja: pliki D-70 w środku, wszystko gra od razu
#   bash build.sh publikacja → wersja NA STRONĘ: bez plików Rolanda, pyta użytkownika
#   bash build.sh sync       → tylko odświeża wspólne pliki i emulator w Zasoby/
#   bash build.sh xcode      → odtwarza projekt i otwiera go w Xcode
#
# DWIE WERSJE – na czym polega różnica
#
# Wtyczka AUv3 siedzi w piaskownicy i nie może zajrzeć do ~/mame-d70 ani nigdzie
# indziej poza swoim pakietem i katalogiem grupy aplikacji. Dlatego to, co ma mieć,
# musi leżeć w jej środku.
#
#   „moja"       – do pakietu wchodzą ROM-y i fabryczna pamięć brzmień z ~/mame-d70.
#                  Instrument gra od razu, bez pytania o cokolwiek. TYLKO U MNIE:
#                  tego pakietu nie wolno nikomu dać, bo nosi oprogramowanie Rolanda.
#   „publikacja" – do pakietu wchodzi emulator, SDL i krój pisma wyświetlacza.
#                  Nic Rolanda. Użytkownik wskazuje zgranie własnego D-70 przy
#                  pierwszym uruchomieniu programu. Ten pakiet idzie na stronę.
set -e
cd "$(dirname "$0")"
SHARED="../../shared"
MAME="${MAME_D70:-$HOME/mame-d70}"
NAME="BHD-70"
PROJECT="Xcode/BHD70.xcodeproj"
APPEX="BHD70AU.appex"
LOG="build.log"

# ---------- Wspólne pliki serii BH → Sources/_shared (kopie, nadpisywane)
# U mnie wspólne pliki serii BH odświeżają się z ~/Developer/shared. W kodzie
# wydanym publicznie tego folderu nie ma – tam Sources/_shared jest już na miejscu
# i zostaje nietknięte, bo inaczej nikt obcy by tego nie zbudował.
if [ -d "$SHARED/BHStyle" ]; then
    echo "🔗 Wspólne pliki: BHStyle"
    rm -rf Sources/_shared
    mkdir -p Sources/_shared/BHStyle
    cp "$SHARED/BHStyle/"*.swift Sources/_shared/BHStyle/
    # Zdjęcie z nagłówka strony – tło górnej części okna (wspólne dla serii)
    mkdir -p Zasoby && cp "$SHARED/design/hero.jpg" Zasoby/hero.jpg
    cat > Sources/_shared/_NIE_EDYTUJ.swift <<NOTE
// Pliki w tym folderze są kopiami z ~/Developer/shared i są nadpisywane przy każdym budowaniu.
// Zmiany wprowadzaj w ~/Developer/shared.
NOTE
else
    [ -d Sources/_shared/BHStyle ] || { echo "❌ Brak Sources/_shared/BHStyle – niepełny kod źródłowy."; exit 1; }
    [ -f Zasoby/hero.jpg ] || { echo "❌ Brak Zasoby/hero.jpg – niepełny kod źródłowy."; exit 1; }
    echo "🔗 Wspólne pliki: te, które są w Sources/_shared (brak ~/Developer/shared)"
fi

# ---------- Którą wersję budujemy
WERSJA="moja"
case "$1" in publikacja|dmg) WERSJA="publikacja" ;; esac

# ---------- Emulator → Zasoby/ (kopie, nadpisywane przy każdym budowaniu)
#
# UWAGA – tu przebiega granica tego, co wolno rozpowszechniać.
# Emulator (MAME, GPL-3) i krój pisma wyświetlacza (dorobiony, bo oryginału nikt
# nie zgrał) wchodzą zawsze. Firmware D-70, kości z falami i fabryczna pamięć
# brzmień są własnością Rolanda – wchodzą TYLKO do mojej wersji.
# Emulator bierze się z repozytorium MAME z poprawkami do D-70. U mnie leży
# w ~/mame-d70; można wskazać inne miejsce zmienną MAME_D70. Kto buduje z kodu
# wydanego publicznie, składa emulator według mame/README.md i wkłada gotowy
# program razem z bibliotekami do Zasoby/ – wtedy ten krok się pomija.
if [ -x "$MAME/d70" ]; then
    echo "🔗 Emulator z $MAME"
    bash "$MAME/bh-uniezaleznij.sh" >/dev/null
    rm -rf Zasoby/roms Zasoby/d70 Zasoby/lib Zasoby/nvram
    mkdir -p Zasoby
    cp "$MAME/d70" Zasoby/d70
    cp -R "$MAME/lib" Zasoby/lib
    # Krój pisma wyświetlacza – jedyna kość, którą wolno nam nosić
    [ -f "$MAME/roms/d70/t6963c_0101.bin" ] && cp "$MAME/roms/d70/t6963c_0101.bin" Zasoby/t6963c_0101.bin
elif [ -x Zasoby/d70 ] && [ -d Zasoby/lib ] && [ -f Zasoby/t6963c_0101.bin ]; then
    echo "🔗 Emulator: ten, który już leży w Zasoby/ (brak $MAME)"
else
    echo "❌ Nie znajduję emulatora."
    echo "   Albo zbuduj go w $MAME (u mnie: galąź d70),"
    echo "   albo złóż go według mame/README.md i włóż program d70 oraz folder lib do Zasoby/."
    echo "   Inne miejsce repozytorium MAME wskazuje zmienna MAME_D70."
    exit 1
fi

if [ "$WERSJA" = "moja" ]; then
    echo "📦 Wersja MOJA – pliki D-70 wchodzą do pakietu (nie do rozdawania!)"
    cp -R "$MAME/roms" Zasoby/roms
    # Fabryczna pamięć brzmień – bez niej D-70 wstaje pusty
    [ -d "$MAME/nvram" ] && cp -R "$MAME/nvram" Zasoby/nvram
else
    echo "🌍 Wersja NA STRONĘ – bez plików Rolanda"
    # Gdyby cokolwiek Rolanda zostało w Zasoby/, lepiej zatrzymać budowanie
    if ls Zasoby/roms Zasoby/nvram Zasoby/roland_d70_* >/dev/null 2>&1; then
        echo "❌ W Zasoby/ leżą pliki Rolanda – nie wolno ich wkładać do pakietu."; exit 1
    fi
fi

cat > Zasoby/_NIE_EDYTUJ.txt <<NOTE
Kopie z ~/mame-d70, nadpisywane przy każdym budowaniu. Zmiany wprowadzaj w ~/mame-d70.

Pliki Rolanda (roms/, nvram/) są tu TYLKO po "bash build.sh" – to moja wersja,
do grania u siebie. Pakietu z nimi nie wolno nikomu dawać.
Wersję na stronę buduje "bash build.sh publikacja" – ta ich nie ma.
NOTE
[ "$1" = "sync" ] && { echo "✅ Odświeżono Zasoby/"; exit 0; }

# ---------- Ikona: icon.png (1024 x 1024) -> katalog zasobow Xcode
if [ -f icon.png ]; then
    SET="Xcode/Resources/Assets.xcassets/AppIcon.appiconset"
    rm -rf "$SET"; mkdir -p "$SET"
    printf '{ "info" : { "author" : "xcode", "version" : 1 } }\n' > "Xcode/Resources/Assets.xcassets/Contents.json"
    WPISY=""
    for s in 16 32 128 256 512; do
        d=$((s * 2))
        sips -z $s $s icon.png --out "$SET/icon_${s}.png" >/dev/null
        sips -z $d $d icon.png --out "$SET/icon_${s}@2x.png" >/dev/null
        WPISY="$WPISY
    { \"filename\" : \"icon_${s}.png\", \"idiom\" : \"mac\", \"scale\" : \"1x\", \"size\" : \"${s}x${s}\" },
    { \"filename\" : \"icon_${s}@2x.png\", \"idiom\" : \"mac\", \"scale\" : \"2x\", \"size\" : \"${s}x${s}\" },"
    done
    printf '{\n  "images" : [%s\n  ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n' "${WPISY%,}" > "$SET/Contents.json"
fi

# ---------- Projekt Xcode (odtwarzany z project.yml)
command -v xcodegen >/dev/null || { echo "❌ Brak XcodeGen. Zainstaluj raz:  brew install xcodegen"; exit 1; }
[ -f "$SHARED/config.sh" ] && source "$SHARED/config.sh"
# Wersja na stronę nie ma Zasoby/roms ani Zasoby/nvram, a Xcode nie znosi wpisów
# wskazujących na nieistniejące pliki – budujemy ją z opisu bez tych dwóch wpisów.
SPEC="project.yml"
if [ "$WERSJA" = "publikacja" ]; then
    SPEC="project.publikacja.yml"
    python3 -I - <<'PY'
linie = open("Xcode/project.yml").read().split("\n")
wynik, pomijaj = [], False
for l in linie:
    if l.strip().startswith("SWIFT_ACTIVE_COMPILATION_CONDITIONS:"):
        continue            # furtka do ~/mame-d70 nie wchodzi do wersji na strone
    if l.strip() in ("- path: ../Zasoby/roms", "- path: ../Zasoby/nvram"):
        pomijaj = True
        continue
    if pomijaj:
        if l.strip().startswith(("type:", "buildPhase:", "optional:")):
            continue
        pomijaj = False
    wynik.append(l)
open("Xcode/project.publikacja.yml", "w").write("\n".join(wynik))
PY
fi
( cd Xcode && TEAM_ID="$TEAM_ID" xcodegen generate --quiet --spec "$SPEC" )
[ "$WERSJA" = "publikacja" ] && rm -f Xcode/project.publikacja.yml
if [ "$1" = "xcode" ]; then open "$PROJECT"; exit 0; fi

fail() {
    grep -E "error:|error -|Error Domain" "$LOG" | sort -u | head -40
    echo "❌ $1 – pełny zapis w $LOG"; exit 1
}

echo "🔨 Kompilacja (aplikacja + wtyczka AUv3)…"
xcodebuild -project "$PROJECT" -scheme BHD70 -configuration Release \
    -destination 'platform=macOS' -derivedDataPath build/DerivedData \
    -allowProvisioningUpdates build > "$LOG" 2>&1 || fail "Błędy kompilacji"

APP="build/DerivedData/Build/Products/Release/${NAME}.app"
AX="$APP/Contents/PlugIns/$APPEX"
[ -x "$AX/Contents/MacOS/d70" ] || fail "Emulator nie trafił do wtyczki"

# ---------- Wersja na stronę: do dist/, bez ruszania tego, czym gram
if [ "$WERSJA" = "publikacja" ]; then
    mkdir -p dist
    rm -rf "dist/${NAME}.app"
    cp -R "$APP" "dist/${NAME}.app"
    # Jeszcze raz, na wszelki wypadek: w gotowym pakiecie nie ma nic Rolanda
    ZNALEZIONE=$(find "dist/${NAME}.app" -type f \
        \( -name "roland_d70_*" -o -name "*waverom*" -o -name "nvram" -o -name "card" \) | head -5)
    if [ -n "$ZNALEZIONE" ]; then
        echo "❌ W gotowym pakiecie są pliki Rolanda:"; echo "$ZNALEZIONE"
        rm -rf "dist/${NAME}.app"; exit 1
    fi
    # Wersja na stronę to PLIK DO ROZDANIA, a nie wtyczka do grania. Pakiet w dist/
    # musi być wyrejestrowany: inaczej system podstawia jego wtyczkę zamiast tej
    # z ~/Applications, a ta nie ma plików Rolanda i instrument milczy. W Logicu
    # kończy się to szumem, bo host trzyma otwarty pakiet, który zmienia mu się
    # pod ręką. Uwaga: zarejestrować ją potrafi także samo URUCHOMIENIE
    # dist/BHD-70.app, więc po takim uruchomieniu puść to jeszcze raz.
    LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    /usr/bin/pluginkit -r "$PWD/dist/${NAME}.app/Contents/PlugIns/${APPEX}" 2>/dev/null || true
    "$LSREG" -u "$PWD/dist/${NAME}.app" 2>/dev/null || true
    # i oddajemy pierwszeństwo wersji zainstalowanej, jeśli jest
    if [ -d "$HOME/Applications/${NAME}.app/Contents/PlugIns/${APPEX}" ]; then
        /usr/bin/pluginkit -a "$HOME/Applications/${NAME}.app/Contents/PlugIns/${APPEX}" 2>/dev/null || true
    fi
    KTORA=$(/usr/bin/pluginkit -m -v -i pl.bronek.bhd70.au 2>/dev/null | head -1)
    echo "✅ Wersja na stronę: dist/${NAME}.app (bez plików Rolanda)"
    echo "   Tego, co masz w ~/Applications, nie ruszałem."
    case "$KTORA" in
        *"/dist/"*) echo "⚠️  Uwaga: system nadal wskazuje wtyczkę z dist/ – zamknij DAW i puść to jeszcze raz." ;;
        *Applications*) echo "   Wtyczka w DAW-ie: ta z ~/Applications (dobrze)." ;;
    esac
    exit 0
fi

# ---------- Instalacja i rejestracja wtyczki (moja wersja)
mkdir -p "$HOME/Applications"
if pgrep -f "Applications/${NAME}.app/Contents/MacOS/" >/dev/null; then
    osascript -e 'quit app id "pl.bronek.bhd70"' 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "Applications/${NAME}.app/Contents/MacOS/" >/dev/null || break; sleep 0.5; done
fi
rm -rf "$HOME/Applications/${NAME}.app"
cp -R "$APP" "$HOME/Applications/"
# KOLEJNOŚĆ JEST WAŻNA: najpierw sprzątamy kopie, których DAW ma nie widzieć
# (folder budowania i wersja na stronę), a dopiero potem rejestrujemy tę właściwą.
# Odwrotnie „pluginkit -r" kasuje świeżo założony wpis i w systemie nie zostaje
# żadna wtyczka – auval mówi wtedy „didn't find the component" i tak już zostaje.
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
/usr/bin/pluginkit -r "$PWD/$AX" 2>/dev/null || true
"$LSREG" -u "$PWD/$APP" 2>/dev/null || true
/usr/bin/pluginkit -r "$PWD/dist/${NAME}.app/Contents/PlugIns/${APPEX}" 2>/dev/null || true
"$LSREG" -u "$PWD/dist/${NAME}.app" 2>/dev/null || true
# Pakiet w ~/Applications właśnie podmieniliśmy (rm + cp), więc LaunchServices zna
# starą ścieżkę. Bez wymuszonego przerejestrowania pluginkit zakłada wpis, który
# zaraz przepada -- i w systemie nie zostaje żadna wtyczka.
"$LSREG" -f "$HOME/Applications/${NAME}.app" 2>/dev/null || true
/usr/bin/pluginkit -a "$HOME/Applications/${NAME}.app/Contents/PlugIns/${APPEX}" 2>/dev/null || true
# Po podmianie pakietu system jeszcze przez kilka sekund pamięta starą wtyczkę
# i auval mówi „didn't find the component". Budzimy go i czekamy, aż zobaczy nową –
# inaczej sprawdzenie zaraz po budowaniu wygląda na porażkę, a nią nie jest.
killall -9 AudioComponentRegistrar 2>/dev/null || true
printf "⏳ Czekam, aż system zobaczy wtyczkę"
for _ in 1 2 3 4 5 6; do
    if auval -v aumu BD70 BHnc 2>/dev/null | grep -q SUCCEEDED; then WIDZI=1; break; fi
    printf "."; sleep 3
done
if [ -n "$WIDZI" ]; then
    echo " jest, auval przechodzi."
else
    echo " jeszcze nie."
    echo "   Daj jej chwilę i sprawdź sam:  auval -v aumu BD70 BHnc"
fi
echo "✅ Zainstalowano: ~/Applications/${NAME}.app (z wtyczką AUv3)"
echo "   Sprawdzenie wtyczki:  auval -v aumu BD70 BHnc"
