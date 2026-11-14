-- One row per account: how long since its last order, and which segment that puts it in.
-- "Today" is the latest order date in each source, not the calendar date, because
-- these are historical datasets.

with

accounts as (

    select * from {{ ref('dim_accounts') }}

),

as_of_dates as (

    select
        source_system,
        max(order_date) as as_of_date
    from {{ ref('fct_order_lines') }}
    group by source_system

),

recency as (

    select
        accounts.account_key,
        accounts.source_system,
        accounts.account_id,
        accounts.account_name,
        accounts.country,
        as_of_dates.as_of_date,
        accounts.first_order_date,
        accounts.last_order_date,
        date_diff(as_of_dates.as_of_date, accounts.last_order_date, day) as days_since_last_order,
        accounts.order_count,
        accounts.total_revenue
    from accounts
    inner join as_of_dates
        on accounts.source_system = as_of_dates.source_system

)

select
    account_key,
    source_system,
    account_id,
    account_name,
    country,
    as_of_date,
    first_order_date,
    last_order_date,
    days_since_last_order,
    case
        when days_since_last_order > {{ var('dormant_days') }} then 'Dormant'
        when days_since_last_order > {{ var('at_risk_days') }} then 'At Risk'
        else 'Active'
    end as account_status,
    order_count,
    total_revenue
from recency
