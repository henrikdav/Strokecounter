#!/bin/sh
# Stamps the built app's Info.plist with a build number and commit from git, so every build is numbered higher than
# the one before and the phone can show which build each device runs (Settings). Run by Xcode after each build of
# the iOS and watch apps (postBuildScripts in project.yml), before the app is signed.
#   CFBundleVersion       the number of commits, e.g. 412
#   StrokeCounterCommit   the short commit id, with "+" when there were uncommitted changes, e.g. 1534b1b+
set -e
repo="$SRCROOT/.."
plist="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
build=$(git -C "$repo" rev-list --count HEAD)
commit=$(git -C "$repo" rev-parse --short HEAD)
if [ -n "$(git -C "$repo" status --porcelain)" ]; then commit="$commit+"; fi
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$plist"
/usr/libexec/PlistBuddy -c "Delete :StrokeCounterCommit" "$plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :StrokeCounterCommit string $commit" "$plist"
