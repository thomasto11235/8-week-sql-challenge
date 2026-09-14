-- 1. Which interests have been present in all month_year dates in our dataset?
SELECT   IMA.id
       , IMA.interest_name
       , COUNT(DISTINCT IME.month_year) AS TotalMonths
FROM     freshsegments.InterestMetrics AS IME
         INNER JOIN freshsegments.InterestMap AS IMA
             ON IME.interest_id = IMA.id
GROUP BY IMA.id, IMA.interest_name
HAVING   COUNT(DISTINCT IME.month_year) >= (SELECT COUNT(DISTINCT month_year)
                                            FROM   freshsegments.InterestMetrics)
ORDER BY COUNT(DISTINCT IME.month_year) DESC;

-- 2. Using this same total_months measure - calculate the cumulative percentage 
-- of all records starting at 14 months - which total_months value passes 
-- the 90% cumulative percentage value?
-- The question is basically asking about data coverage, especially, if we decide
-- to keep interests that appeared in at least N months, how much of the total
-- interest pool do we retain?. The goal is to find cutoff points that keeps 
-- 90% of interests while dropping the rarely appearing ones.
WITH     CTE_14MonthsInterest
AS       (SELECT   IMA.id
                 , IMA.interest_name
                 , COUNT(DISTINCT IME.month_year) AS TotalMonths
          FROM     freshsegments.InterestMetrics AS IME
                   INNER JOIN freshsegments.InterestMap AS IMA
                       ON IME.interest_id = IMA.id
          GROUP BY IMA.id, IMA.interest_name)
SELECT   TotalMonths
       , COUNT(*) AS InterestCountByMonthBuckets
       , SUM(COUNT(*)) OVER () AS TotalInterestCount
       , FORMAT(SUM(COUNT(*)) OVER (ORDER BY TotalMonths DESC) / CAST (SUM(COUNT(*)) OVER () AS FLOAT), 'P2')
FROM     CTE_14MonthsInterest AS MI
GROUP BY TotalMonths;

-- 3. If we were to remove all interest_id values which are lower 
-- than the total_months value we found in the previous question 
-- - how many total data points would we be removing?
WITH   CTE_14MonthsInterest
AS     (SELECT   IMA.id
               , IMA.interest_name
               , COUNT(DISTINCT IME.month_year) AS TotalMonths
        FROM     freshsegments.InterestMetrics AS IME
                 INNER JOIN freshsegments.InterestMap AS IMA
                     ON IME.interest_id = IMA.id
        GROUP BY IMA.id, IMA.interest_name)
,      CTE_InterestCummulativePct
AS     (SELECT   TotalMonths
               , COUNT(*) AS InterestCountByMonthBuckets
               , SUM(COUNT(*)) OVER () AS TotalInterestCount
               , ROUND(SUM(COUNT(*)) OVER (ORDER BY TotalMonths DESC) / CAST (SUM(COUNT(*)) OVER () AS FLOAT) * 100, 2) AS CummPct
        FROM     CTE_14MonthsInterest AS MI
        GROUP BY TotalMonths)
SELECT SUM(InterestCountByMonthBuckets) AS CountDataPointsRemoved
     , SUM(InterestCountByMonthBuckets * TotalMonths) AS RowsRemoved
FROM   CTE_InterestCummulativePct
WHERE  CummPct > 91;

-- 4. Does this decision make sense to remove these data points from 
-- a business perspective? Use an example where there are all 14 months 
-- present to a removed interest example for your arguments 
-- think about what it means to have less months present from a segment perspective.
-- From a business perspective, by discarding data of old interests we can save
-- up the money used for data storage; however, the discarded rows only occupied
-- 3.06% of total rows, so the money saved is minimal. So, in this case keep the
-- data points can be no harm and can help with better analysis.
-- On the other hand, from a segment perspective, keeping the data in full can
-- result in better analyses and understandings without too much abstractions
-- because removing rows can hinders analytical optionality. Low-frequency interests
-- maybe seasonal or event-driven rather than noise and some of them are genuinely 
-- valuable to interpret
-- After removing these interests - how many unique interests 
-- are there for each month?
WITH   CTE_14MonthsInterest
AS     (SELECT   IMA.id
               , IMA.interest_name
               , COUNT(DISTINCT IME.month_year) AS TotalMonths
        FROM     freshsegments.InterestMetrics AS IME
                 INNER JOIN freshsegments.InterestMap AS IMA
                     ON IME.interest_id = IMA.id
        GROUP BY IMA.id, IMA.interest_name)
,      CTE_InterestCummulativePct
AS     (SELECT   TotalMonths
               , COUNT(*) AS InterestCountByMonthBuckets
               , SUM(COUNT(*)) OVER () AS TotalInterestCount
               , ROUND(SUM(COUNT(*)) OVER (ORDER BY TotalMonths DESC) / CAST (SUM(COUNT(*)) OVER () AS FLOAT) * 100, 2) AS CummPct
        FROM     CTE_14MonthsInterest AS MI
        GROUP BY TotalMonths)
SELECT SUM(InterestCountByMonthBuckets) AS CountDataPointsRemoved
     , SUM(InterestCountByMonthBuckets * TotalMonths) AS RowsRemained
FROM   CTE_InterestCummulativePct
WHERE  CummPct <= 91;

-- Or can be represented as:
WITH     CTE_14MonthsInterest
AS       (SELECT   IMA.id
                 , IMA.interest_name
                 , COUNT(DISTINCT IME.month_year) AS TotalMonths
          FROM     freshsegments.InterestMetrics AS IME
                   INNER JOIN freshsegments.InterestMap AS IMA
                       ON IME.interest_id = IMA.id
          GROUP BY IMA.id, IMA.interest_name)
,        CTE_CummulativePercentage
AS       (SELECT   id
                 , TotalMonths
                 , COUNT(*) AS InterestCountByMonthBuckets
                 , SUM(COUNT(*)) OVER () AS TotalInterestCount
                 , ROUND(SUM(COUNT(*)) OVER (ORDER BY TotalMonths DESC) / CAST (SUM(COUNT(*)) OVER () AS FLOAT) * 100, 2) AS CummPct
          FROM     CTE_14MonthsInterest AS MI
          GROUP BY Id, TotalMonths)
SELECT   IME.month_year
       , COUNT(*) AS UniqueInterests
FROM     CTE_CummulativePercentage AS CP
         INNER JOIN freshsegments.InterestMetrics AS IME
             ON CP.id = IME.interest_id
WHERE    CP.CummPct < 91
GROUP BY month_year
ORDER BY month_year;