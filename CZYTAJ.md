# Stosik

Karteczki na ekranie Maca ułożone w stos (wersja 1.0, 27.11.2026). Po angielsku: Stackie.

- `./zbuduj.sh` buduje i instaluje do ~/Applications/Stosik.app, potem ją otwiera.
- `./testuj.sh` robi zrzuty (stos, rozłożony stos, edytor) do test/ na osobnym folderze danych.
- Dane: ~/Library/Application Support/Stosik/karteczki.json (w testach STOSIK_DIR).

## Co umie
- Stos karteczek na pulpicie; najechanie myszką rozkłada stos, karteczka pod myszką wyskakuje.
- Kliknięcie otwiera karteczkę: tytuł, 10 kolorów, tagi (Enter albo przecinek, podpowiedzi z innych karteczek), pilność (ikonka z trzech warstw: niska zielona, średnia pomarańczowa, pilne czerwona), termin z godziną albo bez, zadania z kółeczkami, notatka.
- Data w prawym górnym rogu (termin, a bez terminu dzień założenia, przygaszony), pod nią „jutro”, „dziś”, „za 3 dni”, „po terminie”.
- Przypomnienia macOS: dzień wcześniej o 9:00 i w dniu terminu (z godziną: rano, godzinę przed i o czasie).
- Przeciągnij karteczkę w bok, żeby zmienić kolejność. W otwartej karteczce zadania przesuwasz za uchwyt ≡ po lewej (w górę = ważniejsze). Uchwyt ≡ pod stosem przesuwa cały stos.
- Ikona w pasku menu: nowa karteczka, terminy, położenie stosu (na pulpicie, zwykłe okno, zawsze na wierzchu), archiwum, otwieranie przy logowaniu.
- Tagi i szukanie: lupa pod stosem (tekst i tagi), kliknięcie tagu na karteczce albo menu „Pokaż tag”; żółta pigułka z × wyłącza filtr.
- Kalendarz: szara karteczka na końcu stosu (wielkości zwykłej) (bieżący miesiąc, kropki terminów, ✓ zamknięte, → przed nami). Kliknięcie otwiera duży kalendarz: siatka miesiąca z terminami i zamkniętymi projektami, strzałki między miesiącami, kliknięcie dnia pokazuje, co tego dnia; z prawej podsumowanie (zamknięte projekty, odhaczone zadania, przed nami). Kliknięcie projektu otwiera karteczkę; zamkniętą można przywrócić do stosu. Też w menu: „Kalendarz i podsumowanie” (⌘K).
- Zapisuje się, kiedy zadanie odhaczono i kiedy projekt zamknięto (do podsumowań). Zadania odhaczone przed tą wersją nie mają daty i nie liczą się w podsumowaniu.
- Złożony stos pokazuje 4 karteczki i kalendarz (StackLayout.shown); resztę widać po najechaniu.
- Kalendarz: każdy dzień to kółko z pierścieniem podzielonym po równo na projekty albo tagi z tego dnia (przełącznik „Projekty / Tagi”); dzień liczy projekt, gdy coś w nim odhaczono, miał termin albo został zamknięty. Ciemne kółko = zamknięty projekt, fioletowe = dziś, kropka = termin. Tagi dostają kolory same (tagi.json). Z prawej wykres: zrobione kontra zostało w zadaniach projektów miesiąca.
- Języki: polski i angielski (Sources/Lang.swift: L("tekst po polsku") i słownik EN). Domyślnie język systemu; Menu → „Język · Language” przełącza od razu, bez zamykania. Nowy napis = L("...") w kodzie i para w EN.
- Kalendarz ma widok „Rok”: 12 miesięcy z kółkami dni, kliknięcie miesiąca go otwiera; podsumowanie i wykres liczą wtedy cały rok.
- testuj.sh robi zrzuty po polsku (test/) i po angielsku (test/en/).
- Pasek pod stosem: widać + i liczbę karteczek; po chwili trzymania kursora wysuwa się lupa i koło zębate (szybkie ustawienia: położenie, język, logowanie, kalendarz, zakończ). Złapanie paska i przeciągnięcie przenosi cały stos (ToolbarMouse w Stack.swift).
- Klient, projekt, tagi: trzy osobne pola w karteczce (z podpowiedziami). Klient i projekt widać nad tytułem karteczki (kliknięcie filtruje stos), pod lupą są sekcje Klienci, Projekty, Tagi, a kalendarz ma tryby Klienci / Projekty / Tagi. Kolory nadają się same (tagi.json, klucze „c:” i „p:”); kliknięcie kropki przy kliencie albo projekcie zmienia kolor.
- Pasek pod stosem jest szklany (macOS 26+, starsze: materiał). Otwarta karteczka i kalendarz zawsze w jasnym motywie (podpowiedzi szare).
- Przypomnienia (dzwoneczek obok pilności): lista jak w Kalendarzu, gotowe odstępy (w chwili terminu, 5/15/30 min, 1/2 godz., 1/2 dni, tydzień przed) albo dokładny dzień i godzina. Termin bez godziny liczy się od 9:00. Tylko karteczki z przypomnieniem dostają powiadomienia i podskakują w stosie (dziś, jutro, po terminie; co 6 s, zaległe wyżej). Pole Note.alerts = minuty przed terminem.
- Usuwanie: w rozłożonym stosie złap karteczkę i pociągnij w dół; pojawia się kosz, czerwony = puść, żeby usunąć. „Usuń” w karteczce też wrzuca do kosza. Kosz (kosz.json) trzyma karteczki 30 dni: przywróć albo usuń na zawsze; otwiera się z koła zębatego i z menu w górnym pasku. Pod stosem jest przezroczyste miejsce na kosz (StackLayout.trashRoom).
- Dyktowanie (Dictation.swift, rozpoznawanie mowy macOS, pl-PL albo en-US): mikrofon na pasku pod stosem = nowa karteczka (pierwsze zdanie tytułem, kolejne zadaniami, potem otwiera się karteczka do uzupełnienia klienta i tagów); „Dyktuj” w karteczce = każde zdanie to nowe zadanie. Podział nie potrzebuje kropek: nowe zadanie zaczyna się od bezokolicznika (poprawić, wysłać…; Dictation.swift parseDictation), to co przed pierwszym czasownikiem = projekt i tytuł. Słowa-klucze „klient …”, „projekt …”, „tag …” wypełniają pola. Kropki i „potem” też dzielą. Za pierwszym razem macOS pyta o mikrofon i rozpoznawanie mowy (opisy w Info.plist w zbuduj.sh).

