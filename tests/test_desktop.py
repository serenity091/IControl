import asyncio
import json
import socket
import time
import unittest
from urllib.request import urlopen
from aiohttp import ClientSession
from desktop import ServerThread


class DesktopLifecycleTests(unittest.TestCase):
    def test_close_stops_server_and_live_connection(self):
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        server = ServerThread(port, simulate=True)
        server.start()
        try:
            kind, data = server.events.get(timeout=10)
            self.assertEqual(kind, "ready", data)
            async def connected_shutdown():
                async with ClientSession(f"http://localhost:{port}") as client:
                    ws = await client.ws_connect("/ws")
                    await ws.send_json({"key": server.hub.token, "client": "desktop-test"})
                    self.assertEqual((await ws.receive_json())["type"], "joined")
                    server.stop()
                    await asyncio.wait_for(ws.receive(), 5)
                    await ws.close()
            asyncio.run(connected_shutdown())
            server.thread.join(5)
            self.assertFalse(server.thread.is_alive())
            self.assertEqual(server.hub.output.pads, {})
            with socket.socket() as probe:
                self.assertNotEqual(probe.connect_ex(("127.0.0.1", port)), 0)
        finally:
            server.stop()
            server.thread.join(5)

    def test_port_conflict_does_not_stop_existing_server(self):
        with socket.socket() as occupied:
            occupied.bind(("0.0.0.0", 0))
            occupied.listen()
            port = occupied.getsockname()[1]
            server = ServerThread(port, simulate=True)
            server.start()
            server.thread.join(5)
            self.assertFalse(server.thread.is_alive())
            kind, _ = server.events.get(timeout=1)
            self.assertEqual(kind, "error")
            with socket.socket() as probe:
                self.assertEqual(probe.connect_ex(("127.0.0.1", port)), 0)
