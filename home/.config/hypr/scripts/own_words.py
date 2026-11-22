#!/usr/bin/env python3
"""The user's own words, which the layout fixer's dictionaries know besides their own (Alt+F2 → Словарь):
hunspell's personal dictionaries ~/.config/hypr-rice/words-ru.dic and words-en.dic, a word per line, "word/model"
declining like model. hunspell reads them when it starts, so a change restarts rice-layout-fixer.service.
  own_words.py list           {"ru": [lines], "us": [lines]} as JSON
  own_words.py add <entry>    a word or word/model, into the dictionary of its alphabet
  own_words.py remove <line>  takes the line out of the dictionary that has it
A refusal says why and exits with 1.
"""
import json
import re
import subprocess
import sys

from layout_fixer import OWN_WORDS

DICTIONARIES = {"ru": "ru_RU", "us": "en_US"}
# Letters of one alphabet, a hyphen allowed between them: "кто-то", "e-mail".
ALPHABETS = {"ru": "[а-яё]+(-[а-яё]+)*", "us": "[a-z]+(-[a-z]+)*"}


class Refused(Exception):
    pass


def lines(layout):
    try:
        text = OWN_WORDS[layout].read_text(encoding="utf-8")
    except FileNotFoundError:
        return []
    return [line.strip() for line in text.splitlines() if line.strip()]


def write(layout, kept):
    path = OWN_WORDS[layout]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(line + "\n" for line in kept), encoding="utf-8")
    restart_fixer()


def restart_fixer():
    """Only a running fixer: its hunspell reads the own words again."""
    subprocess.run(["systemctl", "--user", "try-restart", "rice-layout-fixer.service"], capture_output=True)


def known(layout, word):
    """Whether hunspell's own dictionary knows the word: hunspell -l prints the words it does not know."""
    try:
        result = subprocess.run(["hunspell", "-l", "-i", "utf-8", "-d", DICTIONARIES[layout]], input=word,
                                capture_output=True, text=True)
    except FileNotFoundError:
        raise Refused("нет hunspell: его ставит «Исправление опечаток» (Функции)")
    if result.returncode != 0:
        raise Refused(f"нет словаря {DICTIONARIES[layout]}: его ставит «Исправление опечаток» (Функции)")
    return not result.stdout.strip()


def add(entry):
    word, _, model = entry.strip().lower().partition("/")
    layout = next((layout for layout, letters in ALPHABETS.items() if re.fullmatch(letters, word)), None)
    if layout is None:
        raise Refused(f"«{word}» не слово: нужны только русские или только английские буквы, можно через дефис")
    if model and not re.fullmatch(ALPHABETS[layout], model):
        raise Refused(f"образец «{model}» должен быть словом того же языка, что и «{word}»")
    if model and not known(layout, model):
        raise Refused(f"образец «{model}» словарю неизвестен: возьми слово, которое он знает и которое "
                      f"склоняется так же")
    if known(layout, word):
        raise Refused(f"«{word}» словарь и так знает")
    have = lines(layout)
    if any(line.partition("/")[0] == word for line in have):
        raise Refused(f"«{word}» уже в твоём словаре")
    write(layout, have + [f"{word}/{model}" if model else word])


def remove(line):
    for layout in OWN_WORDS:
        have = lines(layout)
        if line in have:
            write(layout, [kept for kept in have if kept != line])
            return
    raise Refused(f"«{line}» нет в твоём словаре")


def main(args):
    if args == ["list"]:
        print(json.dumps({layout: lines(layout) for layout in OWN_WORDS}, ensure_ascii=False))
    elif len(args) == 2 and args[0] == "add":
        add(args[1])
    elif len(args) == 2 and args[0] == "remove":
        remove(args[1])
    else:
        raise SystemExit("own_words.py list | add <слово[/образец]> | remove <строка>")


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except Refused as refusal:
        print(refusal)
        sys.exit(1)
