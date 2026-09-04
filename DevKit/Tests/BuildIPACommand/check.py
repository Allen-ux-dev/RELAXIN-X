from pathlib import Path
import sys

root = Path(__file__).resolve().parents[3]
script = root / "BuildIPA.command"

errors = []
if not script.exists():
    errors.append("BuildIPA.command is missing")
else:
    text = script.read_text(encoding="utf-8")
    required = {
        "macOS preflight": '[[ "$(uname -s)" == "Darwin" ]]',
        "Xcode preflight": "xcodebuild -version",
        "iPhoneOS SDK preflight": "xcrun --sdk iphoneos --show-sdk-path",
        "official ipa target": 'make -C "$BUILD_ROOT_DIR" ipa IPA_OUTPUT="$STAGING_IPA"',
        "fixed output": 'OUTPUT_IPA="$OUTPUT_DIR/RELAXIN-X.ipa"',
        "archive integrity": 'unzip -tq "$STAGING_IPA"',
        "Info.plist validation": "Info.plist",
        "main executable validation": "CFBundleExecutable",
        "signing material rejection": "embedded.mobileprovision",
        "staged sha256": 'shasum -a 256 "$STAGING_IPA"',
        "portable sha256 filename": 'basename "$OUTPUT_IPA"',
    }
    for name, needle in required.items():
        if needle not in text:
            errors.append(f"missing {name}: {needle}")

if errors:
    print("BuildIPACommand: FAIL")
    for error in errors:
        print(f"- {error}")
    sys.exit(1)

print("BuildIPACommand: PASS")
