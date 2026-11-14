-- One row per order line that passed every cleaning rule. This is the table to
-- analyse; excluded lines are counted in mart_data_quality.

with

cleaned as (

    select * from {{ ref('int_order_lines__cleaned') }}

)

select
    order_line_key,
    source_system,
    account_key,
    product_key,
    order_id,
    order_date,
    qty_ordered,
    qty_fulfilled,
    unit_price,
    revenue,
    potential_unfilled_revenue,
    fulfillment_status,
    has_fulfillment_tracking,
    used_fulfillment_assumption
from cleaned
where is_included
