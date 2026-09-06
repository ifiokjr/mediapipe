{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

let
  isCI = builtins.getEnv "CI" != "";
  extra = inputs.ifiokjr-nixpkgs.packages.${pkgs.stdenv.system};
  resolveFlutterSdk = ''
    unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_PARAMETERS
    unset GIT_CONFIG_COUNT GIT_OBJECT_DIRECTORY GIT_DIR GIT_WORK_TREE
    unset GIT_IMPLICIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX

    if [ "''${CI:-}" = "true" ] && [ -x "''${FLUTTER_ROOT:-}/bin/flutter" ]; then
      flutter_sdk="''${FLUTTER_ROOT}"
    else
      flutter_version="$(awk -F'"' '/"flutter"/ { print $4; exit }' "$DEVENV_ROOT/.fvmrc")"
      if ! [[ "$flutter_version" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "The Flutter version in .fvmrc is missing or invalid." >&2
        exit 1
      fi

      local_flutter_sdk="$DEVENV_ROOT/.fvm/flutter_sdk"
      fvm_cache_root="''${FVM_CACHE_PATH:-''${FVM_HOME:-$HOME/fvm}}"
      cached_flutter_sdk="$fvm_cache_root/versions/$flutter_version"
      if [ -x "$local_flutter_sdk/bin/flutter" ]; then
        flutter_sdk="$local_flutter_sdk"
      elif [ -x "$cached_flutter_sdk/bin/flutter" ]; then
        flutter_sdk="$cached_flutter_sdk"
      else
        echo "Flutter $flutter_version is not installed. Run: fvm install $flutter_version" >&2
        exit 1
      fi
    fi
  '';
  projectHook =
    name: script:
    pkgs.writeShellScript name ''
      set -euo pipefail
      project_root="$(${pkgs.git}/bin/git rev-parse --show-toplevel)"
      cd "$project_root"
      export DEVENV_ROOT="$project_root"
      export PATH="${config.env.DEVENV_PROFILE}/bin:$PATH"
      exec "${config.env.DEVENV_PROFILE}/bin/${script}" "$@"
    '';
in
{
  apple.sdk = null;

  packages =
    with pkgs;
    [
      actionlint
      bazelisk
      curl
      dprint
      fvm
      gitleaks
      jq
      ktlint
      llvm
      extra.monochange
      nixfmt-rfc-style
      patchelf
      shfmt
    ]
    ++ lib.optionals stdenv.isDarwin [
      cocoapods
      coreutils
    ]
    ++ lib.optionals (!stdenv.isDarwin || stdenv.hostPlatform.isAarch64) [
      swift-format
      swiftlint
    ];

  scripts = {
    "repo-flutter" = {
      exec = ''
        set -e
        unset CC CXX LD AR NM RANLIB STRIP OBJCOPY OBJDUMP SIZE STRINGS
        unset NIX_CC NIX_BINTOOLS NIX_CFLAGS_COMPILE NIX_LDFLAGS
        unset SDKROOT MACOSX_DEPLOYMENT_TARGET CFLAGS CXXFLAGS LDFLAGS ARCHFLAGS
        ${resolveFlutterSdk}
        "$flutter_sdk/bin/flutter" "$@"
      '';
      binary = "bash";
      packages = [ pkgs.fvm ];
      description = "Run the repository-pinned Flutter SDK.";
    };
    "repo-dart" = {
      exec = ''
        set -e
        ${resolveFlutterSdk}
        "$flutter_sdk/bin/dart" "$@"
      '';
      binary = "bash";
      packages = [ pkgs.fvm ];
      description = "Run Dart from the repository-pinned Flutter SDK.";
    };
    "repo-swift-format" = {
      exec =
        if pkgs.stdenv.isDarwin then ''exec xcrun swift-format "$@"'' else ''exec swift-format "$@"'';
      description = "Run swift-format from Xcode or the pinned Nix package.";
    };
    install = {
      exec = ''
        set -euo pipefail
        repo-flutter pub get
        (cd docs && repo-dart pub get)
      '';
      description = "Resolve the Dart workspace.";
    };
    "lint:format" = {
      exec = ''
        set -euo pipefail
        repo-dart format --output=none --set-exit-if-changed .
        dprint check
        nixfmt --check devenv.nix
      '';
      description = "Check source and configuration formatting.";
    };
    "lint:dart" = {
      exec = ''
        set -euo pipefail
        repo-dart analyze --fatal-infos .
        (cd docs && repo-dart analyze --fatal-infos .)
      '';
      description = "Run strict Dart analysis.";
    };
    "lint:actions" = {
      exec = "actionlint .github/workflows/*.yml";
      description = "Validate GitHub Actions workflows.";
    };
    "lint:kotlin" = {
      exec = ''
        set -euo pipefail
        kotlin_files=()
        while IFS= read -r -d "" path; do
          kotlin_files+=("$path")
        done < <(git ls-files -z "*.kt" "*.kts")
        ktlint --relative --editorconfig=.editorconfig "''${kotlin_files[@]}"
      '';
      description = "Lint every tracked Kotlin source and Gradle Kotlin script.";
    };
    "lint:swift" = {
      exec = ''
        set -euo pipefail
        swift_files=()
        while IFS= read -r -d "" path; do
          swift_files+=("$path")
        done < <(git ls-files -z "*.swift")
        repo-swift-format lint --strict --parallel --configuration .swift-format \
          "''${swift_files[@]}"
        swiftlint lint --strict --no-cache --config .swiftlint.yml \
          "''${swift_files[@]}"
      '';
      description = "Check swift-format conformance and run SwiftLint on every tracked Swift file.";
    };
    "lint:all" = {
      exec = ''
        set -euo pipefail
        lint:format
        lint:dart
        lint:kotlin
        lint:swift
        lint:actions
        monochange check
      '';
      description = "Run every repository lint.";
    };
    "fix:format" = {
      exec = ''
        set -euo pipefail
        repo-dart format .
        dprint fmt
        nixfmt devenv.nix
      '';
      description = "Format source and configuration files.";
    };
    "fix:kotlin" = {
      exec = ''dprint fmt "**/*.{kt,kts}"'';
      description = "Format Kotlin through dprint and ktlint.";
    };
    "fix:swift" = {
      exec = ''dprint fmt "**/*.swift"'';
      description = "Format Swift through dprint and swift-format.";
    };
    "test:unit" = {
      exec = ''
        set -euo pipefail
        repo-dart test test
        repo-dart run melos exec --dir-exists=test --fail-fast --concurrency=1 -- repo-flutter test test
      '';
      description = "Run unit tests for every public package.";
    };
    "test:native" = {
      exec = ''
        set -euo pipefail
        (cd packages/mp_text && repo-dart test integration_test/native_language_detector_test.dart)
        (cd packages/mp_vision && repo-dart test integration_test/native_face_detector_test.dart)
      '';
      description = "Run real text and vision models through the host MediaPipe C runtime.";
    };
    "test:web" = {
      exec = ''
        set -euo pipefail
        for package in mp_audio mp_core mp_genai mp_vision; do
          repo-dart compile js "packages/$package/example/''${package}_example.dart" \
            -o "/tmp/''${package}_example.js"
        done
        (cd packages/mp_text && repo-dart test --platform chrome integration_test/web_language_detector_test.dart)
      '';
      description = "Compile browser entry points and run real Chrome integration tests.";
    };
    "test:android-build" = {
      exec = "cd packages/mp_text/example && repo-flutter build apk --debug";
      description = "Build the mp_text Android plugin fixture.";
    };
    "test:ios-build" = {
      exec = "cd packages/mp_text/example && repo-flutter build ios --simulator --debug --no-codesign";
      description = "Build the mp_text iOS plugin fixture for the simulator.";
    };
    "test:android-device" = {
      exec = ''
        set -euo pipefail
        device_id="''${SEEKER_DEVICE_ID:-SM02E4060324957}"
        if [ ! -f "$DEVENV_ROOT/.mp-sdk/android-arm64/manifest.json" ]; then
          echo "Build the Android runtime first: native:build --target android-arm64" >&2
          exit 1
        fi
        cd packages/mp_text/example
        repo-flutter test integration_test/native_plugin_contract_test.dart -d "$device_id"
      '';
      description = "Run plugin and classic-runtime tests on an attached Android device.";
    };
    "test:all" = {
      exec = ''
        set -euo pipefail
        test:unit
        test:web
        docs:build
      '';
      description = "Run unit tests and build the documentation site.";
    };
    "docs:serve" = {
      exec = ''
        set -euo pipefail
        ${resolveFlutterSdk}
        export PATH="$flutter_sdk/bin/cache/dart-sdk/bin:$PATH"
        cd docs
        "$flutter_sdk/bin/dart" run jaspr_cli:jaspr serve
      '';
      description = "Serve the documentation site locally.";
    };
    "docs:build" = {
      exec = "repo-dart run tool/build_docs.dart";
      description = "Build the static Jaspr documentation site.";
    };
    "package:check" = {
      exec = "repo-dart run melos exec --no-private --concurrency=1 --fail-fast -- repo-dart pub publish --dry-run";
      description = "Validate all pub.dev package archives.";
    };
    "native:build" = {
      exec = ''repo-dart run tool/build_native.dart "$@"'';
      description = "Build the pinned MediaPipe Tasks C runtime for a host or Android target.";
    };
    "native:package" = {
      exec = ''repo-dart run tool/package_native.dart "$@"'';
      description = "Create a deterministic, checksummed native runtime archive.";
    };
    "native:verify" = {
      exec = ''repo-dart run tool/verify_native.dart "$@"'';
      description = "Verify a native runtime manifest, checksums, and Android ELF properties.";
    };
  };

  git-hooks = lib.mkIf (!isCI) {
    package = pkgs.prek;
    hooks = {
      format = {
        enable = true;
        entry = "${projectHook "mp-format-hook" "lint:format"}";
        pass_filenames = false;
        stages = [ "pre-commit" ];
      };
      analyze = {
        enable = true;
        entry = "${projectHook "mp-analyze-hook" "lint:dart"}";
        pass_filenames = false;
        stages = [ "pre-commit" ];
      };
      gitleaks = {
        enable = true;
        name = "secrets";
        entry = "${pkgs.gitleaks}/bin/gitleaks protect --staged --redact";
        pass_filenames = false;
        stages = [ "pre-commit" ];
      };
    };
  };
}
