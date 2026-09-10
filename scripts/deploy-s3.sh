#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

: "${S3_BUCKET:?Set S3_BUCKET to the destination bucket name}"
s3_prefix="${S3_PREFIX:-}"
destination="s3://${S3_BUCKET}"
if [[ -n "$s3_prefix" ]]; then
  destination="${destination}/${s3_prefix#/}"
fi

test -d _site || {
  echo "_site does not exist; run scripts/render-site.sh first." >&2
  exit 1
}

aws s3 sync _site/ "$destination/" --delete
