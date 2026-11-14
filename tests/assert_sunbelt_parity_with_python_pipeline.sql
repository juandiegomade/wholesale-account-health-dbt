-- The dbt models must reproduce what the original, validated Python pipeline reported
-- for Sunbelt: $215,395 total = $199,027 at risk in dormant accounts + $16,368
-- potential unfilled revenue. Fails if any figure is off by more than $1, or if the
-- Sunbelt row is missing.

with

expected as (

    select
        'sunbelt' as source_system,
        199027 as revenue_at_risk_dormant,
        16368 as potential_unfilled_revenue,
        215395 as total_revenue_opportunity

),

actual as (

    select
        source_system,
        revenue_at_risk_dormant,
        potential_unfilled_revenue,
        total_revenue_opportunity
    from {{ ref('mart_opportunity_summary') }}

)

select
    expected.source_system,
    expected.revenue_at_risk_dormant as expected_revenue_at_risk_dormant,
    actual.revenue_at_risk_dormant as actual_revenue_at_risk_dormant,
    expected.potential_unfilled_revenue as expected_potential_unfilled_revenue,
    actual.potential_unfilled_revenue as actual_potential_unfilled_revenue,
    expected.total_revenue_opportunity as expected_total_revenue_opportunity,
    actual.total_revenue_opportunity as actual_total_revenue_opportunity
from expected
left join actual
    on expected.source_system = actual.source_system
where
    actual.source_system is null
    or actual.potential_unfilled_revenue is null
    or abs(actual.revenue_at_risk_dormant - expected.revenue_at_risk_dormant) > 1
    or abs(actual.potential_unfilled_revenue - expected.potential_unfilled_revenue) > 1
    or abs(actual.total_revenue_opportunity - expected.total_revenue_opportunity) > 1
