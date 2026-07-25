# Deep Tracing & Code Review Rules

## Mandatory Execution Protocol
Do NOT evaluate the git diff in isolation line-by-line. You MUST perform active code tracing using codebase search tools:

1. DOMAIN INTENT vs SYNTAX ALIGNMENT
   - Infer class & function intent from file/class names, parameters, and surrounding context.
   - Verify if the logic matches the intent. Flag syntactic correctness that violates semantic goals (e.g., inverted filtering logic, applying global filters to scoped/modal views).

2. DATA CONTRACT MUTATION SCANNING
   - Whenever a diff alters the shape, type, scheme, structure, or key format of data produced or passed around, search the codebase for all consumers of that data.
   - Flag any consumer/handler that will fail to parse or handle the mutated format.

3. SCOPE IDENTITY & BOUNDARY AUDIT
   - Do not assume IDs, tokens, or keys are globally unique. Check if equality checks (`==`) or lookups assume global uniqueness on entity-scoped identifiers.
   - Flag logic where skipping an operation (e.g., via flags like `loadContent: false`) leaves entity-scoped state unmodified, creating false-positive matches across boundaries.

4. LIFECYCLE OVERWRITE & STALE STATE AUDIT
   - Trace state variables when early returns, flags, or short-circuits are introduced. Identify variables left stale and their downstream impact.
   - For changes in initialization or setup sequences, trace subsequent lifecycle methods to ensure earlier configured state is not accidentally wiped or overwritten.

5. THREAD SAFETY & MAIN-THREAD BLOCKING
   - Trace I/O operations, database queries (SQLite/FTS), and heavy computations (zstd/LZString decompression).
   - Flag any synchronous execution of heavy tasks on the Main/UI thread.
   - Flag UI updates (AppKit/UIKit/SwiftUI state mutations) executed off the Main thread without `@MainActor` or `DispatchQueue.main`.

6. RESOURCE LEAK & TRANSACTION INTEGRITY
   - For SQLite queries and custom transactions (`BEGIN`), verify that ALL execution paths (including early returns and `catch` blocks) invoke `ROLLBACK` and finalize resources (`sqlite3_finalize`).
   - Inspect `NotificationCenter` observers and async tasks (`Task { ... }`) for strong `self` capture cycles or missing cleanup on deinit.

7. HIGH-PERFORMANCE VIRTUALIZATION & SYNC CONFLICTS
   - In AppKit/UIKit table and outline views (e.g. `NSOutlineView`), flag indiscriminate `reloadData()` calls for single-item updates. Ensure incremental reloading (`reloadItem`) is used.
   - In sync logic (e.g. CloudKit delta merge), verify isolated local mutations before applying remote payloads to prevent data races.
