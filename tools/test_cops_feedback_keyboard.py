"""Live X11 regression: feedback must reach the box, never the focused desktop.

Run explicitly with: python3 tools/test_cops_feedback_keyboard.py
Uses a temporary window and synthetic input; releases the keyboard on exit.
Requires Linux/X11 and the system X11/XTest libraries, with no Python packages.
"""
import ctypes as c
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import time
import unittest

sys.dont_write_bytecode = True
from cops_feedback_keyboard import Event


@unittest.skipUnless(sys.platform.startswith('linux') and os.environ.get('DISPLAY'),
                     'Requires a Linux/X11 desktop')
class FeedbackKeyboardTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            cls.x = c.CDLL('libX11.so.6')
            cls.xt = c.CDLL('libXtst.so.6')
        except OSError as error:
            raise unittest.SkipTest(str(error))
        cls.x.XOpenDisplay.argtypes = [c.c_char_p]
        cls.x.XOpenDisplay.restype = c.c_void_p
        cls.x.XDefaultRootWindow.argtypes = [c.c_void_p]
        cls.x.XDefaultRootWindow.restype = c.c_ulong
        cls.x.XCreateSimpleWindow.argtypes = [c.c_void_p, c.c_ulong, c.c_int, c.c_int,
            c.c_uint, c.c_uint, c.c_uint, c.c_ulong, c.c_ulong]
        cls.x.XCreateSimpleWindow.restype = c.c_ulong
        functions = {
            'XMapWindow': [c.c_void_p, c.c_ulong],
            'XSelectInput': [c.c_void_p, c.c_ulong, c.c_long],
            'XSetInputFocus': [c.c_void_p, c.c_ulong, c.c_int, c.c_ulong],
            'XGetInputFocus': [c.c_void_p, c.POINTER(c.c_ulong), c.POINTER(c.c_int)],
            'XFlush': [c.c_void_p], 'XPending': [c.c_void_p],
            'XNextEvent': [c.c_void_p, c.POINTER(Event)],
            'XDestroyWindow': [c.c_void_p, c.c_ulong],
            'XCloseDisplay': [c.c_void_p], 'XSync': [c.c_void_p, c.c_int],
        }
        for name, args in functions.items():
            getattr(cls.x, name).argtypes = args
        cls.x.XKeysymToKeycode.argtypes = [c.c_void_p, c.c_ulong]
        cls.x.XKeysymToKeycode.restype = c.c_ubyte
        cls.xt.XTestFakeKeyEvent.argtypes = [c.c_void_p, c.c_uint, c.c_int, c.c_ulong]

    def setUp(self):
        self.process = None
        self.held = set()
        self.display = self.x.XOpenDisplay(None)
        self.assertTrue(self.display)
        self.focus, self.revert = c.c_ulong(), c.c_int()
        self.x.XGetInputFocus(self.display, c.byref(self.focus), c.byref(self.revert))
        self.window = self.x.XCreateSimpleWindow(self.display,
            self.x.XDefaultRootWindow(self.display), 20, 20, 100, 100, 0, 0, 0)
        self.x.XSelectInput(self.display, self.window, 3)  # KeyPress and KeyRelease
        self.x.XMapWindow(self.display, self.window)
        self.x.XSync(self.display, False)
        time.sleep(0.3)  # Let the window manager map it before assigning focus.
        self.x.XSetInputFocus(self.display, self.window, 2, 0)
        self.x.XSync(self.display, False)
        self.desktop_events()  # Discard pre-grab focus/keyboard state events.
        self.process = subprocess.Popen(
            [sys.executable, str(Path(__file__).with_name('cops_feedback_keyboard.py'))],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            bufsize=0)
        self.assertEqual(self.receive(), {'ready': True})

    def tearDown(self):
        for code in self.held:
            self.xt.XTestFakeKeyEvent(self.display, code, 0, 0)
        self.x.XFlush(self.display)
        if self.process is not None:
            if self.process.poll() is None:
                self.process.kill()
            self.process.wait(timeout=3)
            for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
                if stream and not stream.closed:
                    stream.close()
        self.x.XSetInputFocus(self.display, self.focus, self.revert, 0)
        self.x.XDestroyWindow(self.display, self.window)
        self.x.XCloseDisplay(self.display)

    def receive(self):
        self.assertTrue(select.select([self.process.stdout], [], [], 3)[0],
                        'Timed out waiting for captured feedback')
        return json.loads(self.process.stdout.readline())

    def key(self, symbol, pressed):
        code = self.x.XKeysymToKeycode(self.display, symbol)
        self.xt.XTestFakeKeyEvent(self.display, code, pressed, 0)
        if pressed:
            self.held.add(code)
        else:
            self.held.discard(code)
        self.x.XFlush(self.display)

    def desktop_events(self):
        events = []
        self.x.XSync(self.display, False)
        while self.x.XPending(self.display):
            event = Event()
            self.x.XNextEvent(self.display, c.byref(event))
            if event.type in (2, 3):
                events.append(event.type)
        return events

    def test_feedback_and_held_enter_do_not_echo_then_keyboard_is_restored(self):
        text = 'jkdfjsfsmdflksfjkjfs'
        captured = ''
        for char in text:
            self.key(ord(char), 1)
            self.key(ord(char), 0)
            captured += chr(self.receive()['CookedKey'])
        self.assertEqual(captured, text)
        self.assertEqual(self.desktop_events(), [], 'Feedback reached the desktop')
        self.key(0xFF0D, 1)  # Hold Return while the parent requests release.
        self.assertEqual(self.receive()['CookedKey'], 13)
        self.process.stdin.write(b'stop\n')
        self.process.stdin.flush()
        time.sleep(0.15)
        self.assertIsNone(self.process.poll(), 'Released a held submit key too soon')
        self.key(0xFF0D, 0)
        self.assertEqual(self.process.wait(timeout=3), 0)
        self.assertEqual(self.desktop_events(), [], 'Submit key reached the desktop')
        self.key(ord('z'), 1)
        self.key(ord('z'), 0)
        time.sleep(0.05)
        self.assertEqual(self.desktop_events(), [2, 3], 'Keyboard was not restored')

    def test_parent_input_disconnect_releases_keyboard(self):
        self.process.stdin.close()
        self.assertEqual(self.process.wait(timeout=3), 0)


if __name__ == '__main__':
    unittest.main()
