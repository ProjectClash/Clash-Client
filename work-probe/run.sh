#!/bin/bash
# End-to-end probe of a Shadowrocket body rewrite through the real module engine on this Mac.
#
#   work-probe/run.sh after  [macos|ios] [small|large|xl|many|all]   the engine as committed (5f78fa7)
#   work-probe/run.sh before [macos|ios] [small|large|xl|many|all]   ModuleRewriteProgram.swift as of 733de1f
#   work-probe/run.sh all                                        both, both limits, every size, one table
#   work-probe/run.sh strikes [before|after] [macos|ios]          one engine: "many" x3, then small
#
#   macos (default): the engine exactly as it compiles for macOS (10 MiB default body cap)
#   ios:             the same engine with ModuleBodyLimits.current answering .iOS (1 MiB cap, no spill)
#   small 200 kB, large 1.5 MB (the reader's case), xl 10.7 MB (past the macOS cap), and
#   many: 1.5 MB holding the old id 3,000 times, so the rewrite grows it by 72,000 bytes (> 64 KiB)
#
# Everything it makes lives under $TMPDIR/clash-bodyrw/probe/. It binds only 127.0.0.1 ports it has
# checked are free, never touches system proxy, network or trust settings, and loads a guard into
# both Swift processes that aborts on any keychain or trust-settings call. Every process it starts
# is stopped before it exits.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-26.3.0.app/Contents/Developer}"
ROOT="${TMPDIR%/}/clash-bodyrw/probe"
PKG="$ROOT/pkg"
BUILD="$ROOT/build"
GUARD="$ROOT/guard/libkeychainguard.dylib"
PY=/usr/bin/python3
OPENSSL="$(command -v openssl)"
CURL=/usr/bin/curl
MODULE_URL='https://example.test/clash重写模块.module'
PAGE_URL='https://one.google.com/ai?utm_source=google_one&hl=zh_CN'
OLD_ID='g1.ios.20tb.m.v2'
NEW_ID='com.google.gemini.2tb.ai.m.3month_ip_99p'
mkdir -p "$ROOT"

PIDS=()
cleanup() {
    for pid in "${PIDS[@]:-}"; do
        [ -n "$pid" ] && kill "$pid" 2>/dev/null && wait "$pid" 2>/dev/null || true
    done
    PIDS=()
}
trap cleanup EXIT INT TERM

tracked_state() { git -C "$REPO" diff | shasum -a 256 | cut -c1-16; }

build() {
    "$HERE/stage.sh" "$PKG" | sed 's/^/[build] /'
    mkdir -p "$(dirname "$GUARD")"
    xcrun clang -dynamiclib -O1 -framework Security -framework CoreFoundation -o "$GUARD" "$HERE/keychain_guard.c" 2>/dev/null
    echo "[build] ProbePublisher (debug) ..."
    swift build -c debug --package-path "$PKG" --scratch-path "$BUILD" --product ProbePublisher > "$ROOT/build-publisher.log" 2>&1 \
        || { grep -m20 "error:" "$ROOT/build-publisher.log"; exit 1; }
    for product in "$@"; do
        echo "[build] $product (release) ..."
        swift build -c release --package-path "$PKG" --scratch-path "$BUILD" --product "$product" > "$ROOT/build-$product.log" 2>&1 \
            || { grep -m20 "error:" "$ROOT/build-$product.log"; exit 1; }
    done
}

free_ports() {   # free_ports N: N distinct free 127.0.0.1 ports in the range ModuleStore draws from
    "$PY" -I - "$1" <<'PY'
import random, socket, sys
want, out = int(sys.argv[1]), []
while len(out) < want:
    port = random.randint(42000, 48999)
    if port in out:
        continue
    s = socket.socket()
    try:
        s.bind(("127.0.0.1", port))
    except OSError:
        continue
    finally:
        s.close()
    out.append(port)
print(" ".join(map(str, out)))
PY
}

wait_port() {   # wait_port PORT: until something listens on 127.0.0.1:PORT
    for _ in $(seq 1 100); do
        "$PY" -I -c "import socket,sys; s=socket.socket(); s.settimeout(0.2); sys.exit(s.connect_ex(('127.0.0.1', $1)))" && return 0
        sleep 0.1
    done
    echo "nothing listens on 127.0.0.1:$1"; return 1
}

