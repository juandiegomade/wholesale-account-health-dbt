-- One row per product per source, built from the lines that passed cleaning.

with

order_lines as (

    select * from {{ ref('int_order_lines__cleaned') }}
    where is_included

),

-- a product can carry several descriptions; keep the most common one
name_ranked as (

    select
        product_key,
        product_name,
        row_number() over (
            partition by product_key
            order by count(*) desc, product_name asc
        ) as name_rank
    from order_lines
    where product_name is not null
    group by product_key, product_name

),

main_name as (

    select
        product_key,
        product_name
    from name_ranked
    where name_rank = 1

),

products as (

    select
        product_key,
        source_system,
        sku,
        count(*) as line_count,
        sum(qty_fulfilled) as total_qty_fulfilled,
        sum(revenue) as total_revenue
    from order_lines
    group by product_key, source_system, sku

)

select
    products.product_key,
    products.source_system,
    products.sku,
    main_name.product_name,
    products.line_count,
    products.total_qty_fulfilled,
    products.total_revenue
from products
left join main_name
    on products.product_key = main_name.product_key
