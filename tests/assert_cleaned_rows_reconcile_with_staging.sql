-- The cleaning model classifies rows; it must never drop or multiply them.
-- Returns a row for any source whose line count changed between staging and cleaned.

with

staging_counts as (

    select
        'online_retail' as source_system,
        count(*) as staging_rows
    from {{ ref('stg_online_retail__invoice_lines') }}

    union all

    select
        'sunbelt' as source_system,
        count(*) as staging_rows
    from {{ ref('stg_sunbelt__order_lines') }}

),

cleaned_counts as (

    select
        source_system,
        count(*) as cleaned_rows
    from {{ ref('int_order_lines__cleaned') }}
    group by source_system

)

select
    staging_counts.source_system,
    staging_counts.staging_rows,
    cleaned_counts.cleaned_rows
from staging_counts
left join cleaned_counts
    on staging_counts.source_system = cleaned_counts.source_system
where
    cleaned_counts.cleaned_rows is null
    or staging_counts.staging_rows != cleaned_counts.cleaned_rows