## Okienko powitalne i aktualizacje
- Welcome.swift: strony z zapętlonymi animacjami (stos, zadania, przypomnienia, klienci i tagi, kalendarz, kosz, dyktowanie), strona „Zgody” (powiadomienia, mikrofon, rozpoznawanie mowy: stan, „Zezwól”, skrót do Ustawień) i „Co nowego”.
- Pokazuje się samo przy pierwszym uruchomieniu i po każdej nowej wersji (UserDefaults „welcomeSeen” ≠ APP_VERSION); ręcznie: koło zębate → „Witaj i co nowego” albo menu w górnym pasku.

### Jak wydać nową wersję
1. Podnieś `APP_VERSION` w Sources/Welcome.swift i `CFBundleShortVersionString` / `CFBundleVersion` w zbuduj.sh.
2. Dopisz na górze `RELEASES` (Welcome.swift) wpis z wersją, datą i 2–4 punktami (każdy w `L("…")`).
3. Dopisz angielskie tłumaczenia nowych napisów w Sources/Lang.swift (szybki test: skrypt z sesji szuka brakujących kluczy).
4. `./testuj.sh` (zrzuty po polsku i angielsku, m.in. test/14_witaj_*.png), obejrzyj, potem `./zbuduj.sh`.
5. Przy starcie nowej wersji okienko powitalne pokaże się samo z „Co nowego”.
- Po rozłożeniu karty układają się w rzędy (StackLayout.perRow z szerokości ekranu: laptop ok. 6, duży monitor więcej); pasek zjeżdża pod ostatni rząd. Do testu STOSIK_SCREENW=1512.
- Drzemka: dzwoneczek na karteczce w stosie = menu (odłóż 10/30 min, 1 godz., do jutra rano, wycisz do zmiany terminu, włącz). Dotyczy tylko podskakiwania; powiadomienia bez zmian. Podskok co 20 s.
- Wydajność: mysz jest czytana zegarem 60 razy na sekundę, więc w UIState.mouse wartości @Published przypisuj tylko przy zmianie (inaczej cały stos przerysowuje się 60×/s; tak było do 27.11: 44% CPU w spoczynku, po poprawce ok. 1%). Gdy kursor jest daleko, pollMouse kończy od razu.
- Bezpieczeństwo danych: jeśli karteczki.json nie da się odczytać, przed startem powstaje kopia karteczki-kopia-<data>.json w tym samym folderze.
