"""Independent DSU offsets/CRC fixtures plus real WebSocket -> UDP integration."""
import asyncio
import socket
import struct
import time
import unittest
from aiohttp.test_utils import AioHTTPTestCase
from motion import DATA, INFO, VERSION, MotionServer, packet, parse_request, sanitize_motion
from server import Hub, Slot, create_app, neutral


def reference_crc(data):
    crc = 0xffffffff
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ (0xedb88320 if crc & 1 else 0)
    return crc ^ 0xffffffff


def request(kind, payload=b''):
    data = bytearray(b'DSUC' + (1001).to_bytes(2, 'little') + (len(payload)+4).to_bytes(2, 'little') + bytes(4) + b'\x78\x56\x34\x12' + kind.to_bytes(4, 'little') + payload)
    data[8:12] = reference_crc(data).to_bytes(4, 'little')
    return bytes(data)


def sample(seq=1):
    return dict(v=1, seq=seq, timestamp=seq*10000, accel=[.25, -.5, -1], gyro=[90, -180, 45])


class PacketTests(unittest.TestCase):
    def setUp(self):
        self.hub = Hub(simulate=True, dsu_port=None)
        self.dsu = self.hub.motion
        self.dsu.server_id = 0x12345678

    def test_crc_known_check_vector(self):
        self.assertEqual(reference_crc(b'123456789'), 0xcbf43926)

    def test_version_response_fixture(self):
        # Literal bytes independently generated with the published header layout.
        value = packet(VERSION, b'\xe9\x03', 0x12345678)
        self.assertEqual(value[:8], bytes.fromhex('44535553e9030600'))
        self.assertEqual(value[12:], bytes.fromhex('7856341200001000e903'))
        self.assertEqual(int.from_bytes(value[8:12], 'little'), reference_crc(value[:8]+bytes(4)+value[12:]))

    def test_payload_offsets_and_units(self):
        now = time.monotonic()
        self.hub.slots[2] = Slot(client='fixture-phone', ws=object(), motion=sanitize_motion(sample(), now))
        data = self.dsu.data_packet(2, now)
        self.assertEqual(len(data), 100)
        self.assertEqual(data[6:8], b'\x54\x00')
        self.assertEqual(data[16:24], bytes.fromhex('0200100002020202'))
        self.assertEqual(data[31], 1)
        self.assertEqual(data[32:36], b'\x01\x00\x00\x00')
        self.assertEqual(data[36:40], bytes(4))
        self.assertEqual(data[40:44], b'\x80'*4)
        self.assertEqual(data[44:68], bytes(24))
        self.assertEqual(data[76:100], bytes.fromhex('0000803e000000bf000080bf0000b442000034c300003442'))
        self.assertEqual(int.from_bytes(data[68:76], 'little'), int(now*1000000))
        self.assertEqual(int.from_bytes(data[8:12], 'little'), reference_crc(data[:8]+bytes(4)+data[12:]))

    def test_stale_zero_and_monotonic_counter_after_reuse(self):
        now = time.monotonic()
        self.hub.slots[0] = Slot(client='one', ws=object(), motion=sanitize_motion(sample(), now-1))
        first = self.dsu.data_packet(0, now)
        self.assertEqual(first[21], 0)
        self.assertEqual(struct.unpack_from('<6f', first, 76), (0,0,-1,0,0,0))
        self.hub.slots[0] = Slot(client='two', ws=object(), motion=sanitize_motion(sample(), now))
        second = self.dsu.data_packet(0, now+.01)
        self.assertEqual(struct.unpack_from('<I', second, 32)[0], 2)
        self.assertGreaterEqual(struct.unpack_from('<Q', second, 68)[0], struct.unpack_from('<Q', first, 68)[0])

    def test_invalid_requests_and_trailing_bytes(self):
        good = request(VERSION)
        self.assertEqual(parse_request(good+b'extra')[1], VERSION)
        for value in [b'', good[:-1], b'BAD!'+good[4:], good[:8]+bytes(4)+good[12:], good+b'x'*2000]:
            with self.subTest(value=value), self.assertRaises(ValueError): parse_request(value)

    def test_validation(self):
        for bad in [True, [], {}, {**sample(), 'v': True}, {**sample(), 'seq': True},
                    {**sample(), 'timestamp': -1}, {**sample(), 'accel': [0,0,float('nan')]},
                    {**sample(), 'gyro': [0,0,4001]}, {**sample(), 'accel': [True,0,0]},
                    {**sample(), 'gyro': [0,0,10**400]}]:
            with self.subTest(bad=bad), self.assertRaises(ValueError): sanitize_motion(bad, 0)

    def test_subscription_flags_expiry_and_bounds(self):
        class Transport:
            def __init__(self): self.packets = []
            def sendto(self, data, addr): self.packets.append((data, addr))
        self.dsu.transport = Transport()
        addr = ('127.0.0.1', 1234)
        self.dsu.datagram_received(request(DATA, bytes((1,2))+bytes(6)), addr)
        self.assertEqual(self.dsu.subscribers(2), 1)
        self.assertEqual(self.dsu.subscribers(0), 0)
        self.hub.slots[1].client = 'mac-phone'
        self.dsu.datagram_received(request(DATA, bytes((2,0))+self.dsu.mac(1)), addr)
        self.assertEqual(self.dsu.subscribers(1), 1)
        self.dsu.datagram_received(request(INFO, struct.pack('<i', 4)+bytes(range(4))), addr)
        self.assertEqual([p[0][20] for p in self.dsu.transport.packets], [0,1,2,3])
        self.dsu.datagram_received(request(DATA, bytes((0,0))+bytes(6)), addr)
        self.assertEqual(len(self.dsu.subscriptions), 4)
        self.dsu.subscriptions = {k: 0 for k in self.dsu.subscriptions}; self.dsu.tick()
        self.assertFalse(self.dsu.subscriptions)
        self.dsu.datagram_received(request(DATA, bytes((1,9))+bytes(6)), addr)
        self.assertFalse(self.dsu.subscriptions)
        for i in range(200): self.dsu.datagram_received(request(DATA, bytes(8)), ('127.0.0.1', i))
        self.assertEqual(len(self.dsu.subscriptions), 128)


