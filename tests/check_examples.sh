#!/usr/bin/env bash
# Runs every ```sql block in the skills through duckdb and every ```python block through
# python, each skill in one fresh session, so the skills only ever show code that works.
# Usage: tests/check_examples.sh [python-with-duckdb]
set -u
cd "$(dirname "$0")/.."
PY="${1:-python3}"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
fail=0
extract() { # file lang -> concatenated code blocks
  awk -v lang="$2" '
    $0 ~ "^```"lang"$" {on=1; next}
    on && /^```$/ {on=0; print ""; next}
    on {print}' "$1"
}
# fixtures the examples refer to
(cd "$work" && mkdir -p data && duckdb -no-agent -c "
  COPY (SELECT 1 AS id, 'a' AS name) TO 'f.csv' (HEADER, DELIMITER ';');
  COPY (FROM range(5) t(i)) TO 'data/x.parquet';
  COPY (SELECT 1 AS id, 'eu' AS region) TO 'part-0.parquet';
  COPY (SELECT 1 AS id, {'k': 1} AS payload) TO 'events.jsonl' (FORMAT json);
  ATTACH 'file.duckdb'; CREATE TABLE file.test (i INTEGER);" > /dev/null)
for f in skills/*/SKILL.md; do
  name=$(basename "$(dirname "$f")")
  extract "$f" sql > "$work/$name.sql"
  if [ -s "$work/$name.sql" ]; then
    if (cd "$work" && duckdb -no-agent -bail -c ".read $name.sql" > "$name.sql.out" 2> "$name.sql.err"); then
      echo "ok   $name sql ($(grep -c ';' "$work/$name.sql") statements)"
    else
      echo "FAIL $name sql"; cat "$work/$name.sql.err"; fail=1
    fi
  fi
  extract "$f" python > "$work/$name.py"
  if [ -s "$work/$name.py" ]; then
    if (cd "$work" && "$PY" -I -W error::DeprecationWarning "$name.py" > "$name.py.out" 2> "$name.py.err"); then
      echo "ok   $name python ($(wc -l < "$work/$name.py") lines)"
    else
      echo "FAIL $name python"; tail -5 "$work/$name.py.err"; fail=1
    fi
  fi
done
# every ```bash block must at least parse
for f in skills/*/SKILL.md; do
  extract "$f" bash > "$work/b.sh"
  [ -s "$work/b.sh" ] && { bash -n "$work/b.sh" && echo "ok   $(basename "$(dirname "$f")") bash parses" || { echo "FAIL bash syntax in $f"; fail=1; }; }
done
exit $fail
