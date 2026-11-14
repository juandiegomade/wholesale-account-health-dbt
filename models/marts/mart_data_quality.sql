-- How many order lines each source has, how many were kept, and how many were
-- excluded for each reason. One row per source and line status.

with

cleaned as (

    select * from {{ ref('int_order_lines__cleaned') }}

),

by_status as (

    select
        source_system,
        coalesce(exclusion_reason, 'included') as line_status,
        count(*) as line_count,
        countif(used_fulfillment_assumption) as lines_using_fulfillment_assumption
    from cleaned
    group by source_system, line_status

)

select
    to_hex(md5(concat(source_system, '|', line_status))) as data_quality_key,
    source_system,
    line_status,
    line_status = 'included' as is_included,
    line_count,
    safe_divide(line_count, sum(line_count) over (partition by source_system)) as share_of_source_lines,
    lines_using_fulfillment_assumption
from by_status
