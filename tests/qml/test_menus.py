"""The menus' behaviour (tests/qml/BEHAVIOUR.md) checked offscreen; see harness.py for how they run.
    python3 -m unittest discover -s tests/qml           the live menus
    RICE_HOME=<copy> python3 -m unittest ...            another copy (the repo's home/ in CI, an older version)
Each test starts its own shell. Skipped without quickshell."""
import json
import shutil
import socket
import subprocess
import threading
import time
import unittest

from harness import KEY, MENUS, SOURCE_HOME, MenuSandbox, resident

needs_quickshell = unittest.skipUnless(shutil.which("quickshell"), "quickshell is not installed")


@needs_quickshell
class MenuTest(unittest.TestCase):
    def setUp(self):
        self.sandbox = MenuSandbox()
        self.addCleanup(self.sandbox.cleanup)
        self.sandbox.start_shell()

    def tearDown(self):
        self.assertEqual(self.sandbox.errors(), [], "QML errors in the log")

    def theme_expression(self, name):
        """A colour of the theme as the menu sees it: the per-panel layout had a Theme object `theme` in each
        menu; the resident shell has the Theme singleton."""
        return f"String(Theme.{name})" if self.sandbox.resident else f"theme.c.{name}"

    def open(self, menu, argument=""):
        self.sandbox.open(menu, argument)
        return lambda expression: self.sandbox.eval(menu, expression)

    def escape_closes(self, menu):
        self.sandbox.key(menu, KEY["Escape"])
        self.sandbox.wait_closed(menu)


class EveryMenu(MenuTest):
    def test_each_opens_and_closes(self):
        for menu in MENUS:
            with self.subTest(menu=menu):
                self.open(menu)
                self.assertTrue(self.sandbox.is_open(menu))
                self.sandbox.close(menu)
                self.sandbox.wait_closed(menu)

    def test_escape_closes(self):
        for menu in ("power", "themes", "help", "network", "launcher", "notif", "games", "shots", "settings"):
            with self.subTest(menu=menu):
                self.open(menu)
                self.escape_closes(menu)

    def test_colours_come_from_the_theme_and_follow_a_switch(self):
        value = self.open("power")
        self.assertEqual(value(self.theme_expression("accent")), self.sandbox.palette["colors"]["accent"])
        palette = json.loads(json.dumps(self.sandbox.palette))
        palette["colors"]["accent"] = "#123456"
        self.sandbox.write_theme(palette, {"powerStyle": "terminal", "upperTitle": True})
        self.sandbox.wait_for("power", self.theme_expression("accent"), "#123456")
        self.sandbox.wait_for("power", "menu.terminal", True)


class Launcher(MenuTest):
    def test_commands_and_search(self):
        value = self.open("launcher")
        theme_commands = value("menu.commands.filter(c => c.id.startsWith('theme:')).map(c => c.id)")
        self.assertEqual(theme_commands, ["theme:claude", "theme:coffee", "theme:hacker"])
        self.assertFalse(value("menu.results.some(r => r.danger || r.id.startsWith('theme:'))"))
        value("menu.query = 'настройки'")
        self.assertEqual(value("menu.results[0].id"), "settings")
        value("menu.query = 'yfcnhjqrb'")  # «настройки» typed on the us layout
        self.assertEqual(value("menu.results[0].id"), "settings")

    def test_dangerous_command_needs_a_second_enter(self):
        value = self.open("launcher")
        value("menu.query = 'перезагрузка'")
        self.assertEqual(value("menu.results[0].id"), "reboot")
        self.sandbox.key("launcher", KEY["Return"])
        self.assertEqual(value("menu.armed"), "reboot")
        self.assertNotIn("systemctl reboot", self.sandbox.recorded())
        self.assertTrue(self.sandbox.is_open("launcher"))


