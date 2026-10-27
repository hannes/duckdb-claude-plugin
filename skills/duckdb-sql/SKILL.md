---
name: duckdb-sql
description: >
  Write correct DuckDB 2.0 SQL. Use whenever writing, fixing or reviewing SQL that DuckDB
  will run, from any client (duckdb CLI, Python, R, Node, Java, dbt, DuckLake, MotherDuck),
  whenever a DuckDB query returns an error, and whenever the user mentions DuckDB, a .duckdb
  file, or analysing CSV, Parquet or JSON files. Covers what changed in 2.0 (Python-style
  lambdas, partial regex matching, division by zero), friendly SQL idioms, reading and
  writing files, and running SQL through the duckdb CLI in agent mode.
user-invocable: false
---

DuckDB 2.0.0 (October 2026) is the current release. Your training data mostly predates it.
Everything below runs on 2.0.0; prefer it over habits from PostgreSQL, SQLite or older DuckDB.

## Changed in 2.0: the mistakes to avoid

- **Lambdas are Python-style.** `x -> x + 1` fails with "Deprecated lambda arrow". Write
  `lambda x: x + 1`; the optional 1-based index is the last parameter: `lambda x, i: x > i`.
- **`~` matches partially**, like `regexp_matches`. `'abc' ~ 'b'` is `true`. Anchor with `^...$`
  for a full match.
- **`//` and `%` by zero raise an error**; `1 / 0` is still `inf`. Wrap in `TRY(...)` when
  a NULL is wanted.
- **`!` binds tighter than `*`**: `2 * 3!` is 12.
- **`X'FF'` is a BLOB and `B'101'` a BITSTRING**, no longer VARCHAR.
- **`CREATE TABLE t AS SELECT NULL AS x`** gives `x` the type `"NULL"`, not INTEGER. Cast: `NULL::INTEGER`.
- **`MERGE INTO` errors when two source rows match one target row.** Deduplicate the source.
- **Database files written by 2.0 cannot be opened by 1.x** unless written with
  `ATTACH 'f.duckdb' (STORAGE_VERSION 'v1.5.0')`, `-storage-version v1.5.0` on the CLI, or
  `SET storage_compatibility_version = 'v1.5.0'` before creating the file.
- **Variables:** `$name` replaces `getvariable('name')`.
- **Extensions:** `INSTALL AND LOAD spatial;` in one statement. Most core extensions
  (`httpfs`, `json`, `parquet`, `icu`) autoload; `spatial` does not.
- **`SHOW threads`** prints a setting; `DESCRIBE t` describes a table.
- `~`, `!`, and the two literal forms come from the new PEG parser. `SET enable_legacy_parser = true`
  brings back the old parser for one session; treat it as a diagnostic, not a fix.

## Idioms that DuckDB accepts and other dialects do not

```sql
CREATE OR REPLACE TABLE orders AS
    FROM (VALUES (1, 'eu', 10.0, DATE '2026-01-05'),
                 (2, 'eu', 20.0, DATE '2026-01-06'),
                 (3, 'us',  5.0, DATE '2026-02-01'))
    t(id, region, amount, day);

FROM orders;                                      -- FROM-first, SELECT * implied
FROM orders SELECT region, sum(amount) GROUP BY ALL ORDER BY ALL;
SELECT * EXCLUDE (day), amount * 2 AS doubled FROM orders;
SELECT * REPLACE (amount::INTEGER AS amount) FROM orders;
SELECT total: sum(amount), n: count() FROM orders;   -- prefix alias, count() with no star
SELECT region, amount, amount / sum(amount) OVER () AS share FROM orders
    QUALIFY share > 0.1;                          -- filter on a window result
SELECT region, count() FILTER (WHERE amount > 8) AS big FROM orders GROUP BY ALL;
SELECT max(amount, 2) AS top2, arg_max(id, amount) AS best_id FROM orders;  -- top-n per group
SELECT min(COLUMNS(* EXCLUDE (region, day))) FROM orders;        -- one expression over many columns
SELECT COLUMNS('a.*') FROM orders;                                -- columns by regex
SELECT a.x AS lateral_alias, lateral_alias + 1 AS reused FROM (SELECT 1 AS x) a;
FROM orders LIMIT 50%;                            -- percentage limit
PIVOT orders ON region USING sum(amount) GROUP BY day;
```

Lists, structs, maps, JSON:

```sql
SELECT [1, 2, 3] AS l, {'a': 1, 'b': 'two'} AS s, MAP {'k': 1} AS m;
SELECT l[1] AS first, l[-1] AS last, l[2:3] AS slice, s.a, m['k'] AS mk
    FROM (SELECT [1, 2, 3] AS l, {'a': 1} AS s, MAP {'k': 1} AS m);
SELECT [x * 2 FOR x IN [1, 2, 3] IF x > 1] AS comprehension;
SELECT list_transform([1, 2, 3], lambda x: x + 1), list_filter([1, 2, 3], lambda x: x > 1),
       list_reduce([1, 2, 3], lambda acc, x: acc + x);
SELECT unnest([1, 2, 3]) AS v;                      -- one row per element
SELECT unnest({'a': 1, 'b': 2});                    -- struct fields become columns
SELECT ('hello').upper(), 'a,b'.string_split(',');  -- dot chaining on any function
SELECT j->>'$.user.id' AS id, j.user.name AS name FROM (SELECT '{"user":{"id":42,"name":"x"}}'::JSON AS j);
SELECT '{"user":{"id":42}}'::JSON::VARIANT AS v;    -- VARIANT: first-class semi-structured type
```

