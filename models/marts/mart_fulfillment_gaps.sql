-- Potential unfilled revenue by product: what was ordered but not shipped.
-- Only sources that record shipped quantities appear here. A source without
-- fulfillment tracking is "not measurable", which is different from "no gaps".

with

order_lines as (

    select * from {{ ref('fct_order_lines') }}
    where has_fulfillment_tracking

),

products as (

    select * from {{ ref('dim_products') }}

),

gaps as (

    select
        product_key,
        source_system,
        count(*) as line_count,
        countif(potential_unfilled_revenue > 0) as short_line_count,
        sum(qty_ordered) as qty_ordered,
        sum(qty_fulfilled) as qty_fulfilled,
        sum(revenue) as revenue,
        sum(potential_unfilled_revenue) as potential_unfilled_revenue
    from order_lines
    group by product_key, source_system

)

select
    gaps.product_key,
    gaps.source_system,
    products.sku,
    products.product_name,
    gaps.line_count,
    gaps.short_line_count,
    gaps.qty_ordered,
    gaps.qty_fulfilled,
    safe_divide(gaps.qty_fulfilled, gaps.qty_ordered) as fill_rate,
    gaps.revenue,
    gaps.potential_unfilled_revenue
from gaps
inner join products
    on gaps.product_key = products.product_key