class Settings(MenuTest):
    def test_opens_on_the_page_asked_for(self):
        value = self.open("settings", "keys")
        self.assertEqual(value("menu.page"), "keys")

    def test_a_themes_settings_then_escape_steps_back(self):
        value = self.open("settings", "theme:coffee:colors")
        self.assertEqual(value("menu.page"), "theme")
        self.assertEqual(value("themeEdit.editing.name"), "coffee")
        self.assertEqual(value("themeEdit.section"), "colors")
        self.sandbox.key("settings", KEY["Escape"])
        self.assertIsNone(value("themeEdit.editing"))
        self.assertTrue(self.sandbox.is_open("settings"))
        self.escape_closes("settings")

    def test_the_theme_catalog_shows_its_packs_and_escape_closes_it(self):
        value = self.open("settings", "theme")
        # Set as themegen's catalog command prints it: opening the real one would reach GitHub.
        value("ownThemes.packs = [{id: 'hacker-plus', label: 'hacker+', about: 'Темы для хакеров', themes: ["
              "{name: 'mr-robot', label: 'Mr. Robot', preview: '', state: 'absent'},"
              "{name: 'dawn', label: 'Dawn', preview: '', state: 'installed'},"
              "{name: 'night', label: 'Night', preview: '', state: 'taken'}]}]")
        value("ownThemes.dialog = 'catalog'")
        time.sleep(0.3)
        self.sandbox.key("settings", KEY["Escape"])
        self.assertEqual(value("ownThemes.dialog"), "")
        self.assertTrue(self.sandbox.is_open("settings"))

    def test_monitors(self):
        value = self.open("settings")
        self.sandbox.wait_for("settings", "mon.edit.length", 2)
        self.assertEqual(value("mon.keptFields('hl.monitor({ output = \"DP-1\", mode = \"x\", transform = 1, -- c\\n vrr = 1 })')"),
                         {"DP-1": ["transform = 1", "vrr = 1"]})
        value("mon.drop(1, 1925, 30)")  # snaps to the right edge of eDP-1, top aligned
        self.assertEqual(value("[mon.edit[1].x, mon.edit[1].y]"), [1920, 0])
        value("mon.keep()")
        time.sleep(0.6)
        written = (self.sandbox.home / ".config/hypr/monitors.lua").read_text()
        self.assertIn('hl.monitor({ output = "eDP-1", mode = "1920x1080@60", position = "0x0", scale = 1, transform = 1 })',
                      written)
        self.assertIn('hl.monitor({ output = "HDMI-A-1", mode = "2560x1440@144", position = "1920x0", scale = 1.25 })',
                      written)
        self.assertIn('hl.workspace_rule({ workspace = "1", monitor = "eDP-1" })', written)

    def test_keys(self):
        value = self.open("settings", "keys")
        self.sandbox.wait_for("settings", "keys.binds.length", 3)
        self.assertEqual(value("keys.label('SUPER + SHIFT + mouse:275')"), 'Super+Shift+Мышь "назад"')
        self.assertEqual(value("keys.conflicts('ALT + R', 'close')"), "Лаунчер")
        self.assertEqual(value("keys.conflicts('SUPER + G', '')"), "GIMP")
        value("keys.setMainMod('SUPER')")
        self.assertEqual(value("keys.binds.map(b => b.current)"), ["SUPER + R", "SUPER + C", "SUPER + SHIFT + T"])
        value("keys.save()")
        time.sleep(0.6)
        written = (self.sandbox.home / ".config/hypr/binds-user.lua").read_text()
        self.assertIn('mainMod = "SUPER",', written)
        self.assertIn('{ keys = "SUPER + G", cmd = "gimp", name = "GIMP" },', written)

    def test_theme_edits_are_written_pruned(self):
        value = self.open("settings", "theme:coffee:fonts")
        value("themeEdit.chooseFont('Iosevka')")
        self.assertTrue(value("themeEdit.dirty"))
        value("themeEdit.save()")
        time.sleep(0.6)
        edits = json.loads((self.sandbox.home / ".config/hypr-rice/theme-edits.json").read_text())
        self.assertEqual(edits["themes"]["coffee"], {"fonts": {"font": "Iosevka"}})

    def test_panel_modules_are_their_icons_not_what_they_show_now(self):
        value = self.open("settings", "theme:coffee:waybar")
        time.sleep(0.6)
        self.assertIn("themegen.py bar-presence coffee", self.sandbox.recorded())
        self.assertEqual(value("themeEdit.iconOf('clock')"), "", "a clock has no icon: the chip shows its name")
        sample = value("themeEdit.editing.waybar.preview['cpu']")
        self.assertGreater(ord(sample[0]), 0xFFFF, "coffee's cpu icon lies past U+FFFF, which Array.from splits in two")
        self.assertEqual(value("themeEdit.iconOf('cpu')"), sample[0])
        value("themeEdit.setIcon('cpu', '\\u{f0ee0}')")
        self.assertEqual(value("themeEdit.iconOf('cpu')"), "\U000f0ee0")


@unittest.skipUnless(resident(), "the per-panel menus have no features page")
class OwnWords(MenuTest):
    def test_without_a_feature_reading_them_the_tab_is_not_there(self):
        value = self.open("settings", "words")
        self.assertEqual(value("menu.page"), "features")
        self.assertFalse(value("menu.wordsShown"))

    def test_words_listed_added_refused_and_taken_out(self):
        state = self.sandbox.home / ".config/hypr-rice/features.json"
        state.write_text('{"layout-typo": true}')
        value = self.open("settings", "words")
        self.assertEqual(value("menu.page"), "words")
        self.sandbox.wait_for("settings", "ownWords.ru.length", 2)
        value('ownWords.add("айти", () => {})')
        self.sandbox.wait_for("settings", "ownWords.ru", ["горутина/машина", "прив", "айти"])
        value('ownWords.add("привет", () => {})')
        self.sandbox.wait_for("settings", "ownWords.message", '"привет" уже есть в обычном словаре')
        self.sandbox.wait_for("settings", "ownWords.busy", False)
        value('ownWords.remove("прив")')
        self.sandbox.wait_for("settings", "ownWords.ru", ["горутина/машина", "айти"])
        self.assertEqual(value("ownWords.message"), "")


