"""Run real iPhone -> native WebSocket -> Python -> DSU test without logging keys.

First build-for-testing for a signed physical device. Start a LAN preview server.
Pass the generated .xctestrun and device UDID; credentials exist only in a
mode-0600 temporary xctestrun beside the original, deleted after the test.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import socket
import struct
import subprocess
import tempfile
import threading
import time
from urllib.request import urlopen
import zlib


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--xctestrun', type=Path, required=True)
    parser.add_argument('--device', required=True)
    parser.add_argument('--port', type=int, default=8088)
    args = parser.parse_args()
    with urlopen(f'http://localhost:{args.port}/api/bootstrap') as response:
        bootstrap = json.load(response)
    if bootstrap['mode'] != 'preview' or not bootstrap['motion']['available']:
        parser.error('An available preview-mode DSU bridge is required')
    if any(p['connected'] for p in bootstrap['players']):
        parser.error('Disconnect other preview clients before this isolated test')
    configuration = plistlib.loads(args.xctestrun.read_bytes())
    def inject(value):
        if isinstance(value, dict):
            if 'TestBundlePath' in value:
                value.setdefault('EnvironmentVariables', {})['ICONTROL_TEST_PAIR_URL'] = bootstrap['addresses'][0]['url']
            for child in value.values(): inject(child)
        elif isinstance(value, list):
            for child in value: inject(child)
    inject(configuration)
    observations = dict(packets=0, active_packets=0, invalid_crc=0, neutral_after_active=False)
    stopped = threading.Event()
    def receive():
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
            udp.bind(('127.0.0.1', 0)); udp.settimeout(.2)
            next_subscription = 0
            while not stopped.is_set():
                if time.monotonic() >= next_subscription:
                    data = bytearray(struct.pack('<4sHHIII', b'DSUC', 1001, 12, 0, 0x12345678, 0x100002) + bytes(8))
                    struct.pack_into('<I', data, 8, zlib.crc32(data))
                    udp.sendto(data, ('127.0.0.1', bootstrap['motion']['port']))
                    next_subscription = time.monotonic()+1
                try: data, _ = udp.recvfrom(1024)
                except socket.timeout: continue
                if len(data) != 100: continue
                observations['packets'] += 1
                if int.from_bytes(data[8:12], 'little') != zlib.crc32(data[:8]+bytes(4)+data[12:]):
                    observations['invalid_crc'] += 1
                if data[20] != 0: continue
                if data[21] == 2:
                    observations['active_packets'] += 1
                elif observations['active_packets'] and struct.unpack_from('<3f', data, 88) == (0,0,0):
                    observations['neutral_after_active'] = True
    thread = threading.Thread(target=receive); thread.start()
    # Relative __TESTROOT__ paths must still resolve to the build products.
    descriptor, path = tempfile.mkstemp(suffix='.xctestrun', prefix='icontrol-private-', dir=args.xctestrun.parent)
    try:
        with os.fdopen(descriptor, 'wb') as output: plistlib.dump(configuration, output)
        result = subprocess.run(['xcodebuild', 'test-without-building', '-xctestrun', path,
                                 '-destination', f'platform=iOS,id={args.device}',
                                 '-only-testing:IControlTests/DeviceMotionTests'], check=False)
    finally:
        Path(path).unlink(missing_ok=True)
        stopped.set(); thread.join(2)
    print(json.dumps(observations, indent=2))
    if result.returncode or observations['active_packets'] < 30 or observations['invalid_crc'] or not observations['neutral_after_active']:
        raise SystemExit('Physical end-to-end validation failed; inspect the test results')

if __name__ == '__main__': main()
