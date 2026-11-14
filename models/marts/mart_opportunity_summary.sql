-- The headline numbers, one row per source.
-- Revenue at risk = everything the now-dormant accounts bought in the period.
-- Potential unfilled revenue = ordered but not shipped; null where the source
-- does not track shipments (not measurable is not the same as zero).

with

recency as (

    select * from {{ ref('mart_account_recency') }}

),

order_lines as (

    select * from {{ ref('fct_order_lines') }}

),

account_totals as (

    select
        source_system,
        max(as_of_date) as as_of_date,
        count(*) as account_count,
        countif(account_status = 'Active') as active_account_count,
        countif(account_status = 'At Risk') as at_risk_account_count,
        countif(account_status = 'Dormant') as dormant_account_count,
        sum(total_revenue) as total_revenue,
        sum(if(account_status = 'At Risk', total_revenue, 0)) as revenue_in_at_risk_accounts,
        sum(if(account_status = 'Dormant', total_revenue, 0)) as revenue_at_risk_dormant
    from recency
    group by source_system

),

fulfillment_totals as (

    select
        source_system,
        logical_or(has_fulfillment_tracking) as has_fulfillment_tracking,
        sum(potential_unfilled_revenue) as potential_unfilled_revenue
    from order_lines
    group by source_system

)

select
    account_totals.source_system,
    account_totals.as_of_date,
    account_totals.account_count,
    account_totals.active_account_count,
    account_totals.at_risk_account_count,
    account_totals.dormant_account_count,
    account_totals.total_revenue,
    account_totals.revenue_in_at_risk_accounts,
    account_totals.revenue_at_risk_dormant,
    fulfillment_totals.has_fulfillment_tracking,
    if(
        fulfillment_totals.has_fulfillment_tracking,
        fulfillment_totals.potential_unfilled_revenue,
        null
    ) as potential_unfilled_revenue,
    account_totals.revenue_at_risk_dormant
    + if(fulfillment_totals.has_fulfillment_tracking, fulfillment_totals.potential_unfilled_revenue, 0)
        as total_revenue_opportunity
from account_totals
inner join fulfillment_totals
    on account_totals.source_system = fulfillment_totals.source_system
