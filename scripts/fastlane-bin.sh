#!/bin/bash
# Use Homebrew fastlane 2.234+ (supports 11 new ASC locales). Falls back to PATH.
if [[ -x /opt/homebrew/bin/fastlane ]]; then
  exec /opt/homebrew/bin/fastlane "$@"
elif [[ -x /usr/local/bin/fastlane ]]; then
  exec /usr/local/bin/fastlane "$@"
else
  exec fastlane "$@"
fi
