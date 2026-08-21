# GitHub setup and sync runbook

Status checked: 2026-08-21

## Current repository state

- Remote: `https://github.com/Xil146/hvp.git`
- Remote default branch: `main`
- Remote content before this documentation work: one MIT `LICENSE` commit.
- This local folder has been initialized and `origin` added/fetched.
- GitHub CLI account `Xil146` is selected but its saved token is invalid.

No token should ever be pasted into a repository file or chat.

## 1. Re-authenticate GitHub CLI

Open PowerShell and run:

```powershell
gh auth logout -h github.com -u Xil146
gh auth login -h github.com -p https -w
gh auth status
```

The `-w` option opens GitHub's browser/device flow. Sign in as `Xil146` and authorize GitHub CLI. If you prefer SSH, configure an SSH key separately and then change `origin`; HTTPS is simplest here.

## 2. Verify and publish the prepared branch

From this repository:

```powershell
git remote -v
git status --short --branch
git log --oneline --decorate -5
git push -u origin docs/project-foundation
```

Then create a draft pull request:

```powershell
gh pr create --draft --base main --head docs/project-foundation --title "docs: establish HVP architecture and workflow" --fill
```

Review the file list before marking it ready. Merge through GitHub after checks/review; do not force-push `main`.

## 3. Create the Kanban project

In GitHub:

1. Open the `Xil146/hvp` repository, choose **Projects**, then **New project**.
2. Select **Board** and name it `HVP Development`.
3. Create/reorder `Status` options: `Todo`, `Design Check`, `Design`, `Ready`, `In Progress`, `Review`, `Test`, `Done`.
4. Add fields: `Priority` (`P0`-`P3`), `Area`, `Target release`, and `Hardware test required`.
5. Add a workflow that places newly added issues in `Todo`.
6. Add auto-close/archive behavior for items moved to `Done` where appropriate.
7. Add the repository to the project and make the project visible from the repository.

Suggested repository labels:

- Type: `bug`, `feature`, `chore`, `documentation`.
- Area: `ui`, `playback`, `hdr-color`, `audio`, `subtitles`, `persistence`, `packaging`, `testing`.
- Risk: `native-interop`, `security`, `licensing`, `hardware-test`.
- Triage: `needs-design`, `blocked`, `good first issue`.

Do not duplicate board status as labels.

## 4. Protect `main`

Under **Settings -> Rules -> Rulesets**, add a branch ruleset for `main`:

- require a pull request before merge;
- require at least one approval when more than one maintainer is available;
- require conversation resolution;
- require the CI check once the solution exists;
- block force pushes and branch deletion;
- optionally require signed commits/tags after signing is established.

Keep administrators subject to the rules once the initial repository setup is stable.

## 5. Repository settings

- Confirm visibility is Public.
- Enable Issues, Discussions if desired, and private vulnerability reporting.
- Add description/topics such as `windows`, `video-player`, `hdr`, `wpf`, `libmpv`, and `dotnet`.
- Disable unused features rather than leaving empty surfaces.
- Do not add Actions secrets until a workflow needs them. Signing secrets require a protected environment and explicit maintainer approval.

## Troubleshooting

- `gh auth status` reports invalid token: repeat the browser login; do not hand-edit tokens.
- Push says non-fast-forward: `git fetch origin`, inspect `git log --left-right --graph HEAD...origin/main`, and reconcile; never use a force push as the first response.
- Git warns about identity: set `git config user.name` and `git config user.email` for this repo or globally, then retry the commit.
- OneDrive lock errors: close tools holding `.git/index.lock`, wait for sync, and retry. Remove a lock file only after confirming no Git process is active.
