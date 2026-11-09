#!/usr/bin/env bash
# Install Nix, devenv, the Flutter SDK pinned in .fvmrc, and workspace packages.
#
# Idempotent. Nix is a single-user install because this image has no systemd.
# Flakes and nix-command are enabled. devenv and cachix come from nixpkgs, and
# `cachix use devenv` adds the devenv binary cache next to cache.nixos.org.
# Wrappers in /usr/local/bin source the Nix profile, so login shells and
# non-login shells both find `nix` and `devenv` without ~/.bashrc.
#
# After install, from the repository root:
#   devenv shell -- bash -c 'install'
#   devenv shell -- bash -c 'lint:all'
#   devenv shell -- bash -c 'test:unit'
#   devenv shell -- bash -c 'test:web'
#   devenv shell -- bash -c 'docs:build'
#   devenv shell -- bash -c 'docs:links'
#
# iOS and macOS builds need macOS. The Bazel native runtime (`native:build`)
# and attached-device lanes are not part of install.

set -euo pipefail

cd "$(dirname "$0")/.."

flutter_version="$(awk -F'"' '/"flutter"/ { print $4; exit }' .fvmrc)"
if ! [[ "$flutter_version" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "The Flutter version in .fvmrc is missing or invalid." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1 \
  || ! command -v git >/dev/null 2>&1 \
  || ! command -v xz >/dev/null 2>&1 \
  || ! command -v unzip >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils zip
fi

ensure_line() {
  local file="$1"
  local line="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if ! grep -qxF "$line" "$file"; then
    echo "$line" >>"$file"
  fi
}

if [[ ! -x "${HOME}/.nix-profile/bin/nix" ]]; then
  echo "Installing single-user Nix"
  curl -fsSL https://nixos.org/nix/install | sh -s -- --no-daemon --yes
fi

# shellcheck disable=SC1091
. "${HOME}/.nix-profile/etc/profile.d/nix.sh"
ensure_line "${HOME}/.config/nix/nix.conf" "experimental-features = nix-command flakes"
export NIX_CONFIG="${NIX_CONFIG:-}"$'\n'"experimental-features = nix-command flakes"

if [[ ! -x "${HOME}/.nix-profile/bin/cachix" ]]; then
  nix profile add --accept-flake-config nixpkgs#cachix
fi
cachix use devenv
if [[ ! -x "${HOME}/.nix-profile/bin/devenv" ]]; then
  nix profile add --accept-flake-config nixpkgs#devenv
fi

install_wrapper() {
  local name="$1"
  sudo tee "/usr/local/bin/${name}" >/dev/null <<EOF
#!/bin/bash
set -euo pipefail
if [[ -f "\${HOME}/.nix-profile/etc/profile.d/nix.sh" ]]; then
  # shellcheck disable=SC1091
  . "\${HOME}/.nix-profile/etc/profile.d/nix.sh"
fi
exec "\${HOME}/.nix-profile/bin/${name}" "\$@"
EOF
  sudo chmod 755 "/usr/local/bin/${name}"
}

for command_name in nix devenv cachix; do
  install_wrapper "$command_name"
done

sudo tee /etc/profile.d/mp-nix.sh >/dev/null <<'EOF'
# Login shells. Non-login shells use the /usr/local/bin wrappers.
if [ -f "${HOME}/.nix-profile/etc/profile.d/nix.sh" ]; then
  . "${HOME}/.nix-profile/etc/profile.d/nix.sh"
fi
EOF
sudo chmod 644 /etc/profile.d/mp-nix.sh

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
  # `|| true` keeps pipefail from treating SIGPIPE, when awk exits after the
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
mkdir -p "${HOME}/fvm/versions"
ln -sfn "$flutter_home" "${HOME}/fvm/versions/${flutter_version}"

if ! git config --global --get-all safe.directory 2>/dev/null | grep -qx "$flutter_home"; then
  git config --global --add safe.directory "$flutter_home"
fi

export FLUTTER_SUPPRESS_ANALYTICS=1
"$flutter_home/bin/flutter" config --no-analytics --no-cli-animations >/dev/null
"$flutter_home/bin/flutter" precache --linux

echo "Warming the devenv shell"
devenv shell -- true
echo "Resolving the Dart workspace"
devenv shell -- bash -c 'install'
