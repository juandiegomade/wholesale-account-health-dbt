-- Every mart is an aggregate of fct_order_lines, so their totals must agree with it.
-- Returns a row for each source where line counts or revenue drifted apart.

with

fact_totals as (

    select
        source_system,
        count(*) as line_count,
        sum(revenue) as revenue
    from {{ ref('fct_order_lines') }}
    group by source_system

),

summary_totals as (

    select
        source_system,
        total_revenue
    from {{ ref('mart_opportunity_summary') }}

),

product_totals as (

    select
        source_system,
        sum(total_revenue) as total_revenue
    from {{ ref('dim_products') }}
    group by source_system

),

quality_totals as (

    select
        source_system,
        sum(line_count) as included_line_count
    from {{ ref('mart_data_quality') }}
    where is_included
    group by source_system

)

select
    fact_totals.source_system,
    fact_totals.line_count as fact_line_count,
    quality_totals.included_line_count as data_quality_included_line_count,
    fact_totals.revenue as fact_revenue,
    summary_totals.total_revenue as summary_revenue,
    product_totals.total_revenue as product_revenue
from fact_totals
left join summary_totals
    on fact_totals.source_system = summary_totals.source_system
left join product_totals
    on fact_totals.source_system = product_totals.source_system
left join quality_totals
    on fact_totals.source_system = quality_totals.source_system
where
    summary_totals.total_revenue is null
    or product_totals.total_revenue is null
    or quality_totals.included_line_count is null
    or fact_totals.line_count != quality_totals.included_line_count
    or abs(fact_totals.revenue - summary_totals.total_revenue) > 0.01
    or abs(fact_totals.revenue - product_totals.total_revenue) > 0.01
