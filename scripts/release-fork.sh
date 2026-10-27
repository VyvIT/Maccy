#!/bin/bash
# Builds, signs and publishes a release of this fork. Fork builds update
# with Sparkle from appcast-vyvit.xml on the fork's master branch.
#
# Usage: scripts/release-fork.sh <version> [release-notes.md]
#        scripts/release-fork.sh --build-only
#
# Release notes are a Markdown file. Lines starting with "- " become list items.
# Everything is built and committed locally first, publishing asks for confirmation.
# --build-only builds and signs the current version into build/release to try it
# before releasing, without changing the version or committing anything.
#
# Environment:
#   FORK_REPO         GitHub repository to publish to (default: VyvIT/Maccy)
#   FORK_REMOTE       git remote of that repository (default: fork)
#   FORK_BRANCH       branch the update feed is read from (default: master)
#   SIGNING_IDENTITY  code signing certificate in Keychain (default: Maccy Self-Signed),
#                     falls back to ad-hoc signing when missing
#   SPARKLE_ACCOUNT   Keychain account of the Sparkle EdDSA key (default: VyvIT-Maccy)
set -euo pipefail

VERSION=${1:?Usage: $0 <version> [release-notes.md] | --build-only}
NOTES_FILE=${2:-}
BUILD_ONLY=0
if [ "$VERSION" = "--build-only" ]; then
  BUILD_ONLY=1
fi
FORK_REPO=${FORK_REPO:-VyvIT/Maccy}
FORK_REMOTE=${FORK_REMOTE:-fork}
FORK_BRANCH=${FORK_BRANCH:-master}
SIGNING_IDENTITY=${SIGNING_IDENTITY:-Maccy Self-Signed}
SPARKLE_ACCOUNT=${SPARKLE_ACCOUNT:-VyvIT-Maccy}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PROJECT=$ROOT/Maccy.xcodeproj/project.pbxproj
APPCAST=$ROOT/appcast-vyvit.xml
BUILD=$ROOT/build/release
APP=$BUILD/DerivedData/Build/Products/Release/Maccy.app
ZIP=$BUILD/Maccy.app.zip
SPARKLE_BIN=$BUILD/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin
cd "$ROOT"

# A self-signed certificate keeps the signature the same between releases,
# so that macOS keeps the Accessibility permission needed for pasting.
if security find-identity -p codesigning | grep -qF "\"$SIGNING_IDENTITY\""; then
  IDENTITY=$SIGNING_IDENTITY
else
  echo "warning: code signing certificate \"$SIGNING_IDENTITY\" not found, signing ad-hoc." >&2
  echo "warning: macOS will ask to grant Accessibility permission again after updating." >&2
  IDENTITY=-
fi

build_app() {
  rm -rf "$BUILD"
  mkdir -p "$BUILD"

  # Without a Developer ID team, the hardened runtime refuses to load the embedded
  # Sparkle framework unless library validation is disabled.
  cp Maccy/Maccy.entitlements "$BUILD/Maccy.entitlements"
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$BUILD/Maccy.entitlements"

  xcodebuild \
    -project Maccy.xcodeproj \
    -scheme Maccy \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$BUILD/DerivedData" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    CODE_SIGN_ENTITLEMENTS="$BUILD/Maccy.entitlements" \
    DEVELOPMENT_TEAM= \
    build > "$BUILD/build.log" 2>&1 || { tail -30 "$BUILD/build.log"; echo "Build failed, see $BUILD/build.log" >&2; exit 1; }

  # Sparkle helpers are copied ad-hoc signed. Sign them with the same identity,
  # inside out, as described in https://sparkle-project.org/documentation/sandboxing/.
  local sparkle=$APP/Contents/Frameworks/Sparkle.framework
  codesign -f -s "$IDENTITY" -o runtime "$sparkle/Versions/B/XPCServices/Installer.xpc"
  codesign -f -s "$IDENTITY" -o runtime --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc"
  codesign -f -s "$IDENTITY" -o runtime "$sparkle/Versions/B/Autoupdate"
  codesign -f -s "$IDENTITY" -o runtime "$sparkle/Versions/B/Updater.app"
  codesign -f -s "$IDENTITY" -o runtime "$sparkle"
  codesign -f -s "$IDENTITY" -o runtime --preserve-metadata=entitlements "$APP"
  codesign --verify --deep --strict "$APP"
}

if [ "$BUILD_ONLY" = 1 ]; then
  echo "Building Maccy signed with ${IDENTITY}…"
  build_app
  echo "Built $APP"
  exit 0
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "Commit or stash your changes first." >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null; then
  echo "Tag $VERSION already exists." >&2
  exit 1
