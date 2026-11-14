-- Returns, cancellations and unpriced lines are excluded upstream, so nothing in the
-- fact table may be negative, and every line must have a price.

select
    order_line_key,
    qty_ordered,
    qty_fulfilled,
    unit_price,
    revenue,
    potential_unfilled_revenue
from {{ ref('fct_order_lines') }}
where
    qty_ordered < 0
    or qty_fulfilled < 0
    or unit_price <= 0
    or revenue < 0
    or potential_unfilled_revenue < 0
