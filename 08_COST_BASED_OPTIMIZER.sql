-- ============================================================================
-- MODULE 16 : QUERY OPTIMIZATION
-- TOPIC     : The Cost-Based Optimizer
-- ============================================================================
-- BUSINESS OBJECTIVE
--   Demonstrate statistics inspection, stale-statistics symptoms, and
--   parameter-sniffing behavior against the shared employes/departments
--   schema.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- INSPECTING WHAT THE OPTIMIZER KNOWS (PostgreSQL)
-- ----------------------------------------------------------------------------
SELECT
    attname AS column_name,
    n_distinct,
    most_common_vals,
    most_common_freqs
FROM pg_stats
WHERE tablename = 'employes'
  AND attname IN ('dept_id', 'hire_date');

-- ENGINEERING NOTES
-- n_distinct: the planner's estimate of how many distinct values this
-- column has (negative values mean "estimated as a fraction of total rows").
-- most_common_vals / most_common_freqs: the histogram's most frequent
-- values and their observed frequency -- this is what lets the optimizer
-- estimate `WHERE dept_id = 4` differently from `WHERE dept_id = 27` even
-- though both are equality predicates on the same column.

-- ----------------------------------------------------------------------------
-- REPRODUCING A STALE-STATISTICS SYMPTOM
-- ----------------------------------------------------------------------------
-- Simulate a bulk load, then compare plans before and after refreshing
-- statistics.

-- Step 1: baseline plan (assume statistics are current)
EXPLAIN ANALYZE
SELECT emp_name FROM employes WHERE dept_id = 4;

-- Step 2: simulate a large bulk insert that changes the table's actual
-- distribution significantly (illustrative -- adjust volume for your
-- environment)
-- INSERT INTO employes (emp_name, dept_id, hire_date)
-- SELECT 'Bulk Employee ' || gs, 4, CURRENT_DATE
-- FROM generate_series(1, 500000) AS gs;

-- Step 3: re-run WITHOUT refreshing statistics -- the optimizer may still
-- be planning against the OLD row/selectivity estimates
EXPLAIN ANALYZE
SELECT emp_name FROM employes WHERE dept_id = 4;

-- Step 4: refresh statistics, then re-run
ANALYZE employes;

EXPLAIN ANALYZE
SELECT emp_name FROM employes WHERE dept_id = 4;

-- PERFORMANCE COMPARISON
-- Compare "estimated rows" (not actual -- actual is always correct) across
-- steps 1, 3, and 4. Step 3's estimate should badly undercount the true
-- row count for dept_id = 4 after the bulk load; step 4's estimate should
-- realign with reality after ANALYZE.

-- ----------------------------------------------------------------------------
-- MULTI-COLUMN CORRELATION (optimizer assumes independence by default)
-- ----------------------------------------------------------------------------
-- If dept_id and location_id are correlated in departments (e.g. certain
-- departments only exist at certain locations), a combined filter on both
-- is often mis-estimated because the optimizer multiplies each column's
-- independent selectivity together by default.

EXPLAIN ANALYZE
SELECT *
FROM departments
WHERE dept_id = 4
  AND location_id = 2;

-- FIX (PostgreSQL 10+): tell the optimizer these columns are correlated
-- CREATE STATISTICS dept_location_stats (dependencies)
--     ON dept_id, location_id FROM departments;
-- ANALYZE departments;

-- Re-run the same EXPLAIN ANALYZE after creating extended statistics and
-- compare the estimated row count against the actual.

-- ----------------------------------------------------------------------------
-- INTERVIEW INSIGHT
-- ----------------------------------------------------------------------------
-- Q: "A stored procedure runs fast for you locally but a colleague reports
--     it's slow in production with different input. Same code, same
--     schema. What do you check first?"
-- A: Parameter sniffing -- check whether the cached plan was compiled
--    against a parameter value with very different selectivity than the
--    production caller's value; consider OPTION (RECOMPILE) / statement-
--    level hints, or splitting into differently-optimized query paths.

-- ----------------------------------------------------------------------------
-- FURTHER EXPERIMENTS
-- ----------------------------------------------------------------------------
-- 1. Compare `default_statistics_target` at 100 (default) vs 500 for a
--    skewed column and observe how histogram granularity changes the
--    estimate accuracy in EXPLAIN output.
-- 2. On SQL Server or MySQL, reproduce the same "before/after ANALYZE"
--    experiment using that engine's statistics-refresh command
--    (`UPDATE STATISTICS`, `ANALYZE TABLE`).
