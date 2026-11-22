"""layout_fixer.py: the keys it keeps, when it fixes a word, and what it presses; with a fake Hyprland, a fake
virtual keyboard and fake dictionaries (nothing here reads /dev/input or reaches the session)."""
import shutil
import sys
import unittest
from pathlib import Path
from unittest import mock

from rice_sandbox import LIVE_SCRIPTS

sys.path.insert(0, str(LIVE_SCRIPTS))
import layout_fixer  # noqa: E402  (the live scripts folder goes on the path first)
import layout_keys as keys  # noqa: E402

ALT, SHIFT = 56, 42


class FakeSession:
    def __init__(self, layout="us", window=("kitty", False), locked=False):
        self.current = layout
        self.active_window = window
        self.is_locked = locked
        self.switches = []

    def layout(self):
        return self.current

    def switch(self, layout):
        self.switches.append(layout)
        self.current = layout

    def window(self):
        return self.active_window

    def locked(self):
        return self.is_locked


class FakeKeyboard:
    def __init__(self):
        self.taps = []

    def tap(self, code, shifted=False):
        self.taps.append((code, shifted))


class FakeSpeller:
    def __init__(self, *words, suggested=None):
        self.words = set(words)
        self.suggested = suggested or {}

    def knows(self, word):
        return word.lower() in self.words

    def suggestions(self, word):
        return self.suggested.get(word, [])


def strokes(layout, text):
    return keys.strokes_for(layout, text)


