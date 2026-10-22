#!/usr/bin/env python3
"""JellyVault's VCR on the session bus, as an MPRIS player (mpris.gd starts it): how a Linux desktop hands out the
keyboard's media keys (play/pause, next, previous, stop), and what its own player controls (KDE's media applet,
GNOME's, playerctl) see and press.

stdin, a line of JSON at a time from the game: {"status", "id", "title", "album", "length", "pos", "art"} (seconds).
stdout, a line a press: playpause, play, pause, stop, next, prev, seek <s>, pos <s>, raise, quit.
It goes when stdin does (the game's gone)."""

import json
import os
import sys
import time

from gi.repository import Gio, GLib

NAME = "org.mpris.MediaPlayer2.jellyvault"
PATH = "/org/mpris/MediaPlayer2"
XML = """<node>
<interface name="org.mpris.MediaPlayer2">
  <method name="Raise"/>
  <method name="Quit"/>
  <property name="CanQuit" type="b" access="read"/>
  <property name="CanRaise" type="b" access="read"/>
  <property name="HasTrackList" type="b" access="read"/>
  <property name="Identity" type="s" access="read"/>
  <property name="SupportedUriSchemes" type="as" access="read"/>
  <property name="SupportedMimeTypes" type="as" access="read"/>
</interface>
<interface name="org.mpris.MediaPlayer2.Player">
  <method name="Next"/>
  <method name="Previous"/>
  <method name="Pause"/>
  <method name="PlayPause"/>
  <method name="Stop"/>
  <method name="Play"/>
  <method name="Seek"><arg direction="in" type="x" name="Offset"/></method>
  <method name="SetPosition"><arg direction="in" type="o" name="TrackId"/><arg direction="in" type="x" name="Position"/></method>
  <method name="OpenUri"><arg direction="in" type="s" name="Uri"/></method>
  <signal name="Seeked"><arg type="x" name="Position"/></signal>
  <property name="PlaybackStatus" type="s" access="read"/>
  <property name="Rate" type="d" access="readwrite"/>
  <property name="Metadata" type="a{sv}" access="read"/>
  <property name="Volume" type="d" access="readwrite"/>
  <property name="Position" type="x" access="read"/>
  <property name="MinimumRate" type="d" access="read"/>
  <property name="MaximumRate" type="d" access="read"/>
  <property name="CanGoNext" type="b" access="read"/>
  <property name="CanGoPrevious" type="b" access="read"/>
  <property name="CanPlay" type="b" access="read"/>
  <property name="CanPause" type="b" access="read"/>
  <property name="CanSeek" type="b" access="read"/>
  <property name="CanControl" type="b" access="read"/>
</interface>
</node>"""
PRESS = {"PlayPause": "playpause", "Play": "play", "Pause": "pause", "Stop": "stop", "Next": "next", "Previous": "prev", "Raise": "raise", "Quit": "quit"}

state = {"status": "Stopped"}
heard_at = time.monotonic()  # (when the last line came: Position runs on from it, while it's playing)
conn = None
loop = GLib.MainLoop()
partial = b""


def say(line):
    print(line, flush=True)


def position():  # in seconds
    pos = state.get("pos", 0.0)
    if state.get("status") == "Playing":
        pos += time.monotonic() - heard_at
    return min(pos, state["length"]) if state.get("length") else pos


def metadata():
    if state.get("status") == "Stopped":
        return {"mpris:trackid": GLib.Variant("o", "/org/mpris/MediaPlayer2/TrackList/NoTrack")}
    m = {
        "mpris:trackid": GLib.Variant("o", PATH + "/track/" + ("".join(c if c.isalnum() else "_" for c in state.get("id", "")) or "none")),
        "xesam:title": GLib.Variant("s", state.get("title", "")),
    }
    if state.get("album"):
        m["xesam:album"] = GLib.Variant("s", state["album"])
    if state.get("length"):
        m["mpris:length"] = GLib.Variant("x", int(state["length"] * 1e6))
    if state.get("art"):
        m["mpris:artUrl"] = GLib.Variant("s", state["art"])
    return m


