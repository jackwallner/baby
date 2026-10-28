#!/usr/bin/env bash
# Fleet TestFlight release. One script for every XcodeGen app:
#
#   1. bump CURRENT_PROJECT_VERSION in project.yml
#   2. xcodegen generate
#   3. archive Release, signed with the App Store Connect API key
#   4. export with destination=upload (the same key, no Xcode Apple ID session)
#   5. commit the isolated bump once Apple reports "Upload succeeded"
#
# Each repo's scripts/testflight.sh is a shim that cds to the repo root and
# execs this with its project and scheme. Run it from a repo root:
#
#   ~/ios/release/testflight.sh --project Vitals.xcodeproj --scheme Vitals
#
# Options:
#   --dry-run                 show the plan, without credentials or side effects
#   --push                    also push this branch, including earlier commits
#   --upload-only [ARCHIVE]   skip the bump and archive; upload an existing
#                             archive (default build/<scheme>.xcarchive)
#   --no-bump                 keep the current build number
#   --clean                   run xcodebuild clean before archiving
#   --archive PATH            archive path (default build/<scheme>.xcarchive)
#   --post-archive CMD        run CMD <archive> after archiving, before upload;
#                             a non-zero exit aborts the upload
#   --team-id ID              signing team (default YXG4MP6W39)
#   --local                   archive and upload on this Mac instead of GitHub
#   -- ARGS...                extra arguments for the archive xcodebuild call
#
# Public repos archive and upload on a free GitHub-hosted Mac through
# ~/bin/gh-testflight (workflow testflight.yml in jackwallner/gh-sim); the bump,
# release-gate record, commit and push still happen here. Private repos and
# --local or --upload-only runs use this Mac's Xcode.
#
# Credentials: ASC_API_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH from the environment,
# else ~/.baseball_credentials. If the archive or upload fails, an untouched
# project.yml is restored so the repo never looks shipped when nothing was.
# The full xcodebuild log is kept at build/testflight-<build>.log.
set -euo pipefail

PROJECT="" SCHEME="" ARCHIVE="" POST_ARCHIVE="" TEAM_ID="${TEAM_ID:-YXG4MP6W39}"
UPLOAD_ONLY=0 BUMP=1 CLEAN=0 DRY_RUN=0 PUSH=0 LOCAL=0
EXTRA_ARGS=()
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --scheme) SCHEME="$2"; shift 2 ;;
    --archive) ARCHIVE="$2"; shift 2 ;;
    --post-archive) POST_ARCHIVE="$2"; shift 2 ;;
    --team-id) TEAM_ID="$2"; shift 2 ;;
    --upload-only) UPLOAD_ONLY=1; shift ;;
    --no-bump) BUMP=0; shift ;;
    --clean) CLEAN=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --push) PUSH=1; shift ;;
    --local) LOCAL=1; shift ;;
    --) shift; EXTRA_ARGS=("$@"); break ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    -*) echo "error: unknown option $1" >&2; exit 2 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done
for arg in ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}; do
  case "$arg" in
    --dry-run|--help|--upload-only|--no-bump|--clean|--push|--local)
      echo "error: release option $arg appears after --; refusing an ambiguous upload" >&2; exit 2 ;;
  esac
