#!/usr/bin/env bash
# Install the Flutter SDK pinned in .fvmrc and resolve the Dart workspace.
#
# Idempotent: a second run reuses /opt/flutter when its version already matches
# and only refreshes package resolution. Tooling is linked into /usr/local/bin
# because Cloud Agent install and start are login shells that do not load
# ~/.bashrc.
#
# After install, from the repository root:
#   dart format --output=none --set-exit-if-changed .
#   dart analyze --fatal-infos .
#   (cd docs && dart analyze --fatal-infos .)
#   dart test test
#   dart run melos exec --dir-exists=test --fail-fast --concurrency=1 -- flutter test test
#
# `docs` is outside the workspace pubspec, so it has its own package config.
# iOS builds need macOS. The full `devenv shell lint:all` gate (Kotlin, Swift,
# dprint, actionlint, monochange, mdt) and the Bazel native runtime build stay
# on the Nix toolchain used in CI; this script prepares the Linux Dart/Flutter
# path those jobs also run.

set -euo pipefail

cd "$(dirname "$0")/.."

flutter_version="$(awk -F'"' '/"flutter"/ { print $4; exit }' .fvmrc)"
if ! [[ "$flutter_version" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "The Flutter version in .fvmrc is missing or invalid." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1 || ! command -v xz >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils zip
fi

install_flutter() {
  local archive url tmp
  archive="flutter_linux_${flutter_version}-stable.tar.xz"
  url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${archive}"
  tmp="$(mktemp)"
  echo "Downloading Flutter ${flutter_version}"
  curl -fsSL "$url" -o "$tmp"
  rm -rf /tmp/flutter-extract
  mkdir -p /tmp/flutter-extract
  tar -xJf "$tmp" -C /tmp/flutter-extract
  rm -f "$tmp"
  sudo rm -rf /opt/flutter
  sudo mv /tmp/flutter-extract/flutter /opt/flutter
  sudo chown -R "$(id -u):$(id -g)" /opt/flutter
  rm -rf /tmp/flutter-extract
}

version_line=""
if [[ -x /opt/flutter/bin/flutter ]]; then
  # `|| true` keeps `pipefail` from treating SIGPIPE, when awk exits after the
  # first line, as a failed version check.
  version_line="$(/opt/flutter/bin/flutter --version 2>/dev/null | awk 'NR==1 { print; exit }' || true)"
fi

if [[ -n "${FLUTTER_ROOT:-}" && -x "${FLUTTER_ROOT}/bin/flutter" ]]; then
  flutter_home="$FLUTTER_ROOT"
elif [[ "$version_line" == "Flutter ${flutter_version} "* ]]; then
  flutter_home=/opt/flutter
else
  install_flutter
  flutter_home=/opt/flutter
fi

sudo ln -sfn "${flutter_home}/bin/flutter" /usr/local/bin/flutter
sudo ln -sfn "${flutter_home}/bin/dart" /usr/local/bin/dart

if ! git config --global --get-all safe.directory 2>/dev/null | grep -qx "$flutter_home"; then
  git config --global --add safe.directory "$flutter_home"
fi

export FLUTTER_ROOT="$flutter_home"
export FLUTTER_SUPPRESS_ANALYTICS=1
export CI=true

flutter config --no-analytics --no-cli-animations >/dev/null
flutter precache --linux
flutter pub get
(cd docs && dart pub get)
