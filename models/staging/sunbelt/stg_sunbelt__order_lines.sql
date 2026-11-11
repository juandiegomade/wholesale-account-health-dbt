-- One row per order line from the Sunbelt export.
-- Staging only renames, casts, trims and standardizes formats. Business rules
-- (dedup, fulfillment assumptions, revenue) live in the intermediate layer.

with

source as (

    select * from {{ source('sunbelt', 'sunbelt_order_lines') }}

),

typed as (

    select
        trim(order_id) as order_id,
        -- Two date formats in the export. The slash format is month-first: day values
        -- above 12 appear in the second position, never the first.
        coalesce(
            safe.parse_date('%Y-%m-%d', trim(order_date)),
            safe.parse_date('%m/%d/%Y', trim(order_date))
        ) as order_date,
        initcap(trim(account_name)) as account_name,
        -- "sku1001" and "SKU-1001" are the same product
        regexp_replace(upper(trim(sku)), r'^SKU-?', 'SKU-') as sku,
        nullif(trim(product), '') as product_name,
        safe_cast(qty_ordered as numeric) as qty_ordered,
        safe_cast(nullif(trim(qty_fulfilled), '') as numeric) as qty_fulfilled,
        safe_cast(unit_price as numeric) as unit_price,
        nullif(upper(trim(fulfillment_status)), '') as fulfillment_status,
        nullif(trim(channel), '') as sales_channel,

        -- raw values kept for the duplicate check below
        order_id as _raw_order_id,
        order_date as _raw_order_date,
        account_name as _raw_account_name,
        sku as _raw_sku,
        product as _raw_product,
        qty_ordered as _raw_qty_ordered,
        qty_fulfilled as _raw_qty_fulfilled,
        unit_price as _raw_unit_price,
        fulfillment_status as _raw_fulfillment_status,
        channel as _raw_channel
    from source

),

numbered as (

    select
        *,
        row_number() over (
            partition by
                _raw_order_id, _raw_order_date, _raw_account_name, _raw_sku, _raw_product,
                _raw_qty_ordered, _raw_qty_fulfilled, _raw_unit_price, _raw_fulfillment_status, _raw_channel
        ) as copy_number
    from typed

)

select
    to_hex(md5(concat(
        coalesce(_raw_order_id, ''), '|', coalesce(_raw_order_date, ''), '|',
        coalesce(_raw_account_name, ''), '|', coalesce(_raw_sku, ''), '|',
        coalesce(_raw_product, ''), '|', coalesce(_raw_qty_ordered, ''), '|',
        coalesce(_raw_qty_fulfilled, ''), '|', coalesce(_raw_unit_price, ''), '|',
        coalesce(_raw_fulfillment_status, ''), '|', coalesce(_raw_channel, ''), '|',
        cast(copy_number as string)
    ))) as order_line_key,
    order_id,
    order_date,
    account_name,
    sku,
    product_name,
    qty_ordered,
    qty_fulfilled,
    unit_price,
    fulfillment_status,
    sales_channel,
    copy_number > 1 as is_exact_duplicate
from numbered
