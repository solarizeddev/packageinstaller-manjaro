#!/bin/bash
# Merges the latest upstream (CachyOS/packageinstaller) into this checkout,
# checks what the Manjaro build needs after a merge, then builds, tests and
# installs the package (makepkg -sif). Nothing is pushed.
#
# Usage: tools/update-upstream.sh [--no-install] [--no-logo] [REF]
#   REF          what to merge; by default upstream's newest v2.* release tag,
#                or upstream/fresh while 2.0 has no tag yet
#   --no-install merge and check only
#   --no-logo    build with a generic icon in place of the Manjaro logo
#                (same as NO_MANJARO_LOGO=1 makepkg -sif)
#
# On conflicts it stops; fix them, commit, and run it again to go on.
# After it: try the app, then git push.
set -euo pipefail
self=$(readlink -f "$0")
cd "$(dirname "$self")/.."

upstream_url=https://github.com/CachyOS/packageinstaller.git
install=1
ref=
for arg in "$@"; do
    case $arg in
    --no-install) install=0 ;;
    --no-logo) export NO_MANJARO_LOGO=1 ;;
    -h | --help) sed -n '2,15p' "$self" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) ref=$arg ;;
    esac
done

# README.md is manjaro/README-header.md followed by upstream's README without
# its title: on a conflict take upstream's and put the header back.
readme_with_header() {
    { cat manjaro/README-header.md; sed '1{/^# /d}' README.md | sed '/./,$!d'; } > README.md.new
    mv README.md.new README.md
}

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# Conflicts that resolve themselves: README.md (upstream's, with our header put
# back); screenshots/ holds our
# pictures under upstream's names (keep ours, see the check after the merge).
resolve_known() {
    local conflicted
    conflicted=$(git diff --name-only --diff-filter=U)
    if grep -qx README.md <<<"$conflicted"; then
        git checkout --theirs -- README.md
        readme_with_header
        git add README.md
    fi
    grep '^screenshots/' <<<"$conflicted" | while read -r file; do
        git checkout --ours -- "$file" && git add "$file"
    done
    [ -n "$(git diff --name-only --diff-filter=U)" ] || git commit --no-edit >/dev/null
}

conflict_help() {
    cat <<'EOF'

Our changes are marked "Manjaro fork" in the code; MANJARO.md lists them all
("What differs from upstream"). In each file keep upstream's new code and put
our marked lines back. Then:
  git add <files> && git commit       (or: git merge --abort to undo)
and run this script again: it goes on with the checks and the install.
EOF
}

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Uncommitted changes: commit or stash them first." >&2
    exit 1
fi

git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$upstream_url"
say "Fetching upstream"
git fetch --quiet --tags upstream

if [ -z "$ref" ]; then
    # upstream's own release tags (not tags this clone may have from elsewhere)
    ref=$(git ls-remote --tags --refs upstream 'v2.*' | sed 's|.*refs/tags/||' | sort -V | tail -n1)
    [ -n "$ref" ] || ref=upstream/fresh
fi
# a tag is taken from upstream itself: a clone can hold a same-named tag from elsewhere
case $ref in
v*) git fetch --quiet --force upstream "refs/tags/$ref:refs/tags/$ref" ;;
esac
git rev-parse --verify --quiet "$ref^{commit}" >/dev/null || { echo "Unknown ref: $ref" >&2; exit 1; }

count=$(git rev-list --count "HEAD..$ref")
if [ "$count" -gt 0 ]; then
    say "$count new upstream commit(s) in $ref"
    git log --oneline --no-merges -n 40 "HEAD..$ref"
    before=$(git rev-parse HEAD)
    say "Merging $ref"
    git merge --no-edit -m "Merge upstream ${ref#upstream/}" "$ref" || resolve_known
    # still merging, or no merge happened
    if git rev-parse -q --verify MERGE_HEAD >/dev/null || [ "$(git rev-parse HEAD)" = "$before" ]; then
        say "Conflicts"
        git diff --name-only --diff-filter=U | sed 's/^/  /'
        conflict_help
        exit 1
    fi
elif git log -1 --format=%s | grep -q '^Merge upstream' && git rev-parse -q --verify HEAD^2 >/dev/null; then
    # run again after conflicts were fixed by hand: go on from that merge
    before=$(git rev-parse HEAD^1)
    say "Continuing after the merge of $ref"
else
    say "Already up to date with $ref"
    exit 0
fi

say "Texts naming CachyOS (the name alone becomes Manjaro by itself)"
# a text that says more than the name needs a whole-text entry in src/brand.cpp
new_texts=$(git diff "$before" HEAD -- qml src | grep '^+' | grep -i 'cachy' | grep -E 'qsTr\(|tr\(' || true)
if [ -n "$new_texts" ]; then
    echo "New or changed by this merge; check each reads right with Manjaro:"
    echo "$new_texts" | sed 's/^+[[:space:]]*/  /'
else
    echo "  none new"
fi

say "Screenshots"
# ours replace upstream's CachyOS pictures under the same names
shots=$(git diff --name-only "$(git merge-base "$before" "$ref")" "$ref" -- screenshots/ 2>/dev/null || true)
if [ -n "$shots" ]; then
    echo "Upstream changed or added screenshots; take ours again with tools/screenshots.sh:"
    echo "$shots" | sed 's/^/  /'
else
    echo "  upstream changed none"
fi

say "Upstream's app list (pkglist.yaml)"
# ours is manjaro/pkglist.yaml: copy new apps that Manjaro's repositories have
added=$(git diff "$before" HEAD -- pkglist.yaml | grep -E '^\+\s+- ' | sed -E 's/^\+\s+- //' || true)
if [ -n "$added" ]; then
    echo "Added upstream; copy the ones in Manjaro's repositories to manjaro/pkglist.yaml:"
    for name in $added; do
        if pacman -Si "$name" >/dev/null 2>&1; then echo "  $name  (in the repositories)"; else echo "  $name"; fi
    done
else
    echo "  nothing added"
fi

say "Checking our app list against the repositories"
manjaro/check-pkglist.sh || echo "Remove or replace those entries in manjaro/pkglist.yaml."

if [ "$install" -eq 1 ]; then
    say "Building, testing and installing (makepkg -sif)"
    (cd packaging && makepkg -sif --noconfirm)
fi

say "Done: $ref"
cat <<'EOF'
Next: try it (install and remove a package, Update all, an AUR page), then
  git push
EOF
