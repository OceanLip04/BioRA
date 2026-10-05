# Contributing

BioRA is a Swift 6 / SwiftUI macOS project. Keep changes focused on the personal research workspace and preserve the Protocol hierarchy and local-first data boundary.

## Before sending a change

```sh
zsh scripts/test.sh
zsh scripts/build.sh
```

Do not include `.build`, `build`, `PersonalData`, local PDF archives, API keys, model responses containing private research, or macOS metadata files in a pull request. Add or update user-facing strings in both supported languages when changing the interface.

Do not treat a model response as verified experimental evidence. Keep planned work separate from actual observations, preserve Protocol versions, and require review before saving generated content. Never add arbitrary shell or filesystem access for model calls.

Please include the macOS version and a short reproducible description for bug reports. Remove private experiment details, PDF text, screenshots, and credentials from reports.
