#!/usr/bin/env python3
"""Patch Flutter's generated Android Kotlin Gradle file for stable release signing.

The repository intentionally generates android/ in CI. This script is run only
for tagged production releases after android/key.properties and the keystore
have been created from GitHub Secrets.
"""
from pathlib import Path

path = Path('android/app/build.gradle.kts')
if not path.exists():
    raise SystemExit('android/app/build.gradle.kts was not generated.')

text = path.read_text(encoding='utf-8')
if 'ptReleaseSigningConfigured' in text:
    print('Release signing is already configured.')
    raise SystemExit(0)

imports = '''import java.io.FileInputStream\nimport java.util.Properties\n\n'''
if not text.startswith('import java.io.FileInputStream'):
    text = imports + text

properties = '''\n// ptReleaseSigningConfigured\nval keystoreProperties = Properties()\nval keystorePropertiesFile = rootProject.file("key.properties")\nif (!keystorePropertiesFile.exists()) {\n    throw GradleException("android/key.properties is required for tagged release builds")\n}\nkeystoreProperties.load(FileInputStream(keystorePropertiesFile))\n\n'''
plugins_index = text.find('plugins {')
if plugins_index < 0:
    raise SystemExit('Could not find plugins block in generated build.gradle.kts.')
# Place declarations after plugins, because Kotlin Gradle scripts require the
# plugins block before ordinary executable script statements.
plugins_end = text.find('\n}\n', plugins_index)
if plugins_end < 0:
    raise SystemExit('Could not locate the end of the plugins block.')
plugins_end += 3
text = text[:plugins_end] + properties + text[plugins_end:]

signing = '''\n    signingConfigs {\n        create("release") {\n            keyAlias = keystoreProperties["keyAlias"] as String\n            keyPassword = keystoreProperties["keyPassword"] as String\n            storeFile = file(keystoreProperties["storeFile"] as String)\n            storePassword = keystoreProperties["storePassword"] as String\n        }\n    }\n\n'''
build_types = text.find('    buildTypes {')
if build_types < 0:
    raise SystemExit('Could not find buildTypes block in generated build.gradle.kts.')
text = text[:build_types] + signing + text[build_types:]

old = 'signingConfig = signingConfigs.getByName("debug")'
new = 'signingConfig = signingConfigs.getByName("release")'
if old not in text:
    raise SystemExit('Generated release signing line was not found; Flutter template changed.')
text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')
print('Stable Android release signing configured.')
