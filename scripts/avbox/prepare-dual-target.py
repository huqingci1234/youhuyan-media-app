#!/usr/bin/env python3
"""Apply the maintained dual-target overlay to a clean AVBox checkout."""
from pathlib import Path
import re

gradle = Path("app/build.gradle.kts")
if not gradle.is_file():
    raise SystemExit("Expected AVBox app/build.gradle.kts was not found")
source = gradle.read_text(encoding="utf-8")

if 'create("mobile")' not in source and 'create("tv")' not in source:
    anchor = re.search(r'(?m)^\s*signingConfigs\s*\{', source)
    if not anchor:
        raise SystemExit("Could not find signingConfigs insertion point; refusing to patch unknown Gradle layout")
    flavors = '''
    flavorDimensions += "client"
    productFlavors {
        create("mobile") {
            dimension = "client"
            applicationId = "com.youhuyan.media"
        }
        create("tv") {
            dimension = "client"
            applicationId = "com.youhuyan.media.tv"
        }
    }

'''
    source = source[:anchor.start()] + flavors + source[anchor.start():]
elif not ('create("mobile")' in source and 'create("tv")' in source):
    raise SystemExit("Partial flavor configuration detected; refusing ambiguous patch")

source = source.replace(
    'output.outputFileName.set("AVBox_${variant.buildType}.apk")',
    'output.outputFileName.set("YouHuYan_${variant.name}.apk")'
)
gradle.write_text(source, encoding="utf-8")

tv_manifest = Path("app/src/tv/AndroidManifest.xml")
tv_manifest.parent.mkdir(parents=True, exist_ok=True)
tv_manifest.write_text("""<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application>
        <activity-alias
            android:name=".TvLauncherActivity"
            android:targetActivity=".ui.MainActivity"
            android:exported="true"
            android:label="@string/app_name"
            android:banner="@mipmap/ic_launcher">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LEANBACK_LAUNCHER" />
            </intent-filter>
        </activity-alias>
    </application>
</manifest>
""", encoding="utf-8")
print("Applied mobile/tv product flavors and TV Leanback launcher alias.")