class Features(MenuTest):
    def test_features_listed_by_group_and_switched(self):
        value = self.open("settings", "features")
        self.assertEqual(value("menu.page"), "features")
        self.sandbox.wait_for("settings", "features.list.length", 5)
        self.assertEqual(value("features.groups"), ["Анимации", "Система"])
        value("features.toggle(features.list[0])")
        self.sandbox.wait_for("settings", "features.list[0].on", False)
        self.sandbox.wait_for("settings", "features.busy", False)
        value("features.toggle(features.list[2])")
        self.sandbox.wait_for("settings", "features.list[2].on", True)
        switches = [call for call in self.sandbox.recorded() if call.startswith(("features.py on", "features.py off"))]
        self.assertEqual(switches, ["features.py off animations", "features.py on daily-check"])

    def test_a_feature_with_a_caution_is_switched_on_only_once_it_is_accepted(self):
        value = self.open("settings", "features")
        self.sandbox.wait_for("settings", "features.list.length", 5)
        value("features.toggle(features.list[1])")
        self.sandbox.wait_for("settings", "features.list[1].on", False)
        self.sandbox.wait_for("settings", "features.busy", False)
        value("features.toggle(features.list[1])")
        self.assertEqual(value("features.cautioning.id"), "shot-animation")
        self.sandbox.key("settings", KEY["Escape"])
        self.assertIsNone(value("features.cautioning"))
        self.assertFalse(value("features.list[1].on"))
        value("features.toggle(features.list[1])")
        value("features.acceptCaution()")
        self.sandbox.wait_for("settings", "features.list[1].on", True)

    def test_what_the_system_must_allow_is_asked_about_before_switching_on(self):
        value = self.open("settings", "features")
        self.sandbox.wait_for("settings", "features.list.length", 5)
        value("features.toggle(features.list[4])")
        self.assertEqual(value("features.asking.id"), "phone")
        value("features.switchOnWithout()")
        self.sandbox.wait_for("settings", "features.list[4].on", True)
        calls = [call for call in self.sandbox.recorded() if call.startswith(("features.py on", "features.py grant"))]
        self.assertEqual(calls, ["features.py on phone"])

    def test_it_is_allowed_then_the_feature_switched_on(self):
        value = self.open("settings", "features")
        self.sandbox.wait_for("settings", "features.list.length", 5)
        value("features.toggle(features.list[4])")
        value("features.grant()")
        self.sandbox.wait_for("settings", "features.list[4].on", True)
        calls = [call for call in self.sandbox.recorded() if call.startswith(("features.py on", "features.py grant"))]
        self.assertEqual(calls, ["features.py grant phone", "features.py on phone"])

    def test_a_refused_switch_shows_why(self):
        self.open("settings", "features")
        self.sandbox.wait_for("settings", "features.list.length", 5)
        self.sandbox.eval("settings", "features.turn('clipboard', 'on')")
        self.sandbox.wait_for("settings", "features.message",
                              '"История буфера обмена" не включена: нужны пакеты cliphist wl-clipboard')

    def test_missing_packages_are_installed_before_switching_on(self):
        value = self.open("settings", "features")
        self.sandbox.wait_for("settings", "features.list.length", 5)
        value("features.toggle(features.list[3])")
        self.assertEqual(value("features.install.item.packages"), ["cliphist", "wl-clipboard"])
        self.sandbox.key("settings", KEY["Escape"])  # declined: the dialog closes, the feature stays off
        self.assertIsNone(value("features.install.item"))
        self.assertTrue(self.sandbox.is_open("settings"))
        self.assertNotIn("features.py on clipboard", self.sandbox.recorded())

        value("features.toggle(features.list[3])")
        value("features.install.start('secret')")  # one password for both packages
        self.sandbox.wait_for("settings", "features.install.phase", "done")
        self.assertEqual(value("features.install.message"), 'Установлено, "История буфера обмена" включена.')
        self.sandbox.wait_for("settings", "features.list[3].on", True)
        calls = self.sandbox.recorded()
        self.assertEqual([call for call in calls if call.startswith("rice-install-package")],
                         ['rice-install-package --notice "История буфера обмена" включена. '
                          "--switch-on clipboard cliphist wl-clipboard"])
        self.assertEqual(calls.count("features.py on clipboard"), 1)

    def test_feature_comes_on_when_its_install_dialog_was_closed(self):
        value = self.open("settings", "features")
        self.sandbox.wait_for("settings", "features.list.length", 5)
        value("features.toggle(features.list[3])")
        value("features.install.start('secret')")
        self.sandbox.wait_for("settings", "features.install.phase", "running")
        self.sandbox.key("settings", KEY["Escape"])  # the install goes on in the background
        self.assertIsNone(value("features.install.item"))
        self.sandbox.wait_for("settings", "features.list[3].on", True)

    def test_launcher_entry_asks_for_the_page(self):
        value = self.open("launcher")
        self.assertEqual(value("menu.commands.find(c => c.id === 'features').run.slice(1)"), ["features"])


