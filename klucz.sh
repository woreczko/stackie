#!/bin/zsh
# Klucz Claude dla „Zrób zadania”: zapisuje klucz ze schowka i hasło do niego w plikach poza repozytorium.
# zbuduj.sh szyfruje klucz tym hasłem i wkłada do apki; bez hasła nie da się go odczytać.
# Użycie: skopiuj klucz (sk-ant-...) i uruchom ./klucz.sh  (nic nie pojawia się na ekranie)
D="$HOME/Library/Application Support/StackieSigning"
K=$(pbpaste | tr -d '[:space:]')
[[ "$K" == sk-ant-* ]] || { echo "W schowku nie ma klucza (zaczyna się od sk-ant-)."; exit 1; }
read -rs "P1?Hasło dla partnera (do wpisania w Stosiku): "; echo
read -rs "P2?Powtórz hasło: "; echo
[[ -n "$P1" && "$P1" == "$P2" ]] || { echo "Hasła się różnią albo są puste. Nic nie zapisałem."; exit 1; }
mkdir -p "$D"; umask 077
print -rn -- "$K" > "$D/claude.key"; print -rn -- "$P1" > "$D/claude.pass"
chmod 600 "$D/claude.key" "$D/claude.pass"
echo "Zapisane: klucz …${K: -4}, hasło ${#P1} znaków. Wyczyść schowek (skopiuj cokolwiek innego)."