fi
if [ -n "$NOTES_FILE" ] && [ ! -f "$NOTES_FILE" ]; then
  echo "Release notes file $NOTES_FILE not found." >&2
  exit 1
fi

# Undo the version bump and the feed entry when anything fails before the release commit.
COMMITTED=0
trap '[ "$COMMITTED" = 1 ] || git checkout -- "$PROJECT" "$APPCAST"' EXIT

# Sparkle offers an update when its build number is higher than the installed one.
BUILD_NUMBER=$(( $(grep -m1 -oE 'CURRENT_PROJECT_VERSION = [0-9]+' "$PROJECT" | grep -oE '[0-9]+$') + 1 ))
MINIMUM_SYSTEM_VERSION=$(grep -m1 -oE 'MACOSX_DEPLOYMENT_TARGET = [0-9.]+' "$PROJECT" | grep -oE '[0-9.]+$')
sed -i '' -E \
  -e "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/" \
  -e "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $VERSION;/" \
  "$PROJECT"

echo "Building Maccy $VERSION ($BUILD_NUMBER) signed with ${IDENTITY}…"
build_app

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
# Prints sparkle:edSignature="…" length="…" for the appcast enclosure.
SIGNATURE=$("$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" "$ZIP")

python3 -I - "$APPCAST" "$VERSION" "$BUILD_NUMBER" "$MINIMUM_SYSTEM_VERSION" "$FORK_REPO" "$SIGNATURE" "$NOTES_FILE" <<'PYTHON'
import html
import sys
from email.utils import formatdate

appcast, version, build, minimum, repo, signature, notes_file = sys.argv[1:]

items, paragraphs = [], []
for line in (open(notes_file, encoding="utf-8").read().splitlines() if notes_file else []):
    line = line.strip()
    if line.startswith(("- ", "* ")):
        items.append(f"<li>{html.escape(line[2:])}</li>")
    elif line and not line.startswith("#"):
        paragraphs.append(f"<p>{html.escape(line)}</p>")
notes = "".join(paragraphs) + (f"<ul>{''.join(items)}</ul>" if items else "")

item = f"""    <item>
      <title>{version}</title>
      <description><![CDATA[{notes}]]></description>
      <pubDate>{formatdate(localtime=True)}</pubDate>
      <sparkle:releaseNotesLink>https://github.com/{repo}/releases/tag/{version}</sparkle:releaseNotesLink>
      <sparkle:minimumSystemVersion>{minimum}</sparkle:minimumSystemVersion>
      <enclosure
        url="https://github.com/{repo}/releases/download/{version}/Maccy.app.zip"
        sparkle:version="{build}"
        sparkle:shortVersionString="{version}"
        {signature}
        type="application/octet-stream"
      />
    </item>
"""

content = open(appcast, encoding="utf-8").read()
# Newest release goes first.
anchor = "    <item>" if "    <item>" in content else "  </channel>"
open(appcast, "w", encoding="utf-8").write(content.replace(anchor, item + anchor, 1))
PYTHON
xmllint --noout "$APPCAST"

git add "$PROJECT" "$APPCAST"
git commit -q -m "Release $VERSION"
git tag "$VERSION"
COMMITTED=1
echo "Built $ZIP and committed release $VERSION with tag $VERSION."

read -r -p "Publish $VERSION to $FORK_REPO and update its feed on $FORK_BRANCH? [y/N] " answer
if [ "$answer" != "y" ]; then
  echo "Not published. Run these when ready:"
  echo "  git push $FORK_REMOTE $VERSION"
  echo "  gh release create $VERSION '$ZIP' --repo $FORK_REPO --title $VERSION --verify-tag${NOTES_FILE:+ --notes-file '$NOTES_FILE'}"
  echo "  git push $FORK_REMOTE HEAD:$FORK_BRANCH"
  exit 0
fi

# The release must exist before the feed points to it.
git push "$FORK_REMOTE" "$VERSION"
if [ -n "$NOTES_FILE" ]; then
  gh release create "$VERSION" "$ZIP" --repo "$FORK_REPO" --title "$VERSION" --verify-tag --notes-file "$NOTES_FILE"
else
  gh release create "$VERSION" "$ZIP" --repo "$FORK_REPO" --title "$VERSION" --verify-tag --generate-notes
fi
git push "$FORK_REMOTE" "HEAD:$FORK_BRANCH"
echo "Published. Fork builds will be offered $VERSION on their next update check."
