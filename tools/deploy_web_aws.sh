#!/usr/bin/env bash
# Deploy the Godot HTML5 export to S3 (served via CloudFront).
#
# Prereqs (one-time): see tools/aws-web-deploy.md for creating the bucket,
# the CloudFront distribution, and the COOP/COEP response-headers policy.
#
# Usage:
#   1. In Godot: Project > Export > Web > Export Project to  web/index.html
#   2. S3_BUCKET=your-bucket CF_DISTRIBUTION_ID=E123ABC ./tools/deploy_web_aws.sh
#
# Env vars:
#   S3_BUCKET            (required) target bucket name
#   CF_DISTRIBUTION_ID   (optional) CloudFront id; if set, the cache is invalidated
#   WEB_DIR              (optional) export folder, default "web"
set -euo pipefail

WEB_DIR="${WEB_DIR:-web}"
: "${S3_BUCKET:?set S3_BUCKET to your bucket name}"
CF_DISTRIBUTION_ID="${CF_DISTRIBUTION_ID:-}"

if [ ! -f "$WEB_DIR/index.html" ]; then
	echo "ERROR: $WEB_DIR/index.html not found." >&2
	echo "Export the Web preset first: Godot > Project > Export > Web > Export Project." >&2
	exit 1
fi

LONG="public,max-age=31536000,immutable"   # hashed engine assets never change
SHORT="public,max-age=60"                  # entry html/json re-checked often

echo "==> Syncing $WEB_DIR/ to s3://$S3_BUCKET (removing stale files)"
aws s3 sync "$WEB_DIR/" "s3://$S3_BUCKET/" --delete --no-progress --cache-control "$LONG"

# S3/AWS CLI can guess these wrong; re-upload with the content-type browsers
# (and Godot's loader) require. .wasm in particular MUST be application/wasm.
fix() { # glob  content-type  cache-control
	find "$WEB_DIR" -name "$1" -type f | while read -r f; do
		rel="${f#"$WEB_DIR"/}"
		aws s3 cp "$f" "s3://$S3_BUCKET/$rel" \
			--content-type "$2" --cache-control "$3" --no-progress
	done
}

echo "==> Fixing content-types"
fix '*.wasm' application/wasm         "$LONG"
fix '*.pck'  application/octet-stream "$LONG"
fix '*.js'   text/javascript          "$LONG"
fix '*.html' text/html                "$SHORT"
fix '*.json' application/json         "$SHORT"

if [ -n "$CF_DISTRIBUTION_ID" ]; then
	echo "==> Invalidating CloudFront ($CF_DISTRIBUTION_ID)"
	aws cloudfront create-invalidation \
		--distribution-id "$CF_DISTRIBUTION_ID" --paths "/*" >/dev/null
	echo "    invalidation requested"
fi

echo "==> Done. Open your CloudFront domain (https://dxxxx.cloudfront.net) to play."