class MotionIntegrationTests(AioHTTPTestCase):
    async def get_application(self):
        self.hub = Hub(simulate=True, dsu_port=0)
        return create_app(self.hub)

    async def join(self, id='native-001'):
        ws = await self.client.ws_connect('/ws')
        await ws.send_json(dict(type='join', key=self.hub.token, client=id))
        message = await ws.receive_json()
        self.assertTrue(message['capabilities']['motion']['available'])
        return ws

    async def send(self, ws, motion, epoch=0):
        await ws.send_json(dict(type='input', epoch=epoch, state=neutral(), motion=motion))
        await ws.send_json(dict(type='ping'))
        return await ws.receive_json()

    async def test_real_udp_end_to_end_and_disable(self):
        ws = await self.join()
        await self.send(ws, sample())
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
            udp.setblocking(False)
            loop = asyncio.get_running_loop()
            await loop.sock_sendto(udp, request(DATA, b'\x01\x00'+bytes(6)), ('127.0.0.1', self.hub.motion.port))
            data, _ = await asyncio.wait_for(loop.sock_recvfrom(udp, 1024), 1)
            self.assertEqual(struct.unpack_from('<3f', data, 88), (90,-180,45))
            self.assertEqual(data[20], 0)
            await self.send(ws, None)
            while True:
                data, _ = await asyncio.wait_for(loop.sock_recvfrom(udp, 1024), 1)
                if data[21] == 0: break
            self.assertEqual(struct.unpack_from('<3f', data, 88), (0,0,0))
        await ws.close()

    async def test_four_mixed_clients_and_disconnect_isolation(self):
        sockets = [await self.join(f'mixed-00{i}') for i in range(4)]
        for i, ws in enumerate(sockets): await self.send(ws, sample(i+1) if i%2 == 0 else None)
        self.assertEqual([s.motion is not None for s in self.hub.slots], [True,False,True,False])
        await sockets[0].close(); await asyncio.sleep(.02)
        self.assertIsNone(self.hub.slots[0].motion)
        self.assertIsNotNone(self.hub.slots[2].motion)
        for ws in sockets[1:]: await ws.close()

    async def test_replay_does_not_refresh_or_replace_sample(self):
        ws = await self.join(); await self.send(ws, sample(2))
        before = self.hub.slots[0].motion
        await self.send(ws, {**sample(1), 'gyro': [1,2,3]})
        self.assertIs(self.hub.slots[0].motion, before)
        await self.send(ws, None)
        await self.send(ws, sample(2))
        self.assertIsNone(self.hub.slots[0].motion)
        await ws.close()

    async def test_epoch_requires_motion_neutral_and_reused_slot_protected(self):
        ws = await self.join(); await self.send(ws, sample())
        self.hub.slots[0].last_input -= 1
        await ws.send_json(dict(type='input', epoch=0, state=neutral(), motion=sample(2)))
        reset = await ws.receive_json()
        self.assertEqual(reset['type'], 'reset')
        self.assertIsNone(self.hub.slots[0].motion)
        await self.send(ws, sample(3), reset['epoch'])
        self.assertTrue(self.hub.slots[0].awaiting_reset)
        await self.send(ws, None, reset['epoch'])
        await self.send(ws, sample(4), reset['epoch'])
        self.assertIsNotNone(self.hub.slots[0].motion)
        self.hub.slots[0] = Slot(client='replacement')
        await ws.send_json(dict(type='input', epoch=reset['epoch'], state=neutral(), motion=sample(5)))
        await ws.receive()
        self.assertIsNone(self.hub.slots[0].motion)
        await ws.close()

    async def test_malformed_motion_closes_and_neutralizes(self):
        ws = await self.join(); await self.send(ws, sample())
        await ws.send_json(dict(type='input', state=neutral(), motion={**sample(2), 'gyro': [True,0,0]}))
        await ws.receive(); await asyncio.sleep(.02)
        self.assertIsNone(self.hub.slots[0].motion)
        await ws.close()


