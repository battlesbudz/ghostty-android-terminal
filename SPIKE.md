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
   NDK 28.2.13676358 (upstream's own pin), Alpine rootfs produced by
   upstream's own `scripts/build-alpine-rootfs.sh` (official minirootfs,
   sha256 sidecar verified), `./gradlew :app:assembleDebug`, APK uploaded
   as a workflow artifact and attached to a GitHub release in the same run.
2. `app/build.gradle` — **unchanged, byte-identical to upstream.** An
   interim pin of `ndkVersion` to 27.2.12479018 (an artifact of the
   machine that first staged this spike, which could not obtain NDK r28)
   was tried and reverted: upstream's `backend_x86_64.c` calls
   `__builtin_cpu_supports("f16c")`, which only NDK r28's clang accepts,
   so the build requires upstream's pinned NDK.
3. This file (new).
4. `native/arm64emu` — the pinned submodule commit
   (`597189c644e02a175a613f08df3a83afae1cacbf`) is vendored into this
   repository as a plain tree, byte-identical to that commit's tree
   (tree SHA `831629000ccaaf3c85b4dd2b27616dd47ca28ffd`, verified blob by
   blob). Reason: upstream rewrote sylirre/arm64emu's history the same
   day this fork was made (arm64emu, arm64emu-user and chroot-ng were
   merged into a single repository), and the pinned commit no longer
   exists on GitHub, so no git fetch can check it out. The content is
   upstream's, unmodified; the other two submodules
   (`native/arm64chroot`, `native/chroot-ng`) still fetch from upstream
   normally.

Everything else — every line of application and native code — is upstream,
unmodified.
