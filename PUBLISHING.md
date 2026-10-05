# Publishing status

This folder is a standalone source-repository candidate for the personal BioRA macOS app. It contains no parent-repository Git history, user workspace, API keys, app build, or dependency cache. Its Apache-2.0 license applies to this project copy; it does not relicense the mixed parent repository.

The source can be reviewed and published as a GitHub repository separately from the signed-app release. Before distributing a downloadable macOS app:

- Confirm that `com.labmonitor.biora` is an identifier you want to keep for public builds.
- Build, sign, notarize, and test installation on a clean Mac. The local build script uses ad-hoc signing and does not notarize the app.
- Review the complete candidate tree, license, and CI result before making a repository public. This folder has a fresh Git repository and no inherited commit history.

The Swift package has no third-party Swift package dependencies. It imports Apple frameworks and links system SQLite supplied by macOS. The repository does not vendor or redistribute those system libraries.

The app icon in this repository copy was newly generated for BioRA and replaces the icon from the mixed parent project. This checklist is not a legal opinion or a claim that notarization or a release installation test has already been completed.
