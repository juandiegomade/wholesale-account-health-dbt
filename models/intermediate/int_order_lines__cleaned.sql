-- Applies the business rules to every order line. No row is deleted: each line gets an
-- exclusion_reason (null = kept), so the marts can count what was left out and why.
-- A line with several problems gets the first reason that applies, in the order below.

with

order_lines as (

    select * from {{ ref('int_order_lines__unioned') }}

),

classified as (

    select
        *,
        case
            when is_duplicate_line then 'duplicate_line'
            when order_date is null then 'unparseable_date'
            when account_id is null then 'missing_account'
            -- a late return would make a dormant account look recently active
            when is_cancellation or qty_ordered < 0 then 'return_or_cancellation'
            when is_bad_debt_adjustment then 'bad_debt_adjustment'
            -- postage, fees and manual adjustments are not product demand
            when is_non_merchandise then 'non_merchandise'
            when unit_price is null or unit_price <= 0 then 'no_price'
            when qty_ordered is null then 'missing_quantity'
        end as exclusion_reason,
        -- where the shipped quantity is missing, assume the order shipped in full
        -- (and keep a flag so the assumption can be counted)
        coalesce(qty_fulfilled, qty_ordered) as qty_fulfilled_assumed,
        has_fulfillment_tracking and qty_fulfilled is null as used_fulfillment_assumption
    from order_lines

),

final as (

    select
        order_line_key,
        source_system,
        to_hex(md5(concat(source_system, '|', account_id))) as account_key,
        to_hex(md5(concat(source_system, '|', sku))) as product_key,
        order_id,
        order_date,
        account_id,
        account_name,
        country,
        sku,
        product_name,
        qty_ordered,
        qty_fulfilled_assumed as qty_fulfilled,
        unit_price,
        fulfillment_status,
        has_fulfillment_tracking,
        used_fulfillment_assumption,
        qty_fulfilled_assumed * unit_price as revenue,
        -- only lines the source itself marks as short count as unfilled
        case
            when fulfillment_status in ('PARTIAL', 'UNFULFILLED')
                then greatest(qty_ordered - qty_fulfilled_assumed, 0) * unit_price
            else 0
        end as potential_unfilled_revenue,
        exclusion_reason,
        exclusion_reason is null as is_included
    from classified

)

select * from final
