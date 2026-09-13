# Real-World Casebook — Query Optimization

End-to-end case studies connecting business problems to optimization solutions. Each case maps to lessons and engineering documents in this module.

---

## Case 1: HR Compliance Reporting at Scale

**Company context**: Global enterprise, 180,000 employees across 40 countries.

**Business problem**: "Employees hired in 2023" compliance report times out during quarterly audit window.

**Query**:
```sql
SELECT emp_name, hire_date, dept_id
FROM employes
WHERE YEAR(hire_date) = 2023;
```

**Diagnosis**: `YEAR(hire_date)` wraps indexed column → Seq Scan on 180K rows.

**Solution**: SARGable range rewrite + existing index on `hire_date`.

**Result**: 45 seconds → 120ms.

**Lessons**: [03 — SARGability](./03_SARGABILITY_AND_INDEX_USAGE.md), [REWRITE_COOKBOOK #1](./REWRITE_COOKBOOK.md)

---

## Case 2: E-Commerce Product Search

**Company context**: Online retailer, 2M products, peak traffic during sales events.

**Business problem**: Product search by name takes 8+ seconds during Black Friday.

**Query**:
```sql
SELECT product_id, product_name, price
FROM products
WHERE UPPER(product_name) LIKE '%' || UPPER(@search_term) || '%'
ORDER BY price
LIMIT 50;
```

**Diagnosis**: Leading wildcard + function on column → full table scan + sort on every search.

**Solution**: PostgreSQL trigram index (`pg_trgm`) + prefix search where business allows; full-text search for substring requirements.

**Result**: 8,000ms → 25ms (prefix) / 180ms (trigram substring).

**Lessons**: [03 — SARGability](./03_SARGABILITY_AND_INDEX_USAGE.md), [PERFORMANCE_SMELLS #3, #4](./PERFORMANCE_SMELLS.md)

---

## Case 3: SaaS Multi-Tenant Dashboard

**Company context**: B2B SaaS platform, 50,000 tenants, shared database.

**Business problem**: Tenant dashboard query fast for small tenants, 30+ seconds for enterprise tenants with 500K records.

**Query**:
```sql
SELECT event_type, COUNT(*) AS event_count
FROM events
WHERE tenant_id = @tenant_id
  AND created_at >= @start_date
GROUP BY event_type;
```

**Diagnosis**: Composite index on `(tenant_id, created_at)` exists but parameter sniffing cached plan optimized for small tenant (first execution had 50 rows).

**Solution**: `OPTION (RECOMPILE)` for tenant-specific queries; separate query paths for tenant size tiers.

**Result**: Enterprise tenant query: 30,000ms → 450ms.

**Lessons**: [01 — Plan Cache / Parameter Sniffing](./01_QUERY_EXECUTION_LIFECYCLE.md), [OPTIMIZATION_PLAYBOOK #3](./OPTIMIZATION_PLAYBOOK.md)

---

## Case 4: Financial Reconciliation Batch

**Company context**: Payment processor, 500M transactions/month.

**Business problem**: Nightly reconciliation job exceeded 6-hour window after transaction volume doubled.

**Query**:
```sql
SELECT t.account_id,
    (SELECT SUM(amount) FROM transactions t2
     WHERE t2.account_id = t.account_id
       AND t2.status = 'pending') AS pending_total
FROM accounts t
WHERE t.last_activity >= CURRENT_DATE - 30;
```

**Diagnosis**: Correlated scalar subquery in SELECT — SubPlan with loops = number of active accounts (2M).

**Solution**: Window function rewrite with pre-filtered CTE.

**Result**: 6.5 hours → 18 minutes.

**Lessons**: [05 — Subquery Optimization](./05_SUBQUERY_AND_CTE_OPTIMIZATION.md), [PRODUCTION_INCIDENTS #3 (Uber)](./PRODUCTION_INCIDENTS.md)

---

## Case 5: Logistics Inventory Pagination

**Company context**: Warehouse management system, 800M SKU-location records.

**Business problem**: Inventory listing page 100+ unusable; warehouse staff resorting to CSV exports.

**Query**:
```sql
SELECT sku, location, quantity
FROM inventory
WHERE warehouse_id = @wh_id
ORDER BY sku
LIMIT 50 OFFSET @page * 50;
```

**Diagnosis**: OFFSET pagination — page 100 requires generating and discarding 5,000 rows.

**Solution**: Keyset pagination on `(warehouse_id, sku)`.

**Result**: Page 100: 12,000ms → 8ms (flat across all pages).

**Lessons**: [06 — Anti-Patterns #9](./06_COMMON_PERFORMANCE_ANTI_PATTERNS.md), [PRODUCTION_INCIDENTS #4 (GitHub)](./PRODUCTION_INCIDENTS.md)

---

## Case 6: Healthcare Claims Analytics

**Company context**: Insurance provider, 2B claims records, strict HIPAA audit windows.

**Business problem**: Monthly claims summary report must complete within 2-hour audit window; recently taking 4+ hours.

**Query**:
```sql
SELECT provider_id, claim_type, SUM(paid_amount)
FROM claims
WHERE service_date >= '2025-01-01'
  AND service_date < '2026-01-01'
  AND status IN ('paid', 'partially_paid')
GROUP BY provider_id, claim_type;
```

**Diagnosis**: No partition pruning — scanning all historical partitions despite date filter. Statistics stale after year-end bulk import.

**Solution**: Partition by `service_date` (monthly), run ANALYZE post-import, composite index on `(service_date, status, provider_id)`.

**Result**: 4.2 hours → 35 minutes.

**Lessons**: [CROSS_DATABASE — Partitioning](./CROSS_DATABASE_ENGINEERING.md), [01 — Statistics](./01_QUERY_EXECUTION_LIFECYCLE.md)

---

## Related Documents

- [PRODUCTION_INCIDENTS.md](./PRODUCTION_INCIDENTS.md) — detailed post-mortems
- [REWRITE_COOKBOOK.md](./REWRITE_COOKBOOK.md) — canonical fixes
- [performance_lab/](./performance_lab/) — hands-on benchmarks