@unittest.skipUnless(resident(), "the per-panel theme settings installed packages their own way")
class ThemePackageInstall(MenuTest):
    def test_an_installed_theme_shows_in_the_lists(self):
        value = self.open("settings", "theme:coffee:icons")
        value("themeEdit.askInstall({ package: 'tela-circle-icon-theme-git', title: 'Tela Circle', source: 'aur' }, "
              "'Alt+F2 → Тема → Значки')")
        value("themeEdit.install.start('secret')")
        self.sandbox.wait_for("settings", "themeEdit.install.phase", "done")
        self.assertEqual(value("themeEdit.install.message"), "Установлено. Тема появилась в списке.")
        # The section asked for the list once when it opened, and again after the install.
        self.sandbox._wait(lambda: self.sandbox.recorded().count("themegen.py icon-themes") == 2,
                           "the icon themes were not read again")


@unittest.skipUnless(resident(), "the per-panel menus had no clipboard history")
class Clipboard(MenuTest):
    HISTORY = "3\tgit status\n2\t[[ binary data 120 KiB png 1920x1080 ]]\n1\tssh larion@host\n"

    def open_history(self, on=True):
        (self.sandbox.runtime / "clipboard.tsv").write_text(self.HISTORY)
        (self.sandbox.home / ".config/hypr-rice/features.json").write_text(json.dumps({"clipboard": on}))
        value = self.open("clipboard")
        self.sandbox.wait_for("clipboard", "menu.history.entries.length", 3 if on else 0)
        return value

    def test_entries_newest_first_and_search(self):
        value = self.open_history()
        self.assertEqual(value("menu.history.entries.map(e => e.label)"),
                         ["git status", "картинка 1920×1080, 120 КБ", "ssh larion@host"])
        value("menu.query = 'SSH'")
        self.assertEqual(value("menu.results.map(e => e.id)"), ["1"])

    def test_enter_copies_the_entry_and_closes(self):
        self.open_history()
        self.sandbox.key("clipboard", KEY["Down"])
        self.sandbox.key("clipboard", KEY["Return"])
        self.sandbox.wait_closed("clipboard")
        self.sandbox._wait(lambda: "cliphist decode 2" in self.sandbox.recorded(), "the entry was not decoded")
        self.assertTrue(any(call.startswith("wl-copy") for call in self.sandbox.recorded()))

    def test_delete_removes_one_and_clear_needs_a_second_press(self):
        value = self.open_history()
        self.sandbox.key("clipboard", KEY["Delete"])
        self.sandbox.wait_for("clipboard", "menu.history.entries.map(e => e.id).join()", "2,1")
        value("menu.clear()")
        self.assertEqual(value("menu.history.entries.length"), 2)  # armed, not wiped
        value("menu.clear()")
        self.sandbox.wait_for("clipboard", "menu.history.entries.length", 0)

    def test_switched_off_says_where_to_switch_it_on(self):
        value = self.open_history(on=False)
        self.assertNotIn("cliphist list", self.sandbox.recorded())
        self.assertIn("Функции", value("menu.emptyText"))


class ThemePicker(MenuTest):
    def test_moves_and_tabs(self):
        value = self.open("themes")
        self.assertEqual(value("menu.themes.find(t => t.current).name"), "claude")
        value("menu.index = 0")  # offscreen the pointer sits in the window and selects the card under it
        self.sandbox.key("themes", KEY["Right"])
        self.assertEqual(value("menu.index"), 1)
        self.sandbox.key("themes", KEY["Backtab"])
        self.sandbox.key("themes", KEY["Left"])
        self.assertEqual(value("menu.index"), 2)  # wraps
        self.sandbox.key("themes", KEY["PageDown"])
        self.assertEqual(value("menu.page"), 0)  # one tab only
        self.escape_closes("themes")
        self.assertNotIn("changetheme", " ".join(self.sandbox.recorded()))


class Help(MenuTest):
    def test_sections_from_the_binds(self):
        value = self.open("help")
        self.sandbox.wait_for("help", "menu.sections.length > 3", True)
        titles = value("menu.sections.map(s => s.title)")
        self.assertEqual(titles[:4], ["Приложения", "Окна", "Оформление", "Своя группа"])
        self.assertEqual(value("menu.sections[2].rows[0].keys"), "Alt+Shift+T")
        self.assertEqual(value("menu.sections[3].rows[0].keys"), "Alt+M")

    def test_f1_closes(self):
        self.open("help")
        self.sandbox.key("help", KEY["F1"])
        self.sandbox.wait_closed("help")


