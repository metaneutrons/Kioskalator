# Contributing

## Commit convention

[Conventional Commits](https://www.conventionalcommits.org/), without exception.
release-please derives the version and the changelog from the subject lines, so
a commit outside the scheme produces a wrong version or a missing changelog
entry.

```
feat(config): resolve managed preferences ahead of the local file
fix(policy): treat a scheme-relative redirect as a main-frame navigation
docs: describe the locking model
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`,
`ci`, `chore`, `revert`. A breaking change carries `!` after the type and
`BREAKING CHANGE:` in the body.

**The pull request title follows the same scheme.** Merges are squash merges, so
the title becomes the subject line on `main` and decides the next version.

**One pull request carries changes of one kind.** A fix that travels along with
a `feat` pull request is filed under Features in the changelog, where nobody
looks for it. Split the work and merge the parts one after another.

**Everything written into the repository is English** — commit subjects and
bodies, pull request titles and bodies, branch names, changelog entries. A
subject is frozen once pushed; correcting it later means rewriting history.

No AI attribution trailers: no `Co-authored-by:` naming Claude or Anthropic, no
`Generated with Claude Code` line, no `noreply@anthropic.com` as author or
committer. The commit-msg hook and the `commit-hygiene` CI job both reject them.

## Branch naming

`<type>/<short-description>`, matching the commit type, for example
`feat/remote-configuration` or `fix/allowlist-redirect`.

## Local setup

```bash
brew install xcodegen swiftlint lefthook gitleaks
lefthook install
xcodegen generate
```

`xcodegen generate` is required before opening the project: `Kioskalator.xcodeproj`
is generated from `project.yml` and is not committed. Edit `project.yml`, never
the generated project.

## Local checks

What CI runs, in the order it runs it:

```bash
xcrun swift-format lint --strict --recursive App Core/Sources Core/Tests
swiftlint --strict
scripts/check-coverage.sh
xcodegen generate
xcodebuild build -quiet -scheme Kioskalator -destination 'platform=macOS' \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
```

## Two manifests, one authority

The repository has both a SwiftPM package and an Xcode project, and that needs
an explicit division or the two drift:

- **`Core/Package.swift` is authoritative for the dependency graph and the
  lockfile.** `Core/Package.resolved` is the lockfile that gets committed. Add
  every external dependency there, never in `project.yml`.
- **`project.yml` is authoritative for the app product**: targets, entitlements,
  Info.plist and build settings. `Config/Version.xcconfig` holds the single
  `MARKETING_VERSION` that release-please raises.

The app target depends on `Core` as a local package, so `xcodebuild` resolves
the same manifest. CI seeds the generated project's resolved file from
`Core/Package.resolved` and then builds with
`-onlyUsePackageVersionsFromResolvedFile`, so the committed lockfile is the file
that actually governs the app build. Without that seeding step `xcodebuild`
resolves from the network and the committed lockfile describes nothing.

## Formatting and linting

`swift-format` from the toolchain is the formatter. SwiftFormat (nicklockwood)
is deliberately **not** used: two formatters disagree about the same lines and
the repository would then have no defined formatting at all.

`swiftlint --strict` in CI, so a warning fails the run. Disabling a rule inline
is fine where the code is genuinely the exception and the reason stands on the
same line. A file-wide `swiftlint:disable all` is not.

## Tests

Swift Testing for new tests. The logic that decides anything — configuration
resolution, locking, the URL policy, the passcode, the schedules — lives in
`Core/Sources/KioskCore` precisely so it can be tested without a window on
screen.
Code that needs a real screen belongs in `App/` and is kept thin.

Every new gate needs a positive probe and a counter-probe: a valid input must
pass, and a deliberately invalid one must fail for the expected reason. A check
that has only ever seen good input has not demonstrated its failure path.

## Adding a configuration key

A key is not finished until all five are done:

1. A case in `ConfigurationKey` with its type and default.
2. A typed accessor on `KioskConfiguration`.
3. A row in `docs/configuration.md` saying what it does and whether it is
   lockable.
4. A test that shows the resolution order and, for a lockable key, that a lock
   in a higher layer rejects a lower layer's value.
5. A field in the settings pane, or an explicit note in the same pull request
   saying why it has none.
