-- Форма 16-ВН (версия 2) – плоская таблица с колонками по возрастным группам
WITH
  sickleave_cases AS (
    SELECT
      sl.id AS sickleave_id,
      sl.people_id,
      sl.icd10_id,
      sl.sl_reason_id,
      sl.open_dt,
      sl.close_dt,
      sl.out_dt,
      p.birth,
      p.sex,
      (sl.close_dt - sl.open_dt + 1) AS days_count
    FROM
      mm.sickleave sl
      JOIN mm.people p ON p.id = sl.people_id
    WHERE
      sl.is_closed = 1
      AND sl.is_dubl = 0
      AND sl.id = sl.last_sickleave_id
      AND sl.close_dt BETWEEN {{start_date}} AND {{end_date}}
      AND (
        sl.sl_reason_id NOT IN (3, 8, 9)
        OR sl.sl_reason_id IS NULL
      )
  ),
  care_cases AS (
    SELECT
      srv.sickleave_id,
      sl.people_id,
      NULL::int AS icd10_id,
      srv.sl_reason_id,
      srv.beg_dt AS open_dt,
      srv.end_dt AS close_dt,
      sl.out_dt,
      p.birth,
      p.sex,
      (srv.end_dt - srv.beg_dt + 1) AS days_count
    FROM
      mm.sl_service srv
      JOIN mm.sickleave sl ON sl.id = srv.sickleave_id
      JOIN mm.people p ON p.id = sl.people_id
    WHERE
      srv.sl_reason_id = 9
      AND srv.beg_dt IS NOT NULL
      AND srv.end_dt IS NOT NULL
      AND srv.end_dt BETWEEN {{start_date}} AND {{end_date}}
      AND sl.is_closed = 1
      AND sl.is_dubl = 0
      AND sl.id = sl.last_sickleave_id
  ),
  closed_cases AS (
    SELECT
      *
    FROM
      sickleave_cases
    UNION ALL
    SELECT
      *
    FROM
      care_cases
  ),
  diagnosis_codes AS (
    SELECT
      id,
      kod
    FROM
      mm.icd10
  ),
  form_rows AS (
    SELECT
      rown_id,
      name,
      sex,
      fn_type,
      array_str
    FROM
      mm.sl_f16_name
    WHERE
      ver = 2
      AND fn_type IN (1, 3)
  ),
  row_elements AS (
    SELECT DISTINCT
      rown_id,
      name,
      sex,
      fn_type,
      trim(unnest(string_to_array(array_str, ';'))) AS element
    FROM
      form_rows
    WHERE
      array_str IS NOT NULL
  ),
  matched AS (
    SELECT
      re.rown_id,
      re.name,
      re.sex AS row_sex,
      cc.sickleave_id,
      cc.sex AS patient_sex,
      CASE
        WHEN EXTRACT(
          YEAR
          FROM
            AGE (cc.out_dt, cc.birth)
        ) BETWEEN 0 AND 17  THEN 1
        WHEN EXTRACT(
          YEAR
          FROM
            AGE (cc.out_dt, cc.birth)
        ) BETWEEN 18 AND 29  THEN 2
        WHEN EXTRACT(
          YEAR
          FROM
            AGE (cc.out_dt, cc.birth)
        ) BETWEEN 30 AND 39  THEN 3
        WHEN EXTRACT(
          YEAR
          FROM
            AGE (cc.out_dt, cc.birth)
        ) BETWEEN 40 AND 49  THEN 4
        WHEN EXTRACT(
          YEAR
          FROM
            AGE (cc.out_dt, cc.birth)
        ) BETWEEN 50 AND 59  THEN 5
        ELSE 6
      END AS age_group,
      cc.days_count,
      cc.sl_reason_id,
      dc.kod AS diagnosis_kod
    FROM
      closed_cases cc
      LEFT JOIN diagnosis_codes dc ON dc.id = cc.icd10_id
      CROSS JOIN row_elements re
    WHERE
      (
        re.sex IS NULL
        OR re.sex = CASE
          WHEN cc.sex = 1 THEN 'м'
          ELSE 'ж'
        END
      )
      AND (
        (
          re.fn_type = 1
          AND dc.kod IS NOT NULL
          AND (
            (
              position('-' IN re.element) > 0
              AND dc.kod >= split_part(re.element, '-', 1)
              AND dc.kod <= split_part(re.element, '-', 2)
            )
            OR (
              position('-' IN re.element) = 0
              AND dc.kod LIKE re.element || '%'
            )
          )
        )
        OR (
          re.fn_type = 3
          AND cc.sl_reason_id = re.element::int
        )
      )
  ),
  aggregated AS (
    SELECT
      rown_id,
      name,
      patient_sex,
      age_group,
      COUNT(DISTINCT sickleave_id) AS cases_count,
      SUM(days_count) AS days_total
    FROM
      matched
    GROUP BY
      rown_id,
      name,
      patient_sex,
      age_group
  )
SELECT
  rown_id,
  name,
  CASE
    WHEN patient_sex = 1 THEN 'Мужчины'
    ELSE 'Женщины'
  END AS sex_label,
  SUM(
    CASE
      WHEN age_group = 1 THEN cases_count
      ELSE 0
    END
  ) AS cases_0_17,
  SUM(
    CASE
      WHEN age_group = 2 THEN cases_count
      ELSE 0
    END
  ) AS cases_18_29,
  SUM(
    CASE
      WHEN age_group = 3 THEN cases_count
      ELSE 0
    END
  ) AS cases_30_39,
  SUM(
    CASE
      WHEN age_group = 4 THEN cases_count
      ELSE 0
    END
  ) AS cases_40_49,
  SUM(
    CASE
      WHEN age_group = 5 THEN cases_count
      ELSE 0
    END
  ) AS cases_50_59,
  SUM(
    CASE
      WHEN age_group = 6 THEN cases_count
      ELSE 0
    END
  ) AS cases_60plus,
  SUM(
    CASE
      WHEN age_group = 1 THEN days_total
      ELSE 0
    END
  ) AS days_0_17,
  SUM(
    CASE
      WHEN age_group = 2 THEN days_total
      ELSE 0
    END
  ) AS days_18_29,
  SUM(
    CASE
      WHEN age_group = 3 THEN days_total
      ELSE 0
    END
  ) AS days_30_39,
  SUM(
    CASE
      WHEN age_group = 4 THEN days_total
      ELSE 0
    END
  ) AS days_40_49,
  SUM(
    CASE
      WHEN age_group = 5 THEN days_total
      ELSE 0
    END
  ) AS days_50_59,
  SUM(
    CASE
      WHEN age_group = 6 THEN days_total
      ELSE 0
    END
  ) AS days_60plus,
  SUM(cases_count) AS total_cases,
  SUM(days_total) AS total_days
FROM
  aggregated
GROUP BY
  rown_id,
  name,
  patient_sex
ORDER BY
  rown_id,
  patient_sex;