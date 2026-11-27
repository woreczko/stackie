import Foundation

/// Język: z systemu albo wybrany w menu; przełączany bez zamykania apki.
enum Lang {
    static var current = "pl"
    /// "auto", "pl" albo "en"
    static var setting: String {
        get { ProcessInfo.processInfo.environment["STOSIK_LANG"] ?? UserDefaults.standard.string(forKey: "lang") ?? "auto" }
        set { UserDefaults.standard.set(newValue, forKey: "lang"); resolve() }
    }
    static func resolve() {
        let s = setting
        if s == "pl" || s == "en" { current = s; return }
        current = (Locale.preferredLanguages.first ?? "en").hasPrefix("pl") ? "pl" : "en"
    }
    static var locale: Locale { Locale(identifier: current == "pl" ? "pl_PL" : "en_GB") }
}

func L(_ pl: String) -> String { Lang.current == "pl" ? pl : (EN[pl] ?? pl) }
func LF(_ pl: String, _ args: CVarArg...) -> String { String(format: L(pl), arguments: args) }

func monthName(_ m: Int) -> String {
    (Lang.current == "pl"
     ? ["Styczeń", "Luty", "Marzec", "Kwiecień", "Maj", "Czerwiec", "Lipiec", "Sierpień", "Wrzesień", "Październik", "Listopad", "Grudzień"]
     : ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"])[max(0, min(11, m - 1))]
}
func monthShort(_ m: Int) -> String {
    (Lang.current == "pl"
     ? ["STY", "LUT", "MAR", "KWI", "MAJ", "CZE", "LIP", "SIE", "WRZ", "PAŹ", "LIS", "GRU"]
     : ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"])[max(0, min(11, m - 1))]
}
var weekdays: [String] { Lang.current == "pl" ? ["Pn", "Wt", "Śr", "Cz", "Pt", "Sb", "Nd"] : ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"] }

let EN: [String: String] = [
    // karteczka i stos
    "Bez tytułu": "Untitled",
    "+ jeszcze %d": "+ %d more",
    "Pokaż karteczki z tagiem %@": "Show notes tagged %@",
    "Nowa karteczka": "New note",
    "Nic tu nie pasuje": "Nothing matches",
    "Pokaż wszystkie": "Show all",
    
    "Szukaj w karteczkach": "Search notes",
    "TAGI": "TAGS",
    "Kalendarz i podsumowanie miesiąca": "Calendar and monthly summary",
    // terminy
    "dziś": "today", "jutro": "tomorrow", "po terminie": "overdue", "zrobione": "done",
    "za %@": "in %@", "1 dzień": "1 day", "%d dni": "%d days",
    // edytor
    "brak": "none", "niska": "low", "średnia": "medium", "pilne": "urgent",
    "Tytuł": "Title", "Termin": "Due date", "godzina": "time",
    "Dziś": "Today", "Jutro": "Tomorrow", "+7 dni": "+7 days",
    "Zadania": "Tasks", "Zadanie": "Task", "Dodaj zadanie": "Add task", "Notatka": "Note",
    "Przeciągnij, żeby zmienić kolejność": "Drag to reorder",
    "Usuń": "Delete", "Usuń tag": "Remove tag", "Anuluj": "Cancel",
    "Usunąć tę karteczkę na zawsze?": "Delete this note for good?",
    "Zrobione, do archiwum": "Done, archive it", "Przywróć do stosu": "Back to the stack",
    "tag": "tag",
    // kolory
    "Krem": "Cream", "Róż": "Pink", "Pomarańcz": "Orange", "Żółty": "Yellow", "Limonka": "Lime",
    "Mięta": "Mint", "Błękit": "Sky", "Lawenda": "Lavender", "Czerwień": "Red", "Grafit": "Graphite",
    // kalendarz
    "Projekty": "Projects", "Tagi": "Tags", "PODSUMOWANIE": "SUMMARY",
    "zamknięte\nprojekty": "closed\nprojects", "odhaczone\nzadania": "tasks\nticked", "przed\nnami": "coming\nup",
    "Kolory projektów": "Project colours", "Kolory tagów": "Tag colours",
    "Zamknięte": "Closed", "Przed nami": "Coming up", "Terminy w tym miesiącu": "Due this month",
    "Nic tego dnia.": "Nothing that day.", "Jeszcze nic nie zamknięte.": "Nothing closed yet.",
    "To dopiero przed nami.": "Still ahead of us.", "Brak terminów. Spokojnie.": "No deadlines. Relax.",
    "Zamknięte w tym miesiącu": "Closed this month", "Przed nami w tym miesiącu": "Coming up this month",
    "zostało": "left", "zadania z projektów\ntego miesiąca": "tasks in this\nmonth's projects",
    "zamknięte %@": "closed %@", "termin %@": "due %@", "%d/%d zadań": "%d/%d tasks",
    // przypomnienia
    "Karteczka bez tytułu": "Untitled note",
    "Kliknij, żeby otworzyć karteczkę.": "Click to open the note.",
    "Zostało zadań: %d z %d.": "Tasks left: %d of %d.",
    "Dziś termin: %@": "Due today: %@",
    // menu
    "Schowaj stos": "Hide stack", "Pokaż stos": "Show stack", "Kalendarz i podsumowanie": "Calendar and summary",
    "Zbliża się termin": "Coming up", "Położenie stosu": "Stack position",
    "Na pulpicie (pod oknami)": "On the desktop (below windows)", "Zwykłe okno": "Normal window",
    "Zawsze na wierzchu": "Always on top", "Archiwum (%d)": "Archive (%d)", "Pusto": "Empty",
    "Przywróć: %@": "Restore: %@", "Otwieraj przy logowaniu": "Open at login", "Zakończ Stosik": "Quit Stackie",
    "Pokaż tag": "Show tag", "Wszystkie karteczki": "All notes", "Nie udało się ustawić": "Couldn't change that",
    "Język": "Language", "Automatycznie (system)": "Automatic (system)",
    // przykładowe karteczki
    "Witaj w Stosiku": "Welcome to Stackie", "Najedź myszką na stos": "Hover over the stack",
    "Kliknij karteczkę, żeby ją edytować": "Click a note to edit it", "Przeciągnij kartkę w bok": "Drag a note sideways",
    "Kliknij kółeczko, gdy zrobione": "Click the circle when done", "Zakupy": "Shopping",
    "Chleb": "Bread", "Kawa": "Coffee", "Baterie AA": "AA batteries",
    "Szkice": "Sketches", "Eksport": "Export", "dom": "home", "Faktury": "Invoices", "Prezent dla mamy": "Gift for mum", "Klient: kawiarnia": "Client: café",
    "Pierwszy krok": "First step", "bez tagu": "no tag", "bez klienta": "no client", "Zmień kolor": "Change colour", "Odłożone do %@": "Snoozed until %@", "Odłóż na 10 min": "Snooze 10 min", "Odłóż na 30 min": "Snooze 30 min",
    "Odłóż na 1 godz.": "Snooze 1 hour", "Do jutra rano": "Until tomorrow morning", "Włącz podskakiwanie": "Turn hopping back on",
    "Wycisz (do zmiany terminu)": "Mute (until the due date changes)", "Ustaw przypomnienia…": "Set reminders…", "Drzemka i wyciszenie": "Snooze and mute", "Dokładnie…": "Exactly at…", "+ Przypomnienie": "+ Reminder", "Słucham…": "Listening…", "Włączam mikrofon…": "Starting the mic…", "Dyktowanie": "Dictation",
    "Pisz tutaj. Możesz też upuścić plik: PDF, zdjęcie albo inny.": "Write here. You can also drop a file: a PDF, a photo or anything else.",
    "Rower": "Bike ride", "Kino": "Cinema", "Ulotka": "Flyer", "Logo": "Logo", "Menu": "Menu", "Kawiarnia": "Café", "Kawiarnia Róża": "Rose Café", "Drugi krok": "Second step",
    "Karteczki": "Notes",
    "Ustawienia": "Settings",
    "Pliki przy karteczce": "Files on a note",
    "Przeciągnij PDF, zdjęcie albo inny plik na otwartą karteczkę. Stosik trzyma kopię, więc nic nie zginie.": "Drag a PDF, a photo or any file onto an open note. Stackie keeps a copy, so nothing gets lost.",
    "Pliki przy karteczce: przeciągnij PDF, zdjęcie albo inny plik, Stosik trzyma kopię": "Files on notes: drag a PDF, a photo or any file, Stackie keeps a copy",
    "Data i godzina terminu jako pigułki z kalendarzem": "Due date and time as pills with a calendar",
    "Przycisk OK na dole karteczki (albo Cmd+Enter)": "OK button at the bottom of a note (or Cmd+Enter)",
    "Menu w pasku podzielone na sekcje, z ikonkami": "Menu bar menu split into sections, with icons",
    "Pasek pod pierwszą karteczką, mniejszy krzyżyk, powitanie z prawdziwymi karteczkami": "Toolbar under the first note, smaller close button, welcome shows real notes",
    "Upuść, żeby dołączyć": "Drop to attach", "Dołącz plik": "Attach file",
    "Albo przeciągnij plik na karteczkę": "Or drag a file onto the note",
    "Odepnij plik": "Remove file", "Otwórz": "Open", "Pokaż w Finderze": "Show in Finder", "Pliki: %d": "Files: %d",
    "Gotowe": "Done", "Dyktuj": "Dictate", "Podyktuj, co jest do zrobienia": "Dictate what needs doing",
    "Mów, co jest do zrobienia. Każde zdanie to osobne zadanie.": "Say what needs doing. Each sentence becomes a task.",
    "Pierwsze zdanie to tytuł, kolejne to zadania.": "The first sentence is the title, the rest are tasks.",
    "Brak zgody na rozpoznawanie mowy. Włącz ją w Ustawieniach systemowych → Prywatność → Rozpoznawanie mowy.": "Speech recognition isn't allowed. Turn it on in System Settings → Privacy → Speech Recognition.",
    "Brak dostępu do mikrofonu. Włącz go w Ustawieniach systemowych → Prywatność → Mikrofon.": "No microphone access. Turn it on in System Settings → Privacy → Microphone.",
    "Rozpoznawanie mowy jest teraz niedostępne.": "Speech recognition is unavailable right now.", "Nie udało się włączyć mikrofonu.": "Couldn't start the microphone.", "Puść, żeby usunąć": "Let go to delete", "Do kosza": "To the bin", "Kosz": "Bin",
    "Karteczki znikają same po %d dniach.": "Notes are removed for good after %d days.", "Kosz jest pusty": "The bin is empty",
    "zostało %@": "%@ left", "Przywróć": "Restore", "Usuń na zawsze": "Delete for good", "Opróżnij kosz": "Empty bin",
    "Usunąć wszystko z kosza na zawsze?": "Delete everything in the bin for good?", "Kosz (%d)": "Bin (%d)", "USTAWIENIA": "SETTINGS", "Pulpit": "Desktop", "Okno": "Window", "Na wierzchu": "On top",
    "Auto": "Auto", "Zakończ": "Quit", "Złap i przeciągnij, żeby przenieść stos": "Grab and drag to move the stack", 
    "W chwili terminu": "At due time",
    "%@ przed": "%@ before", "Za %@": "In %@", "1 tydzień": "1 week", "%d tyg.": "%d weeks", "%d godz.": "%d h", "%d min": "%d min",
    "Teraz: %@": "Now: %@", "%@ po terminie": "%@ after due", "Po terminie": "Overdue",
    "Dodaj": "Add", "%@: %@": "%@: %@",
    "Klient": "Client", "Projekt": "Project", "Klienci": "Clients",
    "KLIENCI": "CLIENTS", "PROJEKTY": "PROJECTS",
    "np. Kawiarnia Róża": "e.g. Rose Café", "np. Logo, Sklep online": "e.g. Logo, Online shop", "np. pilne, faktura": "e.g. urgent, invoice",
    "Kolory klientów": "Client colours", "Pokaż projekty klienta %@": "Show projects for %@",
    "Nie ma jeszcze klientów ani tagów. Dodasz je w karteczce.": "No clients or tags yet. Add them inside a note.", "Miesiąc": "Month", "Rok": "Year", "zadania z projektów\ntego roku": "tasks in this\nyear's projects", "Terminy w tym roku": "Due this year",
    "Co nowego": "What's new",
    "Dalej": "Next",
    "Wstecz": "Back",
    "Zaczynamy": "Let's go",
    "Data w rogu, pilność w kolorach. Dzwoneczek ustawia przypomnienia, a karteczka podskakuje, gdy termin jest blisko.": "Date in the corner, priority in colour. The bell sets reminders, and the note hops when the deadline is near.",
    "Dorobić obrazki": "Add pictures",
    "Poprawić slajdy": "Fix the slides",
    "Wysłać do klienta": "Send to the client",
    "Prezentacja": "Presentation",
    "Dyktowanie zadań. Stosik słucha tylko, gdy klikniesz mikrofon.": "Dictating tasks. Stackie only listens when you click the mic.",
    "Jedna karteczka to jeden projekt. Odhaczasz kółeczka, a pasek pokazuje postęp. Zadania przesuwasz za uchwyt.": "One note is one project. Tick the circles and the bar shows progress. Drag tasks by the handle.",
    "Jutro termin: Prezentacja": "Due tomorrow: Presentation",
    "Karteczki leżą na pulpicie jak talia kart. Najedź myszką, a stos się rozłoży.": "Notes sit on your desktop like a deck of cards. Hover and the stack fans out.",
    "Każda karteczka może mieć klienta, projekt i tagi. Kliknij jeden z nich, żeby zostawić w stosie tylko to, co do niego pasuje.": "Every note can have a client, a project and tags. Click one to keep only the matching notes in the stack.",
    "Klienci, projekty i tagi": "Clients, projects and tags",
    "Kliknij mikrofon i powiedz, co jest do zrobienia. Każdy czasownik zaczyna nowe zadanie, a „klient”, „projekt” i „tag” wypełniają pola.": "Click the mic and say what needs doing. Each verb starts a new task, and “client”, “project” and “tag” fill in the fields.",
    "Kosz na 30 dni": "A 30-day bin",
    "Mikrofon": "Microphone",
    "Powiadomienia": "Notifications",
    "Rozpoznawanie mowy": "Speech recognition",
    "Otwórz Ustawienia": "Open Settings",
    "Zezwól": "Allow",
    "Zgody": "Permissions",
    "Włączone": "On",
    "Pociągnij karteczkę w dół, aż kosz zrobi się czerwony. Przez 30 dni możesz ją przywrócić.": "Pull a note down until the bin turns red. You can restore it for 30 days.",
    "Projekty i zadania": "Projects and tasks",
    "Przypomnienia o terminach (dzwoneczek w karteczce).": "Deadline reminders (the bell in a note).",
    "Stosik prosi tylko o to, czego potrzebuje. Możesz to zmienić w każdej chwili w Ustawieniach systemowych.": "Stackie only asks for what it needs. You can change it any time in System Settings.",
    "Szara karta na końcu stosu to kalendarz. Kółka dni pokazują, co się działo, a wykres, ile zostało.": "The grey card at the end of the stack is the calendar. Day circles show what happened, and the chart shows what is left.",
    "Terminy i przypomnienia": "Deadlines and reminders",
    "Wersja %@": "Version %@",
    "Witaj i co nowego": "Welcome and what's new",
    "Zamienia podyktowany głos na tekst zadań.": "Turns your voice into task text.",
    "Zostało zadań: 2 z 3.": "Tasks left: 2 of 3.",
    "Stos karteczek na pulpicie jak talia kart: rozkłada się po najechaniu, na mniejszym ekranie w rzędach": "A stack of notes on your desktop like a deck of cards: fans out on hover, in rows on smaller screens",
    "Projekty z zadaniami, klient, projekt i tagi w kolorach, pilność, szukanie i filtr": "Projects with tasks, client, project and colour tags, priority, search and filter",
    "Terminy i przypomnienia jak w Kalendarzu, karteczki podskakują przy bliskim terminie, drzemka na dzwoneczku": "Deadlines and reminders like in Calendar, notes hop when a deadline is near, snooze on the bell",
    "Kalendarz z pierścieniami dni, widok roku i podsumowanie: zrobione i zostało": "Calendar with day rings, a year view and a done-vs-left summary",
    "Kosz na 30 dni: przeciągnij karteczkę w dół": "30-day bin: drag a note down",
    "Dyktowanie zadań głosem, wersja polska (Stosik) i angielska (Stackie)": "Dictate tasks by voice, in Polish (Stosik) and English (Stackie)",
    "Prezentacja dla klienta": "Client presentation",
    "Umówić spotkanie": "Book a meeting",
    "Pomysły na weekend": "Weekend ideas",
    "pomysły": "ideas",
    "Wycieczka rowerowa, kino, nowa kawiarnia.": "Bike ride, cinema, a new café.",
    "Nowe logo": "New logo",
    "Poprawki": "Revisions",
    "Studio Nova poprawić slajdy dorobić obrazki wysłać do klienta": "Studio Nova fix the slides add pictures send to the client",
    "Stosik": "Stackie",
]
