# Nexus package index — staging

The **staging** index of Nexus-Lang packages: where the official index's automation,
its mirror and the tools (`nxpkg`, `nxapp`) are tried end to end before the official
index opens. **It may be reset at any time**: do not depend on it.

It is read over HTTPS, file by file, at <https://index-staging.nx-lang.org/>:

```sh
nxapp info  zlog --index https://index-staging.nx-lang.org/
nxapp install zlog --index https://index-staging.nx-lang.org/
```

or, in `~/.nexus/config.toml`:

```toml
[index.staging]
url  = "https://github.com/nxlang/index-staging.git"
http = "https://index-staging.nx-lang.org/"
require-signature = true
```

## Layout

- `index.toml`: the index's name and rules (`require-signature`: every built package is
  signed).
- one file per package, at a path made from its name (`he/ll/hello.toml`, as
  crates.io lays out its index), and `names`, the list of every package; each file: its owners, its signing keys, its versions (each
  with its public git source, commit and `nxsum2` checksum, and its built packages).

Packages are added by pull request (`nxpkg publish`); the checks run
`nxpkg index check`. Only packages with public sources are accepted.

## Rules

- A published version is never deleted, only yanked.
- The first publisher of a name becomes its owner; a new name, and a change of owners or
  signing keys, is reviewed by a person.
- Reserved: the standard library's module names, `std`, `nexus`, and names one edit away
  from an existing one unless a person accepts it.

## Automation

- `.github/workflows/check.yml`: on every pull request, `nxpkg index check --base
  <base> --verify-build` in two passes, everything downloaded first (`--fetch-only`),
  then the builds with no network at all (`--offline`, in an empty network namespace:
  `.github/scripts/offline.sh`), and the ownership check (`.github/scripts/owners.sh`);
  a new name, or a change of owners or signing keys, is flagged for a person. No
  secret, a read-only token, nothing of the pull request executed.
- `.github/workflows/mirror.yml`: after a merge, each new version's sources (`nxpkg
  index mirror-archive`) and built packages copied to this repository's releases (one
  per package), and named in `mirror` and `urls` (`.github/scripts/mirror.sh`, which
  also runs by hand with `gh` logged in).
- `.github/workflows/periodic.yml`: every Monday, `nxpkg index check --remote` (every
  URL downloaded and checksummed, the mirror included), its report kept; one issue per
  package with a problem, addressed to its owners, closed once fixed; after four weeks,
  an original URL that a mirror backs is removed from `urls`
  (`.github/scripts/report.sh`).

Both are **inactive until the toolchain is public**: they run once the repository
variables `NEXUS_TOOLCHAIN_URL` and `NEXUS_TOOLCHAIN_SHA256` name its archive. Changes to
`.github/` are pushed by the organisation, not by pull request (`index check` accepts
only the packages' files, `names` and `index.toml` in one).

Security: see [SECURITY.md](SECURITY.md).
