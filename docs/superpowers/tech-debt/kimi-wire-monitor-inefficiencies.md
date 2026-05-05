# Kimi Wire Monitor — Known Inefficiencies

> **Impact:** Low for 1–3 terminals. Revisit when scaling to 10+ simultaneous agents or when users report battery drain.

## Current Architecture

`KimiWireSessionMonitor` uses `Timer.scheduledTimer` with a 1.5s interval to poll `~/.kimi/sessions/{md5}/{session}/wire.jsonl`. On each tick:

1. Re-resolves the wire path by scanning all session directories for the most recent `wire.jsonl`
2. Reads the **entire file** via `FileManager.default.contents(atPath:)`
3. Extracts only the new tail bytes since `lastOffset`
4. Splits on newlines and JSON-decodes complete lines
5. Appends parsed records to an in-memory buffer

`AppDelegate.refreshAIForemanSidebar()` runs a separate 2s timer that re-runs `TerminalUnderstandingEngine` on **every** terminal, even when nothing changed.

## Inefficiencies (in order of impact)

### 1. Reads entire file on every poll 🔴

`FileManager.default.contents(atPath:)` loads the full wire file into memory even though we only need the bytes after `lastOffset`.

- **Current cost:** O(total file size) per poll
- **Optimized:** O(new bytes) per poll
- **Example:** A 5MB wire file → reads 5MB every 1.5s even if only 200 bytes were appended

**Fix:** Use `FileHandle(forReadingFrom:)` + `seek(toOffset: lastOffset)` + `readToEnd()` to read only the tail.

### 2. Re-scans all session directories on every poll 🔴

`resolveWirePath()` iterates every `~/.kimi/sessions/*/` subdirectory to find the newest `wire.jsonl` by modification date.

- **Current cost:** O(number of sessions × number of md5 dirs) every 1.5s
- **Optimized:** O(1) when nothing changed

**Fix:** Cache the session directory modification time. Only re-scan when `attributesOfItem(atPath: sessionsBaseDir)[.modificationDate]` changes.

### 3. Timer polling instead of filesystem events 🟡

The monitor wakes up every 1.5s regardless of whether Kimi wrote anything. Wire files change on human timescales (seconds to minutes), not sub-second.

- **Current cost:** ~40 wakeups/minute per terminal
- **Optimized:** Zero wakeups between events

**Fix:** Replace `Timer` with `FSEvents` (`DispatchSource.makeFileSystemObjectSource`) or `dispatch_source_type_vnode` to get instant OS-level notifications when the file changes.

**Tradeoff:** FSEvents can have edge cases with sandboxed apps, network drives, and file rotations. Timer polling is simpler and more robust.

### 4. Re-classifies unchanged terminals 🟡

`refreshAIForemanSidebar()` re-runs `TerminalUnderstandingEngine.understand()` on **all** terminals every 2s, even when their snapshots are identical.

- **Current cost:** O(terminals) per refresh
- **Optimized:** O(changed terminals) per refresh

**Fix:** Snapshot fingerprinting already exists (`snapshotFingerprint`). Skip `understand()` when the fingerprint matches the previous refresh.

### 5. JSON re-decode of already-parsed lines 🟢

`poll()` parses all complete lines in the new data. Since `lastOffset` skips already-parsed bytes, this only affects lines written between polls.

- **Current cost:** O(new lines) per poll
- **Impact:** Negligible — wire files are small, lines are short

**Fix:** Not worth optimizing unless wire files grow to 100k+ lines.

## Benchmarks (estimated)

| Scenario | Timer polling (now) | FSEvents + tail-read | Improvement |
|----------|---------------------|----------------------|-------------|
| 1 terminal, idle | ~0.01% CPU | 0% CPU | Invisible |
| 3 terminals, active | ~0.03% CPU | ~0.001% CPU | Invisible |
| 10 terminals, 5MB wire files | ~0.3% CPU, 50MB/s disk read | ~0.005% CPU, ~1KB/s disk read | Noticeable |
| Latency (TurnEnd → sidebar) | 0–1.5s | ~5ms | UX win |

## When to Optimize

- [ ] **Now:** No. Current implementation is simple, robust, and passes all tests.
- [ ] **After shipping:** If users report battery drain or high CPU in Activity Monitor.
- [ ] **Before scaling:** If you add support for 10+ simultaneous agent terminals.
- [ ] **For latency:** If you want the sidebar to feel "instant" rather than "snappy."

## Recommended Optimization Order

1. **Session dir caching** (1 hour) — Biggest bang for buck. One-line `modificationDate` cache.
2. **Tail-only reading** (2 hours) — Replace `contents(atPath:)` with `FileHandle` seek+read.
3. **Terminal fingerprint skip** (1 hour) — Skip unchanged terminals in `refreshAIForemanSidebar`.
4. **FSEvents** (half day) — Only if latency becomes a product requirement.