certificates() {   # certificates DIR: a probe CA and a one.google.com leaf it signs, for the local origin
    local dir="$1"
    mkdir -p "$dir"
    "$OPENSSL" req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 30 \
        -subj "/CN=work-probe origin CA" -addext "basicConstraints=critical,CA:TRUE" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" -keyout "$dir/origin-ca.key" -out "$dir/origin-ca.pem" 2>/dev/null
    "$OPENSSL" req -new -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -subj "/CN=one.google.com" \
        -keyout "$dir/origin.key" -out "$dir/origin.csr" 2>/dev/null
    printf 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:one.google.com\n' > "$dir/origin.ext"
    "$OPENSSL" x509 -req -in "$dir/origin.csr" -CA "$dir/origin-ca.pem" -CAkey "$dir/origin-ca.key" -CAcreateserial \
        -days 30 -sha256 -extfile "$dir/origin.ext" -out "$dir/origin.pem" 2>/dev/null
    "$OPENSSL" x509 -in "$dir/origin-ca.pem" -outform DER -out "$dir/origin-ca.der"
}

# run_variant before|after macos|ios "sizes..."  -> appends rows to $ROOT/last-results.tsv
run_variant() {
    local which="$1" limits="$2"; shift 2
    local sizes=("$@")
    local product="ProbeTunnel$( [ "$which" = before ] && echo Before || echo After )$( [ "$limits" = ios ] && echo IOS || true )"
    local run="$ROOT/run-$which-$limits-$(date +%H%M%S)"
    mkdir -p "$run/container" "$run/leaves" "$run/bodies"
    echo "== $which / $limits limits ($product) -> $run"
    certificates "$run/certs"
    cat > "$run/clash重写模块.module" <<'MODULE'
#!name=我的重写
#!desc=从 Shadowrocket 迁移
[Body Rewrite]
http-response ^https://one.google.com/ai\?.*$ g1\.ios\.20tb\.m\.v2 com.google.gemini.2tb.ai.m.3month_ip_99p
[MITM]
hostname = %APPEND% one.google.com
MODULE
    read -r engine_port reinject_port origin_port < <(free_ports 3)

    # --- App half: add the module, make the CA, activate, record the engine plan
    DYLD_INSERT_LIBRARIES="$GUARD" "$BUILD/debug/ProbePublisher" --container "$run/container" \
        --module "$run/clash重写模块.module" --module-url "$MODULE_URL" \
        --engine-port "$engine_port" --reinject-port "$reinject_port" --summary "$run/published.json" \
        > "$run/app.log" 2>&1 || { cat "$run/app.log"; exit 1; }
    grep -E "KEYCHAIN GUARD|parsed as|ir.rewriteRules|published:|modules applied|engine plan recorded|mihomo config" "$run/app.log" | sed 's/^/   /'
    local engine_user engine_password
    engine_user="$("$PY" -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["engineUser"])' "$run/published.json")"
    engine_password="$("$PY" -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["enginePassword"])' "$run/published.json")"

    # --- the stand-ins: the local origin, and the re-inject port
    "$PY" -I "$HERE/standin.py" --origin-port "$origin_port" --reinject-port "$reinject_port" \
        --cert "$run/certs/origin.pem" --key "$run/certs/origin.key" --summary "$run/published.json" \
        > "$run/standin.log" 2>&1 &
    PIDS+=($!); local standin=$!
    echo "   standin pid $standin: origin 127.0.0.1:$origin_port, re-inject 127.0.0.1:$reinject_port"
    wait_port "$origin_port"; wait_port "$reinject_port"

    # --- tunnel half: a fresh engine for every case, so nothing is carried between cases, unless
    # ONE_ENGINE=1 (the strikes mode), where one engine serves every case in turn
    local engine="" log="" n=0
    start_engine() {
        rm -rf "$run/leaves"/* "$run/bodies"/* "$run/ready"
        DYLD_INSERT_LIBRARIES="$GUARD" "$BUILD/release/$product" --container "$run/container" \
            --leaves "$run/leaves" --bodies "$run/bodies" --origin-ca-der "$run/certs/origin-ca.der" \
            --profile probe --revision r1 --ready "$run/ready" > "$log" 2>&1 &
        engine=$!; PIDS+=($engine)
        for _ in $(seq 1 100); do [ -f "$run/ready" ] && break; kill -0 "$engine" 2>/dev/null || break; sleep 0.1; done
        [ -f "$run/ready" ] || { cat "$log"; exit 1; }
    }
    stop_engine() { kill -TERM "$engine"; wait "$engine" 2>/dev/null || true; engine=""; }
    for size in "${sizes[@]}"; do
        n=$((n + 1))
        local label="$size"; [ "${ONE_ENGINE:-0}" = 1 ] && label="$n-$size"
        local url="$PAGE_URL"; [ "$size" = large ] || url="$PAGE_URL&probe=$size"
        if [ -z "$engine" ]; then
            log="$run/engine-$label.log"; [ "${ONE_ENGINE:-0}" = 1 ] && log="$run/engine.log"
            start_engine
        fi
        local mark; mark="$(wc -l < "$log")"
        local code
        code="$(env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u no_proxy -u NO_PROXY \
            "$CURL" --noproxy '' --proxy "http://127.0.0.1:$engine_port" --proxy-user "$engine_user:$engine_password" \
            --cacert "$run/container/module-ca.pem" --compressed -sS --max-time 60 \
            -D "$run/headers-$label.txt" -o "$run/body-$label.html" -w '%{http_code}' "$url")" || code="curl-failed"
        kill -USR1 "$engine"; sleep 0.3
        tail -n +"$((mark + 1))" "$log" > "$run/case-$label.log"
        [ "${ONE_ENGINE:-0}" = 1 ] || stop_engine
        "$PY" -I - "$run" "$label" "$which" "$limits" "$code" "$OLD_ID" "$NEW_ID" >> "$ROOT/last-results.tsv" <<'PY'
import json, sys
run, label, which, limits, code, old, new = sys.argv[1:]
body = open(f"{run}/body-{label}.html", "rb").read() if code == "200" else b""
lines = open(f"{run}/case-{label}.log", encoding="utf-8", errors="replace").read().splitlines()
counters = {}
for line in lines:
    if "[probe] counters (asked)" in line:
        counters = json.loads(line.split("[probe] counters (asked) ", 1)[1])
rewritten = sum("body response rewritten" in l for l in lines)
print("\t".join(map(str, [which, limits, label, code, len(body), body.count(old.encode()), body.count(new.encode()),
                          rewritten, counters.get("body_rewrites_total", "?"), counters.get("rewrite_output_too_large", "?"), run])))
PY
        tail -1 "$ROOT/last-results.tsv" | awk -F'\t' '{printf "   %-7s http %s  decoded %9d bytes  old id %d  new id %d  \"body response rewritten\" lines %d  body_rewrites_total %s  rewrite_output_too_large %s\n", $3, $4, $5, $6, $7, $8, $9, $10}'
        grep -E "\[modules\].*(rewritten|not applied|grew|left out|refused|untrusted|cannot)|KEYCHAIN GUARD: [^l]" "$run/case-$label.log" | sed 's/^/      engine: /' | head -8 || true
    done
    [ -z "$engine" ] || stop_engine
    kill "$standin" 2>/dev/null; wait "$standin" 2>/dev/null || true
    PIDS=()
}

main() {
    local before; before="$(tracked_state)"
    local mode="${1:-}"
    case "$mode" in
        before|after)
            local limits="${2:-macos}" size="${3:-all}"
            local sizes=(small large xl many); [ "$size" = all ] || sizes=("$size")
            build "ProbeTunnel$( [ "$mode" = before ] && echo Before || echo After )$( [ "$limits" = ios ] && echo IOS || true )"
            : > "$ROOT/last-results.tsv"
            run_variant "$mode" "$limits" "${sizes[@]}" ;;
        all)
            build ProbeTunnelBefore ProbeTunnelAfter ProbeTunnelBeforeIOS ProbeTunnelAfterIOS
            : > "$ROOT/last-results.tsv"
            for limits in macos ios; do for which in before after; do run_variant "$which" "$limits" small large xl many; done; done ;;
        strikes)
            # one engine: the 3,000-id page three times, then the small page
            local which="${2:-after}" limits="${3:-ios}"
            build "ProbeTunnel$( [ "$which" = before ] && echo Before || echo After )$( [ "$limits" = ios ] && echo IOS || true )"
            : > "$ROOT/last-results.tsv"
            ONE_ENGINE=1 run_variant "$which" "$limits" many many many small ;;
        build) build ProbeTunnelBefore ProbeTunnelAfter ProbeTunnelBeforeIOS ProbeTunnelAfterIOS; return ;;
        *) sed -n '2,13p' "$0"; exit 2 ;;
    esac
    echo
    printf '%-7s %-6s %-7s %-5s %10s %7s %7s %10s %14s %14s\n' variant limits size http decoded old_id new_id log_lines body_rewrites grew_too_large
    awk -F'\t' '{printf "%-7s %-6s %-7s %-5s %10d %7d %7d %10d %14s %14s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10}' "$ROOT/last-results.tsv"
    local leftover; leftover="$(pgrep -fl "$ROOT/(build|pkg)|standin.py" || true)"
    echo "processes left behind: ${leftover:-none}"
    [ "$(tracked_state)" = "$before" ] && echo "tracked files: unchanged by the probe (git diff digest $before)" \
        || echo "tracked files: CHANGED during the probe (git diff digest $before -> $(tracked_state))"
}
main "$@"
