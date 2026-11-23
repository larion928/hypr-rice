"""The theme catalog: a signed list of themes, archives checked against it, installed beside the user's own
themes. The catalog's repository is a local one here, signed with a key made for the test, and the archives
are files: nothing reaches GitHub, and the user's git settings (his signing key) are not read."""
import hashlib
import io
import json
import subprocess
import unittest
import zipfile

from PIL import Image

from rice_sandbox import LIVE_THEMES, THEME_FILES, Sandbox

ISOLATED_GIT = {"GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}


def picture(color):
    """A wallpaper the theme build can read."""
    data = io.BytesIO()
    Image.new("RGB", (8, 8), color).save(data, "PNG")
    return data.getvalue()


class CatalogTest(unittest.TestCase):
    def setUp(self):
        self.sandbox = Sandbox()
        self.sandbox.add_theme("night")
        root = self.sandbox.root
        self.archives = root / "archives"
        self.archives.mkdir()
        self.origin = root / "origin"
        key = root / "author"
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "author", "-f", key], check=True)
        trust = self.sandbox.home / ".config/hypr-rice/allowed_signers"
        trust.write_text(f'hypr-rice namespaces="git" {key.with_suffix(".pub").read_text()}')
        self.git("init", "-q", "-b", "main", self.origin)
        for name, value in (("user.name", "author"), ("user.email", "author@example.org"), ("gpg.format", "ssh"),
                            ("user.signingkey", str(key)), ("commit.gpgsign", "true"),
                            ("uploadpack.allowFilter", "true"), ("uploadpack.allowAnySHA1InWant", "true")):
            self.git("-C", self.origin, "config", name, value)

    def tearDown(self):
        self.sandbox.cleanup()

    def git(self, *arguments):
        subprocess.run(["git", *map(str, arguments)], check=True, capture_output=True,
                       env={"PATH": "/usr/bin", "HOME": str(self.sandbox.root), **ISOLATED_GIT})

    def archive(self, name, extra=None):
        """A theme's zip as the catalog packs it: the night theme's files under the folder name."""
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as out:
            files = {file_name: (LIVE_THEMES / "night" / file_name).read_text() for file_name in THEME_FILES}
            palette = json.loads(files["palette.json"])
            palette.update(name=name, label=name.title())
            files["palette.json"] = json.dumps(palette)
            files["style.css"] = "url('file://__HOME__/.config/hypr/themes/x.png')"
            files["wall.png"] = picture("black")
            for path, content in {**files, **(extra or {})}.items():
                out.writestr(f"{name}/{path}", content)
        return data.getvalue()

    def publish(self, packs, signed=True):
        """A catalog commit listing packs {id: {theme name: archive bytes}}; the archives beside it."""
        catalog = {"archives": self.archives.as_uri() + "/", "packs": []}
        (self.origin / "previews").mkdir(exist_ok=True)
        for pack, themes in packs.items():
            entries = []
            for name, data in themes.items():
                digest = hashlib.sha256(data).hexdigest()
                (self.archives / f"{name}-{digest[:12]}.zip").write_bytes(data)
                (self.origin / "previews" / f"{name}.jpg").write_bytes(b"preview")
                entries.append({"name": name, "label": name.title(), "archive": f"{name}-{digest[:12]}.zip",
                                "sha256": digest, "size": len(data), "preview": f"previews/{name}.jpg"})
            catalog["packs"].append({"id": pack, "label": pack, "themes": entries})
        (self.origin / "catalog.json").write_text(json.dumps(catalog))
        self.git("-C", self.origin, "add", "-A")
        self.git("-C", self.origin, "commit", "-q", "-m", "catalog", *([] if signed else ["--no-gpg-sign"]))

    def themegen(self, *args):
        return self.sandbox.run(["python3", self.sandbox.home / ".config/hypr/scripts/themegen.py", *args],
                                RICE_THEMES_REPO=self.origin.as_uri(), **ISOLATED_GIT)

    def installed(self):
        path = self.sandbox.home / ".config/hypr-rice/catalog-themes.json"
        return json.loads(path.read_text()) if path.exists() else {}

    def theme_folder(self, name):
        return self.sandbox.home / ".config/hypr/themes" / name

    def test_a_signed_catalog_theme_is_installed_beside_the_own_ones(self):
        self.publish({"pack": {"dawn": self.archive("dawn")}})
        result = self.themegen("catalog-install", "dawn")
        self.assertEqual(result.returncode, 0, result.stderr)
        folder = self.theme_folder("dawn")
        self.assertTrue(folder.is_symlink())
        self.assertEqual(folder.resolve(), self.sandbox.home / ".config/hypr-rice/themes/dawn")
        self.assertIn(str(self.sandbox.home), (folder / "style.css").read_text())
        self.assertEqual(self.installed()["dawn"]["pack"], "pack")
        listing = json.loads(self.themegen("catalog").stdout)
        self.assertEqual(listing[0]["themes"][0]["state"], "installed")

    def test_an_empty_catalog_says_so(self):
        self.git("-C", self.origin, "commit", "-q", "--allow-empty", "-m", "start")
        self.git("-C", self.origin, "branch", "-m", "other")
        result = self.themegen("catalog")
        self.assertEqual(result.returncode, 1)
        self.assertIn("автор его ещё не опубликовал", result.stderr)

    def test_an_unsigned_catalog_installs_nothing(self):
        self.publish({"pack": {"dawn": self.archive("dawn")}}, signed=False)
        result = self.themegen("catalog-install", "dawn")
        self.assertEqual(result.returncode, 1)
        self.assertIn("не подписан", result.stderr)
        self.assertFalse(self.theme_folder("dawn").exists())

    def test_an_archive_that_differs_from_the_catalog_is_refused(self):
        self.publish({"pack": {"dawn": self.archive("dawn")}})
        for archive in self.archives.iterdir():
            archive.write_bytes(self.archive("dawn", {"wall2.png": picture("red")}))
        result = self.themegen("catalog-install", "dawn")
        self.assertEqual(result.returncode, 1)
        self.assertIn("не ставлю", result.stderr)
        self.assertFalse(self.theme_folder("dawn").exists())
        self.assertEqual(self.installed(), {})

    def test_an_archive_with_a_file_no_theme_has_is_refused(self):
        self.publish({"pack": {"dawn": self.archive("dawn", {"run.sh": "rm -rf ~"})}})
        result = self.themegen("catalog-install", "dawn")
        self.assertEqual(result.returncode, 1)
        self.assertIn("лишний файл: run.sh", result.stderr)
        self.assertFalse(self.theme_folder("dawn").exists())

    def test_a_theme_may_carry_a_cover_an_animated_header_and_a_font(self):
        extra = {"assets/cover.jpg": b"", "assets/head.webp": b"", "assets/head.gif": b"",
                 "assets/Pixel.ttf": b"", "assets/OFL.txt": b""}
        self.publish({"pack": {"dawn": self.archive("dawn", extra)}})
        result = self.themegen("catalog-install", "dawn")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.theme_folder("dawn") / "assets" / "head.gif").is_file())
        self.assertTrue((self.theme_folder("dawn") / "assets" / "Pixel.ttf").is_file())

    def test_a_pack_installs_every_theme_of_it(self):
        self.publish({"pack": {"dawn": self.archive("dawn"), "dusk": self.archive("dusk")}})
        result = self.themegen("catalog-install", "pack")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sorted(self.installed()), ["dawn", "dusk"])

    def test_an_update_brings_the_changed_archive_and_keeps_the_others(self):
        same = self.archive("dusk")
        self.publish({"pack": {"dawn": self.archive("dawn"), "dusk": same}})
        self.themegen("catalog-install", "pack")
        self.publish({"pack": {"dawn": self.archive("dawn", {"wall2.png": picture("blue")}), "dusk": same}})
        result = self.themegen("catalog-update")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.theme_folder("dawn") / "wall2.png").exists())
        self.assertNotIn("Dusk", result.stderr)

    def test_a_removed_catalog_theme_is_gone_and_can_come_back(self):
        self.publish({"pack": {"dawn": self.archive("dawn")}})
        self.themegen("catalog-install", "dawn")
        result = self.themegen("delete", "dawn")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.theme_folder("dawn").exists())
        self.assertFalse((self.sandbox.home / ".config/hypr-rice/themes/dawn").exists())
        self.assertEqual(self.installed(), {})
        self.assertEqual(self.themegen("catalog-install", "dawn").returncode, 0)

    def test_a_name_another_theme_has_is_not_taken_over(self):
        self.publish({"pack": {"night": self.archive("night")}})
        before = (self.theme_folder("night") / "palette.json").read_text()
        result = self.themegen("catalog-install", "night")
        self.assertEqual(result.returncode, 1)
        self.assertIn("уже есть", result.stderr)
        self.assertEqual((self.theme_folder("night") / "palette.json").read_text(), before)
        listing = json.loads(self.themegen("catalog").stdout)
        self.assertEqual(listing[0]["themes"][0]["state"], "taken")


if __name__ == "__main__":
    unittest.main()
