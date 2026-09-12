"""Loopback-only DSU v1001 motion bridge; see docs/MOTION_PROTOCOL.md."""
import asyncio
import contextlib
import hashlib
import secrets
import socket
import struct
import sys
import time
import zlib
from dataclasses import dataclass

VERSION, INFO, DATA = 0x100000, 0x100001, 0x100002
STALE_SECONDS = .25


def motion_socket():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        if sys.platform == 'win32':
            # A DSU subscriber may close without unregistering. Windows reports
            # its ICMP port-unreachable as WSAECONNRESET on this shared socket;
            # Python 3.12's proactor then stops receiving for every subscriber.
            # Disable that per-socket reporting, not any firewall protection.
            import ctypes as c
            winsock = c.WinDLL('Ws2_32.dll')
            ioctl = winsock.WSAIoctl
            ioctl.argtypes = [c.c_size_t, c.c_ulong, c.c_void_p, c.c_ulong,
                              c.c_void_p, c.c_ulong, c.POINTER(c.c_ulong), c.c_void_p, c.c_void_p]
            ioctl.restype = c.c_int
            enabled, returned = c.c_int(0), c.c_ulong()
            if ioctl(sock.fileno(), 0x9800000C, c.byref(enabled), c.sizeof(enabled),
                     None, 0, c.byref(returned), None, None) != 0:
                raise c.WinError(winsock.WSAGetLastError())
        sock.setblocking(False)
        return sock
    except BaseException:
        sock.close()
        raise


@dataclass(frozen=True)
class MotionSample:
    seq: int
    timestamp: int
    accel: tuple
    gyro: tuple
    received: float


def sanitize_motion(data, now):
    if data is None:
        return None
    if not isinstance(data, dict) or type(data.get("v")) is not int or data["v"] != 1:
        raise ValueError("Unsupported motion version")
    for key in ("seq", "timestamp"):
        if type(data.get(key)) is not int or not 0 <= data[key] <= 2**53-1:
            raise ValueError("Invalid motion counter")
    vectors = []
    for key, limit in (("accel", 16), ("gyro", 4000)):
        values = data.get(key)
        if not isinstance(values, list) or len(values) != 3:
            raise ValueError("Invalid motion vector")
        if any(type(v) not in (int, float) or not -limit <= v <= limit for v in values):
            raise ValueError("Motion value outside finite bounds")
        vectors.append(tuple(values))
    return MotionSample(data["seq"], data["timestamp"], *vectors, now)


def packet(kind, payload, server_id):
    result = bytearray(struct.pack("<4sHHIII", b"DSUS", 1001, len(payload)+4, 0, server_id, kind) + payload)
    struct.pack_into("<I", result, 8, zlib.crc32(result))
    return bytes(result)


def parse_request(data):
    if len(data) < 20 or len(data) > 1024:
        raise ValueError("Invalid DSU size")
    magic, version, size, crc, client, kind = struct.unpack_from("<4sHHIII", data)
    if magic != b"DSUC" or version > 1001 or size < 4 or size+16 > len(data):
        raise ValueError("Invalid DSU header")
    data = data[:size+16]
    if zlib.crc32(data[:8] + bytes(4) + data[12:]) != crc:
        raise ValueError("Invalid DSU CRC")
    return client, kind, data[20:]


