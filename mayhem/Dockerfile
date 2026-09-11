# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile for mimic1 (small form, on the org C/C++ base).
# Build (from the repo root):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile --build-arg COMMIT=$(git rev-parse HEAD) -t mytag .
FROM ghcr.io/savantenvs/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (available to build.sh); do NOT bake it as an ENV.
ARG SOURCE_DATE_EPOCH
# Declared WITHOUT a default so the base's own SANITIZER_FLAGS ENV flows through unless overridden.
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

# mimic1 is an autotools (automake/libtool) project; the base already has autoconf/automake/
# libtool/pkg-config. It needs libpcre2's headers + .pc file (PKG_CHECK_MODULES([PCRE2],
# [libpcre2-8]) in configure.ac) — the base only ships the runtime .so.
USER root
RUN [ -n "$SOURCE_DATE_EPOCH" ] && repro-sources-list.sh || true ; \
    apt-get update && apt-get install -yq --no-install-recommends libpcre2-dev \
 && rm -rf /var/lib/apt/lists/*

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
