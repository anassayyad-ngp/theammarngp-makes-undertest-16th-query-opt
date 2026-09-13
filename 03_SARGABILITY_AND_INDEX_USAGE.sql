-- ============================================================================
-- MODULE 16 : QUERY OPTIMIZATION
-- TOPIC     : SARGability and Index Usage
-- ============================================================================
-- BUSINESS OBJECTIVE
--   Show, side by side, non-SARGable HR reporting queries and their
--   SARGable rewrites, plus how to design a supporting composite index.
--
-- PRODUCTION SCENARIO
--   HR compliance reporting: "employees hired in a given year," "employees
--   whose name matches a search term," on a multi-million-row employes table.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- CASE 1: date function wrapping the indexed column
-- ----------------------------------------------------------------------------

-- POOR PERFORMING VERSION (non-SARGable)
SELECT emp_name, hire_date
FROM employes
WHERE YEAR(hire_date) = 2023;

-- OPTIMIZED VERSION (SARGable — range predicate, column left bare)
SELECT emp_name, hire_date
FROM employes
WHERE hire_date >= '2023-01-01'
  AND hire_date <  '2024-01-01';

-- EXECUTION PLAN DISCUSSION
-- Run EXPLAIN ANALYZE on both against a table with an index on `hire_date`.
-- The first typically shows a Seq Scan regardless of the index; the second
-- should show an Index Scan / Index Range Scan.

-- ----------------------------------------------------------------------------
-- CASE 2: leading wildcard search
-- ----------------------------------------------------------------------------

-- POOR PERFORMING VERSION (leading wildcard defeats a standard B-tree index)
SELECT emp_name
FROM employes
WHERE emp_name LIKE '%ammar%';

-- OPTIMIZED VERSION (only viable when the business requirement allows
-- prefix search instead of substring search)
SELECT emp_name
FROM employes
WHERE emp_name LIKE 'Ammar%';

-- ENGINEERING NOTES
-- If the business genuinely requires substring search (not just prefix),
-- SARGability via a standard B-tree index isn't achievable — the correct
-- fix is a full-text index / trigram index (e.g., PostgreSQL `pg_trgm`),
-- not query rewriting. Know the difference between "can't be SARGable" and
-- "needs a different index type."

-- ----------------------------------------------------------------------------
-- CASE 3: implicit type conversion
-- ----------------------------------------------------------------------------

-- POOR PERFORMING VERSION (dept_id is INT; comparing to a string literal
-- can force an implicit CAST on every row in some engines)
SELECT emp_name
FROM employes
WHERE dept_id = '4';

-- OPTIMIZED VERSION
SELECT emp_name
FROM employes
WHERE dept_id = 4;

-- ----------------------------------------------------------------------------
-- COMPOSITE INDEX DESIGN EXAMPLE
-- ----------------------------------------------------------------------------
-- Business need: "list employees in a department, hired after a given date,
-- ordered by hire date" — run frequently for onboarding compliance reports.

-- CREATE INDEX idx_employes_dept_hiredate
--     ON employes (dept_id, hire_date);

-- USES the index efficiently (leftmost-prefix satisfied, both columns used):
SELECT emp_name, hire_date
FROM employes
WHERE dept_id = 4
  AND hire_date > '2023-01-01'
ORDER BY hire_date;

-- Does NOT use the index efficiently (skips the leading column `dept_id`):
SELECT emp_name, hire_date
FROM employes
WHERE hire_date > '2023-01-01'
ORDER BY hire_date;

-- INDEX RECOMMENDATIONS
-- If the "hire_date only" query above is also a frequent, business-critical
-- report, it needs its OWN index with hire_date leading:
--   CREATE INDEX idx_employes_hiredate ON employes (hire_date);
-- A single composite index cannot efficiently serve both access patterns.

-- ----------------------------------------------------------------------------
-- COVERING INDEX EXAMPLE
-- ----------------------------------------------------------------------------
-- CREATE INDEX idx_employes_covering
--     ON employes (dept_id, emp_name, hire_date);

-- This query can be answered entirely from the index above — no table
-- lookup required (look for "Index Only Scan" in EXPLAIN output):
SELECT emp_name, hire_date
FROM employes
WHERE dept_id = 4;

-- ----------------------------------------------------------------------------
-- INTERVIEW INSIGHT
-- ----------------------------------------------------------------------------
-- Q: "You have an index on hire_date but WHERE YEAR(hire_date) = 2023 is
--     still slow. Why, and what's the fix?"
-- A: The function wraps the column, making the predicate non-SARGable;
--    rewrite as a bare-column range comparison, or (PostgreSQL) create a
--    functional index on YEAR(hire_date) if the function form is required
--    by the application.

-- ----------------------------------------------------------------------------
-- FURTHER EXPERIMENTS
-- ----------------------------------------------------------------------------
-- 1. Create the composite index above and compare EXPLAIN output for a
--    query that uses both columns vs. one that uses only the trailing column.
-- 2. Test a functional index on UPPER(emp_name) and confirm it makes
--    `WHERE UPPER(emp_name) = 'AMMAR'` SARGable again.
