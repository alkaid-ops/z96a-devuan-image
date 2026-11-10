#!/usr/bin/python3
import sys
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk

window = Gtk.Window()
window.set_title("Z96A lock underlay test")
window.set_decorated(False)
window.move(0, 0)
window.resize(1024, 768)
window.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)


def clicked(_window, _event):
    with open(sys.argv[1], "a", encoding="ascii") as output:
        output.write("click\n")
    return True


window.connect("button-press-event", clicked)
window.show_all()
Gtk.main()
