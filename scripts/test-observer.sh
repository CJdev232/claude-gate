#!/bin/bash
# Test observer mode against running claude-gate instance
# Requires: new binary running with observer mode support

set -uo pipefail

PORT=${1:-9191}
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'
PASS=0
FAIL=0

post() {
    curl -s "http://127.0.0.1:${PORT}$1" \
        -X POST -d "$2" -H 'Content-Type: application/json' \
        --connect-timeout 3 --max-time 10 2>/dev/null
}

check() {
    local name="$1" expected="$2" actual="$3"
    if echo "$actual" | grep -q "$expected"; then
        echo -e "  ${GREEN}PASS${NC}  $name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC}  $name — expected /$expected/, got: $actual"
        FAIL=$((FAIL + 1))
    fi
}

echo ""
echo "${CYAN}Observer Mode Tests (port $PORT)${NC}"
echo "────────────────────────────────"

# Test 1: Normal request (no permission_mode) — should behave as before
RESP=$(post "/permission" '{"tool_name":"Read","session_id":"obs-test-1","cwd":"/tmp","tool_input":{"file_path":"/tmp/test.txt"}}')
check "Normal request (Read, no permission_mode)" '"behavior":"allow"' "$RESP"

# Test 2: permission_mode=default — should behave as normal
RESP=$(post "/permission" '{"tool_name":"Read","session_id":"obs-test-2","cwd":"/tmp","permission_mode":"default","tool_input":{"file_path":"/tmp/test.txt"}}')
check "permission_mode=default (Read)" '"behavior":"allow"' "$RESP"

# Test 3: permission_mode=auto — observer mode, instant allow even for ask tools
# Bash parent is normally "ask" which would trigger popover+timeout, but in observer mode should be instant allow
RESP=$(post "/permission" '{"tool_name":"Bash","session_id":"obs-test-3","cwd":"/tmp","permission_mode":"auto","tool_input":{"command":"echo hello"}}')
check "permission_mode=auto (Bash) → instant allow" '"behavior":"allow"' "$RESP"

# Test 4: permission_mode=bypassPermissions — observer mode, instant allow
RESP=$(post "/permission" '{"tool_name":"Bash","session_id":"obs-test-4","cwd":"/tmp","permission_mode":"bypassPermissions","tool_input":{"command":"rm -rf /"}}')
check "permission_mode=bypassPermissions (Bash) → instant allow" '"behavior":"allow"' "$RESP"

# Test 5: Observer mode for subagent — normally denied, but observer should allow
post "/subagent-start" '{"session_id":"obs-sub-1"}' >/dev/null
RESP=$(post "/permission" '{"tool_name":"Bash","session_id":"obs-sub-1","cwd":"/tmp","permission_mode":"auto","tool_input":{"command":"echo test"}}')
check "Observer mode overrides subagent deny" '"behavior":"allow"' "$RESP"
post "/subagent-stop" '{"session_id":"obs-sub-1"}' >/dev/null

# Test 6: Verify JSONL file was written
LOGFILE="$HOME/.claude-gate/activity.jsonl"
if [ -f "$LOGFILE" ]; then
    LINES=$(wc -l < "$LOGFILE" | tr -d ' ')
    if [ "$LINES" -gt 0 ]; then
        echo -e "  ${GREEN}PASS${NC}  Activity log has $LINES entries at $LOGFILE"
        PASS=$((PASS + 1))
        # Show last 3 entries
        echo "        Last entries:"
        tail -3 "$LOGFILE" | while read -r line; do
            TOOL=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['toolName'])" 2>/dev/null)
            DECISION=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['decision'])" 2>/dev/null)
            OBSERVER=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['isObserver'])" 2>/dev/null)
            echo "          $TOOL → $DECISION (observer=$OBSERVER)"
        done
    else
        echo -e "  ${RED}FAIL${NC}  Activity log exists but is empty"
        FAIL=$((FAIL + 1))
    fi
else
    echo -e "  ${RED}FAIL${NC}  Activity log not found at $LOGFILE"
    FAIL=$((FAIL + 1))
fi

# Test 7: Response time for observer mode should be fast (< 1s, not waiting for timeout)
START=$(python3 -c "import time; print(time.time())")
RESP=$(post "/permission" '{"tool_name":"Write","session_id":"obs-test-speed","cwd":"/tmp","permission_mode":"auto","tool_input":{"file_path":"/tmp/x","content":"test"}}')
END=$(python3 -c "import time; print(time.time())")
ELAPSED=$(python3 -c "print(round($END - $START, 2))")
if python3 -c "exit(0 if $ELAPSED < 1.0 else 1)"; then
    echo -e "  ${GREEN}PASS${NC}  Observer response time: ${ELAPSED}s (< 1s, no timeout wait)"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC}  Observer response too slow: ${ELAPSED}s (expected < 1s)"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "────────────────────────────────"
echo -e "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
echo "────────────────────────────────"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
