"""Generate the GitHub Pages documents; no network calls or user data collection."""
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / 'public'
SITE.mkdir(parents=True, exist_ok=True)
# Keep the website's branding identical to the shipped iPhone app.
(SITE / 'app-icon.png').write_bytes(
    (ROOT / 'ios/IControl/Assets.xcassets/AppIcon.appiconset/AppIcon.png').read_bytes()
)
BASE = 'https://serenity091.github.io/IControl/'
REPO = 'https://github.com/serenity091/IControl'
RELEASE = REPO + '/releases/tag/windows-v1.0.0-rc.1'
APP_STORE = 'https://apps.apple.com/app/id6811429633'

def page(path, title, body):
    prefix = '../' if path else './'
    folder = SITE / path
    folder.mkdir(parents=True, exist_ok=True)
    canonical = BASE + (path + '/' if path else '')
    content = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{escape(title)} · Phone Controller</title><meta name="description" content="Phone Controller: a wireless iPhone gamepad for your Windows PC. Support, setup and privacy information.">
<meta name="color-scheme" content="dark"><meta name="theme-color" content="#181818">
<link rel="canonical" href="{canonical}"><link rel="icon" href="{prefix}app-icon.png" type="image/png"><link rel="apple-touch-icon" href="{prefix}app-icon.png"><link rel="stylesheet" href="{prefix}style.css"></head>
<body><header><a class="brand" href="{prefix}"><img src="{prefix}app-icon.png" alt="" width="44" height="44">Phone Controller</a><nav aria-label="Main navigation"><a href="{prefix}support/">Support</a><a href="{prefix}privacy/">Privacy</a></nav></header>
<main>{body}</main><footer><span>Phone Controller · Maintained by <a href="https://github.com/serenity091">serenity091</a></span><a href="{REPO}">Source on GitHub</a></footer></body></html>'''
    (folder / 'index.html').write_text(content, encoding='utf-8')

page('', 'Wireless gamepad for your PC', f'''
<p class="eyebrow">Your phone. Your controls.</p><h1>A gamepad in<br>your pocket.</h1>
<p class="lead">Turn your iPhone into a wireless controller for your Windows PC, with customizable touch controls and optional motion input.</p>
<div class="actions"><a class="button" href="{APP_STORE}">Download on the App Store</a><a class="button secondary" href="{RELEASE}">Windows companion download</a><a class="button secondary" href="support/">Setup and support</a></div>
<p><small>Free on the App Store for iPhone. Windows companion: release candidate.</small></p>
<div class="card"><h2>Made for local play</h2><p>Use a full two-stick controller or a left- or right-hand single-stick layout. Move and resize controls, switch between upright and sideways layouts, and enable native haptic feedback.</p><p>Up to four phones can connect independently. Each phone supplies one motion source.</p></div>
<h2>What you need</h2><p>An iPhone running iOS 17 or later, a Windows PC with the companion and ViGEmBus driver, and a trusted local Wi-Fi network. Games must support controller input. Motion requires a compatible DSU client and its own bindings.</p>
<p>No app account, ads or analytics. Local controller traffic is unencrypted. The app does not connect directly to consoles or include games. <a href="privacy/">Read the privacy policy.</a></p>''')

page('support', 'Support and setup', f'''
<p class="eyebrow">Get connected</p><h1>Support &amp; setup</h1><p class="lead">Use your iPhone as a controller for a Windows PC on the same local network.</p>
<h2>1. Set up your PC</h2><ol><li><a href="{RELEASE}">Download the Windows companion ZIP</a>, extract it, and keep the included files together.</li><li>Install the ViGEmBus driver from its <a href="https://github.com/nefarius/ViGEmBus/releases">official releases</a>. The companion does not install a driver automatically.</li><li>Open <strong>Phone Controller.exe</strong> and keep its window open. Python is not required for the packaged download.</li><li>If Windows blocks the connection, run <strong>Enable Wi-Fi access.cmd</strong> from the extracted folder and approve its administrator prompt. The helper permits local private-network connections.</li></ol>
<h2>2. Pair your iPhone</h2><ol><li><a href="{APP_STORE}">Download Phone Controller from the App Store</a>.</li><li>Connect the phone and PC to the same trusted Wi-Fi network.</li><li>In Phone Controller, tap <strong>Scan QR</strong>, scan the code in the PC window, then tap <strong>Join game</strong>.</li><li>Allow Local Network access. Camera access is optional: you can paste the complete pairing URL instead. Scanning with Apple's Camera opens the browser controller.</li></ol>
<h2>3. Choose your controls</h2><p>Choose Full controller or a standalone Left or Right Joy-Con mode. Use Edit layout to move and resize controls. Motion and haptic feedback are optional in Controller settings. Each mode and holding/orientation combination has its own saved layout.</p>
<p>In games or emulators, select the PC's virtual Xbox input device and bind controls as needed. Motion uses the companion's DSU server at <code>127.0.0.1:26760</code>. The phone's player slots P1–P4 correspond to DSU pads 0–3. See the <a href="{REPO}/blob/codex/native-ios-motion/docs/JOYCON_SETUP.md">standalone Joy-Con binding guide</a> for exact mappings.</p>
<h2>Troubleshooting</h2><ul><li><strong>Cannot connect:</strong> allow Local Network in iOS Settings, run the Wi-Fi helper on Windows, and avoid guest networks with client isolation.</li><li><strong>Old QR stopped working:</strong> restart pairing with the new QR after restarting the companion.</li><li><strong>No game input:</strong> confirm ViGEmBus is installed and your game's controller bindings are configured. Preview mode does not create virtual controllers.</li><li><strong>No motion:</strong> enable Motion on the phone, calibrate while still, and configure the game's DSU source. Not every game supports motion or a standalone half.</li></ul>
<div class="card"><h2>Contact support</h2><p><a href="{REPO}/issues/new">Open a support issue on GitHub</a> or <a href="{REPO}/issues">browse existing issues</a>. This is the project's support channel and requires a GitHub account to post.</p><p>Include the app version, iOS version, Windows version and steps to reproduce the problem. GitHub issues are public: do not post pairing keys, QR codes, personal information or private logs.</p></div>
<p><a href="../privacy/">Privacy policy</a>. Phone Controller is an independent app, not affiliated with Nintendo or Microsoft. It does not provide IR, NFC, Nintendo HD rumble or absolute positional tracking.</p>''')

policy = (ROOT / 'ios/IControl/PrivacyPolicy.txt').read_text(encoding='utf-8').strip().split('\n\n')
body = '<p class="eyebrow">Your information</p><h1>Privacy policy</h1>'
for index, part in enumerate(policy):
    if index == 0:
        body += '<p><small>' + escape(part).replace('\n','<br>') + '</small></p>'
    elif '\n' in part:
        heading, text = part.split('\n',1)
        body += '<h2>' + escape(heading) + '</h2><p>' + escape(text) + '</p>'
    else:
        body += '<p>' + escape(part) + '</p>'
body += f'<p><a href="{REPO}/issues/new">Contact the developer through GitHub support</a>.</p>'
page('privacy', 'Privacy policy', body)
print('Generated home, support and privacy pages in public/.')
