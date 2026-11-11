-- Staging must not drop or add Sunbelt rows; filtering happens later.

with

raw_counts as (

    select count(*) as raw_rows
    from {{ source('sunbelt', 'sunbelt_order_lines') }}

),

staging_counts as (

    select count(*) as staging_rows
    from {{ ref('stg_sunbelt__order_lines') }}

)

select
    raw_counts.raw_rows,
    staging_counts.staging_rows
from raw_counts
cross join staging_counts
where raw_counts.raw_rows != staging_counts.staging_rows
