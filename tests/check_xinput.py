r"""Manual Windows end-to-end check against a running, idle IControl server.

Run: .venv\Scripts\python.exe tests\check_xinput.py
This presses test inputs on virtual controllers briefly. Do not run during a game.
"""
import asyncio
import ctypes as c
from urllib.parse import urlsplit, parse_qs

from aiohttp import ClientSession


class Gamepad(c.Structure):
    _fields_ = [("buttons", c.c_ushort), ("lt", c.c_ubyte), ("rt", c.c_ubyte),
                ("lx", c.c_short), ("ly", c.c_short), ("rx", c.c_short), ("ry", c.c_short)]


class State(c.Structure):
    _fields_ = [("packet", c.c_ulong), ("gamepad", Gamepad)]


api = c.WinDLL("xinput1_4")
api.XInputGetState.argtypes = [c.c_uint, c.POINTER(State)]
api.XInputGetState.restype = c.c_uint


def read():
    pads = []
    for index in range(4):
        state = State()
        if api.XInputGetState(index, c.byref(state)) == 0:
            pads.append((index, state.gamepad))
    return pads


async def main():
    async with ClientSession("http://localhost:8080") as session:
        async with session.get("/api/bootstrap") as response:
            config = await response.json()
        assert config["mode"] == "live" and not config["error"], "Server must have live output"
        assert not any(p["connected"] or p["reserved"] for p in config["players"]), "Release all phone slots first"
        assert config["controllerCount"] == 0, "Idle server should not create controllers"
        baseline_count = len(read())
        assert baseline_count == 0, "Disconnect physical XInput devices before this four-device test"
        key = parse_qs(urlsplit(config["addresses"][0]["url"]).fragment)["key"][0]
        sockets, players = [], []
        try:
            for i, button in enumerate(["A", "B", "X", "Y"]):
                ws = await session.ws_connect("/ws")
                sockets.append(ws)
                await ws.send_json({"key": key, "client": f"xinput-check-{i}", "name": f"Output test {i+1}"})
                message = await ws.receive_json()
                assert message["type"] == "joined", message
                players.append(message["player"])
                async with session.get('/api/status') as response:
                    assert (await response.json())["controllerCount"] == i+1
                await ws.send_json({"type": "input", "state": {"buttons": [button], "lx": .5, "ly": -.5, "rx": -.25, "ry": .25, "zl": 1, "zr": .5}})
            for attempt in range(20):
                for ws, button in zip(sockets, ["A", "B", "X", "Y"]):
                    await ws.send_json({"type": "input", "state": {"buttons": [button], "lx": .5, "ly": -.5, "rx": -.25, "ry": .25, "zl": 1, "zr": .5}})
                await asyncio.sleep(.1)
                reports = read()
                if len(reports) == 4 and all(p.buttons for _, p in reports):
                    break
            assert len(reports) == 4, f"Expected 4 XInput devices, got {len(reports)}"
            assert {p.buttons for _, p in reports} == {0x2000, 0x1000, 0x8000, 0x4000}, "Buttons did not arrive as four distinct devices"
            for index, pad in reports:
                assert abs(pad.lx-16383) <= 1 and abs(pad.ly+16383) <= 1, f"Left stick mismatch on {index}"
                assert abs(pad.rx+8191) <= 1 and abs(pad.ry-8191) <= 1, f"Right stick mismatch on {index}"
                assert pad.lt == 255 and abs(pad.rt-127.5) <= .5, f"Trigger mismatch on {index}: {pad.lt}, {pad.rt}"
                print(f"PASS XInput {index}: button=0x{pad.buttons:04x}, both sticks and triggers match")
        finally:
            for ws in sockets:
                await ws.close()
            for player in players:
                async with session.post(f"/api/players/{player}/release", headers={"X-Admin-Token": config["adminToken"]}) as response:
                    assert response.status == 200
        for _ in range(20):
            if not read():
                break
            await asyncio.sleep(.1)
        assert not read(), "Virtual controllers remained after phones disconnected"
        print("PASS Windows controller count scaled from 0 to 4 and back to 0")


if __name__ == "__main__":
    asyncio.run(main())