class Power(MenuTest):
    def test_arrows_and_arming(self):
        value = self.open("power")
        value("menu.current = 0")
        self.sandbox.key("power", KEY["Right"])
        self.assertEqual(value("menu.current"), 1)
        self.sandbox.key("power", KEY["Return"])
        self.assertEqual(value("menu.armed"), "logout")
        self.assertTrue(self.sandbox.is_open("power"))
        self.sandbox.key("power", KEY["Up"])
        self.assertEqual([value("menu.current"), value("menu.armed")], [0, ""])


class Notifications(MenuTest):
    def test_grouped_by_day_as_plain_text(self):
        value = self.open("notif")
        self.sandbox.wait_for("notif", "menu.items.length", 3)
        rows = value("menu.rows.map(r => r.kind + ':' + (r.label || r.nid))")
        self.assertEqual(rows[:3], ["day:Сегодня", "n:a1", "n:a2"])
        self.assertEqual(rows[3][:4], "day:")
        self.assertEqual(value("menu.plain(menu.items[0].summary + ' ' + menu.items[0].body)"), "Загрузка завершена file &lt;1&gt;.zip")
        self.assertEqual(value("menu.unread"), 2)


class Network(MenuTest):
    def test_networks_from_nmcli(self):
        value = self.open("network")
        self.sandbox.wait_for("network", "net.networks.length", 3)
        self.assertEqual(value("net.fields('Cafe\\\\:Free:802-11-wireless')"), ["Cafe:Free", "802-11-wireless"])
        # In use first, the best signal per name; saved before the rest once nmcli's saved list is in.
        networks = value("net.networks.map(n => [n.ssid, n.signal])")
        self.assertEqual(networks[0], ["Home", 80])
        self.assertCountEqual(networks[1:], [["Cafe:Free", 40], ["Neighbour", 60]])
        self.sandbox.wait_for("network", "net.active ? net.active.ip : ''", "192.168.1.5")


class Games(MenuTest):
    def test_filter_and_escape_out_of_a_dialog(self):
        value = self.open("games")
        self.sandbox.wait_for("games", "menu.games.length", 2)
        value("menu.query = 'port'")
        self.assertEqual(value("menu.shown.map(g => g.name)"), ["Portal 2"])
        value("menu.dialog = 'add'")
        self.sandbox.key("games", KEY["Escape"])
        self.assertEqual(value("menu.dialog"), "")
        self.assertTrue(self.sandbox.is_open("games"))
        self.escape_closes("games")


class Shots(MenuTest):
    def test_preview_then_escape(self):
        value = self.open("shots")
        self.assertEqual(value("menu.stamp('screenshot_20261006_143300.png')"), "6 окт, 14:33")
        value("menu.preview = 0")
        self.sandbox.key("shots", KEY["Escape"])
        self.assertEqual(value("menu.preview"), -1)
        self.escape_closes("shots")


@unittest.skipUnless(resident(), "the per-panel menus have no resident shell")
class Player(MenuTest):
    # The sandbox has no session bus, so no MPRIS player: only the empty state can be seen here.
    def test_without_players_the_card_says_so_and_the_bar_shows_the_icon_alone(self):
        value = self.open("player")
        self.assertIsNone(value("menu.player"))
        self.assertEqual(json.loads(value("Players.barJson"))["class"], "none")
        self.escape_closes("player")


class FakeMpv:
    """mpv's control socket as the wallpaper's player gives it: answers the clip's tracks (one sound track) and
    keeps every command it got."""

    ANSWERS = {"track-list": [{"type": "video"}, {"type": "audio"}], "duration": 100.0, "time-pos": 12.5}

    def __init__(self, path):
        self.received = []
        self.server = socket.socket(socket.AF_UNIX)
        self.server.bind(str(path))
        self.server.listen()
        threading.Thread(target=self.serve, daemon=True).start()

    def serve(self):
        while True:
            try:
                connection, _ = self.server.accept()
            except OSError:  # closed by the test
                return
            with connection, connection.makefile("rw") as stream:
                for line in stream:
                    message = json.loads(line)
                    command = message["command"]
                    self.received.append(command)
                    data = self.ANSWERS.get(command[1]) if command[0] == "get_property" else None
                    stream.write(json.dumps({"data": data, "request_id": message.get("request_id", 0),
                                             "error": "success"}) + "\n")
                    stream.flush()

    def sent(self, name):
        return [command[2] for command in self.received if command[:2] == ["set_property", name]]

    def close(self):
        self.server.close()


