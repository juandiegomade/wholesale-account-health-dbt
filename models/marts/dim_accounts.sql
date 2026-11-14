-- One row per account per source, built from the lines that passed cleaning.

with

order_lines as (

    select * from {{ ref('int_order_lines__cleaned') }}
    where is_included

),

-- an account can show more than one country; keep the one with the most lines
country_ranked as (

    select
        account_key,
        country,
        row_number() over (
            partition by account_key
            order by count(*) desc, country asc
        ) as country_rank
    from order_lines
    where country is not null
    group by account_key, country

),

main_country as (

    select
        account_key,
        country
    from country_ranked
    where country_rank = 1

),

accounts as (

    select
        account_key,
        source_system,
        account_id,
        any_value(account_name) as account_name,
        min(order_date) as first_order_date,
        max(order_date) as last_order_date,
        count(distinct order_id) as order_count,
        sum(revenue) as total_revenue
    from order_lines
    group by account_key, source_system, account_id

)

select
    accounts.account_key,
    accounts.source_system,
    accounts.account_id,
    accounts.account_name,
    main_country.country,
    accounts.first_order_date,
    accounts.last_order_date,
    accounts.order_count,
    accounts.total_revenue
from accounts
left join main_country
    on accounts.account_key = main_country.account_key
