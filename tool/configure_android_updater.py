#!/usr/bin/env python3
"""Add the Android permission required to hand a downloaded APK to installer."""
from pathlib import Path

manifest = Path('android/app/src/main/AndroidManifest.xml')
if not manifest.exists():
    raise SystemExit('AndroidManifest.xml was not generated.')

text = manifest.read_text(encoding='utf-8')
permission = '<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />'
if permission in text:
    print('Updater install permission already present.')
    raise SystemExit(0)

indented_application = '    <application'
if indented_application in text:
    text = text.replace(
        indented_application,
        f'    {permission}\n{indented_application}',
        1,
    )
elif '<application' in text:
    text = text.replace(
        '<application',
        f'{permission}\n<application',
        1,
    )
else:
    raise SystemExit('Could not find <application> in AndroidManifest.xml.')

manifest.write_text(text, encoding='utf-8')
print('Android updater install permission added.')