@unittest.skipUnless(resident(), "the per-panel menus have no resident shell")
class ClipColour(MenuTest):
    """A theme with ui.json "clipColour" turns the shell's palette grey where its clip is grey."""

    def setUp(self):
        super().setUp()
        theme = self.sandbox.home / ".config/hypr/themes/claude"
        (theme / "assets").mkdir(exist_ok=True)
        (theme / "assets/clip-colour.json").write_text(json.dumps([1] * 12 + [0] * 8 + [1] * 80))
        ui = json.loads((self.sandbox.home / ".config/hypr/ui.json").read_text())
        self.sandbox.write_theme(self.sandbox.palette,
                                 {**ui, "clipColour": {"clip": "clip.mp4", "track": "assets/clip-colour.json"}})
        self.player = FakeMpv(self.sandbox.runtime / "hypr-rice-wallpaper.sock")
        self.player.ANSWERS = {**FakeMpv.ANSWERS, "path": str(theme / "clip.mp4")}
        self.addCleanup(self.player.close)
        self.switch(True)

    def switch(self, on):
        state = self.sandbox.home / ".config/hypr-rice/features.json"
        state.parent.mkdir(parents=True, exist_ok=True)
        state.write_text(json.dumps({"clip-colour": on}))

    def test_the_palette_greys_where_the_clip_does_and_comes_back(self):
        value = self.open("player")
        self.sandbox._ipc(self.sandbox.processes["shell"], "wallpaper", "hidden", "false")
        self.sandbox.wait_for("player", "Theme.colourfulness", 0)  # 12.5 s into the clip
        red, green, blue = (value(f"parseInt(Theme.accent.slice({start}, {start + 2}), 16)") for start in (1, 3, 5))
        self.assertTrue(red == green == blue, value("Theme.accent"))
        self.assertEqual(value("Theme.crit").lower(), self.sandbox.palette["colors"]["crit"].lower(), "crit says something")

        bar = (self.sandbox.home / ".config/hypr-rice/waybar/clip-colours.css").read_text()
        accent = next(line.split()[2].rstrip(";") for line in bar.splitlines() if line.startswith("@define-color accent "))
        self.assertTrue(accent[1:3] == accent[3:5] == accent[5:7], bar)
        self.assertNotIn("crit", bar)
        borders = [call for call in self.sandbox.recorded() if call.startswith("hyprctl eval")]
        self.assertIn('active_border={colors={"#b0b0b0ff","#e4e4e4ff"},angle=45},inactive_border={colors={"#767676ab"}',
                      borders[-1])

        self.player.ANSWERS = {**self.player.ANSWERS, "time-pos": 30.0}
        self.sandbox.wait_for("player", "Theme.colourfulness", 1)
        self.assertEqual(value("Theme.accent").lower(), self.sandbox.palette["colors"]["accent"].lower())
        self.assertEqual((self.sandbox.home / ".config/hypr-rice/waybar/clip-colours.css").read_text(), "")
        borders = [call for call in self.sandbox.recorded() if call.startswith("hyprctl eval")]
        self.assertEqual(borders[-1], 'hyprctl eval hl.config({general={col={active_border={colors={"#e3a857ff","#f3e3c0ff"},'
                                      'angle=45},inactive_border={colors={"#7d746aab"},angle=0}}}})')

    def test_switched_off_the_colours_come_back_at_once(self):
        self.open("player")
        self.sandbox._ipc(self.sandbox.processes["shell"], "wallpaper", "hidden", "false")
        self.sandbox.wait_for("player", "Theme.colourfulness", 0)
        self.switch(False)
        self.sandbox.wait_for("player", "Theme.colourfulness", 1)
        self.assertEqual((self.sandbox.home / ".config/hypr-rice/waybar/clip-colours.css").read_text(), "")
        borders = [call for call in self.sandbox.recorded() if call.startswith("hyprctl eval")]
        self.assertIn('"#e3a857ff","#f3e3c0ff"', borders[-1])

    def test_another_clip_on_the_same_theme_keeps_the_palette(self):
        self.player.ANSWERS = {**self.player.ANSWERS, "path": "/elsewhere/clip.mp4"}
        value = self.open("player")
        self.sandbox._ipc(self.sandbox.processes["shell"], "wallpaper", "hidden", "false")
        self.sandbox.wait_for("player", "Wallpaper.path", "/elsewhere/clip.mp4")
        time.sleep(0.8)
        self.assertEqual(value("Theme.colourfulness"), 1)


