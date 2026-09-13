-- Read-only aggregate diagnostics: no user IDs, emails, tokens or secrets.
select provider,status,count(*) as rows
from public.offerwall_events group by provider,status order by provider,status;

select source_type,metadata->>'provider' as labelled_provider,count(*) as rows
from public.coin_adjustments where amount>0
group by source_type,metadata->>'provider' order by source_type;

select count(*) as cpx_labelled_positive_credits
from public.coin_adjustments where amount>0 and (
 lower(coalesce(source_id,'')) like 'cpx:%'
 or (source_type='offerwall_credit' and lower(coalesce(metadata->>'provider',''))
     in ('cpx','cpx-research','cpx_research'))
 or coalesce(reason,'') ~* '^CPX([[:space:]:_-]|$)');

select event_name,count(*) as rows from public.sq_product_events
where event_name='cpx_wall_open_requested' group by event_name;
