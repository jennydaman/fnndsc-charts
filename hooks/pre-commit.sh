#!/usr/bin/env bash

g="$(git diff --name-only --cached | grep -E 'Chart\.(yaml)|(lock)' | grep oci://localhost)"
if [ -n "$g" ]; then
  echo "Error: some charts depend on the local registry."
  echo "$g"
  exit 1
fi

