"""Independent X11 preview. Receive latest-only UDP state; never control the task."""
import ctypes as C
import ctypes.util
import json
import math
import os
from pathlib import Path
import select
import socket
import sys
import time


def points(value):
    if not value:
        return []
    if not isinstance(value[0], list):
        value = [value]
    return [p for p in value if len(p) == 2 and all(v is not None and math.isfinite(v) for v in p)]


def rgb(value):
    if not isinstance(value, list):
        value = [value] * 3
    return tuple(max(0, min(255, round(v))) for v in value[:3])


class XColor(C.Structure):
    _fields_ = [('pixel', C.c_ulong), ('red', C.c_ushort), ('green', C.c_ushort),
                ('blue', C.c_ushort), ('flags', C.c_byte), ('pad', C.c_byte)]


class ClientMessage(C.Structure):
    _fields_ = [('type', C.c_int), ('serial', C.c_ulong), ('send_event', C.c_int),
                ('display', C.c_void_p), ('window', C.c_ulong), ('message_type', C.c_ulong),
                ('format', C.c_int), ('data', C.c_long * 5)]


class WMHints(C.Structure):
    _fields_ = [('flags', C.c_long), ('input', C.c_int), ('initial_state', C.c_int),
                ('icon_pixmap', C.c_ulong), ('icon_window', C.c_ulong),
                ('icon_x', C.c_int), ('icon_y', C.c_int), ('icon_mask', C.c_ulong),
                ('window_group', C.c_ulong)]


class SizeHints(C.Structure):
    _fields_ = [('flags', C.c_long), ('values', C.c_int * 16), ('win_gravity', C.c_int)]


