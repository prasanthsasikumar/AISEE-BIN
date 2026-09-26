#!/bin/sh
# Downloads Immersal's native iOS library (SDK 2.4.0) for device builds. The
# SDK licence does not allow redistributing it, so it is not in the repo; the
# Xcode project runs this before every build and it is a no-op once present.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$DIR/libPosePlugin.a"
URL="https://raw.githubusercontent.com/immersal/imdk-unity/2.4.0/Runtime/Plugins/iOS/libPosePlugin.a"
SHA="45fad535dcbf0139feb9b15dafe74c8315436db21a138271924e10e56d2fca8f"
if [ -f "$LIB" ] && [ "$(shasum -a 256 "$LIB" | cut -d' ' -f1)" = "$SHA" ]; then exit 0; fi
echo "Fetching libPosePlugin.a (Immersal SDK 2.4.0)"
curl -fsSL -o "$LIB.tmp" "$URL"
GOT="$(shasum -a 256 "$LIB.tmp" | cut -d' ' -f1)"
if [ "$GOT" != "$SHA" ]; then echo "libPosePlugin.a sha256 mismatch: $GOT" >&2; rm -f "$LIB.tmp"; exit 1; fi
mv "$LIB.tmp" "$LIB"