done
[[ -n "$PROJECT" && -n "$SCHEME" ]] || { echo "error: --project and --scheme are required" >&2; exit 2; }
ROOT="$PWD"
[[ -f "$ROOT/project.yml" ]] || { echo "error: no project.yml in $ROOT; archive identity needs the repo spec" >&2; exit 2; }
[[ ${#POSITIONAL[@]} -le 1 ]] || { echo "error: unexpected positional arguments" >&2; exit 2; }
ARCHIVE="${ARCHIVE:-${POSITIONAL[0]:-$ROOT/build/$SCHEME.xcarchive}}"
[[ "$ARCHIVE" = /* ]] || ARCHIVE="$ROOT/$ARCHIVE"
# GitHub does the Xcode work unless this already is the runner, the caller asked
# for this Mac, or the repo is private (GitHub would bill its Mac minutes).
REMOTE=0
if [[ -z "${GH_TESTFLIGHT_RUNNER:-}" && $LOCAL -eq 0 && $UPLOAD_ONLY -eq 0 && $DRY_RUN -eq 0 ]]; then
  SLUG=$(git -C "$ROOT" remote get-url origin 2> /dev/null | sed -E 's#^.*github\.com[:/]##; s#\.git$##' || true)
  if [[ -n "$SLUG" ]] && [[ "$(gh api "repos/$SLUG" --jq .private 2> /dev/null)" = false ]]; then
    REMOTE=1
  else
    echo "==> ${SLUG:-This repo} is not a public GitHub repo; archiving on this Mac"
  fi
fi
if [[ $DRY_RUN -eq 1 ]]; then
  echo "DRY TestFlight: project=$PROJECT scheme=$SCHEME archive=$ARCHIVE upload-only=$UPLOAD_ONLY bump=$BUMP push=$PUSH local=$LOCAL"
  echo "DRY Validate archive identity and run post-archive checks before uploading; no actions performed"
  exit 0
fi

# Credentials. The API key signs the archive and authenticates the upload, so a
# missing or stale Xcode Apple ID session cannot fail the run.
CREDENTIALS="${ASC_CREDENTIALS_FILE:-$HOME/.baseball_credentials}"
if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]] && [[ -f "$CREDENTIALS" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$CREDENTIALS"
  set +a
fi
if [[ $REMOTE -eq 0 ]] && [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || ! -f "${ASC_KEY_PATH:-/nonexistent}" ]]; then
  echo "error: ASC_API_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH are required (see $CREDENTIALS)" >&2
  exit 1
fi
AUTH=(-allowProvisioningUpdates
      -authenticationKeyPath "${ASC_KEY_PATH:-}"
      -authenticationKeyID "${ASC_API_KEY_ID:-}"
      -authenticationKeyIssuerID "${ASC_ISSUER_ID:-}")

mkdir -p "$ROOT/build"
BUILD_LABEL="upload"
OLD_BUILD="" NEW_BUILD="" BUMPED=0 UPLOADED=0 BUMP_HASH=""

restore_bump() {
  if [[ $BUMPED -eq 1 && $UPLOADED -eq 0 && "$(shasum -a 256 "$ROOT/project.yml")" == "$BUMP_HASH" ]]; then
    git -C "$ROOT" checkout -- project.yml
    echo "==> Restored project.yml (build $OLD_BUILD); nothing was uploaded" >&2
  elif [[ $BUMPED -eq 1 && $UPLOADED -eq 0 ]]; then
    echo "==> project.yml still carries the bump to $NEW_BUILD and nothing was uploaded" >&2
  fi
}
trap restore_bump EXIT

if [[ $UPLOAD_ONLY -eq 0 ]]; then
  if [[ $BUMP -eq 1 ]]; then
    git -C "$ROOT" diff HEAD --quiet -- project.yml || {
      echo "error: project.yml has pending changes; commit them separately or use --no-bump" >&2; exit 1;
    }
    git -C "$ROOT" diff --cached HEAD --quiet -- project.yml || {
      echo "error: project.yml has staged changes; commit them separately or use --no-bump" >&2; exit 1;
    }
    OLD_BUILD=$(grep -E '^\s*CURRENT_PROJECT_VERSION:' "$ROOT/project.yml" | head -1 \
      | sed -E 's/.*CURRENT_PROJECT_VERSION:[[:space:]]*"?([0-9]+)"?.*/\1/')
    [[ "$OLD_BUILD" =~ ^[0-9]+$ ]] || { echo "error: cannot parse CURRENT_PROJECT_VERSION in project.yml" >&2; exit 1; }
    NEW_BUILD=$((OLD_BUILD + 1))
    echo "==> Bump build $OLD_BUILD -> $NEW_BUILD"
    sed -i.bump-bak -E "s/(CURRENT_PROJECT_VERSION:[[:space:]]*\"?)$OLD_BUILD(\"?)([[:space:]]*(#.*)?)$/\1$NEW_BUILD\2\3/" "$ROOT/project.yml"
    rm -f "$ROOT/project.yml.bump-bak"
    grep -qE "CURRENT_PROJECT_VERSION:[[:space:]]*\"?$NEW_BUILD\"?" "$ROOT/project.yml" || { echo "error: bump did not apply" >&2; exit 1; }
    BUMPED=1
    BUMP_HASH=$(shasum -a 256 "$ROOT/project.yml")
    BUILD_LABEL="$NEW_BUILD"
  else
    BUILD_LABEL=$(grep -E '^\s*CURRENT_PROJECT_VERSION:' "$ROOT/project.yml" | head -1 \
      | sed -E 's/.*CURRENT_PROJECT_VERSION:[[:space:]]*"?([0-9]+)"?.*/\1/')
    echo "==> Keeping build $BUILD_LABEL"
  fi
fi
LOG="$ROOT/build/testflight-$BUILD_LABEL.log"
: > "$LOG"
echo "==> Log: $LOG"

if [[ $REMOTE -eq 1 ]]; then
  echo "==> Archive and upload $SCHEME on a GitHub Mac"
  GH_ARGS=(--project "$PROJECT" --scheme "$SCHEME")
  [[ $CLEAN -eq 1 ]] && GH_ARGS+=(--clean)
  [[ -n "$POST_ARCHIVE" ]] && GH_ARGS+=(--post-archive "$POST_ARCHIVE")
  [[ ${#EXTRA_ARGS[@]} -gt 0 ]] && GH_ARGS+=(-- "${EXTRA_ARGS[@]}")
  GH_TESTFLIGHT=$(command -v gh-testflight || echo "$HOME/bin/gh-testflight")
  if ! "$GH_TESTFLIGHT" "${GH_ARGS[@]}" 2>&1 | tee -a "$LOG"; then
    echo "error: GitHub archive or upload failed (see $LOG)" >&2
    exit 1
  fi
  UPLOADED=1
fi

if [[ $REMOTE -eq 0 && $UPLOAD_ONLY -eq 0 ]]; then
  echo "==> xcodegen generate"
  xcodegen generate >> "$LOG" 2>&1 || { tail -20 "$LOG" >&2; exit 1; }

  if [[ $CLEAN -eq 1 ]]; then
    echo "==> Clean"
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -quiet clean >> "$LOG" 2>&1
  fi

  rm -rf "$ARCHIVE"
  echo "==> Archive $SCHEME (Release) with API key $ASC_API_KEY_ID"
  if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
      -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
      "${AUTH[@]}" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} -quiet archive 2>&1 | tee -a "$LOG"; then
    echo "error: archive failed (see $LOG)" >&2
    exit 1
  fi

fi

if [[ $REMOTE -eq 0 ]]; then
[[ -d "$ARCHIVE" ]] || { echo "error: archive not found: $ARCHIVE" >&2; exit 1; }
python3 "$HOME/ios/release/testflight_archive.py" "$ROOT/project.yml" "$ARCHIVE"
if [[ -n "$POST_ARCHIVE" ]]; then
  echo "==> Post-archive check: $POST_ARCHIVE"
  "$POST_ARCHIVE" "$ARCHIVE" || { echo "error: post-archive check failed; not uploading" >&2; exit 1; }
fi

STAGING="$ROOT/build/upload-staging"
PLIST="$ROOT/build/ExportOptions-upload.plist"
mkdir -p "$STAGING"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>destination</key>
	<string>upload</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
	<key>method</key>
	<string>app-store-connect</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
EOF

echo "==> Upload $(basename "$ARCHIVE") to TestFlight"
set +e
EXPORT_LOG=$(mktemp "${TMPDIR:-/tmp}/testflight-export.XXXXXX")
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$STAGING" \
  -exportOptionsPlist "$PLIST" "${AUTH[@]}" 2>&1 | tee -a "$LOG" "$EXPORT_LOG"
EXPORT_STATUS=${PIPESTATUS[0]}
set -e
if [[ $EXPORT_STATUS -ne 0 ]] || ! grep -q "Upload succeeded" "$EXPORT_LOG"; then
  rm -f "$EXPORT_LOG"
  echo "error: upload did not succeed (exit $EXPORT_STATUS, see $LOG)" >&2
  exit 1
fi
rm -f "$EXPORT_LOG"
UPLOADED=1
fi

# The release gate (~/ios/qa) needs to know which commit this build came from:
# release.py check accepts the build only when that commit has a passing receipt.
# GitHub runners have no ~/ios/qa; the local caller prints the verdict instead.
if [[ $UPLOAD_ONLY -eq 0 && -f "$HOME/ios/qa/qa_gate.py" ]]; then
  python3 "$HOME/ios/qa/qa_gate.py" record-build "$ROOT" "$BUILD_LABEL" >> "$LOG" 2>&1 || true
  if [[ -f "$ROOT/qa/gate.json" ]]; then
    echo "==> Release gate: $(python3 "$HOME/ios/qa/qa_gate.py" verify "$ROOT" --build "$BUILD_LABEL" 2>&1 | tail -1)"
  fi
fi

if [[ $BUMPED -eq 1 ]]; then
  if [[ "$(shasum -a 256 "$ROOT/project.yml")" != "$BUMP_HASH" ]]; then
    echo "error: project.yml changed during the upload; refusing to commit pending edits" >&2
    exit 1
  fi
  git -C "$ROOT" diff --cached HEAD --quiet -- project.yml || {
    echo "error: project.yml was staged during the upload; refusing to overwrite pending index changes" >&2; exit 1;
  }
  git -C "$ROOT" add project.yml
  git -C "$ROOT" commit --only -m "chore: bump build $OLD_BUILD to $NEW_BUILD" -- project.yml >> "$LOG" 2>&1
  if [[ $PUSH -eq 1 ]] && git -C "$ROOT" remote get-url origin >/dev/null 2>&1; then
    git -C "$ROOT" push origin HEAD >> "$LOG" 2>&1 \
      || echo "warning: build $NEW_BUILD uploaded but 'git push origin HEAD' failed; push it by hand" >&2
  fi
fi

echo "==> Build $BUILD_LABEL of $SCHEME uploaded; App Store Connect shows it under TestFlight once processed"
