r"""Windows EXE smoke test with isolated preview ports and synthetic motion.

Run: .venv\Scripts\python.exe tests/check_packaged_motion.py
Does not drive XInput or change Eden. This cannot verify physical phone motion.
"""
import asyncio
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

from aiohttp import ClientSession

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from test_motion import DATA, reference_crc, request, sample


def free_port(kind):
    with socket.socket(socket.AF_INET, kind) as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


async def main():
    http_port, dsu_port = free_port(socket.SOCK_STREAM), free_port(socket.SOCK_DGRAM)
    exe = Path(__file__).resolve().parents[1] / 'dist' / 'Phone Controller.exe'
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = subprocess.SW_HIDE
    process = subprocess.Popen([str(exe), '--simulate', '--port', str(http_port),
                                '--dsu-port', str(dsu_port), '--auto-close', '30'], startupinfo=startup)
    sockets = []
    frames = []
    config = None
    stopped = False
    try:
        async with ClientSession(f'http://localhost:{http_port}') as session:
            deadline = time.monotonic() + 15
            while True:
                try:
                    async with session.get('/api/bootstrap') as response:
                        config = await response.json()
                    break
                except OSError:
                    if time.monotonic() > deadline or process.poll() is not None:
                        raise AssertionError('Packaged server did not start')
                    await asyncio.sleep(.1)
            assert config['mode'] == 'preview'
            assert config['motion']['available'], config['motion']
            key = parse_qs(urlsplit(config['addresses'][0]['url']).fragment)['key'][0]
            async def join(i):
                ws = await session.ws_connect('/ws')
                sockets.append(ws)
                await ws.send_json(dict(type='join', key=key, client=f'packaged-test-{i}'))
                joined = await ws.receive_json()
                assert joined['type'] == 'joined'
                frame = dict(type='input', epoch=joined['epoch'], state={})
                if joined['player'] % 2 == 1:
                    frame['motion'] = sample(joined['player'])
                frames.append((ws, frame))
                await ws.send_json(frame)
                await ws.send_json(dict(type='ping'))
                assert (await ws.receive_json())['type'] == 'pong'
                return joined['player']
            assert sorted(await asyncio.gather(*(join(i) for i in range(4)))) == [1, 2, 3, 4]

            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
                udp.setblocking(False)
                loop = asyncio.get_running_loop()
                async def stream():
                    sequence = 10
                    while True:
                        sequence += 1
                        for ws, frame in frames:
                            if 'motion' in frame:
                                frame['motion'] = sample(sequence)
                            await ws.send_json(frame)
                        await asyncio.sleep(1/30)
                sender = asyncio.create_task(stream())
                await loop.sock_sendto(udp, request(DATA, bytes(8)), ('127.0.0.1', dsu_port))
                observed = {}
                async def receive():
                    data, _ = await asyncio.wait_for(loop.sock_recvfrom(udp, 1024), 2)
                    assert len(data) == 100 and data[:4] == b'DSUS'
                    assert int.from_bytes(data[8:12], 'little') == reference_crc(data[:8]+bytes(4)+data[12:])
                    return data
                deadline = time.monotonic() + 3
                try:
                    while len(observed) < 4:
                        assert time.monotonic() < deadline, 'Expected motion slots did not become active'
                        data = await receive()
                        if data[21] == (2 if data[20] % 2 == 0 else 0):
                            observed[data[20]] = data
                finally:
                    sender.cancel()
                    try:
                        await sender
                    except asyncio.CancelledError:
                        pass
                for i in (0, 2):
                    assert struct.unpack_from('<6f', observed[i], 76) == (.25, -.5, -1, 90, -180, 45)
                print('PASS packaged WebSocket -> DSU: four mixed clients, independent slots and valid CRC/axes')

                # Source samples must expire even while the socket stays connected.
                await asyncio.sleep(.3)
                deadline = time.monotonic() + 2
                cleared = set()
                while len(cleared) < 2:
                    assert time.monotonic() < deadline, 'Stale motion did not clear'
                    data = await receive()
                    if data[20] in (0, 2) and data[21] == 0:
                        assert struct.unpack_from('<6f', data, 76) == (0, 0, -1, 0, 0, 0)
                        cleared.add(data[20])
                print('PASS packaged stale motion becomes neutral')

                # Stop the desktop while connections and a DSU subscription exist.
                async with session.post('/api/stop', headers={'X-Admin-Token':config['adminToken']}) as response:
                    assert response.status == 200
                await asyncio.to_thread(process.wait, 10)
                stopped = True
            for ws in sockets:
                await ws.close()
        for kind, port in ((socket.SOCK_STREAM, http_port), (socket.SOCK_DGRAM, dsu_port)):
            with socket.socket(socket.AF_INET, kind) as probe:
                probe.bind(('127.0.0.1', port))
        assert process.returncode == 0
        print('PASS packaged desktop shutdown exits and releases TCP/UDP ports')
    finally:
        # The test-owned process has a 30-second self-close fallback, including on assertion failure.
        if not stopped and process.poll() is None:
            try:
                if config:
                    async with ClientSession(f'http://localhost:{http_port}') as cleanup:
                        async with cleanup.post('/api/stop', headers={'X-Admin-Token':config['adminToken']}):
                            pass
            finally:
                await asyncio.to_thread(process.wait, 35)


if __name__ == '__main__':
    asyncio.run(main())
