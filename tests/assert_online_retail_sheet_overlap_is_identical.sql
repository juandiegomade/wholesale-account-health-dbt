-- The staging model drops the 2009-2010 sheet's rows from 2010-12-01 onward because the
-- 2010-2011 sheet repeats them. That is only safe while both copies hold the same rows.
-- Returns every row found in one sheet's overlap window but not in the other's.

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
        country
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
        country
    from {{ source('online_retail', 'online_retail_ii_2010_2011') }}
    where safe.parse_datetime('%Y-%m-%d %H:%M:%S', invoice_date) < datetime '2010-12-10 00:00:00'

),

only_in_2009_2010 as (

    select * from window_2009_2010
    except distinct
    select * from window_2010_2011

),

only_in_2010_2011 as (

    select * from window_2010_2011
    except distinct
    select * from window_2009_2010

)

select
    'only in 2009-2010 sheet' as issue,
    invoice,
    stock_code,
    description,
    quantity,
    invoice_date,
    price,
    customer_id,
    country
from only_in_2009_2010

union all

select
    'only in 2010-2011 sheet' as issue,
    invoice,
    stock_code,
    description,
    quantity,
    invoice_date,
    price,
    customer_id,
    country
from only_in_2010_2011
