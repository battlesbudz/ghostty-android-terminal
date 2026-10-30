# Sandbox feasibility spike (fork)

This repository is a **fork of
[sylirre/ghostty-android-terminal](https://github.com/sylirre/ghostty-android-terminal)**,
kept as a fork deliberately so that upstream attribution is inherent and
upstream gets visible usage. All application code is upstream's work; the
upstream [LICENSE](LICENSE) (Apache-2.0) and [NOTICE](NOTICE) files are
preserved untouched. (libghostty, vendored by upstream, is MIT-licensed;
see upstream's notices.)

Upstream base commit: `b75be1c28d606c2206616aacf1489e063f4bd751`.

## Purpose

A Phase 0 feasibility spike for Faraday, a separate project: can an
arm64chroot + libghostty terminal app — where guest code is never executed
from app-writable storage, so Android's W^X / SELinux rules at modern
targetSdk are not a blocker — run a real Alpine Linux userland on a current
phone fast enough to serve as an on-device sandbox? This fork exists only
to build that proof app via GitHub Actions. No app behavior is changed.

## Changes vs upstream (complete list)

1. `.github/workflows/build-spike.yml` (new) — manual `workflow_dispatch`
   build: Temurin JDK 21, Android SDK platform 36 + build-tools 36.0.0 +
   NDK 27.2.12479018, Alpine rootfs produced by upstream's own
   `scripts/build-alpine-rootfs.sh` (official minirootfs, sha256 sidecar
   verified), `./gradlew :app:assembleDebug`, APK uploaded as a workflow
   artifact and attached to a GitHub release in the same run.
2. `app/build.gradle` — `ndkVersion "28.2.13676358"` → `"27.2.12479018"`
   (build-only pin; upstream's README requires NDK r27+).
3. This file (new).

Everything else — every line of application and native code — is upstream,
unmodified.
