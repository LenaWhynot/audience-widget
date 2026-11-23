#!/usr/bin/env python3
"""Build self-contained macOS app. Python is a source-build tool only, never an app dependency."""
from pathlib import Path
import subprocess,plistlib,shutil,sys
ROOT=Path(__file__).resolve().parent
BUILD=ROOT/'build'
QA='--qa' in sys.argv
VERSION='1.0.0'
NAME='Audience Widget QA' if QA else 'Audience Widget'
DEST=BUILD/'qa' if QA else BUILD/'release'
APP=DEST/(NAME+'.app')
MAC=APP/'Contents/MacOS';RES=APP/'Contents/Resources'
MAC.mkdir(parents=True,exist_ok=True);RES.mkdir(parents=True,exist_ok=True)
SDK=subprocess.check_output(['xcrun','--show-sdk-path'],text=True).strip()
sources=[str(ROOT/'src'/n) for n in ['Core.swift','LiveDune.swift','KeyStore.swift','main.swift']]
archs=['arm64'] if QA else ['arm64','x86_64']
parts=[]
for arch in archs:
 out=DEST/('AudienceWidget-'+arch)
 args=['swiftc',*sources,'-O','-gnone','-module-name','AudienceWidget','-sdk',SDK,'-target',arch+'-apple-macos13.0','-file-prefix-map',str(ROOT)+'=AudienceWidget','-debug-prefix-map',str(ROOT)+'=AudienceWidget','-o',str(out),'-framework','AppKit','-framework','SwiftUI','-framework','Security','-framework','LocalAuthentication']
 if QA:args+=['-D','QA']
 subprocess.run(args,check=True)
 parts.append(str(out))
exe=MAC/'AudienceWidget'
if len(parts)>1:subprocess.run(['lipo','-create',*parts,'-output',str(exe)],check=True)
else:shutil.copy2(parts[0],exe)
exe.chmod(0o755)
for name in ['threads.svg','tiktok.svg']:shutil.copy2(ROOT/'assets'/name,RES/name)
icon=BUILD/'icon.png';icons=BUILD/'Audience.iconset';icons.mkdir(parents=True,exist_ok=True)
subprocess.run(['swift',str(ROOT/'src/icon.swift'),str(icon)],check=True)
for size in [16,32,128,256,512]:
 for scale in [1,2]:
  path=icons/f'icon_{size}x{size}{"@2x" if scale==2 else ""}.png'
  subprocess.run(['sips','-z',str(size*scale),str(size*scale),str(icon),'--out',str(path)],check=True,stdout=subprocess.DEVNULL)
subprocess.run(['iconutil','-c','icns',str(icons),'-o',str(RES/'Audience.icns')],check=True)
info={'CFBundleExecutable':'AudienceWidget','CFBundleIdentifier':'app.audiencewidget.desktop.qa' if QA else 'app.audiencewidget.desktop.share','CFBundleName':NAME,'CFBundleDisplayName':NAME,'CFBundleVersion':'1','CFBundleShortVersionString':VERSION,'CFBundlePackageType':'APPL','CFBundleIconFile':'Audience','LSUIElement':True,'LSMinimumSystemVersion':'13.0','NSHighResolutionCapable':True,'NSAppTransportSecurity':{'NSAllowsArbitraryLoads':False}}
with (APP/'Contents/Info.plist').open('wb') as f:plistlib.dump(info,f)
subprocess.run(['codesign','--force','--deep','--sign','-',str(APP)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(APP)],check=True)
print(APP)
