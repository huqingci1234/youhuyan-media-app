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

# Give DPAD focus a visible ring on cards; Compose clickable handles focus navigation.
card = Path("app/src/main/java/com/github/avbox/osc/ui/components/PressableCard.kt")
if not card.is_file():
    raise SystemExit("PressableCard.kt not found; refusing to skip TV focus affordance")
card_source = card.read_text(encoding="utf-8")
if "collectIsFocusedAsState" not in card_source:
    card_source = card_source.replace(
        "import androidx.compose.foundation.interaction.collectIsPressedAsState",
        "import androidx.compose.foundation.interaction.collectIsPressedAsState\\nimport androidx.compose.foundation.interaction.collectIsFocusedAsState"
    )
    card_source = card_source.replace(
        "import androidx.compose.foundation.background",
        "import androidx.compose.foundation.background"
    )
    if "import androidx.compose.foundation.border" not in card_source:
        card_source = card_source.replace(
            "import androidx.compose.foundation.interaction.MutableInteractionSource",
            "import androidx.compose.foundation.border\\nimport androidx.compose.foundation.interaction.MutableInteractionSource"
        )
    if "import androidx.compose.material3.MaterialTheme" not in card_source:
        card_source = card_source.replace(
            "import androidx.compose.foundation.shape.RoundedCornerShape",
            "import androidx.compose.foundation.shape.RoundedCornerShape\\nimport androidx.compose.material3.MaterialTheme"
        )
    card_source = card_source.replace(
        "val pressed by interactionSource.collectIsPressedAsState()",
        "val pressed by interactionSource.collectIsPressedAsState()\\n    val focused by interactionSource.collectIsFocusedAsState()"
    )
    card_source = card_source.replace(
        ".clip(shape)\\n            .combinedClickable(",
        ".clip(shape)\\n            .border(width = if (focused) 3.dp else 0.dp, color = MaterialTheme.colorScheme.primary, shape = shape)\\n            .combinedClickable("
    )
    card.write_text(card_source, encoding="utf-8")

tv_manifest = Path("app/src/tv/AndroidManifest.xml")
tv_manifest.parent.mkdir(parents=True, exist_ok=True)
tv_manifest.write_text("""<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-feature
        android:name="android.software.leanback"
        android:required="true" />
    <application>
        <activity
            android:name=".ui.MainActivity"
            android:screenOrientation="landscape" />
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