class Viewer:
    def __init__(self, config):
        self.x = C.CDLL(ctypes.util.find_library('X11'))
        signatures = {
            'XOpenDisplay': ([C.c_char_p], C.c_void_p),
            'XDefaultScreen': ([C.c_void_p], C.c_int),
            'XRootWindow': ([C.c_void_p, C.c_int], C.c_ulong),
            'XDefaultDepth': ([C.c_void_p, C.c_int], C.c_int),
            'XDefaultColormap': ([C.c_void_p, C.c_int], C.c_ulong),
            'XAllocColor': ([C.c_void_p, C.c_ulong, C.POINTER(XColor)], C.c_int),
            'XCreateSimpleWindow': ([C.c_void_p, C.c_ulong, C.c_int, C.c_int, C.c_uint, C.c_uint,
                                     C.c_uint, C.c_ulong, C.c_ulong], C.c_ulong),
            'XCreatePixmap': ([C.c_void_p, C.c_ulong, C.c_uint, C.c_uint, C.c_uint], C.c_ulong),
            'XCreateGC': ([C.c_void_p, C.c_ulong, C.c_ulong, C.c_void_p], C.c_void_p),
            'XSetForeground': ([C.c_void_p, C.c_void_p, C.c_ulong], C.c_int),
            'XFillRectangle': ([C.c_void_p, C.c_ulong, C.c_void_p, C.c_int, C.c_int, C.c_uint, C.c_uint], C.c_int),
            'XDrawRectangle': ([C.c_void_p, C.c_ulong, C.c_void_p, C.c_int, C.c_int, C.c_uint, C.c_uint], C.c_int),
            'XDrawArc': ([C.c_void_p, C.c_ulong, C.c_void_p, C.c_int, C.c_int, C.c_uint, C.c_uint, C.c_int, C.c_int], C.c_int),
            'XFillArc': ([C.c_void_p, C.c_ulong, C.c_void_p, C.c_int, C.c_int, C.c_uint, C.c_uint, C.c_int, C.c_int], C.c_int),
            'XDrawLine': ([C.c_void_p, C.c_ulong, C.c_void_p, C.c_int, C.c_int, C.c_int, C.c_int], C.c_int),
            'XDrawString': ([C.c_void_p, C.c_ulong, C.c_void_p, C.c_int, C.c_int, C.c_char_p, C.c_int], C.c_int),
            'XCopyArea': ([C.c_void_p, C.c_ulong, C.c_ulong, C.c_void_p, C.c_int, C.c_int, C.c_uint, C.c_uint, C.c_int, C.c_int], C.c_int),
            'XStoreName': ([C.c_void_p, C.c_ulong, C.c_char_p], C.c_int),
            'XSetWMHints': ([C.c_void_p, C.c_ulong, C.POINTER(WMHints)], C.c_int),
            'XSetWMNormalHints': ([C.c_void_p, C.c_ulong, C.POINTER(SizeHints)], None),
            'XInternAtom': ([C.c_void_p, C.c_char_p, C.c_int], C.c_ulong),
            'XSetWMProtocols': ([C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong), C.c_int], C.c_int),
            'XSelectInput': ([C.c_void_p, C.c_ulong, C.c_long], C.c_int),
            'XMapWindow': ([C.c_void_p, C.c_ulong], C.c_int),
            'XPending': ([C.c_void_p], C.c_int),
            'XNextEvent': ([C.c_void_p, C.c_void_p], C.c_int),
            'XFlush': ([C.c_void_p], C.c_int),
            'XCloseDisplay': ([C.c_void_p], C.c_int),
        }
        for name, (args, result) in signatures.items():
            fn = getattr(self.x, name)
            fn.argtypes, fn.restype = args, result
        display = config['display'].encode()
        self.d = self.x.XOpenDisplay(display)
        if not self.d:
            raise RuntimeError(f'Cannot open X11 display {display!r}')
        screen = self.x.XDefaultScreen(self.d)
        x, y, right, bottom = config['windowRect']
        self.width, self.height = round(right-x), round(bottom-y)
        self.window = self.x.XCreateSimpleWindow(self.d, self.x.XRootWindow(self.d, screen),
            round(x), round(y), self.width, self.height, 0, 0, 0)
        self.gc = self.x.XCreateGC(self.d, self.window, 0, None)
        self.pixmap = self.x.XCreatePixmap(self.d, self.window, self.width, self.height,
            self.x.XDefaultDepth(self.d, screen))
        self.colormap = self.x.XDefaultColormap(self.d, screen)
        self.colors = {}
        self.source = config['screenRect']
        self.scale = min(self.width/(self.source[2]-self.source[0]), self.height/(self.source[3]-self.source[1]))
        self.x.XStoreName(self.d, self.window, b'CoPs experimenter preview')
        hints = WMHints(); hints.flags = 1; hints.input = 0
        self.x.XSetWMHints(self.d, self.window, C.byref(hints))
        sizes = SizeHints(); sizes.flags = (1 << 4) | (1 << 5)  # PMinSize | PMaxSize.
        sizes.values[4:8] = self.width, self.height, self.width, self.height
        self.x.XSetWMNormalHints(self.d, self.window, C.byref(sizes))
        self.exposed = False
        self.delete_atom = self.x.XInternAtom(self.d, b'WM_DELETE_WINDOW', 0)
        atom = C.c_ulong(self.delete_atom)
        self.x.XSetWMProtocols(self.d, self.window, C.byref(atom), 1)
        self.x.XSelectInput(self.d, self.window, 1 << 15)  # ExposureMask; no keyboard capture.
        self.x.XMapWindow(self.d, self.window)
        self.x.XFlush(self.d)

    def color(self, value):
        key = rgb(value)
        if key not in self.colors:
            c = XColor(0, *(v*257 for v in key), 7, 0)
            self.x.XAllocColor(self.d, self.colormap, C.byref(c))
            self.colors[key] = c.pixel
        self.x.XSetForeground(self.d, self.gc, self.colors[key])

    def point(self, p):
        return [round((p[i]-self.source[i])*self.scale) for i in range(2)]

    def dot(self, p, size, color):
        x, y = self.point(p)
        diameter = max(1, round(size*self.scale))
        self.color(color)
        self.x.XFillArc(self.d, self.pixmap, self.gc, x-diameter//2, y-diameter//2,
                       diameter, diameter, 0, 360*64)

    def draw(self, f):
        self.color(f.get('backgroundColor', 128))
        self.x.XFillRectangle(self.d, self.pixmap, self.gc, 0, 0, self.width, self.height)
        if f.get('active', False):
            if f.get('showFixation', False):
                r = f['fixationRect']; x, y = self.point(r[:2]); right, bottom = self.point(r[2:])
                self.color(f.get('foregroundColor', 255))
                self.x.XDrawRectangle(self.d, self.pixmap, self.gc, x, y, max(1,right-x), max(1,bottom-y))
            self.color(f.get('circleColor', 255))
            radius = max(1, round(f.get('circleRadiusPx', 0)*self.scale))
            for p in points(f.get('targetPositions', [])):
                x, y = self.point(p)
                self.x.XDrawArc(self.d, self.pixmap, self.gc, x-radius, y-radius, 2*radius, 2*radius, 0, 360*64)
            if f.get('showCenter', False):
                x, y = self.point(f['centerPx']); r = max(1, round(f['centerHalfSizePx']*self.scale))
                self.color(f['centerColor'])
                self.x.XDrawLine(self.d, self.pixmap, self.gc, x-r, y, x+r, y)
                self.x.XDrawLine(self.d, self.pixmap, self.gc, x, y-r, x, y+r)
            gaze = f.get('gazePositions', [])
            if gaze and not isinstance(gaze[0], list): gaze = [gaze]
            colors = f.get('gazeColors', [255, 0, 0])
            for i, p in enumerate(gaze):
                if points([p]):
                    color = colors[min(i, len(colors)-1)] if isinstance(colors[0], list) else colors
                    self.dot(p, f.get('gazeDotSize', 16), color)
            for p in points(f.get('validationTarget', [])):
                self.dot(p, f.get('validationTargetSize', 10), f.get('foregroundColor', 255))
            for p in points(f.get('pointerPositions', [])):
                self.dot(p, 3, [0, 255, 0])
        if f.get('showReward', False):
            self.color(f.get('foregroundColor', 255)); x, y = self.point([100, 100])
            self.x.XDrawString(self.d, self.pixmap, self.gc, x, y, b'REWARD', 6)
        self.x.XCopyArea(self.d, self.pixmap, self.window, self.gc, 0, 0, self.width, self.height, 0, 0)
        self.x.XFlush(self.d)

    def closed(self):
        event = (C.c_long * 24)()
        while self.x.XPending(self.d):
            self.x.XNextEvent(self.d, C.byref(event))
            client = C.cast(C.byref(event), C.POINTER(ClientMessage)).contents
            if client.type == 33 and client.data[0] == self.delete_atom:
                return True
            if client.type == 12:
                self.exposed = True
        return False


