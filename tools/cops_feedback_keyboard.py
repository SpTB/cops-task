"""Capture X11 feedback typing without forwarding it to MATLAB's desktop.

The parent keeps stdin open for the lifetime of the feedback screen. Closing
stdin requests release; parent termination also closes it. No third party
Python packages are needed. stdout carries newline-delimited JSON events.
"""
import ctypes as c
import json
import os
import select
import sys


class KeyEvent(c.Structure):
    _fields_ = [
        ('type', c.c_int), ('serial', c.c_ulong), ('send_event', c.c_int),
        ('display', c.c_void_p), ('window', c.c_ulong), ('root', c.c_ulong),
        ('subwindow', c.c_ulong), ('time', c.c_ulong), ('x', c.c_int),
        ('y', c.c_int), ('x_root', c.c_int), ('y_root', c.c_int),
        ('state', c.c_uint), ('keycode', c.c_uint), ('same_screen', c.c_int),
    ]


class Event(c.Union):
    _fields_ = [('type', c.c_int), ('key', KeyEvent), ('padding', c.c_long * 24)]


def emit(message):
    print(json.dumps(message, ensure_ascii=True), flush=True)


def capture():
    x = c.CDLL('libX11.so.6')
    x.XOpenDisplay.argtypes = [c.c_char_p]
    x.XOpenDisplay.restype = c.c_void_p
    x.XDefaultRootWindow.argtypes = [c.c_void_p]
    x.XDefaultRootWindow.restype = c.c_ulong
    x.XConnectionNumber.argtypes = [c.c_void_p]
    x.XGrabKeyboard.argtypes = [c.c_void_p, c.c_ulong, c.c_int, c.c_int, c.c_int, c.c_ulong]
    x.XUngrabKeyboard.argtypes = [c.c_void_p, c.c_ulong]
    x.XPending.argtypes = [c.c_void_p]
    x.XNextEvent.argtypes = [c.c_void_p, c.POINTER(Event)]
    x.XFlush.argtypes = [c.c_void_p]
    x.XCloseDisplay.argtypes = [c.c_void_p]
    x.XQueryKeymap.argtypes = [c.c_void_p, c.c_void_p]
    x.XLookupString.argtypes = [c.POINTER(KeyEvent), c.c_void_p, c.c_int,
                               c.POINTER(c.c_ulong), c.c_void_p]
    x.XOpenIM.argtypes = [c.c_void_p, c.c_void_p, c.c_char_p, c.c_char_p]
    x.XOpenIM.restype = c.c_void_p
    x.XCreateIC.argtypes = [c.c_void_p]  # Remaining arguments are variadic.
    x.XCreateIC.restype = c.c_void_p
    x.XSetICFocus.argtypes = [c.c_void_p]
    x.XDestroyIC.argtypes = [c.c_void_p]
    x.XCloseIM.argtypes = [c.c_void_p]
    x.Xutf8LookupString.argtypes = [c.c_void_p, c.POINTER(KeyEvent), c.c_void_p,
                                   c.c_int, c.POINTER(c.c_ulong), c.POINTER(c.c_int)]
    display = x.XOpenDisplay(None)
    if not display:
        raise RuntimeError('Cannot open the X11 display for participant feedback.')
    grabbed = False
    im = ic = None
    try:
        root = x.XDefaultRootWindow(display)
        # owner_events=False sends all core keyboard events to this client,
        # including keys otherwise destined for MATLAB's command window.
        status = x.XGrabKeyboard(display, root, 0, 1, 1, 0)
        if status != 0:
            raise RuntimeError(f'Cannot capture feedback keyboard (X11 status {status}).')
        grabbed = True
        im = x.XOpenIM(display, None, None, None)
        if im:
            ic = x.XCreateIC(im, c.c_char_p(b'inputStyle'), c.c_ulong(0x408),
                             c.c_char_p(b'clientWindow'), c.c_ulong(root), c.c_void_p())
            if ic:
                x.XSetICFocus(ic)
        x.XFlush(display)
        emit({'ready': True})
        stopping = False
        parent_pid = os.getppid()
        fd = x.XConnectionNumber(display)
        while True:
            if os.getppid() != parent_pid:
                break
            # Process a stop/EOF even while key-repeat events keep arriving.
            if not stopping and select.select([sys.stdin], [], [], 0)[0]:
                if not sys.stdin.readline():
                    break  # Parent exited without the normal stop handshake.
                stopping = True
            if stopping:
                state = c.create_string_buffer(32)
                x.XQueryKeymap(display, state)
                if not any(state.raw):
                    break  # Consume the final ENTER release before ungrabbing.
            if not x.XPending(display):
                select.select([fd] if stopping else [fd, sys.stdin], [], [], 0.01)
                continue
            event = Event()
            x.XNextEvent(display, c.byref(event))
            if event.type != 2 or stopping:  # KeyPress only
                continue
            buffer = c.create_string_buffer(128)
            symbol = c.c_ulong()
            if ic:
                result = c.c_int()
                count = x.Xutf8LookupString(ic, c.byref(event.key), buffer, 127,
                                             c.byref(symbol), c.byref(result))
                if count > 127:  # XBufferOverflow; use a correctly sized buffer.
                    buffer = c.create_string_buffer(count + 1)
                    count = x.Xutf8LookupString(ic, c.byref(event.key), buffer, count,
                                                 c.byref(symbol), c.byref(result))
                text = buffer.raw[:count].decode('utf-8', errors='replace')
            else:
                count = x.XLookupString(c.byref(event.key), buffer, 127, c.byref(symbol), None)
                text = buffer.raw[:count].decode('latin-1')
            if symbol.value == 0xFFC1:  # F4 remains an operator skip command.
                emit({'Pressed': True, 'CookedKey': -1, 'QuitRequested': True})
            else:
                for char in text:
                    emit({'Pressed': True, 'CookedKey': ord(char)})
    finally:
        if ic:
            x.XDestroyIC(ic)
        if im:
            x.XCloseIM(im)
        if grabbed:
            x.XUngrabKeyboard(display, 0)
            x.XFlush(display)
        x.XCloseDisplay(display)


if __name__ == '__main__':
    try:
        capture()
    except (Exception, KeyboardInterrupt) as error:
        emit({'error': str(error)})
        sys.exit(1)
