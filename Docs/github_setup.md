# GitHub setup and sync runbook

Status checked: 2026-08-21

## Current repository state

- Remote: `https://github.com/Xil146/hvp.git`
- Remote default branch: `main`
- Foundation pull request [#1](https://github.com/Xil146/hvp/pull/1) was reviewed and squash-merged as `8539b30`.
- The public [`HVP Development`](https://github.com/users/Xil146/projects/1) project is linked to the repository with the documented Board view, fields, Status flow, and default automations.
- The active [`Protect main`](https://github.com/Xil146/hvp/rules/21169431) ruleset requires pull requests, resolved conversations, and the exact GitHub Actions check `Windows build, test, publish`; it also blocks force pushes and deletion. The required check was added only after its first successful Phase 0 scaffold run on PR #7.
- The documented repository labels exist. A `dependencies` label is also present because `.github/dependabot.yml` applies it.
- Issues, Discussions, Projects, secret scanning/push protection, and private vulnerability reporting are enabled. The unused wiki and downloads surfaces are disabled.
- This local folder is initialized with `origin` attached and `main` tracks `origin/main`.

No token should ever be pasted into a repository file or chat.

## 1. Verify GitHub CLI authentication

No authentication action is currently needed for the initial sync. Before future GitHub changes, verify:

```powershell
gh auth status
```

If it reports an invalid token, repair it with:

```powershell
gh auth logout -h github.com -u Xil146
gh auth login -h github.com -p https -w
gh auth status
```

The `-w` option opens GitHub's browser/device flow. Sign in as `Xil146` and authorize GitHub CLI. If you prefer SSH, configure an SSH key separately and then change `origin`; HTTPS is simplest here.

## 2. Verify and update a prepared branch

From this repository:

```powershell
git remote -v
git status --short --branch
git log --oneline --decorate -5
git push
```

Pull request #1 followed this process and is merged. Use the same review and merge path for future branches; do not force-push `main`.

## 3. Kanban project configuration

The current project is [`HVP Development`](https://github.com/users/Xil146/projects/1). Its configuration is:

1. Use a **Board** view named `Board`.
2. Create/reorder `Status` options: `Todo`, `Design Check`, `Design`, `Ready`, `In Progress`, `Review`, `Test`, `Done`.
3. Add fields: `Priority` (`P0`-`P3`), `Area`, `Target release`, and `Hardware test required`.
4. Add a workflow that places newly added issues in `Todo`.
5. Add auto-close/archive behavior for items moved to `Done` where appropriate.
6. Add the repository to the project and make the project visible from the repository.

Suggested repository labels:

- Type: `bug`, `feature`, `chore`, `documentation`.
- Area: `ui`, `playback`, `hdr-color`, `audio`, `subtitles`, `persistence`, `packaging`, `testing`.
- Risk: `native-interop`, `security`, `licensing`, `hardware-test`.
- Triage: `needs-design`, `blocked`, `good first issue`.
- Automation: `dependencies` (required by `.github/dependabot.yml`).

Do not duplicate board status as labels.

## 4. Protect `main`

Under **Settings -> Rules -> Rulesets**, add a branch ruleset for `main`:

- require a pull request before merge;
- require at least one approval when more than one maintainer is available;
- require conversation resolution;
- require the exact `Windows build, test, publish` check from GitHub Actions;
- block force pushes and branch deletion;
- optionally require signed commits/tags after signing is established.

Keep administrators subject to the rules once the initial repository setup is stable.

The active ruleset currently requires zero approvals because the repository has one maintainer. Increase this to one approval when a second maintainer is available.

The required CI workflow runs on every pull request so documentation-only PRs
cannot be stranded waiting for a required check that was skipped by path filters.

## 5. Repository settings

- Keep visibility Public.
- Keep Issues, Discussions, Projects, and private vulnerability reporting enabled.
- Keep the description and topics (`windows`, `video-player`, `hdr`, `wpf`, `libmpv`, and `dotnet`) current.
- Keep unused features disabled rather than leaving empty surfaces.
- Do not add Actions secrets until a workflow needs them. Signing secrets require a protected environment and explicit maintainer approval.

## Troubleshooting

- `gh auth status` reports invalid token: repeat the browser login; do not hand-edit tokens.
- Push says non-fast-forward: `git fetch origin`, inspect `git log --left-right --graph HEAD...origin/main`, and reconcile; never use a force push as the first response.
- Git warns about identity: set `git config user.name` and `git config user.email` for this repo or globally, then retry the commit.
- OneDrive lock errors: close tools holding `.git/index.lock`, wait for sync, and retry. Remove a lock file only after confirming no Git process is active.