def main(config_file):
    config = json.loads(Path(config_file).read_text())
    viewer = Viewer(config)
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.bind(('127.0.0.1', 0)); sock.setblocking(False)
            ready = Path(config['readyFile'])
            temporary = ready.with_suffix('.tmp')
            temporary.write_text(json.dumps({'port': sock.getsockname()[1], 'pid': os.getpid(),
                                             'window': viewer.window}))
            temporary.replace(ready)
            frame = {'backgroundColor': config['backgroundColor']}
            viewer.draw(frame)
            next_draw = 0; next_parent_check = 0; dirty = False; last_sequence = -1
            received = 0; rendered = 0
            while not viewer.closed():
                now = time.monotonic()
                if now >= next_parent_check:
                    try: os.kill(config['parentPid'], 0)
                    except ProcessLookupError: break
                    next_parent_check = now+1
                    if 'statusFile' in config:
                        status = {'received': received, 'rendered': rendered, 'lastSequence': last_sequence}
                        Path(config['statusFile']).write_text(json.dumps(status))
                select.select([sock], [], [], min(.01, max(0, next_draw-now)) if dirty else .01)
                latest = None
                for _ in range(256):  # Bound queue work; retain only the newest valid sequence.
                    try:
                        packet = json.loads(sock.recv(65535))
                        if packet.get('token') != config['token']: continue
                        if packet.get('close'): return
                        if packet['sequence'] > last_sequence:
                            last_sequence = packet['sequence']; latest = packet['frame']; received += 1
                    except BlockingIOError: break
                    except (ValueError, KeyError, TypeError): continue
                if latest is not None: frame = latest; dirty = True
                if viewer.exposed: dirty = True; viewer.exposed = False
                if dirty and time.monotonic() >= next_draw:
                    viewer.draw(frame); dirty = False; rendered += 1
                    next_draw = time.monotonic()+1/config['rateHz']
    finally:
        viewer.x.XCloseDisplay(viewer.d)


if __name__ == '__main__':
    main(sys.argv[1])
