"""Point the project-local editor at the Android SDK, Java and a signing key."""
import base64
import json
import os
from pathlib import Path
import re
import subprocess
from bootstrap import VERSIONS, templates, DATA


def prepare():
    sdk = Path(os.environ["ANDROID_HOME"])
    java = Path(os.environ["JAVA_HOME"])
    templates()
    suffix = ".exe" if os.name == "nt" else ""
    # All settings and signing material stay inside this project's ignored .tools.
    key = DATA / "debug.keystore"
    # CI can supply one stable key (base64 in ANDROID_KEYSTORE_BASE64, alias
    # androiddebugkey, password android) so each build installs over the last.
    # Locally, ANDROID_KEYSTORE_FILE can point at the same keystore file.
    supplied = os.environ.get("ANDROID_KEYSTORE_BASE64", "").strip()
    local = os.environ.get("ANDROID_KEYSTORE_FILE", "").strip()
    key.parent.mkdir(parents=True, exist_ok=True)
    if supplied or local:
        key.write_bytes(base64.b64decode(supplied) if supplied else Path(local).read_bytes())
    if not key.exists():
        subprocess.run([str(java / "bin" / ("keytool" + suffix)), "-genkeypair", "-keystore", str(key),
                        "-storepass", "android", "-keypass", "android", "-alias", "androiddebugkey",
                        "-dname", "CN=Canopy Development", "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000"], check=True)
    version = ".".join(VERSIONS["godot"].split(".")[:2])
    settings = DATA / ("editor_settings-" + version + ".tres")
    text = settings.read_text() if settings.exists() else '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
    values = {"export/android/android_sdk_path": str(sdk), "export/android/java_sdk_path": str(java),
              "export/android/debug_keystore": str(key), "export/android/debug_keystore_user": "androiddebugkey",
              "export/android/debug_keystore_pass": "android"}
    for name, value in values.items():
        text = re.sub(r"^" + re.escape(name) + r"=.*\n?", "", text, flags=re.MULTILINE)
        text = text.rstrip() + "\n" + name + "=" + json.dumps(value) + "\n"
    settings.write_text(text)
    return sdk, java, key
