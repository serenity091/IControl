"""IControl: a local, four-player phone-to-XInput bridge."""
import argparse
import asyncio
import contextlib
import io
import ipaddress
import json
import math
import secrets
import socket
import time
import webbrowser
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import urlsplit

import qrcode
import qrcode.image.svg
from aiohttp import web, WSMsgType

ROOT = Path(__file__).parent
BUTTONS = {
    "A": 0x1000, "B": 0x2000, "X": 0x4000, "Y": 0x8000,
    "UP": 1, "DOWN": 2, "LEFT": 4, "RIGHT": 8,
    "PLUS": 0x10, "MINUS": 0x20, "L3": 0x40, "R3": 0x80,
    "L": 0x100, "R": 0x200, "HOME": 0x400,
}


def neutral():
    return {"buttons": [], "lx": 0, "ly": 0, "rx": 0, "ry": 0, "zl": 0, "zr": 0}


def sanitize(data):
    if not isinstance(data, dict):
        raise ValueError("Expected controller state")
    buttons = data.get("buttons", [])
    if not isinstance(buttons, list) or len(buttons) > 32:
        raise ValueError("Invalid buttons")
    result = neutral()
    result["buttons"] = sorted({b for b in buttons if isinstance(b, str) and b in BUTTONS})
    for axis in ("lx", "ly", "rx", "ry", "zl", "zr"):
        value = data.get(axis, 0)
        try:
            finite = not isinstance(value, bool) and isinstance(value, (float, int)) and math.isfinite(value)
        except OverflowError:
            finite = False
        if not finite:
            raise ValueError("Invalid axis")
        result[axis] = max(0 if axis in ("zl", "zr") else -1, min(1, value))
    return result


class Output:
    def __init__(self, simulate=False):
        self.pads = {}
        self.vg = None
        self.error = None
        self.simulate = simulate
        if not simulate:
            try:
                import vgamepad as vg
                self.vg = vg
            except Exception as exc:
                self.error = f"Virtual controllers unavailable: {exc}. Install ViGEmBus and restart IControl."
                self.pads.clear()

    def attach(self, index):
        if index not in self.pads:
            self.pads[index] = None if self.simulate else self.vg.VX360Gamepad()

    def detach(self, index):
        if index in self.pads:
            self.apply(index, neutral())
            del self.pads[index]

    def apply(self, index, state):
        pad = self.pads.get(index)
        if pad is None:
            return
        pad.reset()
        for button in state["buttons"]:
            pad.press_button(button=BUTTONS[button])
        pad.left_joystick_float(x_value_float=state["lx"], y_value_float=state["ly"])
        pad.right_joystick_float(x_value_float=state["rx"], y_value_float=state["ry"])
        pad.left_trigger_float(value_float=state["zl"])
        pad.right_trigger_float(value_float=state["zr"])
        pad.update()

    def close(self):
        for index in list(self.pads):
            self.detach(index)


@dataclass
class Slot:
    client: str = ""
    name: str = ""
    ws: object = None
    last_input: float = 0
    reserved_until: float = 0
    state: dict = field(default_factory=neutral)
    epoch: int = 0
    awaiting_reset: bool = False
    announced_epoch: int = -1


def lan_addresses():
    addresses = []
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        try:
            sock.connect(("192.0.2.1", 80))
            addresses.append(sock.getsockname()[0])
        except OSError:
            pass
    try:
        addresses.extend(socket.gethostbyname_ex(socket.gethostname())[2])
    except OSError:
        pass
    return list(dict.fromkeys(a for a in addresses if not ipaddress.ip_address(a).is_loopback)) or ["127.0.0.1"]


class Hub:
    def __init__(self, port=8080, simulate=False, output=None):
        self.port = port
        self.token = secrets.token_urlsafe(24)
        self.admin_token = secrets.token_urlsafe(24)
        self.instance = secrets.token_hex(8)
        self.addresses = lan_addresses()
        self.output = output if output is not None else Output(simulate)
        self.slots = [Slot() for _ in range(4)]

    def reset(self, index):
        self.slots[index].state = neutral()
        self.output.apply(index, neutral())

    def expire_inputs(self, index, now):
        slot = self.slots[index]
        if slot.ws is not None and not slot.awaiting_reset and now-slot.last_input > .75:
            self.reset(index)
            slot.epoch += 1
            slot.awaiting_reset = True

    def join_url(self, address):
        return f"http://{address}:{self.port}/play#key={self.token}"

    def status(self):
        return {
            "app": "IControl",
            "instance": self.instance,
            "controllerCount": len(self.output.pads),
            "maxPlayers": 4,
            "mode": "preview" if self.output.simulate else "live",
            "error": self.output.error,
            "players": [{"player": i + 1, "connected": s.ws is not None,
                         "name": s.name, "reserved": s.ws is None and s.reserved_until > time.monotonic(),
                         "state": s.state} for i, s in enumerate(self.slots)],
        }

    async def watchdog(self):
        while True:
            await asyncio.sleep(.15)
            now = time.monotonic()
            for i, slot in enumerate(self.slots):
                self.expire_inputs(i, now)
                if slot.ws is None and slot.reserved_until < now:
                    slot.client = slot.name = ""