@unittest.skipUnless(resident(), "the per-panel menus have no resident shell")
class WallpaperSound(MenuTest):
    def setUp(self):
        super().setUp()
        self.player = FakeMpv(self.sandbox.runtime / "hypr-rice-wallpaper.sock")
        self.addCleanup(self.player.close)

    def switch(self, **features):
        state = self.sandbox.home / ".config/hypr-rice/features.json"
        state.parent.mkdir(parents=True, exist_ok=True)
        state.write_text(json.dumps({key.replace("_", "-"): on for key, on in features.items()}))

    def tell(self, *args):
        return self.sandbox._ipc(self.sandbox.processes["shell"], "wallpaper", *args)

    def test_the_sound_fades_in_and_a_hidden_wallpaper_pauses_only_once_it_faded_out(self):
        self.switch(wallpaper_sound=True, wallpaper_pause=True)
        value = self.open("player")
        self.assertEqual(self.tell("hidden", "false"), "ok")
        self.sandbox.wait_for("player", "Wallpaper.level", 1)
        self.assertEqual(self.player.sent("aid"), ["auto"])
        self.assertEqual(self.player.sent("volume")[-1], 50)
        self.assertEqual(value("Wallpaper.duration"), 100)

        self.tell("hidden", "true")
        self.sandbox.wait_for("player", "Wallpaper.level", 0)
        time.sleep(0.2)
        after_fade = self.player.received[self.player.received.index(["set_property", "volume", 0]):]
        self.assertEqual(after_fade[-2:], [["set_property", "aid", "no"], ["set_property", "pause", True]])

        self.tell("hidden", "false")
        self.sandbox.wait_for("player", "Wallpaper.level", 1)
        self.assertEqual(self.player.sent("pause")[-1], False)

    def test_switched_off_it_stays_silent_and_the_card_switches_it(self):
        self.switch(wallpaper_sound=False, wallpaper_pause=False)
        value = self.open("player")
        self.tell("hidden", "false")
        self.sandbox.wait_for("player", "Wallpaper.hasSound", True)
        self.tell("hidden", "true")
        time.sleep(0.3)
        self.assertEqual((self.player.sent("aid"), self.player.sent("pause")), ([], [False]))
        value("Wallpaper.switchSound()")
        time.sleep(0.5)
        self.assertIn("features.py on wallpaper-sound", self.sandbox.recorded())

    def test_before_the_player_is_stopped_its_sound_fades_out(self):
        self.switch(wallpaper_sound=True)
        self.open("player")
        self.tell("hidden", "false")
        self.sandbox.wait_for("player", "Wallpaper.level", 1)
        self.assertEqual(int(self.tell("silence")), 500)
        self.sandbox.wait_for("player", "Wallpaper.level", 0, timeout=2)
        self.assertEqual(self.player.sent("aid")[-1], "no")
        self.assertEqual(self.tell("silence"), "0")

    def test_the_card_asks_how_far_the_clip_played_only_while_open(self):
        self.switch(wallpaper_sound=False)
        self.open("wallpaper")
        self.tell("hidden", "false")
        self.sandbox.wait_for("wallpaper", "Wallpaper.position", 12.5)
        self.assertEqual(self.sandbox.eval("wallpaper", "Wallpaper.status"), "звук выключен")
        self.escape_closes("wallpaper")
        asked = len([command for command in self.player.received if command == ["get_property", "time-pos"]])
        time.sleep(1.2)
        self.assertEqual(len([command for command in self.player.received if command == ["get_property", "time-pos"]]),
                         asked)

    def test_the_lock_screen_quiets_it_and_the_volume_is_kept(self):
        self.switch(wallpaper_sound=True)
        self.open("player")
        self.tell("hidden", "false")
        self.sandbox.wait_for("player", "Wallpaper.level", 1)
        self.tell("louder")
        self.sandbox.wait_for("player", "Wallpaper.volume", 60)
        self.assertEqual(json.loads((self.sandbox.home / ".config/hypr-rice/wallpaper-sound.json").read_text()),
                         {"volume": 60})
        self.assertEqual(self.tell("locked", "true"), "ok")
        self.sandbox.wait_for("player", "Wallpaper.level", 0)
        self.tell("locked", "false")
        self.sandbox.wait_for("player", "Wallpaper.level", 1)
        self.assertEqual(self.player.sent("volume")[-1], 60)


@unittest.skipUnless(resident(), "the per-panel menus have no resident shell")
class Phone(MenuTest):
    # The sandbox has no session bus and the feature is off: no watcher runs, no phone is known.
    def test_with_the_feature_off_the_menu_says_so_and_the_bar_is_empty(self):
        value = self.open("phone")
        self.assertIn("выключен", value("menu.emptyText()"))
        self.assertEqual(json.loads(value("Phones.barJson")), {"text": "", "tooltip": "", "class": "none"})
        self.escape_closes("phone")

    def test_bar_shows_the_charge_of_a_phone_in_reach(self):
        self.open("phone")
        phone = ('{ name: "A&B", paired: true, reachable: true, battery: { charge: 50, charging: true } }')
        bar = json.loads(self.sandbox.eval("phone", "Phones.barState(" + phone + ")"))
        self.assertEqual(bar, {"text": "\U000f011c 50% \U000f0084", "tooltip": "A&amp;B: заряд 50%, заряжается",
                               "class": "charging"})

    def test_bar_keeps_the_glyph_to_click_while_no_phone_is_paired(self):
        self.open("phone")
        phone = '{ name: "A", paired: false, reachable: true, battery: null }'
        bar = json.loads(self.sandbox.eval("phone", "Phones.barState(" + phone + ")"))
        self.assertEqual(bar, {"text": "\U000f011c", "tooltip": "A: не сопряжён, клик, чтобы сопрячь",
                               "class": "none"})


