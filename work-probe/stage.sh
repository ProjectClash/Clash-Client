#!/bin/bash
# Lays out the throwaway SwiftPM package that builds the probe from this worktree's real sources.
# Usage: stage.sh <package dir>
# Every project file is symlinked, never copied. The only real files written are these build-only
# substitutes, generated from the worktree (and git) on every run so they can be checked:
#   ProbeTunnelBefore*: ModuleRewriteProgram.swift = the worktree file with commit 5f78fa7 reversed;
#                       checked to equal 733de1f's file plus the uncommitted JQBuild init(room:) workaround
#   ProbeTunnel*IOS:    ModuleBodies.swift = the worktree file with ModuleBodyLimits.current answering .iOS
#                       when PROBE_IOS_LIMITS is defined (the iOS 1 MiB default, no spill, iOS memory guard)
#   ProbePublisher:     Mac/ClashMacApp.swift without its @main line (the probe's main.swift is the entry)
#   ClashMacClient:     SourceViewer/ClashMacSourceViewer.swift with a weak box in one detached task, the
#                       only change Xcode 26.3's Swift 6.2 needs to compile that package (a view, never shown)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
PKG="$(mkdir -p "$1" && cd "$1" && pwd -P)"
FIX=5f78fa7
PREFIX=733de1f
RWP=apple/ClashClient/Extension/Module/ModuleRewriteProgram.swift
BODIES=apple/ClashClient/Extension/Module/ModuleBodies.swift

rm -rf "$PKG/Sources" "$PKG/generated"
mkdir -p "$PKG/Sources" "$PKG/generated"
sed -e "s|@REPO@|$REPO|g" -e "s|@PKG@|$PKG|g" "$HERE/Package.swift.in" > "$PKG/Package.swift"
rm -f "$PKG/Clash.xcframework"
ln -s "$(cd "$REPO/Clash.xcframework" && pwd -P)" "$PKG/Clash.xcframework"

# --- build-only substitutes
GEN="$PKG/generated"
git -C "$REPO" show "$PREFIX:$RWP" > "$GEN/ModuleRewriteProgram.before.swift"
# the one Xcode 26.3 workaround that file needs: JQBuild's memberwise initializer is private there
/usr/bin/python3 -I - "$GEN/ModuleRewriteProgram.before.swift" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = "        let room: ModuleProgramRoom\n\n"
assert s.count(old) == 1
open(p, "w", encoding="utf-8").write(s.replace(old, old + "        init(room: ModuleProgramRoom) { self.room = room }\n\n"))
PY
grep -q 'let maximumLength = max(body.count, ModuleBodyLimits.current.defaultBytes)' "$GEN/ModuleRewriteProgram.before.swift"
! grep -q 'growthBytes' "$GEN/ModuleRewriteProgram.before.swift"

/usr/bin/python3 -I - "$REPO/$BODIES" "$GEN/ModuleBodies.ios.swift" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
old = "    static var current: ModuleBodyLimits {\n        #if os(macOS)\n        return .macOS\n"
new = "    static var current: ModuleBodyLimits {\n        #if os(macOS) && !PROBE_IOS_LIMITS\n        return .macOS\n"
assert src.count(old) == 1, "ModuleBodyLimits.current is not where the probe expects it"
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(old, new))
PY

# --- ClashMacClient (the Mac configuration centre, which the App target links) with one build-only
# substitute: Xcode 26.3's Swift 6.2 rejects ClashMacSourceViewer.swift ("sending 'self' risks causing
# data races" at its search task). The substitute hands the task a weak box instead of capturing
# self; it is a view the probe never shows. Everything else is symlinked.
MAC="$PKG/deps/ClashMacClient"
rm -rf "$PKG/deps"
mkdir -p "$MAC"
sed -e "s|path: \"../ClashClientKit\"|path: \"$REPO/apple/ClashClientKit\"|" \
    -e "s|path: \"../ClashClientUI\"|path: \"$REPO/apple/ClashClientUI\"|" \
    "$REPO/apple/ClashMacClient/Package.swift" > "$MAC/Package.swift"
grep -q "$REPO/apple/ClashClientKit" "$MAC/Package.swift"
VIEWER=apple/ClashMacClient/Sources/ClashMacClient/SourceViewer/ClashMacSourceViewer.swift
(cd "$REPO/apple/ClashMacClient" && find Sources -type f ! -name .DS_Store) | while IFS= read -r rel; do
    mkdir -p "$MAC/$(dirname "$rel")"
    ln -s "$REPO/apple/ClashMacClient/$rel" "$MAC/$rel"
