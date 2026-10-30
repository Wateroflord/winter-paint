"""Настраивает Android-проект: разрешения и название."""
import pathlib, re
ROOT = pathlib.Path("android/app")
m = ROOT / "src/main/AndroidManifest.xml"
t = m.read_text(encoding="utf-8")
for p in ["android.permission.INTERNET"]:
    if p not in t:
        t = re.sub(r"(<manifest[^>]*>)", rf'\1\n    <uses-permission android:name="{p}"/>', t, count=1)
t = re.sub(r'android:label="[^"]*"', 'android:label="Winter Paint"', t, count=1)

m.write_text(t, encoding="utf-8")
print("patched")
