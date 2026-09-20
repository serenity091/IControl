"""Build the standalone Windows executable with its local web assets."""
from pathlib import Path
from PIL import Image, ImageDraw
import PyInstaller.__main__

ROOT = Path(__file__).resolve().parent
assets = ROOT / "assets"
assets.mkdir(exist_ok=True)
icon = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
d = ImageDraw.Draw(icon)
d.rounded_rectangle((8, 8, 248, 248), radius=45, fill="#292929")
d.rounded_rectangle((33, 63, 223, 191), radius=38, fill="#dddddd")
d.rectangle((60, 97, 78, 151), fill="#292929")
d.rectangle((42, 115, 96, 133), fill="#292929")
for x, y, color in [(174, 146, "#328529"), (198, 122, "#bd2927"), (150, 122, "#2466b2"), (174, 98, "#e1b521")]:
    d.ellipse((x-12, y-12, x+12, y+12), fill=color)
icon.save(assets / "phone-controller.ico", sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])

PyInstaller.__main__.run([
    str(ROOT / "desktop.py"), "--name=Phone Controller", "--onefile", "--windowed", "--noconfirm",
    f"--icon={assets / 'phone-controller.ico'}", f"--distpath={ROOT / 'dist'}", f"--workpath={ROOT / 'build'}",
    f"--specpath={ROOT}", f"--add-data={ROOT / 'static'};static", f"--add-data={assets};assets",
    "--collect-binaries=vgamepad", "--hidden-import=vgamepad.win.virtual_gamepad", "--exclude-module=vgamepad.lin",
])
