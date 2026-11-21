"""The keys of the us and ru layouts (ЙЦУКЕН) and the character each gives, unshifted and shifted: what a key
typed means in either layout, and which key types a character. Linux key codes (input-event-codes.h)."""

BACKSPACE = 14
ENTER = 28
LEFT_SHIFT = 42
SPACE = 57
DIGIT_KEYS = range(2, 12)  # 1 … 0 on the top row

# Each row: its key codes, then us plain, us shifted, ru plain, ru shifted.
ROWS = (
    ((41, *range(2, 14)), "`1234567890-=", "~!@#$%^&*()_+", "ё1234567890-=", "Ё!\"№;%:?*()_+"),
    (range(16, 28), "qwertyuiop[]", "QWERTYUIOP{}", "йцукенгшщзхъ", "ЙЦУКЕНГШЩЗХЪ"),
    (range(30, 41), "asdfghjkl;'", "ASDFGHJKL:\"", "фывапролджэ", "ФЫВАПРОЛДЖЭ"),
    (range(44, 54), "zxcvbnm,./", "ZXCVBNM<>?", "ячсмитьбю.", "ЯЧСМИТЬБЮ,"),
    ((43,), "\\", "|", "\\", "/"),
    ((SPACE,), " ", " ", " ", " "),
)

# {layout: {(code, shifted): character}}
CHARACTERS = {"us": {}, "ru": {}}
for codes, us_plain, us_shifted, ru_plain, ru_shifted in ROWS:
    for column, code in enumerate(codes):
        CHARACTERS["us"][(code, False)] = us_plain[column]
        CHARACTERS["us"][(code, True)] = us_shifted[column]
        CHARACTERS["ru"][(code, False)] = ru_plain[column]
        CHARACTERS["ru"][(code, True)] = ru_shifted[column]

# {layout: {character: (code, shifted)}}; the first key wins where one character has two (space).
STROKES = {layout: {} for layout in CHARACTERS}
for layout, characters in CHARACTERS.items():
    for stroke, character in characters.items():
        STROKES[layout].setdefault(character, stroke)

TYPING_KEYS = sorted({code for code, _ in CHARACTERS["us"]})


def other(layout):
    return "ru" if layout == "us" else "us"


def typed(layout, strokes):
    """The text the strokes [(code, shifted)] give in the layout."""
    return "".join(CHARACTERS[layout][stroke] for stroke in strokes)


def strokes_for(layout, text):
    """The strokes that type text in the layout, or None when one of its characters is not on it."""
    strokes = [STROKES[layout].get(character) for character in text]
    return None if None in strokes else strokes


def layout_of(text):
    """The layout a text was typed in: ru when it has a Cyrillic letter."""
    return "ru" if any("а" <= character.lower() <= "я" or character in "ёЁ" for character in text) else "us"
