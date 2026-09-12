"""Local-only fixture for Xcode's native networking tests. Never package this file."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from aiohttp import web
from server import Hub, create_app, local_admin, neutral, sanitize
hub = Hub(port=8089, simulate=True, dsu_port=0)
app = create_app(hub)

async def expire(request):
    local_admin(request)
    for i, slot in enumerate(hub.slots):
        if slot.ws is not None:
            slot.last_input -= 1
            hub.expire_inputs(i, __import__('time').monotonic())
    return web.json_response({'ok': True})

legacy_state = neutral()
async def legacy_socket(request):
    global legacy_state
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    await ws.receive_json()
    await ws.send_json(dict(type='joined', player=1, epoch=0, mode='preview'))
    async for message in ws:
        data = __import__('json').loads(message.data)
        if data.get('type') == 'input':
            legacy_state = sanitize(data.get('state'))
        elif data.get('type') == 'ping':
            await ws.send_json(dict(type='pong', time=data.get('time')))
    legacy_state = neutral()
    return ws

async def legacy_status(request):
    return web.json_response(legacy_state)

async def legacy_lifecycle(app):
    legacy = web.Application()
    legacy.router.add_get('/ws', legacy_socket)
    legacy.router.add_get('/state', legacy_status)
    runner = web.AppRunner(legacy)
    await runner.setup()
    try:
        await web.TCPSite(runner, '127.0.0.1', 8090).start()
        yield
    finally:
        await runner.cleanup()

app.cleanup_ctx.append(legacy_lifecycle)
app.router.add_post('/test/expire', expire)
web.run_app(app, host='127.0.0.1', port=8089, access_log=None)
