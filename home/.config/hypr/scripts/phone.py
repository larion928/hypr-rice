#!/usr/bin/env python3
"""The phones KDE Connect knows, for the phone menu (services/Phones.qml).

kdeconnectd (rice-kdeconnect.service, feature "kdeconnect") keeps them on the session bus: the daemon at
/modules/kdeconnect, a device at /modules/kdeconnect/devices/<id>, a device's plugins below it (battery, ping,
findmyphone, share, clipboard, sftp). No call here starts the daemon: with the feature off it is not running,
and `watch` reports that instead of bringing it up.
"""
import json
import subprocess
import sys
from pathlib import Path

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402  (gi.require_version has to come first)

from command_table import Command, run  # noqa: E402

BUS_NAME = "org.kde.kdeconnect"
DAEMON_PATH = "/modules/kdeconnect"
DAEMON = "org.kde.kdeconnect.daemon"
DEVICE = "org.kde.kdeconnect.device"
PROPERTIES = "org.freedesktop.DBus.Properties"


class PhoneError(Exception):
    pass


def bus():
    try:
        return Gio.bus_get_sync(Gio.BusType.SESSION, None)
    except GLib.Error as error:
        raise PhoneError(f"Нет сессионной шины D-Bus: {error.message}") from error


def call(connection, path, interface, method, args=None, reply="()"):
    try:
        result = connection.call_sync(BUS_NAME, path, interface, method, args, GLib.VariantType(reply),
                                      Gio.DBusCallFlags.NO_AUTO_START, 10000, None)
    except GLib.Error as error:
        raise PhoneError(f"KDE Connect не ответил ({method}): {error.message}") from error
    return result.unpack()


def device_path(device_id):
    return f"{DAEMON_PATH}/devices/{device_id}"


def properties(connection, path, interface):
    return call(connection, path, PROPERTIES, "GetAll", GLib.Variant("(s)", (interface,)), "(a{sv})")[0]


def battery(connection, device_id, plugins):
    if "kdeconnect_battery" not in plugins:
        return None
    values = properties(connection, device_path(device_id) + "/battery", DEVICE + ".battery")
    if not values.get("hasBattery"):
        return None
    return {"charge": values.get("charge", -1), "charging": values.get("isCharging", False)}


def device(connection, device_id):
    path = device_path(device_id)
    values = properties(connection, path, DEVICE)
    paired = values.get("isPaired", False)
    reachable = values.get("isReachable", False)
    plugins = call(connection, path, DEVICE, "loadedPlugins", reply="(as)")[0] if paired and reachable else []
    return {"id": device_id, "name": values.get("name", device_id), "type": values.get("type", ""),
            "reachable": reachable, "paired": paired,
            "requested": values.get("isPairRequested", False),
            "requestedByPeer": values.get("isPairRequestedByPeer", False),
            "key": values.get("verificationKey", ""),
            "battery": battery(connection, device_id, plugins) if plugins else None}


def snapshot(connection):
    """{"running": false} while the daemon is not on the bus; else every device it knows, paired or seen."""
    try:
        ids = call(connection, DAEMON_PATH, DAEMON, "devices", GLib.Variant("(b)", (False,)), "(as)")[0]
        return {"running": True, "devices": [device(connection, device_id) for device_id in ids]}
    except PhoneError:
        return {"running": False, "devices": []}


def watch():
    """A line of JSON (snapshot) at start and after every change KDE Connect signals, until killed."""
    connection = bus()
    loop = GLib.MainLoop()
    pending = []

    def report():
        pending.clear()
        print(json.dumps(snapshot(connection), ensure_ascii=False), flush=True)
        return GLib.SOURCE_REMOVE

    # One change (a phone coming into reach) arrives as a burst of signals: one line for all of them.
    def changed(*_):
        if not pending:
            pending.append(GLib.timeout_add(200, report))

    connection.signal_subscribe(BUS_NAME, None, None, None, None, Gio.DBusSignalFlags.NONE, changed)
    # Calls back at once, whether the daemon is there or not: that gives the first line.
    Gio.bus_watch_name_on_connection(connection, BUS_NAME, Gio.BusNameWatcherFlags.NONE, changed, changed)
    loop.run()


def plugin_call(device_id, plugin, method, args=None):
    call(bus(), f"{device_path(device_id)}/{plugin}", f"{DEVICE}.{plugin}", method, args)


def ping(device_id):
    plugin_call(device_id, "ping", "sendPing")


def ring(device_id):
    plugin_call(device_id, "findmyphone", "ring")


def send_clipboard(device_id):
    plugin_call(device_id, "clipboard", "sendClipboard")


def share(device_id, paths):
    urls = [Path(path).resolve().as_uri() for path in paths]
    plugin_call(device_id, "share", "shareUrls", GLib.Variant("(as)", (urls,)))


def picked_files():
    """The files picked in zenity's window, none when it was cancelled."""
    result = subprocess.run(["zenity", "--file-selection", "--multiple", "--separator=\n",
                             "--title=Отправить на телефон"], capture_output=True, text=True)
    return [line for line in result.stdout.splitlines() if line]


def share_picked(device_id):
    files = picked_files()
    if files:
        share(device_id, files)


def browse(device_id):
    """The phone's storage mounted over sftp (sshfs), opened in Thunar."""
    connection = bus()
    path = device_path(device_id) + "/sftp"
    interface = DEVICE + ".sftp"
    if not call(connection, path, interface, "mountAndWait", reply="(b)")[0]:
        reason = call(connection, path, interface, "getMountError", reply="(s)")[0]
        problem = f"Файлы телефона не открылись: {reason or 'KDE Connect не сказал почему'}"
        notify(problem)  # the menu closed when the files were asked for
        raise PhoneError(problem)
    mount_point = call(connection, path, interface, "mountPoint", reply="(s)")[0]
    subprocess.Popen(["thunar", mount_point], start_new_session=True)


def pairing(method):
    return lambda device_id: call(bus(), device_path(device_id), DEVICE, method)


def notify(text):
    subprocess.run(["notify-send", "-a", "KDE Connect", "-i", "kdeconnect", "Телефон", text])


ERRORS = (PhoneError, OSError)
COMMANDS = {
    "watch": Command(watch, "", "a JSON line with every device at start and after each change", ERRORS),
    "ping": Command(ping, "<id>", "a ping notification on the phone", ERRORS),
    "ring": Command(ring, "<id>", "the phone rings, to be found", ERRORS),
    "clipboard": Command(send_clipboard, "<id>", "the clipboard to the phone", ERRORS),
    "share": Command(share_picked, "<id>", "files picked in a window, to the phone", ERRORS),
    "browse": Command(browse, "<id>", "the phone's files in Thunar", ERRORS),
    "pair": Command(pairing("requestPairing"), "<id>", "asks the phone to pair", ERRORS),
    "accept": Command(pairing("acceptPairing"), "<id>", "accepts the phone's pairing request", ERRORS),
    "reject": Command(pairing("cancelPairing"), "<id>", "turns down or withdraws a pairing request", ERRORS),
    "unpair": Command(pairing("unpair"), "<id>", "forgets the pairing", ERRORS),
}

if __name__ == "__main__":
    sys.exit(run("phone.py", COMMANDS, sys.argv[1:]))
