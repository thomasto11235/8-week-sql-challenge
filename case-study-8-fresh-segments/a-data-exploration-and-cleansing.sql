SELECT [month]
     , [year]
     , month_year
FROM   freshsegments.InterestMetrics;

-- 1. Update the fresh_segments.interest_metrics table by 
-- modifying the month_year column to be a date data type 
-- with the start of the month
UPDATE  freshsegments.InterestMetrics
    SET month_year = CONVERT (DATE, CONCAT('01-', month_year), 105)
WHERE   month_year IS NOT NULL;

-- 2. What is count of records in the fresh_segments.interest_metrics 
-- for each month_year value sorted in chronological order (earliest to latest) 
-- with the null values appearing first?
SELECT   month_year
       , COUNT(*) AS NumberOfRecords
FROM     freshsegments.InterestMetrics
GROUP BY month_year
ORDER BY month_year;

-- 3. What do you think we should do with these null values 
-- in the fresh_segments.interest_metrics
SELECT *
FROM   freshsegments.InterestMetrics
WHERE  month_year IS NULL;

DELETE FROM freshsegments.InterestMetrics
WHERE month_year IS NULL AND interest_id IS NULL;

-- I think we should exclude them but if we want to exclude them, we have to
-- calculate the ranking as well as the percentile_ranking for each interest again
-- so there's a trade-off that must be made against keeping these with placeholder values
-- or exclude them then recalculate parameters.
-- 4. How many interest_id values exist in the fresh_segments.interest_metrics table
-- but not in the fresh_segments.interest_map table? 
-- What about the other way around?
-- How many interest_id values exist in the fresh_segments.interest_metrics table
-- but not in the fresh_segments.interest_map table? 
SELECT COUNT(DISTINCT IME.interest_id) AS NotInMap
FROM   freshsegments.InterestMetrics AS IME
WHERE  NOT EXISTS (SELECT *
                   FROM   freshsegments.InterestMap AS IMA
                   WHERE  IME.interest_id = IMA.id);

SELECT COUNT(DISTINCT IME.interest_id) AS NotInMap
FROM   freshsegments.InterestMap AS IMA
       RIGHT OUTER JOIN freshsegments.InterestMetrics AS IME
           ON IMA.id = IME.interest_id
WHERE  IME.interest_id IS NULL;

-- The other way around
SELECT COUNT(DISTINCT IMA.id) AS NotInMetric
FROM   freshsegments.InterestMap AS IMA
WHERE  NOT EXISTS (SELECT *
                   FROM   freshsegments.InterestMetrics AS IME
                   WHERE  IME.interest_id = IMA.id);

SELECT COUNT(DISTINCT IMA.id) AS NotInMetric
FROM   freshsegments.InterestMap AS IMA
       LEFT OUTER JOIN freshsegments.InterestMetrics AS IME
           ON IMA.id = IME.interest_id
WHERE  IME.interest_id IS NULL;

-- Another method

SELECT 
  COUNT(DISTINCT IME.interest_id),
  COUNT(DISTINCT IMA.id),
  SUM(CASE WHEN IME.interest_id IS NULL THEN 1 END) AS NotInMap,
  SUM(CASE WHEN IMA.id IS NULL THEN 1 END) AS NotInMetrics
FROM freshsegments.InterestMap AS IMA
  FULL OUTER JOIN freshsegments.InterestMetrics AS IME
    ON IMA.id = IME.interest_id



-- 5. Summarise the id values in the fresh_segments.interest_map 
-- by its total record count in this table
SELECT COUNT(*) AS TotalCount
FROM   freshsegments.InterestMap;

SELECT   IMA.id
       , IMA.interest_name
       , COUNT(*) AS RecordsPerInterest
FROM     freshsegments.InterestMap AS IMA
         INNER JOIN freshsegments.InterestMetrics AS IME
             ON IMA.id = IME.interest_id
GROUP BY IMA.id, IMA.interest_name
ORDER BY COUNT(*);

-- 6. What sort of table join should we perform for our analysis and why? 
-- Check your logic by checking the rows where interest_id = 21246 
-- in your joined output and include all columns 
-- from fresh_segments.interest_metrics and all columns from 
-- fresh_segments.interest_map except from the id column.
SELECT *
FROM   freshsegments.InterestMetrics AS a
       RIGHT OUTER JOIN freshsegments.InterestMap AS b
           ON a.interest_id = b.id
WHERE  interest_id = 21246;

-- Use inner join 
-- 7. Are there any records in your joined table where the month_year 
-- value is before the created_at value from the fresh_segments.interest_map 
-- table? Do you think these values are valid and why?
SELECT COUNT(*)
FROM   freshsegments.InterestMetrics AS IME
       INNER JOIN freshsegments.InterestMap AS IMA
           ON IME.interest_id = IMA.id
WHERE  IME.month_year < IMA.created_at;

SELECT COUNT(*)
FROM   freshsegments.InterestMetrics AS IME
       INNER JOIN freshsegments.InterestMap AS IMA
           ON IME.interest_id = IMA.id
WHERE  IME.month_year < DATETRUNC(month, IMA.created_at);


-- it is valid because each month_year is default to the first date of a month;
-- hence, each record in the metrics table represents a month aggregation data
-- of a specific interest and if we look closely, we will see that there is no
-- records has its MONTH(month_year) < MONTH(created_at). In other words, 
-- month_year is a representation of a specific month (instead of July, 
-- we see July 1st) so if the interest label is created on a later date, as long
-- as its month does not less than the earliest month represented in the metrics
-- table then it is valid, it's like you create a label in July 6, and you start
-- analysis by the end of July and label it by July 1st to represent the data
-- for July.