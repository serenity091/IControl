"""Native desktop host. The server and virtual controllers share this process."""
import argparse
import asyncio
import json
import os
import queue
import threading
import tkinter as tk
from tkinter import ttk, messagebox
import webbrowser
from pathlib import Path

import qrcode
from PIL import ImageTk
from aiohttp import web
from server import Hub, Slot, create_app


class ServerThread:
    def __init__(self, port=8080, simulate=False, dsu_port=26760):
        self.port, self.simulate = port, simulate
        self.dsu_port = dsu_port
        self.events = queue.Queue()
        self.loop = None
        self.stop_event = None
        self.stop_requested = threading.Event()
        self.thread = threading.Thread(target=self.run, name="Phone Controller server", daemon=False)

    def start(self):
        self.thread.start()

    def stop(self):
        self.stop_requested.set()
        if self.loop is not None and self.stop_event is not None and not self.loop.is_closed():
            self.loop.call_soon_threadsafe(self.stop_event.set)

    def release(self, index):
        async def release_slot():
            slot = self.hub.slots[index]
            self.hub.reset(index)
            self.hub.output.detach(index)
            self.hub.slots[index] = Slot()
            if slot.ws is not None:
                await slot.ws.close(code=4003, message=b"Released by laptop")
        if self.loop and not self.loop.is_closed():
            asyncio.run_coroutine_threadsafe(release_slot(), self.loop)

    def run(self):
        try:
            asyncio.run(self.serve())
        except Exception as exc:
            self.events.put(("error", str(exc)))
        finally:
            self.events.put(("stopped", None))

    async def serve(self):
        self.loop = asyncio.get_running_loop()
        self.stop_event = asyncio.Event()
        self.hub = Hub(self.port, self.simulate, dsu_port=self.dsu_port)
        runner = web.AppRunner(create_app(self.hub, self.stop), access_log=None, shutdown_timeout=2)
        try:
            await runner.setup()
            await web.TCPSite(runner, "0.0.0.0", self.port).start()
            self.events.put(("ready", {"addresses": self.hub.addresses,
                                       "urls": [self.hub.join_url(a) for a in self.hub.addresses]}))
            while not self.stop_requested.is_set():
                self.events.put(("status", self.hub.status()))
                try:
                    await asyncio.wait_for(self.stop_event.wait(), timeout=.25)
                    break
                except asyncio.TimeoutError:
                    pass
        finally:
            await runner.cleanup()
            self.hub.output.close()


