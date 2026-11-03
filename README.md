# cobol-demos

Small, self-contained COBOL applications built with GnuCOBOL. Each app
ships two ways from the same source:

- **CLI**: a native binary, released per app from a git tag
- **Web**: a CGI program behind busybox httpd, deployed as its own Fly app

| App | What it does |
| --- | --- |
| [`amortise`](amortise/) | Loan amortisation schedules: exact decimal maths, edited report output |
| [`ledger`](ledger/) | Batch ledger update: sort, balanced-line master-file update, statements, exceptions and control totals |

## Layout

Every app is a directory that builds, tests and deploys without
reference to anything outside it:

```
<app>/
  src/        COBOL programs: a shared core, a CLI front end, a CGI front end
  copy/       copybooks (record layouts and interfaces)
  tests/      golden-file tests (run.sh, expected/)
  www/        static files served next to the CGI program
  Makefile    build, test, install
  Dockerfile  web image, which also runs the CLI
  fly.toml    the app's own Fly configuration
```

## Working locally

```sh
brew install gnucobol        # or: apt-get install gnucobol3
make test                    # every app
make -C amortise test        # one app
```

Tests compare each program's stdout, stderr and exit status with files in
`tests/expected/`. After a deliberate change in output, regenerate them
with `UPDATE=1 ./tests/run.sh` and review the diff.

## Deployment

Each app has its own workflow (`.github/workflows/<app>.yml`) that only
triggers on changes under its directory. Pushes to `main` run the tests
and then `flyctl deploy` for that app alone. Pull requests only test.

One-off setup per app:

```sh
cd amortise
fly apps create cobol-demos-amortise         # must match app in fly.toml
fly tokens create deploy -a cobol-demos-amortise
# store the token as the repo secret FLY_API_TOKEN_AMORTISE
```

## Releasing a CLI

Push a tag named `<app>-v<version>`:

```sh
git tag amortise-v1.0.0 && git push origin amortise-v1.0.0
```

`release.yml` tests the app and attaches Linux x86_64 and macOS arm64
binaries to a GitHub release. The binaries link against the GnuCOBOL
runtime, so users need `libcob` installed (`brew install gnucobol`, or
`apt-get install libcob4`). The Docker image is the no-dependency
alternative, and `make install PREFIX=...` installs from source.

## Adding an app

1. Create `<app>/` with the layout above, a Makefile providing `build`,
   `test` and `install`, and binaries named `build/<app>`.
2. Copy `.github/workflows/amortise.yml` to `<app>.yml` and replace the
   app name and secret name.
3. Add the app to `APPS` in the root Makefile and to the table above.
