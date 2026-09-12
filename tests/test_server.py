import asyncio
import unittest
from aiohttp.test_utils import AioHTTPTestCase

from server import Hub, Slot, create_app, neutral, sanitize


class RecordingOutput:
    error = None
    simulate = True

    def __init__(self):
        self.states = [neutral() for _ in range(4)]
        self.pads = {}

    def attach(self, index):
        self.pads[index] = True

    def detach(self, index):
        self.pads.pop(index, None)

    def apply(self, index, state):
        self.states[index] = state

    def close(self):
        pass


class StateTests(unittest.TestCase):
    def test_rejects_nonfinite_and_wrong_shapes(self):
        for data in (None, [], {"buttons": "A"}, {"lx": float("nan")}, {"ry": float("inf")}, {"zl": True}, {"lx": 10**400}):
            with self.subTest(data=data), self.assertRaises(ValueError):
                sanitize(data)

    def test_clamps_axes_and_filters_unknown_buttons(self):
        result = sanitize({"buttons": ["A", "A", "unknown", {}], "lx": 8, "ry": -3, "zl": -1})
        self.assertEqual(result["buttons"], ["A"])
        self.assertEqual((result["lx"], result["ry"], result["zl"]), (1, -1, 0))


class IntegrationTests(AioHTTPTestCase):
    async def get_application(self):
        self.output = RecordingOutput()
        self.hub = Hub(output=self.output)
        return create_app(self.hub)

    async def join(self, client="device-001", key=None):
        ws = await self.client.ws_connect("/ws")
        await ws.send_json({"key": key if key is not None else self.hub.token, "client": client, "name": client})
        return ws, await ws.receive_json()

    async def test_four_independent_players_and_fifth_rejected(self):
        self.assertEqual(len(self.output.pads), 0)
        sockets = []
        for i in range(4):
            ws, message = await self.join(f"device-00{i}")
            sockets.append(ws)
            self.assertEqual(message["player"], i+1)
            self.assertEqual(len(self.output.pads), i+1)
            await ws.send_json({"type": "input", "state": {"buttons": ["A"], "lx": i/4}})
        await asyncio.sleep(.05)
        self.assertEqual([s["lx"] for s in self.output.states], [0,.25,.5,.75])
        fifth, message = await self.join("device-fifth")
        self.assertEqual(message["type"], "error")
        self.assertIn("four", message["message"])
        await fifth.close()
        for ws in sockets:
            await ws.close()

    async def test_disconnect_resets_and_reconnect_reclaims_slot(self):
        ws, _ = await self.join()
        await ws.send_json({"type": "input", "state": {"buttons": ["A"], "zl": 1}})
        await asyncio.sleep(.03)
        self.assertEqual(self.output.states[0]["buttons"], ["A"])
        await ws.close()
        await asyncio.sleep(.03)
        self.assertEqual(self.output.states[0], neutral())
        self.assertEqual(len(self.output.pads), 0)
        other, message = await self.join("device-002")
        self.assertEqual(message["player"], 2)
        again, message = await self.join()
        self.assertEqual(message["player"], 1)
        self.assertEqual(set(self.output.pads), {0, 1})
        await again.close()
        await other.close()

    async def test_watchdog_releases_without_disconnect(self):
        ws, _ = await self.join()
        await ws.send_json({"type": "input", "state": {"buttons": ["R"], "rx": 1}})
        await asyncio.sleep(1)
        self.assertEqual(self.output.states[0], neutral())
        self.assertTrue(self.hub.status()["players"][0]["connected"])
        await ws.close()

    async def test_stale_queued_input_cannot_reactivate_after_timeout(self):
        ws, _ = await self.join()
        await ws.send_json({"type": "input", "state": {"lx": 1}})
        await asyncio.sleep(.03)
        self.hub.slots[0].last_input -= 1
        # Even if this packet arrives before the next watchdog tick, it is stale.
        await ws.send_json({"type": "input", "state": {"lx": 1}})
        reset = await ws.receive_json()
        self.assertEqual(reset["type"], "reset")
        self.assertEqual(self.output.states[0], neutral())
        # Knowing the new generation isn't enough: the phone must clear first.
        await ws.send_json({"type": "input", "epoch": reset["epoch"], "state": {"lx": 1}})
        await asyncio.sleep(.03)
        self.assertEqual(self.output.states[0], neutral())
        await ws.send_json({"type": "input", "epoch": reset["epoch"], "state": neutral()})
        await ws.send_json({"type": "input", "epoch": reset["epoch"], "state": {"rx": -.5}})
        await asyncio.sleep(.03)
        self.assertEqual(self.output.states[0]["rx"], -.5)
        await ws.close()

    async def test_healthy_stationary_hold_survives_keepalives(self):
        ws, _ = await self.join()
        for _ in range(8):
            await ws.send_json({"type": "input", "state": {"lx": 1}})
            await asyncio.sleep(.15)
            self.assertEqual(self.output.states[0]["lx"], 1)
        await ws.close()

    async def test_released_connection_cannot_write_to_reused_slot(self):
        ws, _ = await self.join()
        self.hub.slots[0] = Slot(client="new-owner")
        await ws.send_json({"type": "input", "state": {"lx": 1}})
        await ws.receive()
        self.assertEqual(self.output.states[0], neutral())
        await ws.close()

    async def test_pairing_secret_required(self):
        ws, message = await self.join(key="invalid")
        self.assertEqual(message["type"], "error")
        self.assertFalse(any(p["connected"] for p in self.hub.status()["players"]))
        await ws.close()

    async def test_duplicate_phone_cannot_reset_current_connection(self):
        ws, _ = await self.join()
        await ws.send_json({"type": "input", "state": {"buttons": ["X"]}})
        duplicate, message = await self.join()
        self.assertEqual(message["type"], "error")
        self.assertEqual(self.output.states[0]["buttons"], ["X"])
        await duplicate.close()
        await ws.close()

    async def test_malformed_input_disconnects_and_releases(self):
        ws, _ = await self.join()
        await ws.send_json({"type": "input", "state": {"buttons": ["X"]}})
        await ws.send_str('{"type":"input","state":{"lx":"bad"}}')
        await ws.receive()
        await asyncio.sleep(.03)
        self.assertEqual(self.output.states[0], neutral())
        await ws.close()

    async def test_admin_release_requires_token_and_frees_slot(self):
        ws, _ = await self.join()
        response = await self.client.post("/api/players/1/release")
        self.assertEqual(response.status, 403)
        response = await self.client.post("/api/players/1/release", headers={"X-Admin-Token": self.hub.admin_token})
        self.assertEqual(response.status, 200)
        await ws.receive()
        await ws.close()
        new, message = await self.join("device-002")
        self.assertEqual(message["player"], 1)
        await new.close()

    async def test_dashboard_origin_and_qr(self):
        response = await self.client.get("/api/bootstrap", headers={"Host": "untrusted.example"})
        self.assertEqual(response.status, 403)
        response = await self.client.get("/api/qr")
        self.assertEqual(response.status, 200)
        self.assertIn("svg", await response.text())
        response = await self.client.get("/api/qr?ip=evil.example")
        self.assertEqual(response.status, 400)
        response = await self.client.get("/play")
        self.assertEqual(response.status, 200)


if __name__ == "__main__":
    unittest.main()
