# HotPocket Engine Builder

Evernode hosts compile hpcore, hpfs and hpws from source using the recipe in this folder. Hosts never download an engine binary. A release tag on hpcore resolves to a commit, and that commit fixes the recipe, the manifest and every pinned input.

## Layout
```
builder/
├── README.md              this file
├── engine.json            the engine manifest for this commit
├── deps.lock              pinned third-party sources (name, version, sha256, url)
├── Dockerfile             builder image, one per OS through build args
├── Dockerfile.smoke       clean runtime image used only to smoke test outputs
├── build-engine.sh        compiles everything inside the offline container
└── packages/
    ├── build-ubt20.txt    apt packages needed to compile on Ubuntu 20.04
    ├── build-ubt24.txt
    ├── runtime-ubt20.txt  apt packages the engine needs at run time on 20.04
    └── runtime-ubt24.txt
```

## Engine manifest
`engine.json` describes the engine release for this commit. hpcore's own commit is not in the file, because a host gets it by resolving the tag. Component repos are not in it either. Hosts take repo names from their own config, so a manifest can never redirect a host to a different repo.

| Field | Rule | Checked by |
| --- | --- | --- |
| `schema` | Manifest format. Raise it only when the layout changes in a way older hosts cannot read. | Hosts |
| `version` | Equals the release tag and `HP_VERSION` in `src/util/version.hpp`. | CI on every tag |
| `min_sashimono` | Lowest `sagent version` that can run this release. Raise it whenever hpcore raises `MIN_CONFIG_VERSION` above the template's `hp_version` or needs a new sagent feature. | Hosts, before building |
| `components.*.tag` | Release tag of the component, on its `release` branch. | CI and hosts |
| `components.*.commit` | Equals what `git ls-remote` returns for that tag. | CI and hosts |
| `components.*.version` | Equals what the built binary prints. | Host smoke test |
| `platforms.*` | One entry per supported OS, at most two. The base image is pinned by digest, and apt comes from a dated snapshot. | CI build matrix |

## Updating the pins
Base image digests. Write the full `docker.io/library/ubuntu@sha256:...` value.
```
docker pull ubuntu:20.04 && docker inspect --format '{{index .RepoDigests 0}}' ubuntu:20.04
docker pull ubuntu:24.04 && docker inspect --format '{{index .RepoDigests 0}}' ubuntu:24.04
```

Apt snapshot. Pick a timestamp later than the creation time of every pinned base image, otherwise the base image can hold packages newer than the snapshot and the `-dev` packages fail to install. Then confirm the snapshot exists for every pocket of both codenames.
```
docker image inspect --format '{{.Created}}' <base_image>
for suite in focal focal-updates focal-security noble noble-updates noble-security; do
    curl -fsIL -o /dev/null -w "$suite %{http_code}\n" "https://snapshot.ubuntu.com/ubuntu/20261111T000000Z/dists/$suite/Release"
done
```

Component commits, after hpfs and hpws are tagged. The tags are annotated, so use the commit on the `^{}` line.
```
git ls-remote https://github.com/sankhaBA/hpfs.git 'refs/tags/0.5.1^{}' 'refs/tags/0.5.1'
git ls-remote https://github.com/sankhaBA/hpws.git 'refs/tags/0.9.1^{}' 'refs/tags/0.9.1'
```

## Cutting a release
Components are tagged first, because the manifest names their commits. Release branches move by fast-forward only, and all tags are annotated.

1. For each component that changed, fast-forward its `release` branch to the default branch (`main` for hpfs, `master` for hpws) and push the tag. Its release workflow checks the tag against the source version, builds it, and creates a release with no binaries.
```
git -C hpfs fetch origin && git -C hpfs switch release && git -C hpfs merge --ff-only origin/main
git -C hpfs push origin release
git -C hpfs tag -a 0.5.1 -m "Release 0.5.1" && git -C hpfs push origin 0.5.1
```
2. Put the component tags and commits into `engine.json`, as in [Updating the pins](#updating-the-pins), and merge that to hpcore `main`. CI fails while a named tag is missing or points to another commit.
3. Fast-forward hpcore `release` and push a tag equal to `HP_VERSION`. The engine release workflow verifies the manifest, builds and smoke tests every platform, and publishes a pre-release with no binaries.
```
git -C hpcore fetch origin && git -C hpcore switch release && git -C hpcore merge --ff-only origin/main
git -C hpcore push origin release
git -C hpcore tag -a 0.6.6 -m "Release 0.6.6" && git -C hpcore push origin 0.6.6
gh run watch --repo sankhaBA/hpcore
```
4. After the testnet trial, promote the pre-release.
```
gh release edit 0.6.6 --repo sankhaBA/hpcore --prerelease=false --latest
```
5. To revoke a release, add its version to `engine.revoked` of each affected network in evernode-resources `definitions/definitions.json`.

## Repository variables
The release workflows need these Actions variables. They use only the built-in `GITHUB_TOKEN`, so no secrets are needed.

| Repo | Variable | Value |
| --- | --- | --- |
| hpcore | `RELEASE_BRANCH` | Branch every release tag must be on, normally `release`. |
| hpcore | `ENGINE_REPO_OWNER` | Owner of the hpfs and hpws repos the manifest tags are checked against. |
| hpfs, hpws | `RELEASE_BRANCH` | Branch every release tag must be on, normally `release`. |
