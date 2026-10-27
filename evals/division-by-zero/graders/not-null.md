---
type: llm
---
PASS if the answer says the statement raises an error (division by zero) in DuckDB 2.0, optionally mentioning TRY() or error_on_division_by_zero as ways to get NULL instead.
FAIL if the answer says it returns NULL, infinity, or 0 without saying that the default is an error.
