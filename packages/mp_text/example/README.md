# mp_text_example

Build fixture for the Android and iOS implementations of `mp_text`.

It verifies that Flutter can register and launch the plugin on both mobile
platforms. The app does not bundle a model because the proofreader and
summarizer models have separate distribution and licensing terms.

Run it from the repository root through devenv:

```sh
devenv shell test:android-build
devenv shell test:ios-build
```

Model-backed tests must provide a compatible `.litertlm` model without
committing it to this repository.
