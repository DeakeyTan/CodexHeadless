#!/usr/bin/env bash

codex_headless_version() {
  if [[ -n "${CODEX_HEADLESS_VERSION:-}" ]]; then
    printf '%s\n' "${CODEX_HEADLESS_VERSION#v}"
    return
  fi
  if [[ -n "${GITHUB_REF_NAME:-}" && "$GITHUB_REF_NAME" == v* ]]; then
    printf '%s\n' "${GITHUB_REF_NAME#v}"
    return
  fi
  local tag
  tag="$(git describe --tags --exact-match 2>/dev/null || true)"
  if [[ "$tag" == v* ]]; then
    printf '%s\n' "${tag#v}"
    return
  fi
  printf '%s\n' "0.9.0-dev"
}