class MotionServer(asyncio.DatagramProtocol):
    def __init__(self, hub, port=26760):
        self.hub, self.port = hub, port
        self.transport = self.task = None
        self.closed = None
        self.error = None
        self.server_id = secrets.randbits(32)
        self.subscriptions = {}  # (endpoint, client ID, slot) -> expiry
        self.counters = [0]*4
        self.timestamps = [0]*4

    async def start(self):
        if self.port is None:
            self.error = "Motion bridge disabled"
            return
        sock = None
        try:
            self.closed = asyncio.get_running_loop().create_future()
            sock = motion_socket()
            sock.bind(('127.0.0.1', self.port))
            self.transport, _ = await asyncio.get_running_loop().create_datagram_endpoint(
                lambda: self, sock=sock)
            sock = None  # The transport owns the socket after successful creation.
            self.port = self.transport.get_extra_info("sockname")[1]
            self.task = asyncio.create_task(self.run())
        except OSError as exc:
            self.error = f"Motion unavailable: UDP 127.0.0.1:{self.port}: {exc}"
        finally:
            if sock is not None:
                sock.close()

    def connection_lost(self, exc):
        if self.closed is not None and not self.closed.done():
            self.closed.set_result(None)

    async def close(self):
        if self.task:
            self.task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self.task
        # Send a final neutral sample before closing; delivery is best effort.
        for slot in self.hub.slots:
            slot.motion = None
        self.tick()
        if self.transport:
            transport = self.transport
            self.transport = None
            transport.close()
            # close() only schedules flushing. Keep the Windows event loop alive
            # until pending datagrams finish and connection_lost releases the socket.
            try:
                await asyncio.wait_for(asyncio.shield(self.closed), .5)
            except asyncio.TimeoutError:
                transport.abort()
                await self.closed
        self.subscriptions.clear()

    def capability(self):
        return {"version": 1, "available": self.transport is not None,
                "host": "127.0.0.1", "port": self.port, "error": self.error}

    def subscribers(self, index):
        now = time.monotonic()
        return sum(i == index and expiry > now for (_, _, i), expiry in self.subscriptions.items())

    def mac(self, index):
        client = self.hub.slots[index].client
        return b"\x02" + hashlib.sha256(client.encode()).digest()[:5] if client else bytes(6)

    def fresh(self, index, now):
        slot = self.hub.slots[index]
        return (slot.ws is not None and not slot.awaiting_reset and slot.motion is not None
                and now-slot.motion.received <= STALE_SECONDS)

    def metadata(self, index, now, active=False):
        fresh = self.fresh(index, now)
        return bytes((index, 2 if fresh else 0, 2 if fresh else 0, 2 if fresh else 0)) + self.mac(index) + bytes((0, int(fresh and active)))

    def datagram_received(self, data, addr):
        try:
            client, kind, payload = parse_request(data)
            now = time.monotonic()
            if kind == VERSION and len(payload) <= 1:  # C++ empty struct can occupy one byte.
                self.transport.sendto(packet(VERSION, struct.pack("<H", 1001), self.server_id), addr)
            elif kind == INFO and len(payload) >= 4:
                count, = struct.unpack_from("<i", payload)
                if not 1 <= count <= 4 or len(payload) < 4+count or any(i > 3 for i in payload[4:4+count]):
                    return
                for index in payload[4:4+count]:
                    self.transport.sendto(packet(INFO, self.metadata(index, now), self.server_id), addr)
            elif kind == DATA and len(payload) == 8:
                flags, index = payload[:2]
                if flags > 3 or (flags & 1 and index > 3):
                    return
                self.subscriptions = {k: v for k, v in self.subscriptions.items() if v > now}
                for i in range(4):
                    if flags == 0 or (flags & 1 and i == index) or (flags & 2 and payload[2:] == self.mac(i) and any(payload[2:])):
                        key = (addr, client, i)
                        if key in self.subscriptions or len(self.subscriptions) < 128:
                            self.subscriptions[key] = now + 5
        except (ValueError, struct.error):
            return

    def data_packet(self, index, now):
        self.counters[index] = (self.counters[index]+1) & 0xffffffff
        body = bytearray(80)
        body[:12] = self.metadata(index, now, active=True)
        struct.pack_into("<I", body, 12, self.counters[index])
        body[20:24] = bytes((128,)*4)  # Motion-only source; use XInput for buttons.
        fresh = self.fresh(index, now)
        sample = self.hub.slots[index].motion if fresh else None
        # Server clock survives phone reconnects and keeps stale zero samples advancing.
        timestamp = int((sample.received if sample else now)*1_000_000)
        self.timestamps[index] = max(self.timestamps[index], timestamp)
        struct.pack_into("<Q6f", body, 48, self.timestamps[index],
                         *(sample.accel + sample.gyro if sample else (0, 0, -1, 0, 0, 0)))
        return packet(DATA, body, self.server_id)

    def tick(self):
        now = time.monotonic()
        self.subscriptions = {k: v for k, v in self.subscriptions.items() if v > now}
        packets = {}
        for (addr, _, index) in self.subscriptions:
            if index not in packets:
                packets[index] = self.data_packet(index, now)
            if self.transport:
                self.transport.sendto(packets[index], addr)

    async def run(self):
        while True:
            self.tick()
            await asyncio.sleep(1/60)
