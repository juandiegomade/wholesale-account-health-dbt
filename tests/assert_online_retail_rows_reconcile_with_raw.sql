-- Staging must keep every raw row except the 2009-2010 sheet's repeated last nine days.
-- Returns a row (= test failure) if any line was lost or added along the way.

with

sheet_2009_2010 as (

    select
        count(*) as total_rows,
        countif(
            safe.parse_datetime('%Y-%m-%d %H:%M:%S', invoice_date) >= datetime '2010-12-01 00:00:00'
        ) as overlap_rows
    from {{ source('online_retail', 'online_retail_ii_2009_2010') }}

),

sheet_2010_2011 as (

    select count(*) as total_rows
    from {{ source('online_retail', 'online_retail_ii_2010_2011') }}

),

staging as (

    select count(*) as total_rows
    from {{ ref('stg_online_retail__invoice_lines') }}

),

compared as (

    select
        staging.total_rows as staging_rows,
        sheet_2009_2010.total_rows + sheet_2010_2011.total_rows - sheet_2009_2010.overlap_rows as expected_rows
    from sheet_2009_2010
    cross join sheet_2010_2011
    cross join staging

)

select
    staging_rows,
    expected_rows
from compared
where staging_rows != expected_rows
