---
name: duckdb-python
description: >
  Use the DuckDB Python client (duckdb 2.0 on PyPI) correctly. Use whenever writing Python
  that imports duckdb or queries DataFrames, Parquet or CSV with SQL, when a duckdb Python
  call raises, and when choosing between pandas, Polars, Arrow and DuckDB for data work.
  Covers connect, sql versus execute, lazy relations, fetching, DataFrame interop,
  parameters, the appender, threads, and the methods removed in 2.0.
user-invocable: false
---

The current client is `duckdb` 2.0.0, requires Python 3.11 or newer, and installs with
`pip install duckdb`. On Python 3.10 pip silently falls back to 1.x. Everything below runs
on 2.0.0.

## Two ways to run SQL, and when to use each

```python
import duckdb

con = duckdb.connect()                 # in-memory; duckdb.connect("file.duckdb") persists
con.execute("CREATE TABLE t AS SELECT range AS i FROM range(10)")   # DDL and DML: execute
rel = con.sql("FROM t WHERE i > 5")    # a query: sql() returns a lazy relation
print(rel.fetchall())                  # [(6,), (7,), (8,), (9,)]
```

- `con.execute(sql)` runs now and holds one result; read it with `fetchall()`, `fetchone()`,
  `fetchmany(n)`, `df()`, `pl()`, `fetchnumpy()`. Use it for `CREATE`, `INSERT`, `COPY`,
  `SET`, and for row-at-a-time loops. In 2.0 `con.sql("CREATE ...")` returns a relation that
  a notebook would print and thereby run again, so keep DDL on `execute`.
- `con.sql(sql)` returns a relation. It runs nothing until read, and runs again on every read.
  Relations compose: `con.sql("FROM rel WHERE i < 8")` refers to the Python variable `rel`.
- Removed from relations in 2.0: `fetchone()`, `fetchmany()`, `execute()`, `fetch_df_chunk()`.
  Use `rel.iter_rows()` to iterate, `rel.materialize()` to run once and keep rows,
  `rel.to_arrow_reader()` for batches.
- Removed from `execute()` results in 2.0: `fetch_arrow_table()`, `fetch_record_batch()`,
  `arrow()`, `pl()`. Use `con.sql(q).to_arrow_table()`, `.to_arrow_reader()`, `.pl()`.

## Getting results out

```python
rel = con.sql("SELECT i, i * 2 AS d FROM t")
rows = rel.fetchall()                  # list of tuples
pdf = rel.df()                         # pandas
pldf = rel.pl()                        # Polars
tbl = rel.to_arrow_table()             # Arrow table (batch_size= to tune, default 131072)
for i, d in rel.iter_rows():           # row by row, whole result held in the engine
    pass
rel.write_parquet("out.parquet")       # raises IOException if the file exists
rel.write_parquet("out.parquet", overwrite=True)
con.execute("COPY (FROM t) TO 'out.csv' (HEADER)")
```

## DataFrames and files are tables

```python
import pandas as pd, polars as pl, pyarrow as pa
pdf = pd.DataFrame({"a": [1, 2]}); pldf = pl.DataFrame({"a": [3]}); arrow_t = pa.table({"a": [4]})
con.sql("FROM pdf UNION ALL FROM pldf UNION ALL FROM arrow_t").order("a").show()   # by variable name
con.sql("FROM 'out.parquet' WHERE i > 7").show()                           # files by path
con.read_csv("f.csv")                  # relation; also read_parquet, read_json
con.register("named", pdf)             # when the variable name is not visible to DuckDB
```

DataFrames are read-only inside SQL; `INSERT INTO pdf` fails. Loading one into a table is
`con.execute("CREATE TABLE a AS FROM pdf")`, which is faster than row-wise appends.

## Parameters

```python
con.execute("FROM t WHERE i > ?", [5]).fetchall()
con.execute("FROM t WHERE i > $lo AND i < $hi", {"lo": 5, "hi": 8}).fetchall()
con.executemany("INSERT INTO t VALUES (?)", [(10,), (11,)])
```

Parameters are for values. Table and column names cannot be parameters; build those with
f-strings only from trusted input.

## Loading many rows

```python
con.execute("CREATE TABLE people (id INTEGER PRIMARY KEY, name VARCHAR)")
with con.appender("people") as ap:     # new in 2.0; flushes on normal exit
    ap.append_row(1, "Mark")
    ap.append_rows([(2, "Hannes"), (3, "Gabor")])
```

`con.appender(table, action="upsert")`, `"update"` and `"delete"` with `key=[...]` exist.
If the data is already a DataFrame or Arrow table, `INSERT INTO people FROM df` is faster
than the appender. Cast and constraint errors surface at flush time.

## Connections, threads, settings

```python
con = duckdb.connect("file.duckdb", read_only=True)
con = duckdb.connect(config={"threads": 4, "memory_limit": "4GB"})
con = duckdb.connect("compat.duckdb", config={"storage_compatibility_version": "v1.5.0"})  # readable by 1.5
```

- One connection is one session. A second thread must use `con.cursor()`; a shared connection
  raises `ResourceInUseException` in 2.0 instead of waiting.
- An `execute()` result left half-read blocks the next query with `ResourceInUseException`;
  finish reading it or run `con.execute` again, which replaces it.
- After `con.begin()`, any failing statement aborts the transaction; `con.rollback()` then
  `con.begin()` again.
- `with duckdb.connect("file.duckdb") as con:` closes the connection. Only one process may
  write a database file at a time.
- Extensions: `con.install_extension("h3", repository="community"); con.load_extension("h3")`,
  or `con.execute("INSTALL AND LOAD spatial")`.
- Python functions in SQL: `con.create_function("f", f, [int], int)`; keep them for logic
  SQL cannot express, they run row by row.

## Expression API renames in 2.0

`ColumnExpression("x") == "y"` compares with the string value `"y"`, not column `y`; use
`duckdb.ColumnExpression("y")`. `ColumnExpression("t.x")` is one name with a dot; pass two
arguments for a qualified name. Relation attribute access such as `rel.offset` now hits a
method; use `rel["offset"]` for a column of that name.

For SQL itself follow the `duckdb-sql` skill of this plugin; its 2.0 changes (lambda syntax,
partial regex, division by zero) apply to SQL strings in Python too.
