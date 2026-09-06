# Contributing

Thank you for helping improve MP.

## Set up

Install Nix with flakes enabled, `devenv`, and the Flutter version in `.fvmrc`.
Then run:

```sh
devenv shell install
devenv shell test:all
```

## Pull requests

Work on a conventional branch such as `feat/camera-orientation`, never directly
on `main`. Keep changes focused, add tests for behavior, and update public API
documentation alongside code.

Any pull request that changes a public package must include a changeset:

```sh
monochange create --interactive
monochange check
monochange step validate
monochange run prepare-release --dry-run --format markdown
```

The `mp` group releases every package at the same version. A package may have no
user-visible change in a particular release, but its version still advances with
the group.

## Quality gates

Before requesting review, run:

```sh
devenv shell lint:all
devenv shell test:all
devenv shell package:check
```

Generated FFI bindings must be reproducible from the pinned upstream tag. Never
edit `bindings.g.dart` manually. Model binaries, credentials, and local native
builds do not belong in Git.

## Platform work

Platform claims require evidence on the corresponding real runtime. Add a
focused integration test, record the tested operating-system/runtime versions,
and avoid silently emulating unsupported upstream behavior.