class LifecycleTests(unittest.IsolatedAsyncioTestCase):
    async def test_closed_subscriber_does_not_stop_receiving_new_clients(self):
        hub = Hub(simulate=True, dsu_port=0)
        await hub.motion.start()
        loop = asyncio.get_running_loop()
        address = ('127.0.0.1', hub.motion.port)
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as first:
                first.bind(('127.0.0.1', 0)); first.setblocking(False)
                await loop.sock_sendto(first, request(DATA, bytes(8)), address)
                await asyncio.wait_for(loop.sock_recvfrom(first, 1024), 1)
            # Continuing to send to the closed peer produces ICMP port-unreachable
            # on Windows. It must not stop the shared server's receive loop.
            await asyncio.sleep(.15)
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as second:
                second.bind(('127.0.0.1', 0)); second.setblocking(False)
                await loop.sock_sendto(second, request(VERSION), address)
                data, _ = await asyncio.wait_for(loop.sock_recvfrom(second, 1024), 1)
                self.assertEqual(data[16:20], VERSION.to_bytes(4, 'little'))
        finally:
            await hub.motion.close()

    async def test_close_with_queued_packets_releases_port_before_returning(self):
        hub = Hub(simulate=True, dsu_port=0)
        await hub.motion.start()
        port = hub.motion.port
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as receiver:
                receiver.bind(('127.0.0.1', 0))
                hub.motion.datagram_received(request(DATA, bytes(8)), receiver.getsockname())
                for _ in range(32):
                    hub.motion.tick()
                await hub.motion.close()
                # No sleep: close must wait for the actual OS socket release.
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
                    probe.bind(('127.0.0.1', port))
        finally:
            await hub.motion.close()

    async def test_port_conflict_and_cleanup(self):
        hub = Hub(simulate=True, dsu_port=0)
        await hub.motion.start()
        port = hub.motion.port
        other = Hub(simulate=True, dsu_port=port)
        await other.motion.start()
        self.assertFalse(other.motion.capability()['available'])
        self.assertIn(str(port), other.motion.error)
        await other.motion.close()
        await hub.motion.close()
        await asyncio.sleep(.02)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe: probe.bind(('127.0.0.1', port))
        self.assertTrue(hub.motion.task.done())
