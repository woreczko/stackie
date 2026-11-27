#!/bin/zsh
# Zrzuty stosu, edytora i kalendarza po polsku (test/) i po angielsku (test/en/) na osobnym folderze danych.
cd "${0:A:h}"
./zbuduj.sh --tylko-buduj || exit 1
mkdir -p test/en
T=$(mktemp -d)
STOSIK_THEME=light STOSIK_SCREENW=1512 STOSIK_LANG=pl STOSIK_DIR=$T/pl STOSIK_SNAP=$PWD/test build/Stosik.app/Contents/MacOS/Stosik
STOSIK_THEME=light STOSIK_LANG=en STOSIK_DIR=$T/en STOSIK_SNAP=$PWD/test/en build/Stosik.app/Contents/MacOS/Stosik
ls test test/en