class Desktop:
    def __init__(self, root, port=8080, simulate=False, auto_close=None, dsu_port=26760):
        self.root = root
        self.port = port
        self.closing = False
        self.failed = False
        self.server = ServerThread(port, simulate, dsu_port)
        self.scale = root.winfo_fpixels("1i") / 96
        self.qr_size = round(240 * self.scale)
        root.title("Phone Controller")
        root.geometry(f"{round(760*self.scale)}x{round(620*self.scale)}")
        root.minsize(round(720*self.scale), round(600*self.scale))
        root.configure(bg="#ededed")
        root.protocol("WM_DELETE_WINDOW", self.close)
        icon = Path(__file__).parent / "assets" / "phone-controller.ico"
        if icon.exists():
            root.iconbitmap(str(icon))
        style = ttk.Style(root)
        style.theme_use("clam")
        style.configure("TButton", font=("Segoe UI", 10), padding=(12, 7))
        style.configure("TCombobox", padding=5)
        header = tk.Frame(root, bg="#252525", padx=24, pady=17)
        header.pack(fill="x")
        tk.Label(header, text="Phone Controller", font=("Segoe UI", 21, "bold"), bg="#252525", fg="white").pack(side="left")
        self.status = tk.Label(header, text="Starting server…", bg="#252525", fg="#aadd83", font=("Segoe UI", 10))
        self.status.pack(side="right")
        body = tk.Frame(root, bg="#ededed", padx=24, pady=20)
        body.pack(fill="both", expand=True)
        left = tk.Frame(body, bg="#ededed")
        left.pack(side="left", fill="y", padx=(0, 28))
        tk.Label(left, text="Scan to connect", bg="#ededed", font=("Segoe UI", 14, "bold")).pack(anchor="w")
        tk.Label(left, text="Phone and PC on the same Wi-Fi", bg="#ededed", fg="#666666", font=("Segoe UI", 10)).pack(anchor="w", pady=(3, 12))
        self.qr = tk.Label(left, bg="white")
        self.qr.pack()
        self.address = ttk.Combobox(left, state="readonly", width=29)
        self.address.pack(fill="x", pady=(12, 8))
        self.address.bind("<<ComboboxSelected>>", self.update_qr)
        ttk.Button(left, text="Copy phone link", command=self.copy_link).pack(fill="x")
        right = tk.Frame(body, bg="#ededed")
        right.pack(side="left", fill="both", expand=True)
        self.count = tk.Label(right, text="No players connected", bg="#ededed", font=("Segoe UI", 14, "bold"), anchor="w")
        self.count.pack(fill="x", pady=(0, 12))
        self.players = tk.Frame(right, bg="#ededed")
        self.players.pack(fill="x")
        self.player_signature = None
        self.hint = tk.Label(right, text="Controllers appear as phones join.\nSupports up to 4 players.\n\nIn Eden, choose a Pro Controller\nand bind each phone's buttons.\n\nClosing this window stops the server\nand disconnects all controllers.", bg="#ededed", fg="#555555", font=("Segoe UI", 10), justify="left", anchor="nw")
        self.hint.pack(fill="both", expand=True, pady=12)
        ttk.Button(right, text="Open browser dashboard", command=lambda: webbrowser.open(f"http://localhost:{port}")).pack(fill="x", side="bottom")
        self.footer = tk.Label(root, text="Starting…", anchor="w", padx=24, pady=9, bg="#dddddd", fg="#555555", font=("Segoe UI", 9))
        self.footer.pack(fill="x", side="bottom")
        self.server.start()
        root.after(100, self.poll)
        if auto_close is not None:
            root.after(int(auto_close * 1000), self.close)

    def update_qr(self, event=None):
        index = self.address.current()
        if index < 0:
            return
        self.url = self.urls[index]
        qr = qrcode.QRCode(box_size=6, border=4)
        qr.add_data(self.url)
        qr.make(fit=True)
        from PIL import Image
        self.photo = ImageTk.PhotoImage(qr.make_image(fill_color="black", back_color="white").get_image().resize((self.qr_size, self.qr_size), Image.Resampling.NEAREST))
        self.qr.configure(image=self.photo, width=self.qr_size, height=self.qr_size)

    def copy_link(self):
        if hasattr(self, "url"):
            self.root.clipboard_clear()
            self.root.clipboard_append(self.url)
            self.footer.configure(text="Phone link copied.")

    def poll(self):
        try:
            while True:
                kind, value = self.server.events.get_nowait()
                if kind == "ready":
                    self.urls = value["urls"]
                    self.address["values"] = [f"{a}:{self.port}" for a in value["addresses"]]
                    self.address.current(0)
                    self.update_qr()
                    self.footer.configure(text=f"Server: localhost:{self.port}   |   Close this window to stop")
                elif kind == "status":
                    active = [p for p in value["players"] if p["connected"] or p["reserved"]]
                    count = sum(p["connected"] for p in active)
                    self.count.configure(text=f"{count} player{'s' if count != 1 else ''} connected" if count else "No players connected")
                    self.status.configure(text="Driver unavailable" if value["error"] else "Preview mode" if value["mode"] == "preview" else "Server running")
                    if value.get("motion", {}).get("error"):
                        self.hint.configure(text=value["motion"]["error"], wraplength=330)
                    if value["error"]:
                        self.hint.configure(text=value["error"], wraplength=330)
                    signature = [(p["player"], p["name"], p["connected"]) for p in active]
                    if signature != self.player_signature:
                        self.player_signature = signature
                        for child in self.players.winfo_children():
                            child.destroy()
                        if not active:
                            tk.Label(self.players, text="Waiting for a phone…", bg="white", fg="#777777", font=("Segoe UI", 11), padx=12, pady=18, anchor="w").pack(fill="x")
                        for player in active:
                            row = tk.Frame(self.players, bg="white", padx=10, pady=8)
                            row.pack(fill="x", pady=(0, 5))
                            tk.Label(row, text=f"P{player['player']}  {player['name'][:18]}" + ("" if player["connected"] else " (reconnecting)"), bg="white", font=("Segoe UI", 10), anchor="w").pack(side="left")
                            ttk.Button(row, text="Release", command=lambda i=player["player"]-1: self.server.release(i)).pack(side="right")
                elif kind == "error":
                    self.failed = True
                    self.status.configure(text="Could not start", fg="#ffaaaa")
                    self.hint.configure(text=f"{value}\n\nPort {self.port} may already be in use. Close the other Phone Controller window or stop the old server, then open this app again.", wraplength=310)
                elif kind == "stopped" and not self.failed:
                    self.closing = True
        except queue.Empty:
            pass
        if self.closing and not self.server.thread.is_alive():
            self.root.destroy()
            return
        self.root.after(100, self.poll)

    def close(self):
        if not self.closing:
            self.closing = True
            self.status.configure(text="Stopping…")
            self.footer.configure(text="Releasing controllers and stopping the server…")
            self.server.stop()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--simulate", action="store_true")
    parser.add_argument("--auto-close", type=float, help=argparse.SUPPRESS)
    parser.add_argument("--no-motion", action="store_true")
    parser.add_argument("--dsu-port", type=int, default=26760)
    args = parser.parse_args()
    if not 1 <= args.dsu_port <= 65535:
        parser.error("DSU port must be between 1 and 65535")
    try:
        import ctypes
        ctypes.windll.shcore.SetProcessDpiAwareness(1)
    except Exception:
        pass
    root = tk.Tk()
    app = Desktop(root, args.port, args.simulate, args.auto_close, None if args.no_motion else args.dsu_port)
    try:
        root.mainloop()
    finally:
        app.server.stop()
        app.server.thread.join(timeout=10)


if __name__ == "__main__":
    main()