Joins and modifications:

```sql
CREATE OR REPLACE TABLE prices AS FROM (VALUES (DATE '2026-01-01', 1.0), (DATE '2026-02-01', 2.0)) t(day, price);
SELECT o.id, p.price FROM orders o ASOF JOIN prices p ON o.day >= p.day;   -- latest price at or before
SELECT * FROM orders POSITIONAL JOIN prices;
INSERT INTO orders BY NAME SELECT 4 AS id, 'eu' AS region, 1.0 AS amount, DATE '2026-03-01' AS day;
CREATE OR REPLACE TABLE stock (sku VARCHAR PRIMARY KEY, qty INTEGER);
INSERT OR REPLACE INTO stock VALUES ('a', 1), ('b', 1);
INSERT OR REPLACE INTO stock VALUES ('a', 2);     -- upsert on the primary key; INSERT OR IGNORE skips instead
WITH moved AS (DELETE FROM orders WHERE region = 'us' RETURNING *)
    SELECT count() FROM moved;                        -- data-modifying CTE
SET VARIABLE threshold = 15;
FROM orders WHERE amount > $threshold;
```

Keep SQL plain where DuckDB matches the standard: `CASE`, CTEs, window functions, `STRING_AGG`,
`date_trunc`, `strftime`, `::` casts, `INTERVAL 3 DAY`, `generate_series` (inclusive) and
`range` (exclusive) all work as expected. Identifiers are double-quoted and case-insensitive;
backticks are not identifiers.

## Files are tables

```sql
FROM 'data/*.parquet';                              -- globs, Parquet, CSV, JSON by extension
FROM read_csv('f.csv', header = true, delim = ';', columns = {'id': 'INTEGER', 'name': 'VARCHAR'});
FROM read_csv('f.csv', ignore_errors = true, union_by_name = true, filename = true);
FROM read_parquet('part-*.parquet', hive_partitioning = true);
FROM read_json('events.jsonl');                    -- auto-detects newline-delimited and arrays
COPY orders TO 'out.parquet' (FORMAT parquet, COMPRESSION zstd);
COPY orders TO 'by_region' (FORMAT parquet, PARTITION_BY (region), OVERWRITE_OR_IGNORE);
```

Remote files work the same with `httpfs`, which autoloads: `FROM 'https://.../f.parquet'`,
`FROM 's3://bucket/*.parquet'`. Credentials go in secrets, never in the URL:
`CREATE SECRET (TYPE s3, PROVIDER credential_chain);`. Query parameters in S3 URLs are
disabled in 2.0.

Before trusting a file's schema, look at it: `DESCRIBE FROM 'f.csv'` and `SUMMARIZE FROM 'f.csv'`.

## Running SQL from a shell

The `duckdb` CLI detects Claude Code and switches on agent mode: compact Markdown tables with
types in the header, results capped at 1000 rows and 10 kB with a footer that says how many
rows were cut, errors as JSON on stderr, and progress on stderr for long queries. Do not add
`-csv` or `-json` unless you need that format; they switch agent mode off. Do not add `LIMIT`
just to protect the context; the cap does that.

```bash
duckdb -c "FROM 'f.parquet' LIMIT 5"                # in-memory database
duckdb mydb.duckdb -c "FROM orders"                 # persistent database
duckdb -readonly mydb.duckdb -c ".tables"            # when you only read
duckdb mydb.duckdb <<'SQL'
SET max_execution_time = 30000;                     -- 30 s bound on each statement
DESCRIBE FROM orders;                               -- result columns without running the query
EXPLAIN ANALYZE FROM orders WHERE amount > 10;      -- compact plan with times and bytes read
SQL
duckdb -manual list_transform                        -- documentation of a function
duckdb -c "FROM duckdb_functions() WHERE function_name ILIKE '%regexp%' SELECT DISTINCT function_name"
```

Use heredocs for multi-line SQL. Read error JSON: a `Binder Error` lists candidate names, a
`Catalog Error` means the table or function does not exist (`.tables`, `duckdb_functions()`),
a `Parser Error` gives the position. Fix the SQL and rerun; do not switch to Python to
inspect data the CLI can show.

## Performance

DuckDB parallelises on its own; settings matter only on big inputs. `SET threads = 4` and
`SET memory_limit = '8GB'` bound resources, `SET preserve_insertion_order = false` speeds up
large unordered loads and exports, `EXPLAIN ANALYZE` shows where time goes. Filter and
project early when reading Parquet; DuckDB pushes both into the scan. Parquet beats CSV
for anything read twice.

## Where to look things up

`duckdb -manual <function>`, `FROM duckdb_functions()`, `FROM duckdb_settings()`, and
https://duckdb.org/docs/2.0/ (the version is in the URL; `stable` also points at 2.0).
The `duckdb-skills` plugin's `duckdb-docs` skill searches the documentation offline.
