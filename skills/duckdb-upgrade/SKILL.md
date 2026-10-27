---
name: duckdb-upgrade
description: >
  Upgrade DuckDB 1.x code, SQL and database files to DuckDB 2.0, and explain errors that
  appear after an upgrade. Use when the user upgrades or migrates DuckDB, asks what changed
  or broke in 2.0, or hits one of these messages: "Deprecated lambda arrow", "can only read
  versions between", "storage version", "Division by zero", "ResourceInUseException",
  "fetchone" or "fetch_arrow_table" missing on a relation, "enable_legacy_parser", or a
  Parser Error on SQL that worked before.
---

DuckDB 2.0.0 LTS (October 2026) is supported until at least October 2027. 1.5 is supported
until March 2027; 1.4 LTS until 17 November 2026. 2.0 reads and writes 1.x database files
unchanged, so an upgrade is reversible as long as no new file is created.

## Symptom to fix

| Symptom | Cause | Fix |
|---|---|---|
| `Deprecated lambda arrow (->) detected` | `x -> expr` lambdas are off by default | Rewrite as `lambda x: expr`; `SET lambda_syntax = 'enable_single_arrow'` bridges one session and is removed in 2.1 |
| `IO Error: ... can only read versions between 64 and 68` on an old DuckDB | File written by 2.0 (storage version 69) | Write for the old version: `ATTACH 'f.duckdb' (STORAGE_VERSION 'v1.5.0')`, CLI `-storage-version v1.5.0`, or `SET storage_compatibility_version = 'v1.5.0'` before creation; or convert with `EXPORT DATABASE` on the new side and `IMPORT DATABASE` on the old |
| Regex `~` suddenly matches more | `~` now matches partially | Anchor the pattern `^...$`, or `SET regex_match_operator_semantics = 'full'` |
| `2 * 3!` changed from 720 to 12 | `!` binds tighter | Parenthesise `(2 * 3)!` |
| `Division by zero` error from `//` or `%` | New default | `TRY(a // b)` or `SET error_on_division_by_zero = false` |
| `X'...'` or `B'...'` behaves differently | Now BLOB and BITSTRING literals | Cast when VARCHAR was intended |
| Column typed `"NULL"` from `CREATE TABLE AS SELECT NULL` | Untyped NULL keeps the NULL type | `NULL::INTEGER`, or `SET legacy_disable_null_type = true` |
| `MERGE INTO` error about multiple matching rows | Well-defined semantics now | Deduplicate the source or make the `ON` condition unique |
| S3 URL `?s3_access_key_id=` ignored | URL parameters disabled | Use `CREATE SECRET`; `SET s3_enable_deprecated_url_parameters = true` after `LOAD httpfs` bridges |
| `custom_profiling_settings`, `enable_http_logging`, `profiling_mode` unknown or ignored | Removed or deprecated | `tracked_metrics`; `CALL enable_logging('HTTP')`; `PRAGMA enable_profiling` |
| `preserve_identifier_case` is now a string | `'preserve_case'`, `'lowercase'`, `'uppercase'`; `true`/`false` still map | No change needed |
| `duckdb_logs` empty in the CLI | CLI log storage is not queryable | `CALL enable_logging(storage = 'memory')` |
| Parser Error on SQL that 1.x accepted | New PEG parser | Check the message position; `ORDER BY true` and other non-integer literals are rejected. `SET enable_legacy_parser = true` autoloads the old parser to confirm the cause |

## Python client

| Symptom | Fix |
|---|---|
| `pip install duckdb` gives 1.4.x | Python 3.11 or newer is required; 3.10 gets the last 1.x |
| `'DuckDBPyRelation' object has no attribute 'fetchone'` (also `fetchmany`, `execute`, `fetch_df_chunk`) | `con.execute(q)` for cursor-style loops; `rel.iter_rows()`; `rel.materialize()` |
| `fetch_arrow_table`, `fetch_record_batch`, `arrow()`, `pl()` missing on an `execute()` result | `con.sql(q).to_arrow_table()`, `.to_arrow_reader()`, `.pl()` |
| `ResourceInUseException` | Two threads on one connection: give each a `con.cursor()`. Or a half-read `execute()` result: finish or replace it |
| `IOException: file exists` from `write_parquet` or `write_csv` | Pass `overwrite=True` |
| Notebook prints and reruns `CREATE TABLE` | `con.sql()` returns a relation now; use `con.execute()` for DDL |
| `ColumnExpression("a") == "b"` compares with a string | Strings are values in 2.0; use `ColumnExpression("b")` for a column |
| `TransactionException` after an error inside `begin()` | Any failed statement aborts the transaction; `rollback()` first |
| Arrow batches are smaller | Default batch size is 131072 rows; pass `batch_size=` |

## Build and platform

C++17 is required to build; the amalgamation is deprecated; release binaries are built with
Clang. `osx_amd64` is phased out and gone in 2.1. ICU is no longer bundled: the `icu`
extension implements time zones and collations itself with IANA data, and queries do not change.

## Procedure for a code base

1. Find arrow lambdas: `grep -rnE '\b[a-z_]+\s*->\s' --include='*.sql' --include='*.py'`
   and rewrite them; JSON `->` and `->>` operators are unrelated and stay.
2. Find `~` and `!~` regex operators and decide whether partial matching changes results.
3. Find `//` and `%` where the divisor can be zero.
4. Decide the storage version: if any 1.x process will open the files, write with
   `storage_compatibility_version = 'v1.5.0'` until all are upgraded.
5. Python: fix the removed methods and add `cursor()` per thread.
6. Run the test suite against 2.0 on a copy of the data before switching production.

Full guide: https://duckdb.org/docs/2.0/operations_manual/migration.html and
https://duckdb.org/docs/2.0/clients/python/migration.
