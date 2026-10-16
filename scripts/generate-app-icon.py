#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Export the README's SVG to checked-in macOS assets (requires librsvg/iconutil)."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
renderer = shutil.which('rsvg-convert')
if not renderer:
    raise SystemExit('Install librsvg (for example: brew install librsvg) to regenerate icons.')
source = ROOT / 'docs/images/keyhatch.svg'
catalog = ROOT / 'Resources/Assets.xcassets'
appicon = catalog / 'AppIcon.appiconset'
appicon.mkdir(parents=True, exist_ok=True)
info = {'author': 'xcode', 'version': 1}
images = []
with tempfile.TemporaryDirectory(prefix='keyhatch-icon-') as temporary:
    iconset = Path(temporary) / 'Keyhatch.iconset'
    iconset.mkdir()
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            filename = f'icon_{size}x{size}' + ('@2x' if scale == 2 else '') + '.png'
            output = iconset / filename
            subprocess.run([renderer, '--width', str(size * scale), '--height', str(size * scale),
                            '--output', str(output), str(source)], check=True)
            shutil.copyfile(output, appicon / filename)
            images.append({'idiom': 'mac', 'size': f'{size}x{size}',
                           'scale': f'{scale}x', 'filename': filename})
    subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o',
                    str(ROOT / 'Resources/Keyhatch.icns')], check=True)
(catalog / 'Contents.json').write_text(json.dumps({'info': info}, indent=2) + '\n')
(appicon / 'Contents.json').write_text(json.dumps({'images': images, 'info': info}, indent=2) + '\n')
print('Generated macOS AppIcon catalog and Keyhatch.icns from docs/images/keyhatch.svg')
