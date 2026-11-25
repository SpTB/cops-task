"""Preview geometry and latest-only transport checks without opening an X window."""
import importlib.util
import json
import os
from pathlib import Path
import socket
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('overlay_viewer', Path(__file__).with_name('cops_overlay_viewer.py'))
viewer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(viewer)


class Recorder:
    def __init__(self): self.calls = []
    def __getattr__(self, name):
        def record(*args): self.calls.append((name, args))
        return record


class FakeViewer:
    instance = None
    def __init__(self, config):
        FakeViewer.instance = self
        self.frames = []; self.exposed = False; self.x = Recorder(); self.d = 0; self.window = 0
    def closed(self): return False
    def draw(self, frame): self.frames.append(frame)


class OverlayTests(unittest.TestCase):
    def test_missing_gaze_is_filtered_and_single_point_shape_is_supported(self):
        self.assertEqual(viewer.points([960, 540]), [[960, 540]])
        self.assertEqual(viewer.points([[960, 540], [None, 540], [float('nan'), 3]]), [[960, 540]])
        self.assertEqual(viewer.points([]), [])

    def test_native_coordinates_and_colors(self):
        v = object.__new__(viewer.Viewer); v.source = [100, 50, 2020, 1130]; v.scale = .5
        self.assertEqual(v.point([1060, 590]), [480, 270])
        self.assertEqual(viewer.rgb(128), (128, 128, 128))
        self.assertEqual(viewer.rgb([300, -2, 15]), (255, 0, 15))

    def test_renderer_handles_validation_targets_missing_gaze_and_reward(self):
        v = object.__new__(viewer.Viewer)
        v.x = Recorder(); v.d = 1; v.window = 2; v.pixmap = 3; v.gc = 4
        v.source = [0, 0, 1920, 1080]; v.scale = .5; v.width = 960; v.height = 540
        v.color = lambda color: None
        v.draw({'active': True, 'showFixation': True, 'fixationRect': [900, 500, 1020, 580],
                'validationTarget': [960, 540], 'validationTargetSize': 20,
                'gazePositions': [[None, None], [980, 560]], 'gazeColors': [255, 0, 0],
                'showReward': True})
        dots = [args for name, args in v.x.calls if name == 'XFillArc']
        self.assertEqual(len(dots), 2)
        self.assertTrue(any(name == 'XDrawString' for name, _ in v.x.calls))
        self.assertEqual(v.x.calls[-1][0], 'XFlush')

    def test_latest_sequence_wins_and_wrong_session_is_ignored(self):
        with tempfile.TemporaryDirectory() as folder:
            ready = Path(folder, 'ready.json'); config = Path(folder, 'config.json')
            config.write_text(json.dumps({'readyFile': str(ready), 'parentPid': os.getpid(),
                                           'token': 'session', 'rateHz': 30, 'backgroundColor': 128}))
            with patch.object(viewer, 'Viewer', FakeViewer):
                errors = []
                def run():
                    try: viewer.main(config)
                    except Exception as err: errors.append(err)
                thread = threading.Thread(target=run, daemon=True); thread.start()
                deadline = time.monotonic()+2
                while not ready.exists() and time.monotonic()<deadline: time.sleep(.005)
                self.assertTrue(ready.exists())
                address = ('127.0.0.1', json.loads(ready.read_text())['port'])
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                    def send(sequence, token='session'):
                        sock.sendto(json.dumps({'token': token, 'sequence': sequence,
                                               'frame': {'value': sequence}}).encode(), address)
                    sock.sendto(b'bad-json', address)
                    send(1); send(3); send(2); send(99, 'wrong-session')
                    deadline = time.monotonic()+2
                    while not any(f.get('value') == 3 for f in FakeViewer.instance.frames) and time.monotonic()<deadline:
                        time.sleep(.005)
                    values = [f['value'] for f in FakeViewer.instance.frames if 'value' in f]
                    self.assertEqual(values[-1], 3)
                    self.assertNotIn(99, values)
                    sock.sendto(json.dumps({'token': 'session', 'close': True}).encode(), address)
                thread.join(2)
                self.assertFalse(thread.is_alive())
                self.assertEqual(errors, [])


if __name__ == '__main__': unittest.main()
