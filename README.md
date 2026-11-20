# Bun 1.4.5 Test Runner Minimal Reproductions

Minimal, zero-dependency reproductions for two issues observed on **Bun `1.4.5+a7733435c`** (`Windows 11 Pro 10.0.26300 x64`).

> ⚠️ **Safety Warning:** Do **not** run `timeout-alloc.test.ts` or `timeout-cpu.test.ts` directly without an external timeout/memory limit. Under Bun `1.4.5`, `timeout-alloc.test.ts` grows at ~1.7 GB/s without stopping at `--timeout=1000` and can exhaust system commit memory. Use `scripts/run-safe.ps1` (or an OS memory/time cap) when reproducing.

---

## Environment

- **Bun:** `1.4.5+a7733435c`
- **OS:** `Microsoft Windows 11 Pro` (`10.0.26300`, x64)

---

## Repro 1: `bun test --parallel` coordinator does not enforce `--timeout` on hung/allocating workers

Files in [`repro-1-parallel-timeout/`](./repro-1-parallel-timeout):

- `pass.test.ts`: trivial passing test
- `timeout-cpu.test.ts`: synchronous `while (true) {}`
- `timeout-alloc.test.ts`: synchronous allocation loop (`while (true)`)
- `async-alloc.test.ts`: control — same allocation loop yielding via `setTimeout(..., 0)`

### Safe Run Commands (PowerShell on Windows)

```powershell
# Case 1: synchronous CPU loop in --parallel=2 worker (6s watchdog)
bun run repro:cpu:safe

# Case 2: synchronous allocation loop in --parallel=2 worker (6s / 1536 MB watchdog)
bun run repro:alloc:safe

# Control: yielding async allocation loop terminates cleanly at --timeout=1000
bun run repro:control
```

### Observed Results (`Bun 1.4.5+a7733435c`)

| Case | Command | `--timeout` | Observed Behavior | Peak Private Memory |
|---|---|---|---|---|
| Case 1 (`timeout-cpu.test.ts` + `pass.test.ts`) | `bun test --parallel=2 --timeout=1000` | `1000ms` | `pass.test.ts` passed (`0.09ms`), coordinator + worker (`2` procs) stayed hung past `1000ms` until killed by 6s external watchdog (`6.555s`) | `167.20 MB` |
| Case 2 (`timeout-alloc.test.ts` + `pass.test.ts`) | `bun test --parallel=2 --timeout=1000` | `1000ms` | `pass.test.ts` passed (`0.09ms`), worker (`2` procs total) ignored `1000ms` timeout and grew from `4.6 MB` (`0.02s`) -> `808.7 MB` (`0.54s`) -> `1721.48 MB` (`1.05s`) until killed by 1536 MB external watchdog (`1.377s`) | `1721.48 MB` (`1508.73 MB` WS) |
| Control (`async-alloc.test.ts` + `pass.test.ts`) | `bun test --parallel=2 --timeout=1000` | `1000ms` | Timed out cleanly (`this test timed out after 1000ms`, exit code `1`, `1.315s`) | `851.45 MB` |

---

## Repro 2: `import('file://...?query')` ignores searchParams & collides with `mock.module()`

Files in [`repro-2-file-url-query-mock/`](./repro-2-file-url-query-mock):

- `counter-dep.ts`: increments a global counter on each module evaluation
- `dep.ts`: exports `App` and `Comp`
- `file-url-query.test.ts`: compares relative `./counter-dep.ts?q=1` vs `file://` URL `?q=1` / `?q=2`
- `mock-module-file-query.test.ts`: tries a `vi.importActual()`-style `await import(fileUrl + '?bun-actual')` inside `mock.module('./dep.ts', ...)`

### Run Commands

```bash
bun run repro:file-query
bun run repro:mock-query
```

### Observed Results (`Bun 1.4.5+a7733435c`)

- `file-url-query.test.ts`:
  - `import('./counter-dep.ts?q=1')` evaluates a distinct instance (`loadCount === 2`), as expected.
  - `import(`${pathToFileURL(p).href}?q=1`)` and `?q=2` return the exact same cached module as `./counter-dep.ts` (`mFileQ1 === mRel`, `loadCount === 1`), causing `expect(mFileQ1).not.toBe(mRel)` to fail.
- `mock-module-file-query.test.ts`:
  - Importing `${pathToFileURL(depPath).href}?bun-actual` inside `mock.module('./dep.ts', async () => ...)` collides with the pending mock for `./dep.ts`, returning an empty namespace (`{}`), causing `expect(typeof mod.Comp).toBe('function')` to fail (`Received: "undefined"`).