class ResidentShell(MenuTest):
    def test_toggle_opens_then_closes(self):
        for menu in MENUS:
            with self.subTest(menu=menu):
                self.sandbox.toggle(menu)
                self.sandbox._wait(lambda: self.sandbox.is_open(menu), f"{menu} did not open")
                self.sandbox.toggle(menu)
                self.sandbox.wait_closed(menu)

    def test_screenshot_escape_cancels(self):
        self.sandbox.freeze_screens()
        self.open("shot", "region")
        self.escape_closes("shot")
        self.assertEqual(len(list((self.sandbox.home / "Pictures/screenshots").iterdir())), 2)

    def test_full_screenshot_is_saved(self):
        self.sandbox.freeze_screens()
        self.sandbox.toggle("shot", "full")
        self.sandbox._wait(lambda: len(list((self.sandbox.home / "Pictures/screenshots").iterdir())) == 3, "no screenshot")
        self.sandbox.wait_closed("shot")
        self.assertIn("wl-copy --type image/png", self.sandbox.recorded())

    def test_closed_menu_is_unloaded(self):
        self.open("settings")
        self.sandbox.close("settings")
        self.sandbox.wait_closed("settings")
        self.assertEqual(self.sandbox._ipc(self.sandbox.processes["shell"], "test", "evaluate", "settings",
                                           "menu === null"), "true")


SCRIPTS = {"launcher": ("launcher", ""), "settings-panel": ("settings", "monitors"), "theme-picker": ("themes", ""),
           "help-panel": ("help", ""), "power-menu": ("power", ""), "notif-panel": ("notif", ""),
           "network-panel": ("network", ""), "games": ("games", ""), "shots-gallery": ("shots", ""),
           "player-panel": ("player", ""), "phone-panel": ("phone", ""),
           "wallpaper-panel": ("wallpaper", "")}
# A quickshell that records its arguments; `ipc` fails until `-d` (the start) has run once when $DOWN is set.
FAKE_QUICKSHELL = """#!/bin/sh
printf '%s\\n' "$*" >> "$CALLS"
case "$1" in
    -d) rm -f "$DOWN" ;;
    list) [ -e "$DOWN" ] || echo "  Process ID: 1" ;;
    ipc) [ -e "$DOWN" ] && exit 1; [ "$5" = isOpen ] && echo false ;;
esac
exit 0
"""


@unittest.skipUnless(resident(), "the per-panel menus' scripts started Quickshell themselves")
class LauncherScripts(unittest.TestCase):
    def setUp(self):
        self.sandbox = MenuSandbox()
        self.addCleanup(self.sandbox.cleanup)
        fake = self.sandbox.stubs / "quickshell"
        fake.write_text(FAKE_QUICKSHELL)
        fake.chmod(0o755)
        self.shell = f"{self.sandbox.home}/.config/quickshell/shell"

    def run_script(self, script, *args, down=False):
        env = self.sandbox.env()
        env["DOWN"] = str(self.sandbox.root / "down")
        if down:
            (self.sandbox.root / "down").touch()
        subprocess.run([str(SOURCE_HOME / ".local/bin" / script), *args], env=env, check=True, timeout=10)
        return self.sandbox.recorded()

    def test_each_script_toggles_its_menu(self):
        for script, (menu, argument) in SCRIPTS.items():
            with self.subTest(script=script):
                self.assertIn(f"ipc -p {self.shell} call menus toggle {menu} {argument}".rstrip(),
                              [line.rstrip() for line in self.run_script(script)])

    def test_settings_page_is_passed(self):
        self.assertIn(f"ipc -p {self.shell} call menus toggle settings theme:claude:colors",
                      self.run_script("settings-panel", "theme:claude:colors"))
        self.assertIn(f"ipc -p {self.shell} call menus toggle settings features",
                      self.run_script("settings-panel", "features"))

    def test_media_keys_reach_the_shells_player(self):
        for argument, function in (("play-pause", "togglePlaying"), ("next", "next"), ("previous", "previous")):
            with self.subTest(argument=argument):
                self.assertIn(f"ipc -p {self.shell} call player {function}", self.run_script("player-panel", argument))

    def test_the_bar_asks_the_shell_but_never_starts_it(self):
        env = self.sandbox.env()
        env["DOWN"] = str(self.sandbox.root / "down")
        (self.sandbox.root / "down").touch()
        result = subprocess.run([str(SOURCE_HOME / ".local/bin/player-panel"), "bar"], env=env, capture_output=True,
                                text=True, check=True, timeout=10)
        self.assertEqual(json.loads(result.stdout)["class"], "none")
        self.assertNotIn(f"-d -n -p {self.shell}", self.sandbox.recorded())

    def test_shell_is_started_when_not_running(self):
        calls = self.run_script("power-menu", down=True)
        self.assertIn(f"-d -n -p {self.shell}", calls)
        self.assertEqual(calls[-1].rstrip(), f"ipc -p {self.shell} call menus toggle power")


if __name__ == "__main__":
    unittest.main()
