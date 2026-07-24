#!/usr/bin/env bash
# Turn a plain-markdown draft into a Jekyll post and get a PR ready to open.
#
# Usage: scripts/publish.sh drafts/my-post.md
#
# The draft needs no front matter: the first non-empty line is the title
# (a leading "# " is stripped if present), everything after it is the body.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# macOS system Ruby is too old for Jekyll; use the Homebrew Ruby installed
# for this project instead (see Gemfile / README for why).
if [ -d "/opt/homebrew/opt/ruby@3.2/bin" ]; then
	export PATH="/opt/homebrew/opt/ruby@3.2/bin:$PATH"
fi

if [ $# -ne 1 ]; then
	echo "Usage: $0 drafts/my-post.md" >&2
	exit 1
fi

DRAFT="$1"
if [ ! -f "$DRAFT" ]; then
	echo "Draft not found: $DRAFT" >&2
	exit 1
fi

# --- extract title (first non-empty line, leading '# ' stripped) and body ---
TITLE=""
TITLE_LINE_NUM=0
LINE_NUM=0
while IFS= read -r line; do
	LINE_NUM=$((LINE_NUM + 1))
	trimmed="$(echo "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
	if [ -n "$trimmed" ]; then
		TITLE="$(echo "$trimmed" | sed -E 's/^#+[[:space:]]*//')"
		TITLE_LINE_NUM=$LINE_NUM
		break
	fi
done < "$DRAFT"

if [ -z "$TITLE" ]; then
	echo "Couldn't find a title (first non-empty line) in $DRAFT" >&2
	exit 1
fi

BODY="$(tail -n "+$((TITLE_LINE_NUM + 1))" "$DRAFT")"

# --- slugify ---
SLUG="$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
if [ -z "$SLUG" ]; then
	echo "Couldn't derive a slug from title: $TITLE" >&2
	exit 1
fi

DATE="$(date +%F)"
DEST="_posts/${DATE}-${SLUG}.md"

if [ -e "$DEST" ]; then
	echo "$DEST already exists — rename the draft or edit that post directly." >&2
	exit 1
fi

# escape double quotes in the title for the YAML front matter
ESCAPED_TITLE="$(echo "$TITLE" | sed 's/"/\\"/g')"

{
	echo "---"
	echo "layout: post"
	echo "title: \"$ESCAPED_TITLE\""
	echo "date: $DATE"
	echo "---"
	echo
	echo "$BODY"
} > "$DEST"

echo "Wrote $DEST"

echo "Building site locally to check for errors..."
bundle exec jekyll build

BRANCH="post/$SLUG"
git checkout -b "$BRANCH"
git add "$DEST"
git commit -m "Add post: $TITLE"
git push -u origin "$BRANCH"

ORIGIN_URL="$(git config --get remote.origin.url)"
# git@github.com:owner/repo.git  or  https://github.com/owner/repo.git -> owner/repo
REPO_SLUG="$(echo "$ORIGIN_URL" | sed -E 's#^git@github.com:##; s#^https://github.com/##; s#\.git$##')"

COMPARE_URL="https://github.com/${REPO_SLUG}/compare/master...${BRANCH}?expand=1"
echo "Opening PR page: $COMPARE_URL"
open "$COMPARE_URL"

rm "$DRAFT"
echo "Done. Review and click 'Create pull request' in the browser tab that just opened."
