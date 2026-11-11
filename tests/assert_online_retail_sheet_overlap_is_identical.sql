-- The staging model drops the 2009-2010 sheet's rows from 2010-12-01 onward because the
-- 2010-2011 sheet repeats them. That is only safe if both copies hold exactly the same
-- rows, including how many times each row appears (the data has exact duplicates).
--
-- Method: stack both windows, count each complete record per sheet, and return every
-- record whose count differs. GROUP BY treats NULLs as equal, so the many rows with a
-- null customer_id compare correctly (a join on the eight columns would not).

with

window_2009_2010 as (

    select
        invoice,
        stock_code,
        description,
        quantity,
        invoice_date,
        price,
        customer_id,
        country,
        1 as in_2009_2010,
        0 as in_2010_2011
    from {{ source('online_retail', 'online_retail_ii_2009_2010') }}
    where safe.parse_datetime('%Y-%m-%d %H:%M:%S', invoice_date) >= datetime '2010-12-01 00:00:00'

),

window_2010_2011 as (

    select
        invoice,
        stock_code,
        description,
        quantity,
        invoice_date,
        price,
        customer_id,
        country,
        0 as in_2009_2010,
        1 as in_2010_2011
    from {{ source('online_retail', 'online_retail_ii_2010_2011') }}
    where safe.parse_datetime('%Y-%m-%d %H:%M:%S', invoice_date) < datetime '2010-12-10 00:00:00'

),

stacked as (

    select * from window_2009_2010
    union all
    select * from window_2010_2011

),

record_counts as (

    select
        invoice,
        stock_code,
        description,
        quantity,
        invoice_date,
        price,
        customer_id,
        country,
        sum(in_2009_2010) as copies_in_2009_2010,
        sum(in_2010_2011) as copies_in_2010_2011
    from stacked
    group by
        invoice,
        stock_code,
        description,
        quantity,
        invoice_date,
        price,
        customer_id,
        country

)

select
    invoice,
    stock_code,
    description,
    quantity,
    invoice_date,
    price,
    customer_id,
    country,
    copies_in_2009_2010,
    copies_in_2010_2011
from record_counts
where copies_in_2009_2010 != copies_in_2010_2011
