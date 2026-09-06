# docs

The Jaspr source for the MP API and package documentation.

## Serve locally

From the repository root:

```sh
devenv shell docs:serve
```

## Build

```sh
devenv shell docs:build
```

The generated static site is written to `docs/build/jaspr/` with links rooted
at `/mediapipe/` for GitHub Pages.
