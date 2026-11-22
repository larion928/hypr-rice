"""own_words.py: the user's own words added to and taken out of hunspell's personal dictionaries, in a temporary
folder; the fixer's restart is only recorded."""
import contextlib
import io
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from rice_sandbox import LIVE_SCRIPTS

sys.path.insert(0, str(LIVE_SCRIPTS))
import own_words  # noqa: E402  (the live scripts folder goes on the path first)


@unittest.skipUnless(shutil.which("hunspell") and Path("/usr/share/hunspell/ru_RU.dic").exists()
                     and Path("/usr/share/hunspell/en_US.dic").exists(), "hunspell со словарями не установлен")
class OwnWordsTest(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.folder = Path(folder.name) / "hypr-rice"
        paths = {"us": self.folder / "words-en.dic", "ru": self.folder / "words-ru.dic"}
        dictionaries = mock.patch.dict(own_words.OWN_WORDS, paths)
        dictionaries.start()
        self.addCleanup(dictionaries.stop)
        restart = mock.patch.object(own_words, "restart_fixer")
        self.restart = restart.start()
        self.addCleanup(restart.stop)

    def test_a_word_goes_into_the_dictionary_of_its_alphabet_and_the_fixer_restarts(self):
        own_words.add("Прив")
        own_words.add("фича/свеча")
        own_words.add("lol")
        self.assertEqual(self.listed(), {"ru": ["прив", "фича/свеча"], "us": ["lol"]})
        self.assertEqual(self.restart.call_count, 3)

    def test_what_is_not_added_says_why(self):
        own_words.add("прив")
        for entry, reason in (("привет", "и так знает"), ("прив", "уже в твоём словаре"),
                              ("прив-lol", "не слово"), ("фича/ыыы", "словарю неизвестен"),
                              ("фича/cat", "того же языка")):
            with self.subTest(entry=entry), self.assertRaisesRegex(own_words.Refused, reason):
                own_words.add(entry)
        self.assertEqual(self.listed()["ru"], ["прив"])

    def test_a_line_is_taken_out(self):
        own_words.add("прив")
        own_words.add("фича/свеча")
        own_words.remove("фича/свеча")
        self.assertEqual(self.listed()["ru"], ["прив"])
        with self.assertRaisesRegex(own_words.Refused, "нет в твоём словаре"):
            own_words.remove("фича")

    def listed(self):
        printed = io.StringIO()
        with contextlib.redirect_stdout(printed):
            own_words.main(["list"])
        return json.loads(printed.getvalue())


if __name__ == "__main__":
    unittest.main()