HUB_KEY = web.AppKey("hub", Hub)


def local_admin(request):
    # Both peer and Host must be local, preventing LAN access and DNS rebinding.
    host = urlsplit("http://" + request.host).hostname
    try:
        local = ipaddress.ip_address(request.remote).is_loopback
    except ValueError:
        local = False
    if not local or host not in ("localhost", "127.0.0.1", "::1"):
        raise web.HTTPForbidden(text="Open the laptop dashboard at http://localhost:8080")


@web.middleware
async def headers(request, handler):
    response = await handler(request)
    response.headers.update({"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff",
                             "Referrer-Policy": "no-referrer", "X-Frame-Options": "DENY",
                             "Content-Security-Policy": "default-src 'self'; connect-src 'self' ws:; style-src 'self' 'unsafe-inline'; img-src 'self' data:; frame-ancestors 'none'"})
    return response


async def dashboard(request):
    local_admin(request)
    return web.FileResponse(ROOT / "static" / "index.html")


async def play(request):
    return web.FileResponse(ROOT / "static" / "play.html")


async def bootstrap(request):
    local_admin(request)
    hub = request.app[HUB_KEY]
    return web.json_response({**hub.status(), "adminToken": hub.admin_token,
                              "addresses": [{"ip": a, "url": hub.join_url(a)} for a in hub.addresses]})


async def status(request):
    local_admin(request)
    return web.json_response(request.app[HUB_KEY].status())


async def qr(request):
    local_admin(request)
    hub = request.app[HUB_KEY]
    address = request.query.get("ip", hub.addresses[0])
    if address not in hub.addresses:
        raise web.HTTPBadRequest()
    code = qrcode.make(hub.join_url(address), image_factory=qrcode.image.svg.SvgPathImage, border=3)
    buffer = io.BytesIO()
    code.save(buffer)
    return web.Response(body=buffer.getvalue(), content_type="image/svg+xml")


async def release(request):
    local_admin(request)
    hub = request.app[HUB_KEY]
    if not secrets.compare_digest(request.headers.get("X-Admin-Token", ""), hub.admin_token):
        raise web.HTTPForbidden()
    index = int(request.match_info["index"]) - 1
    if not 0 <= index < 4:
        raise web.HTTPBadRequest()
    slot = hub.slots[index]
    ws = slot.ws
    hub.reset(index)
    hub.output.detach(index)
    hub.slots[index] = Slot()
    if ws is not None:
        await ws.close(code=4003, message=b"Released by laptop")
    return web.json_response({"ok": True})


