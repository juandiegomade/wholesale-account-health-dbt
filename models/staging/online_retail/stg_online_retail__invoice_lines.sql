-- One row per invoice line from both sheets of the Online Retail II workbook.
-- Staging only renames, casts, trims and flags. Business rules (what counts as
-- revenue, which lines to exclude) live in the intermediate layer.

with

sheet_2009_2010 as (

    select
        *,
        '2009-2010' as source_sheet
    from {{ source('online_retail', 'online_retail_ii_2009_2010') }}

),

sheet_2010_2011 as (

    select
        *,
        '2010-2011' as source_sheet
    from {{ source('online_retail', 'online_retail_ii_2010_2011') }}

),

unioned as (

    select * from sheet_2009_2010
    union all
    select * from sheet_2010_2011

),

typed as (

    select
        source_sheet,
        trim(invoice) as invoice_number,
        upper(trim(stock_code)) as stock_code,
        nullif(trim(description), '') as product_description,
        safe_cast(quantity as int64) as quantity,
        safe.parse_datetime('%Y-%m-%d %H:%M:%S', invoice_date) as invoiced_at,
        safe_cast(price as numeric) as unit_price,
        nullif(trim(customer_id), '') as customer_id,
        nullif(trim(country), '') as country,

        -- raw values kept for the duplicate check below
        invoice as _raw_invoice,
        stock_code as _raw_stock_code,
        description as _raw_description,
        quantity as _raw_quantity,
        invoice_date as _raw_invoice_date,
        price as _raw_price,
        customer_id as _raw_customer_id,
        country as _raw_country
    from unioned

),

-- The 2009-2010 sheet repeats its last nine days (2010-12-01 to 2010-12-09) at the
-- start of the 2010-2011 sheet, row for row (22,523 identical rows). Keep each day
-- from exactly one sheet: the 2010-2011 sheet owns everything from 2010-12-01 on.
deduplicated_sheets as (

    select *
    from typed
    where not (
        source_sheet = '2009-2010'
        and invoiced_at >= datetime '2010-12-01 00:00:00'
    )

),

-- Some lines are exact copies of each other (same invoice, product, quantity, time,
-- price and customer). Number the copies so every line gets a unique key; the
-- intermediate layer decides what to do with them.
numbered as (

    select
        *,
        row_number() over (
            partition by
                source_sheet, _raw_invoice, _raw_stock_code, _raw_description, _raw_quantity,
                _raw_invoice_date, _raw_price, _raw_customer_id, _raw_country
        ) as copy_number
    from deduplicated_sheets

),

final as (

    select
        *,
        to_hex(md5(concat(
            source_sheet, '|',
            coalesce(_raw_invoice, ''), '|', coalesce(_raw_stock_code, ''), '|',
            coalesce(_raw_description, ''), '|', coalesce(_raw_quantity, ''), '|',
            coalesce(_raw_invoice_date, ''), '|', coalesce(_raw_price, ''), '|',
            coalesce(_raw_customer_id, ''), '|', coalesce(_raw_country, ''), '|',
            cast(copy_number as string)
        ))) as invoice_line_key
    from numbered

)

select
    invoice_line_key,
    source_sheet,
    invoice_number,
    stock_code,
    product_description,
    quantity,
    invoiced_at,
    date(invoiced_at) as invoice_date,
    unit_price,
    customer_id,
    country,
    starts_with(invoice_number, 'C') as is_cancellation,
    starts_with(invoice_number, 'A') as is_bad_debt_adjustment,
    (
        stock_code in unnest({{ var('non_merchandise_stock_codes') | tojson }})
        or regexp_contains(stock_code, r'^({{ var('non_merchandise_stock_code_prefixes') | join('|') }})')
    ) as is_non_merchandise,
    copy_number > 1 as is_exact_duplicate
from final