def prop(name):
    playing = state.get("status") != "Stopped"
    return {
        "CanQuit": GLib.Variant("b", True),
        "CanRaise": GLib.Variant("b", True),
        "HasTrackList": GLib.Variant("b", False),
        "Identity": GLib.Variant("s", "JellyVault"),
        "SupportedUriSchemes": GLib.Variant("as", []),
        "SupportedMimeTypes": GLib.Variant("as", []),
        "PlaybackStatus": GLib.Variant("s", state.get("status", "Stopped")),
        "Rate": GLib.Variant("d", 1.0),
        "Metadata": GLib.Variant("a{sv}", metadata()),
        "Volume": GLib.Variant("d", 1.0),
        "Position": GLib.Variant("x", int(position() * 1e6)),
        "MinimumRate": GLib.Variant("d", 1.0),
        "MaximumRate": GLib.Variant("d", 1.0),
        "CanGoNext": GLib.Variant("b", playing),
        "CanGoPrevious": GLib.Variant("b", playing),
        "CanPlay": GLib.Variant("b", playing),
        "CanPause": GLib.Variant("b", playing),
        "CanSeek": GLib.Variant("b", playing),
        "CanControl": GLib.Variant("b", True),
    }[name]


def on_call(_conn, _sender, _path, _iface, method, args, invocation):
    if method in PRESS:
        say(PRESS[method])
    elif method == "Seek":
        say("seek %f" % (args[0] / 1e6))
    elif method == "SetPosition":
        say("pos %f" % (args[1] / 1e6))
    invocation.return_value(None)


def on_get(_conn, _sender, _path, _iface, name):
    return prop(name)


def on_set(*_args):  # (Rate and Volume: the game's own, not ours to change)
    return True


def changed(names):
    if conn is not None and names:
        conn.emit_signal(None, PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged", GLib.Variant(
            "(sa{sv}as)", ("org.mpris.MediaPlayer2.Player", {n: prop(n) for n in names}, [])))


def heard(new):
    global state, heard_at
    was, expected = state, position()
    state, heard_at = new, time.monotonic()
    names = []
    if new.get("status") != was.get("status"):
        names += ["PlaybackStatus", "CanGoNext", "CanGoPrevious", "CanPlay", "CanPause", "CanSeek"]
    if any(new.get(k) != was.get(k) for k in ("id", "title", "album", "length", "art")) or new.get("status") == "Stopped" != was.get("status"):
        names.append("Metadata")
    changed(names)
    if conn is not None and new.get("status") != "Stopped" and new.get("id") == was.get("id") and abs(new.get("pos", 0.0) - expected) > 2.0:
        conn.emit_signal(None, PATH, "org.mpris.MediaPlayer2.Player", "Seeked", GLib.Variant("(x)", (int(new.get("pos", 0.0) * 1e6),)))


def on_stdin(fd, _cond):
    global partial
    chunk = os.read(fd, 65536)
    if not chunk:
        loop.quit()
        return False
    partial += chunk
    *lines, partial = partial.split(b"\n")
    for line in lines:
        try:
            heard(json.loads(line))
        except ValueError:
            pass
    return True


def on_bus(c, _name):
    global conn
    conn = c
    node = Gio.DBusNodeInfo.new_for_xml(XML)
    for iface in node.interfaces:
        if hasattr(c, "register_object_with_closures2"):  # (PyGObject 3.52 on; register_object's deprecated there)
            c.register_object_with_closures2(PATH, iface, on_call, on_get, on_set)
        else:
            c.register_object(PATH, iface, on_call, on_get, on_set)


GLib.io_add_watch(sys.stdin.fileno(), GLib.PRIORITY_DEFAULT, GLib.IOCondition.IN | GLib.IOCondition.HUP, on_stdin)
Gio.bus_own_name(Gio.BusType.SESSION, NAME, Gio.BusNameOwnerFlags.NONE, on_bus, None, lambda *_: loop.quit())
loop.run()
