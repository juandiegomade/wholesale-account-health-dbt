-- Both sources in one shape: one row per order line, same column names and types.
-- Nothing is filtered here. Each source keeps its own flags so the next model can
-- decide what to exclude and say why.

with

online_retail as (

    select
        invoice_line_key as order_line_key,
        'online_retail' as source_system,
        invoice_number as order_id,
        invoice_date as order_date,
        customer_id as account_id,
        -- this source has no customer names, only IDs
        customer_id as account_name,
        country,
        stock_code as sku,
        product_description as product_name,
        cast(quantity as numeric) as qty_ordered,
        -- no shipped quantity in this source
        cast(null as numeric) as qty_fulfilled,
        unit_price,
        cast(null as string) as fulfillment_status,
        false as has_fulfillment_tracking,
        -- only rows where every column matches count as duplicates here: the same
        -- product can legitimately appear twice on one invoice at different quantities
        is_exact_duplicate as is_duplicate_line,
        is_cancellation,
        is_bad_debt_adjustment,
        is_non_merchandise
    from {{ ref('stg_online_retail__invoice_lines') }}

),

sunbelt as (

    select
        order_line_key,
        'sunbelt' as source_system,
        order_id,
        order_date,
        account_name as account_id,
        account_name,
        cast(null as string) as country,
        sku,
        product_name,
        qty_ordered,
        qty_fulfilled,
        unit_price,
        fulfillment_status,
        true as has_fulfillment_tracking,
        -- same rule as the original Python pipeline: one line per order, product,
        -- account and date
        row_number() over (
            partition by order_id, sku, account_name, order_date
            order by order_line_key
        ) > 1 as is_duplicate_line,
        false as is_cancellation,
        false as is_bad_debt_adjustment,
        false as is_non_merchandise
    from {{ ref('stg_sunbelt__order_lines') }}

),

unioned as (

    select * from online_retail
    union all
    select * from sunbelt

)

select
    order_line_key,
    source_system,
    order_id,
    order_date,
    account_id,
    account_name,
    country,
    sku,
    product_name,
    qty_ordered,
    qty_fulfilled,
    unit_price,
    fulfillment_status,
    has_fulfillment_tracking,
    is_duplicate_line,
    is_cancellation,
    is_bad_debt_adjustment,
    is_non_merchandise
from unioned