class FixerTest(unittest.TestCase):
    def setUp(self):
        self.session = FakeSession()
        self.keyboard = FakeKeyboard()
        self.spellers = {"us": FakeSpeller("hello", "dog", suggested={"helo": ["hello", "halo", "he'ló"]}),
                         "ru": FakeSpeller("привет", "мир", suggested={"превет": ["преет", "привет"]})}
        patcher = mock.patch.object(layout_fixer.time, "sleep")
        patcher.start()
        self.addCleanup(patcher.stop)

    def fixer(self, **modes):
        return layout_fixer.Fixer(self.session, self.keyboard, self.spellers, layout_fixer.Modes(**modes))

    def type(self, fixer, text, layout="us"):
        for code, shifted in strokes(layout, text):
            if shifted:
                fixer.key(SHIFT, 1)
            fixer.key(code, 1)
            fixer.key(code, 0)
            if shifted:
                fixer.key(SHIFT, 0)

    def press_hotkey(self, fixer, request="word"):
        fixer.key(ALT, 1)
        fixer.key(SHIFT, 1)
        fixer.key(keys.SPACE, 1)
        fixer.ask(request)
        fixer.key(keys.SPACE, 0)
        fixer.key(SHIFT, 0)
        fixer.key(ALT, 0)

    def test_the_hotkey_retypes_the_last_word_and_its_space_in_the_other_layout(self):
        fixer = self.fixer()
        self.type(fixer, "ok ghbdtn ")
        self.press_hotkey(fixer)
        word = strokes("us", "ghbdtn ")
        self.assertEqual(self.keyboard.taps, [(keys.BACKSPACE, False)] * len(word) + word)
        self.assertEqual(self.session.switches, ["ru"])
        self.assertEqual(keys.typed("ru", word), "привет ")

    def test_it_waits_for_the_modifiers_to_be_released(self):
        fixer = self.fixer()
        self.type(fixer, "ghbdtn")
        fixer.key(ALT, 1)
        fixer.key(keys.SPACE, 1)
        fixer.ask("word")
        self.assertEqual(self.keyboard.taps, [])
        fixer.key(ALT, 0)
        self.assertNotEqual(self.keyboard.taps, [])

    def test_a_second_press_switches_the_word_back(self):
        fixer = self.fixer()
        self.type(fixer, "ghbdtn")
        self.press_hotkey(fixer)
        self.press_hotkey(fixer)
        self.assertEqual(self.session.switches, ["ru", "us"])

    def test_backspace_takes_a_key_back(self):
        fixer = self.fixer()
        self.type(fixer, "ghbdtnx")
        fixer.key(keys.BACKSPACE, 1)
        self.assertEqual(fixer.strokes.tail(), strokes("us", "ghbdtn"))

    def test_a_click_enter_or_a_combination_forget_the_word(self):
        for forget in (lambda fixer: fixer.reset(), lambda fixer: fixer.key(keys.ENTER, 1),
                       lambda fixer: (fixer.key(29, 1), fixer.key(30, 1), fixer.key(29, 0))):
            with self.subTest():
                fixer = self.fixer()
                self.type(fixer, "ghbdtn")
                forget(fixer)
                self.press_hotkey(fixer)
                self.assertEqual(self.keyboard.taps, [])

    def test_nothing_is_kept_or_typed_while_the_screen_is_locked(self):
        self.session.is_locked = True
        fixer = self.fixer()
        self.type(fixer, "ghbdtn")
        self.assertEqual(fixer.strokes.keys, [])
        self.press_hotkey(fixer)
        self.assertEqual(self.keyboard.taps, [])

    def test_automatic_fix_after_a_space(self):
        fixer = self.fixer(automatic=True)
        self.type(fixer, "ghbdtn ")
        self.assertEqual(self.session.switches, ["ru"])
        self.assertEqual(self.keyboard.taps[-7:], strokes("us", "ghbdtn "))

    def test_automatic_fix_keeps_a_comma_meant_in_the_other_layout(self):
        fixer = self.fixer(automatic=True)
        self.type(fixer, "ghbdtn? ")
        self.assertEqual(self.session.switches, ["ru"])

    def test_no_automatic_fix_for_a_word_of_the_layout_typed_in(self):
        fixer = self.fixer(automatic=True)
        self.type(fixer, "hello dog ")
        self.assertEqual(self.session.switches, [])

    def test_no_automatic_fix_for_unknown_words_digits_one_letter_or_fullscreen(self):
        for text, window in (("qwzx ", ("kitty", False)), ("ghbdtn1 ", ("kitty", False)), ("d ", ("kitty", False)),
                             ("ghbdtn ", ("game", True))):
            with self.subTest(text=text):
                self.session = FakeSession(window=window)
                fixer = self.fixer(automatic=True)
                self.type(fixer, text)
                self.assertEqual(self.session.switches, [])

    def test_no_automatic_fix_in_an_excluded_window(self):
        fixer = self.fixer(automatic=True, excluded=frozenset({"kitty"}))
        self.type(fixer, "ghbdtn ")
        self.assertEqual(self.session.switches, [])

    def presses_show(self, fixer, typed, layout, presses):
        """Each press of the key on the word typed erases what is shown and types the next of presses."""
        self.type(fixer, typed, layout)
        for shown in presses:
            self.keyboard.taps = []
            erased = len(fixer.strokes.tail())
            self.press_hotkey(fixer)
            self.assertEqual(self.keyboard.taps[:erased], [(keys.BACKSPACE, False)] * erased)
            self.assertEqual(keys.typed(self.session.current, self.keyboard.taps[erased:]), shown)

    def test_a_typo_becomes_each_suggestion_in_turn_then_what_was_typed(self):
        self.session = FakeSession(layout="ru")
        fixer = self.fixer(typos=True)
        self.presses_show(fixer, "так превет, ", "ru", ["преет, ", "привет, ", "превет, ", "преет, "])
        self.assertEqual(self.session.switches, [])

    def test_a_suggestion_off_the_layout_is_left_out(self):
        fixer = self.fixer(typos=True)
        self.presses_show(fixer, "helo", "us", ["hello", "halo", "helo"])

    def test_with_typos_a_word_of_the_other_layout_still_switches(self):
        fixer = self.fixer(typos=True)
        self.presses_show(fixer, "ghbdtn ", "us", ["привет ", "ghbdtn "])
        self.assertEqual(self.session.switches, ["ru", "us"])

    def test_with_typos_a_known_word_or_one_without_suggestions_switches(self):
        for typed in ("hello", "qwzx"):
            with self.subTest(typed=typed):
                self.session = FakeSession()
                self.presses_show(self.fixer(typos=True), typed, "us", [keys.typed("ru", strokes("us", typed))])

    def test_without_typos_a_typo_only_switches(self):
        self.presses_show(self.fixer(), "helo", "us", ["рудщ"])

    def test_typing_on_forgets_the_suggestions(self):
        fixer = self.fixer(typos=True)
        self.presses_show(fixer, "helo", "us", ["hello"])
        self.presses_show(fixer, " helo", "us", ["hello"])

    def test_automatic_fix_never_replaces_a_typo(self):
        fixer = self.fixer(automatic=True, typos=True)
        self.type(fixer, "helo ")
        self.assertEqual(self.keyboard.taps, [])

    def test_the_selection_is_typed_over_in_the_other_layout(self):
        fixer = self.fixer()
        with mock.patch.object(layout_fixer.subprocess, "run",
                               return_value=mock.Mock(stdout="руддщ")) as run:
            fixer.ask("selection")
        self.assertEqual(run.call_args.args[0][:2], ["wl-paste", "--primary"])
        self.assertEqual(self.session.switches, ["us"])
        self.assertEqual(keys.typed("us", self.keyboard.taps), "hello")


@unittest.skipUnless(shutil.which("hunspell") and Path("/usr/share/hunspell/ru_RU.dic").exists(),
                     "hunspell с русским словарём не установлен")
class SpellerTest(unittest.TestCase):
    def test_russian_suggestions_come_most_frequent_first(self):
        speller = layout_fixer.Speller("ru_RU", layout_fixer.frequent_words(layout_fixer.RUSSIAN_WORDS))
        self.addCleanup(speller.process.kill)
        self.assertTrue(speller.knows("привет"))
        self.assertEqual(speller.suggestions("превет")[0], "привет")  # hunspell alone puts it fifth
        self.assertEqual(speller.suggestions("привет"), [])


class LayoutKeysTest(unittest.TestCase):
    def test_every_character_types_back_to_itself(self):
        for layout in ("us", "ru"):
            text = "".join(keys.CHARACTERS[layout].values())
            self.assertEqual(keys.typed(layout, keys.strokes_for(layout, text)), text)

    def test_a_character_off_the_layout_has_no_strokes(self):
        self.assertIsNone(keys.strokes_for("us", "привет"))

    def test_the_layout_of_a_text(self):
        self.assertEqual(keys.layout_of("Ёлка"), "ru")
        self.assertEqual(keys.layout_of("tree, 42"), "us")


if __name__ == "__main__":
    unittest.main()