done
rm "$MAC/Sources/ClashMacClient/SourceViewer/ClashMacSourceViewer.swift"
/usr/bin/python3 -I - "$REPO/$VIEWER" "$MAC/Sources/ClashMacClient/SourceViewer/ClashMacSourceViewer.swift" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
edits = [
    ("        let task = Task.detached(priority: .userInitiated) { [weak self] in\n",
     "        let probeBox = ProbeWeakBox(self)\n        let task = Task.detached(priority: .userInitiated) {\n"),
    ("MainActor.assumeIsolated { self?.take(taken, full: full, generation: generation) }",
     "MainActor.assumeIsolated { probeBox.value?.take(taken, full: full, generation: generation) }"),
    ("            await MainActor.run { self?.finish(generation) }\n",
     "            await MainActor.run { probeBox.value?.finish(generation) }\n"),
]
for old, new in edits:
    assert src.count(old) == 1, old
    src = src.replace(old, new)
src += "\n// work-probe build-only substitute: a weak reference the detached search task may carry\nprivate struct ProbeWeakBox<T: AnyObject>: @unchecked Sendable {\n    weak var value: T?\n    init(_ value: T) { self.value = value }\n}\n"
open(sys.argv[2], "w", encoding="utf-8").write(src)
PY

# --- the App's @main struct, without @main: the probe's main.swift is the entry point instead
APPMAIN=apple/ClashClient/Sources/Mac/ClashMacApp.swift
/usr/bin/python3 -I - "$REPO/$APPMAIN" "$GEN/ClashMacApp.swift" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
assert src.count("\n@main\n") == 1
open(sys.argv[2], "w", encoding="utf-8").write(src.replace("\n@main\n", "\n// @main removed by work-probe/stage.sh (build-only)\n"))
PY

# --- one source tree per executable, mirroring repo paths so nothing collides
section_files() {   # section_files <section>: the files one [section] of sources.list names ("**" globs, "!" drops)
    /usr/bin/python3 -I - "$REPO" "$HERE/sources.list" "$1" <<'PY'
import sys, pathlib, fnmatch
repo, listing, want = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
section, keep, drop = None, [], []
for raw in open(listing, encoding="utf-8"):
    line = raw.split("#", 1)[0].strip()
    if not line:
        continue
    if line.startswith("[") and line.endswith("]"):
        section = line[1:-1]
        continue
    if section != want:
        continue
    (drop if line.startswith("!") else keep).append(line.lstrip("!"))
seen = []
for pattern in keep:
    found = sorted(p.relative_to(repo).as_posix() for p in repo.glob(pattern) if p.is_file())
    if not found:
        sys.exit(f"sources.list: {pattern} names no file")
    seen += [f for f in found if f not in seen]
for f in seen:
    if not any(fnmatch.fnmatchcase(f, d) for d in drop):
        print(f)
PY
}

lay() {   # lay <target> <section> <main file>
    local target="$1" section="$2" main="$3" root="$PKG/Sources/$1" rel src count=0
    mkdir -p "$root/probe"
    while IFS= read -r rel; do
        mkdir -p "$root/$(dirname "$rel")"
        src="$REPO/$rel"
        case "$target:$rel" in ProbeTunnelBefore*:"$RWP") src="$GEN/ModuleRewriteProgram.before.swift" ;; esac
        case "$target:$rel" in *IOS:"$BODIES") src="$GEN/ModuleBodies.ios.swift" ;; esac
        case "$target:$rel" in ProbePublisher:"$APPMAIN") src="$GEN/ClashMacApp.swift" ;; esac
        ln -s "$src" "$root/$rel"
        count=$((count + 1))
    done < <(section_files "$section")
    ln -s "$HERE/$main" "$root/probe/main.swift"
    echo "  $target: $count project files"
}

lay ProbePublisher app PublisherMain.swift
for variant in ProbeTunnelAfter ProbeTunnelBefore ProbeTunnelAfterIOS ProbeTunnelBeforeIOS; do
    lay "$variant" tunnel TunnelMain.swift
done
rm -f "$GEN"/*.orig
echo "staged into $PKG"
