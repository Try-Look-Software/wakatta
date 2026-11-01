#!/bin/bash
# Files an issue in Try-Look-Software/animango-backend for the fix agent in
# claude-fix-issue.yml, which can only reach other repos through this script.
# Uses BACKEND_REPO_TOKEN, a fine-grained token limited to that repo.
#
# Usage: .github/scripts/file-backend-issue.sh <title> <body>
# Prints the new issue's URL.
set -euo pipefail

if [ "$#" -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
  echo "usage: $0 <title> <body>" >&2
  exit 2
fi
if [ -z "${BACKEND_REPO_TOKEN:-}" ]; then
  echo "BACKEND_REPO_TOKEN isn't set, so backend issues can't be filed from here." >&2
  exit 1
fi

GH_TOKEN="$BACKEND_REPO_TOKEN" gh issue create \
  --repo Try-Look-Software/animango-backend \
  --title "$1" \
  --body "$2"
