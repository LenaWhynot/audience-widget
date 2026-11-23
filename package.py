#!/usr/bin/env python3
"""Explicit allowlist packaging: never copy runtime state, credentials, QA app or build logs."""
from pathlib import Path
import shutil,hashlib,json,zipfile
ROOT=Path(__file__).resolve().parent
VERSION='1.0.0'
DIST=ROOT/'dist';DIST.mkdir(exist_ok=True)
folder=DIST/f'Audience Widget {VERSION} Universal'
if folder.exists():shutil.rmtree(folder)
folder.mkdir()
shutil.copytree(ROOT/'build/release/Audience Widget.app',folder/'Audience Widget.app')
for src,dst in [('START.html','Начните здесь.html'),('LICENSE.txt','LICENSE.txt'),('THIRD-PARTY.md','THIRD-PARTY.md')]:shutil.copy2(ROOT/src,folder/dst)
source=folder/'Source';source.mkdir()
files=['README.md','LICENSE.txt','THIRD-PARTY.md','START.html','build.py','package.py','src/Core.swift','src/LiveDune.swift','src/KeyStore.swift','src/main.swift','src/icon.swift','tests/main.swift','assets/threads.svg','assets/tiktok.svg','assets/SIMPLE-ICONS-LICENSE.txt']
for name in files:
 dest=source/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/name,dest)
manifest=[]
for p in sorted(folder.rglob('*')):
 if p.is_file():manifest.append({'path':str(p.relative_to(folder)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(folder/'VERSION.json').write_text(json.dumps({'version':VERSION,'architectures':['arm64','x86_64'],'minimum_macos':'13.0','signature':'ad-hoc; not notarized','files':manifest},indent=2))
hashes=[]
for p in sorted(folder.rglob('*')):
 if p.is_file():hashes.append(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+str(p.relative_to(folder)))
(folder/'SHA256.txt').write_text('\n'.join(hashes)+'\n')
archive=DIST/f'AudienceWidget-{VERSION}-macOS-Universal.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for p in sorted(folder.rglob('*')):z.write(p,str(p.relative_to(DIST)))
sha=hashlib.sha256(archive.read_bytes()).hexdigest()
(DIST/'SHA256.txt').write_text(f'{sha}  {archive.name}\n')
print(json.dumps({'zip':str(archive),'bytes':archive.stat().st_size,'sha256':sha}))