async def controller_socket(request):
    hub = request.app[HUB_KEY]
    origin = request.headers.get("Origin")
    if origin and origin != f"http://{request.host}":
        raise web.HTTPForbidden()
    ws = web.WebSocketResponse(heartbeat=10, max_msg_size=4096)
    await ws.prepare(request)
    index = None
    slot = None
    try:
        message = await asyncio.wait_for(ws.receive(), timeout=5)
        data = json.loads(message.data)
        if not isinstance(data, dict) or not isinstance(data.get("key"), str) or not secrets.compare_digest(data["key"], hub.token):
            await ws.send_json({"type": "error", "message": "Scan the QR code on the laptop to join.", "fatal": True})
            return ws
        client = data.get("client")
        if not isinstance(client, str) or not 8 <= len(client) <= 80:
            raise ValueError("Invalid device ID")
        if hub.output.error:
            await ws.send_json({"type": "error", "message": hub.output.error, "fatal": True})
            return ws
        now = time.monotonic()
        index = next((i for i, s in enumerate(hub.slots) if s.client == client), None)
        if index is not None and hub.slots[index].ws is not None:
            await ws.send_json({"type": "error", "message": "This phone is already connected in another tab. Close that tab and retry.", "fatal": True})
            index = None
            return ws
        if index is None:
            index = next((i for i, s in enumerate(hub.slots) if s.ws is None and s.reserved_until <= now), None)
        if index is None:
            await ws.send_json({"type": "error", "message": "All four players are taken. Release a player on the laptop, then retry.", "fatal": True})
            return ws
        try:
            hub.output.attach(index)
        except Exception as exc:
            await ws.send_json({"type": "error", "message": f"Could not create a controller. Check ViGEmBus: {exc}", "fatal": True})
            return ws
        slot = hub.slots[index]
        slot.client, slot.name, slot.ws = client, str(data.get("name", "Phone"))[:32], ws
        slot.last_input = now
        slot.epoch, slot.announced_epoch, slot.awaiting_reset = 0, -1, False
        hub.reset(index)
        await ws.send_json({"type": "joined", "player": index + 1, "epoch": slot.epoch, "mode": "preview" if hub.output.simulate else "live"})
        rate_start, count = now, 0
        async for message in ws:
            if hub.slots[index] is not slot or slot.ws is not ws:
                break
            if message.type != WSMsgType.TEXT:
                break
            now = time.monotonic()
            if now - rate_start >= 1:
                rate_start, count = now, 0
            count += 1
            if count > 180:
                await ws.close(code=1008, message=b"Too many updates")
                break
            data = json.loads(message.data)
            if not isinstance(data, dict):
                raise ValueError("Invalid message")
            if data.get("type") == "input":
                hub.expire_inputs(index, now)
                incoming = sanitize(data.get("state"))
                if data.get("epoch", 0) != slot.epoch or (slot.awaiting_reset and incoming != neutral()):
                    if slot.announced_epoch != slot.epoch:
                        await ws.send_json({"type": "reset", "epoch": slot.epoch})
                        slot.announced_epoch = slot.epoch
                    continue
                slot.awaiting_reset = False
                slot.state = incoming
                slot.last_input = now
                hub.output.apply(index, slot.state)
            elif data.get("type") == "ping":
                await ws.send_json({"type": "pong", "time": data.get("time")})
    except (ValueError, TypeError, asyncio.TimeoutError):
        await ws.close(code=1008, message=b"Invalid controller message")
    finally:
        if index is not None and slot is not None and hub.slots[index] is slot and slot.ws is ws:
            hub.reset(index)
            hub.output.detach(index)
            slot.ws = None
            slot.reserved_until = time.monotonic() + 15
        await ws.close()
    return ws


async def lifecycle(app):
    task = asyncio.create_task(app[HUB_KEY].watchdog())
    yield
    task.cancel()
    with contextlib.suppress(asyncio.CancelledError):
        await task
    app[HUB_KEY].output.close()


async def shutdown(app):
    await asyncio.gather(*(s.ws.close(code=1001, message=b"Server shutting down") for s in app[HUB_KEY].slots if s.ws is not None))


async def stop_server(request):
    local_admin(request)
    if not secrets.compare_digest(request.headers.get("X-Admin-Token", ""), request.app[HUB_KEY].admin_token):
        raise web.HTTPForbidden()
    callback = request.app.get(STOP_KEY)
    def stop():
        if callback is not None:
            callback()
            return
        raise web.GracefulExit()
    asyncio.get_running_loop().call_later(.3, stop)
    return web.json_response({"ok": True})


STOP_KEY = web.AppKey("stop_callback", object)


def create_app(hub, stop_callback=None):
    app = web.Application(middlewares=[headers], client_max_size=4096)
    app[HUB_KEY] = hub
    if stop_callback is not None:
        app[STOP_KEY] = stop_callback
    app.add_routes([web.get("/", dashboard), web.get("/api/bootstrap", bootstrap),
                    web.get("/api/status", status), web.get("/api/qr", qr),
                    web.post("/api/players/{index:\\d+}/release", release),
                    web.post("/api/stop", stop_server), web.get("/play", play),
                    web.get("/ws", controller_socket), web.static("/static/", ROOT / "static")])
    app.cleanup_ctx.append(lifecycle)
    app.on_shutdown.append(shutdown)
    return app


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="IControl local phone controllers")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--simulate", action="store_true", help="Preview without virtual controller output")
    parser.add_argument("--open", action="store_true", help="Open the laptop dashboard")
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("Port must be between 1 and 65535")
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        try:
            probe.bind(("0.0.0.0", args.port))
        except OSError:
            from urllib.request import urlopen
            try:
                with urlopen(f"http://localhost:{args.port}/api/status", timeout=2) as response:
                    running = json.load(response).get("app") == "IControl"
            except Exception:
                running = False
            if running and args.open:
                webbrowser.open(f"http://localhost:{args.port}")
                parser.exit(message="IControl is already running. Opened its dashboard.\n")
            parser.exit(1, f"Port {args.port} is already in use. Stop that server or choose --port.\n")
    hub = Hub(args.port, args.simulate)
    print(f"IControl dashboard: http://localhost:{args.port}")
    print(hub.output.error or ("PREVIEW ONLY: no controller output" if args.simulate else "Ready. Virtual controllers are created as phones join (up to four)."))
    if args.open:
        import threading
        threading.Timer(1.5, lambda: webbrowser.open(f"http://localhost:{args.port}")).start()
    web.run_app(create_app(hub), host="0.0.0.0", port=args.port, access_log=None)
