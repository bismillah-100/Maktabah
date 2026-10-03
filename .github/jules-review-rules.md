# Deep Tracing, Code & Documentation Review Rules

---

## PART I: CODE & INFRASTRUCTURE REVIEW RULES

### Mandatory Execution Protocol
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

8. BUILD & INFRASTRUCTURE INTEGRITY
   - For changes in `ci_scripts/**`, `.github/workflows/**`, or `Package.swift`, verify signing profiles, secret references, and runner environment compatibility.
   - Flag insecure script executions, unquoted variables, or broken dependency graph declarations.

---

## PART II: TECHNICAL DOCUMENTATION CONSISTENCY RULES
*(Enforced whenever a diff touches `docs/**`, `mkdocs.yml`, or documentation markdown files)*

1. STANDARISASI KONSTRUK SWIFT (Swift Constructs)
   - Pertahankan istilah konstruk Swift dalam bahasa aslinya (`class`, `struct`, `enum`, `actor`, `protocol`).
   - **JANGAN** menerjemahkan konstruk Swift menjadi "kelas", "struktur", "cacahan", "enumerasi", atau "protokol" ketika merujuk pada tipe kode Swift.
   - **Pengecualian**:
     * Kata "struktur" hanya boleh digunakan untuk konteks arsitektur/organisasi umum (misal: "struktur direktori", "struktur data umum", "struktur arsitektur").
     * Istilah antarmuka seperti "Size Class" (UI) tetap dipertahankan sebagai istilah resmi Apple.

2. ISTILAH TEKNIS, CONCURRENCY & RUNTIME SWIFT
   - **JANGAN** menerjemahkan istilah teknis pemrograman atau runtime Swift ke bahasa Indonesia sehari-hari:
     * `Task` / `task` **JANGAN** diterjemahkan menjadi "tugas".
     * `continuation` **JANGAN** diterjemahkan menjadi "kelanjutan".
     * `closure` / `handler` **JANGAN** diterjemahkan menjadi "penutupan" / "penangan".
     * `thread` **JANGAN** diterjemahkan menjadi "utas" (gunakan `*thread*` / *thread-safety*).
     * `lock` **JANGAN** diterjemahkan menjadi "gembok" (gunakan `*lock*` / *lock-free*).
   - Contoh:
     * Salah: "...melanjutkan (resume) seluruh tugas yang tertahan sekaligus membatalkan Task utama."
     * Benar: "...melanjutkan (resume) seluruh task yang tertahan sembari membatalkan Task utama."

3. FORMAT HEADING KOMPONEN
   - Semua judul komponen Swift harus menggunakan format: `### [Nama Komponen] ([Tipe Konstruk])`
   - Benar: `### ResultsDelegate (Protocol)`, `### SearchResultItem (Struct)`, `### SearchEngine (Class)`, `### CacheCoordinator (Actor)`
   - Salah: `### Protocol ResultsDelegate`, `### Struct: SearchResultItem`, `### SearchResultItem (struct)` (Huruf pertama tipe harus kapital).

4. PENYEDERHANAAN FRASA BERULANG (Conciseness)
   - Hindari frasa berulang "Tipe struct ...", "Tipe enum ...", "Tipe class ...".
   - Sederhanakan menjadi "Struct ...", "Enum ...", "Class ..." atau langsung sebutkan nama tipenya.

5. PENGGUNAAN ISTILAH TEKNIS & EYD
   - Gunakan `*instance*` (cetak miring) atau nama objeknya langsung saat merujuk pada objek hasil instansiasi OOP. **JANGAN** gunakan "instansi" (yang berarti badan/lembaga pemerintah).
   - Pertahankan istilah teknis standar industri dalam format cetak miring (*italic*) atau kode (`inline code`):
     * *thread-safe*, *concurrency*, *lock-free*, *debounce*, *throttle*, *cache*, *orphan records*, *payload*, *fallback*, *pipeline*, *batching*.
   - Gunakan tata bahasa Indonesia baku (EYD) yang lugas tanpa terjemahan kaku/harfiah.

6. INTEGRITAS KODE & DIAGRAM
   - Jangan ubah blok kode asli (Swift, SQL, Shell, JSON) selain perbaikan dokumentasi jika ada.
   - Pertahankan sintaks diagram Mermaid (`mermaid`), link referensi dokumen, dan tabel markdown.

---

## SEVERITY CLASSIFICATION FOR FINDINGS

- **`### [BLOCKING]`**:
  * Code: Data corruption, memory leaks without cleanup, main-thread blocking I/O, insecure secrets/scripts.
  * Docs: Menerjemahkan konstruk Swift ("kelas", "struktur", "protokol"), mendistorsi istilah concurrency (`Task` -> "tugas", `thread` -> "utas"), heading komponen salah, diagram Mermaid rusak.
- **`### [WARN]`**:
  * Code: Sub-optimal virtualization, stale lifecycle states, missing edge-case handling.
  * Docs: Frasa berulang ("Tipe struct..."), kata "instansi" alih-alih `*instance*`, istilah teknis tanpa format cetak miring/inline code, terjemahan kaku.
- **`### [NIT]`**:
  * Code/Docs: Formatting minor, spasi, typo kosmetik yang tidak mengubah semantik.
