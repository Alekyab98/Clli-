WITH 
  null_agg AS (
    SELECT trans_dt, event_time, fqdn, vendor, MAX(TO_JSON_STRING(labels)) AS labels,
      SAFE_CAST(SUM(
        CASE
          WHEN metric_name = 'ggsn_nbr_of_subscribers' AND JSON_VALUE(labels, '$.group') = 'ggsn_global_stats' THEN CAST(metric_sum_value AS FLOAT64)
          ELSE NULL
        END) AS FLOAT64) AS total_subscribers
    FROM `vz-it-pr-gudv-dtwndo-0.aid_nwperf_aether_core_tbls_v.aether_smf_performance`
    WHERE trans_dt = '2024-12-20' 
    and fqdn ='alprgagqvzwcsmf-y-ec-conss-001'
    GROUP BY trans_dt, event_time, vendor, fqdn
  ),
  not_null_agg AS (
    SELECT trans_dt, event_time, fqdn, vendor, TO_JSON_STRING(labels) AS labels,
      SAFE_CAST(SUM(
        CASE
          WHEN metric_name = 'active_sessions' AND JSON_VALUE(labels, '$.group') = 'apn_pgw_upf_stats' THEN CAST(metric_sum_value AS FLOAT64)
          ELSE NULL
        END) AS FLOAT64) AS active_sessions
    FROM `vz-it-pr-gudv-dtwndo-0.aid_nwperf_aether_core_tbls_v.aether_smf_performance`
    WHERE trans_dt = '2024-12-20'
    and fqdn ='alprgagqvzwcsmf-y-ec-conss-001'
    GROUP BY trans_dt, event_time, vendor, fqdn, labels
  ),
  null_unnset AS (
    SELECT trans_dt, event_time, vendor, fqdn, metric.metric_name AS metric_name, SUM(metric.metric_value) AS value,
      SAFE_CAST(NULL AS STRING) AS key_group
    FROM null_agg,
      UNNEST([
        STRUCT('total_subscribers' AS metric_name, null_agg.total_subscribers AS metric_value)
      ]) AS metric
    GROUP BY trans_dt, event_time, vendor, fqdn, metric_name, key_group
  ),
  not_null_unnset AS (
    SELECT trans_dt, event_time, vendor, fqdn, metric.metric_name AS metric_name, SUM(metric.metric_value) AS value,
      metric.group_by_label AS key_group
    FROM not_null_agg,
      UNNEST([
        STRUCT('active_sessions' AS metric_name, not_null_agg.active_sessions AS metric_value,
          TO_JSON_STRING(STRUCT('apn' AS group_by_key_name, JSON_VALUE(labels, '$.apn') AS group_by_key_value)) AS group_by_label)
      ]) AS metric
    GROUP BY trans_dt, event_time, vendor, fqdn, metric_name, key_group
  ),
  fqdn_table AS (
    -- Fetch the mapping of Primary and Secondary FQDNs
    SELECT 
      primary_fqdn,
      secondary_fqdn,
     `Site Name`,
      region,
      longitude,
      latitude,
      Timezone
    FROM `vz-it-np-gudv-dev-dtwndo-0.aid_nwperf_aether_core_tbls.fqdn_table` f
  ),
  primary_fqdn_mapping AS (
    SELECT 
      smf.*,
      CASE
        -- If FQDN exists as a Primary FQDN, return it as is
        WHEN smf.fqdn IN (SELECT primary_fqdn FROM fqdn_table) THEN smf.fqdn
        
        -- If FQDN exists as a Secondary FQDN, fetch the corresponding Primary FQDN
        WHEN smf.fqdn IN (SELECT secondary_fqdn FROM fqdn_table) THEN (
          SELECT 
          primary_fqdn 
          FROM fqdn_table 
          WHERE secondary_fqdn = smf.fqdn
        )     
        ELSE NULL
      END AS primary_fqdn

    FROM (
      SELECT 
        trans_dt, 
        event_time, 
        vendor, 
        fqdn, 
        metric_name, 
        value, 
        key_group
      FROM null_unnset
      where value is not null
      UNION ALL
      SELECT 
        trans_dt, 
        event_time, 
        vendor, 
        fqdn, 
        metric_name, 
        value, 
        key_group
      FROM not_null_unnset
       where value is not null
    ) smf
  )
SELECT 
  trans_dt,
  event_time,
  vendor,
  fqdn,
  metric_name,
  value,
  key_group,
  primary_fqdn,
  -- `Site Name`,
  --     region,
  --     longitude,
  --     latitude,
  --     Timezone
FROM primary_fqdn_mapping
ORDER BY primary_fqdn;
