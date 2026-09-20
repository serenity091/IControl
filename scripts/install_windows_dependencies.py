"""Install pinned Windows dependencies without vgamepad's interactive MSI launch.

vgamepad 0.1.0 does not implement VGAMEPAD_SKIP_VIGEMBUS_INSTALL. Patch only
its setup-time installer condition in a verified temporary source archive;
the packaged runtime is unchanged. The user installs ViGEmBus separately.
"""
import hashlib
import importlib.metadata
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
URL = 'https://files.pythonhosted.org/packages/8a/54/0eaddc33f84247963af078f364b37153d09fcd6cdc398f243ec3e8842c56/vgamepad-0.1.0.tar.gz'
SHA256 = '57f6bd01aec0c172947517fb782d150ef9b285f7f4d524c317374fa5c24a89de'

def main():
    if sys.platform != 'win32':
        raise SystemExit('This installer is for Windows. Use requirements.txt on macOS.')
    try:
        installed = importlib.metadata.version('vgamepad') == '0.1.0'
    except importlib.metadata.PackageNotFoundError:
        installed = False
    if not installed:
        with tempfile.TemporaryDirectory(prefix='phone-controller-deps-') as folder:
            folder = Path(folder)
            archive = folder / 'vgamepad.tar.gz'
            with urllib.request.urlopen(URL, timeout=60) as response:
                data = response.read()
            if hashlib.sha256(data).hexdigest() != SHA256:
                raise SystemExit('vgamepad source hash mismatch; refusing to install.')
            archive.write_bytes(data)
            with tarfile.open(archive) as package:
                package.extractall(folder, filter='data')
            source = folder / 'vgamepad-0.1.0'
            setup = source / 'setup.py'
            text = setup.read_text()
            original = 'if not vigem_installed:'
            if text.count(original) != 1:
                raise SystemExit('Unexpected vgamepad setup script; refusing to patch.')
            setup.write_text(text.replace(original, 'if False:  # Driver installation is a separate user step.'))
            print('Installing pinned vgamepad without running its bundled driver installer.', flush=True)
            subprocess.run([sys.executable, '-m', 'pip', 'install', '--no-deps', str(source)], check=True)
    requirements = ROOT / ('requirements-build.txt' if '--build' in sys.argv else 'requirements.txt')
    subprocess.run([sys.executable, '-m', 'pip', 'install', '-r', str(requirements)], check=True)

if __name__ == '__main__':
    main()
