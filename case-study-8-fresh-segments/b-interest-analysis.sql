-- 1. Using our filtered dataset by removing the interests with less than 6 months 
-- worth of data, which are the top 10 and bottom 10 interests 
-- which have the largest composition values in any month_year? 
-- Only use the maximum composition value for each interest 
-- but you must keep the corresponding month_year
WITH   CTE_14MonthsInterest
AS     (SELECT   IMA.id
               , IMA.interest_name
               , COUNT(DISTINCT IME.month_year) AS TotalMonths
        FROM     freshsegments.InterestMetrics AS IME
                 INNER JOIN freshsegments.InterestMap AS IMA
                     ON IME.interest_id = IMA.id
        GROUP BY IMA.id, IMA.interest_name)
,      CTE_CummulativePercentage
AS     (SELECT   id
               , TotalMonths
               , COUNT(*) AS InterestCountByMonthBuckets
               , SUM(COUNT(*)) OVER () AS TotalInterestCount
               , ROUND(SUM(COUNT(*)) OVER (ORDER BY TotalMonths DESC) / CAST (SUM(COUNT(*)) OVER () AS FLOAT) * 100, 2) AS CummPct
        FROM     CTE_14MonthsInterest AS MI
        GROUP BY Id, TotalMonths)
SELECT IME.month_year
     , IME.interest_id
     , IME.composition
     , IME.index_value
     , IME.ranking
     , IME.percentile_ranking
INTO   freshsegments.FilteredInterests
FROM   CTE_CummulativePercentage AS CP
       INNER JOIN freshsegments.InterestMetrics AS IME
           ON CP.id = IME.interest_id
              AND CP.CummPct < 91;

WITH     CTE_MaxComposition
AS       (SELECT month_year
               , interest_id
               , composition
               , MAX(composition) OVER (PARTITION BY interest_id) AS MaxComposition
          FROM   freshsegments.FilteredInterests)
,        CTE_Top10Interests
AS       (SELECT month_year
               , interest_id
               , MaxComposition
               , ROW_NUMBER() OVER (PARTITION BY month_year ORDER BY MaxComposition DESC) AS BestInterestsRanking
          FROM   CTE_MaxComposition)
,        CTE_Bottom10Interests
AS       (SELECT month_year
               , interest_id
               , MaxComposition
               , ROW_NUMBER() OVER (PARTITION BY month_year ORDER BY MaxComposition ASC) AS WorstInterestsRanking
          FROM   CTE_MaxComposition)
SELECT   T10.month_year
       , IMA1.interest_name AS Top10Interest
       , T10.MaxComposition AS Top10Composition
       , IMA2.interest_name AS Bottom10Interest
       , B10.MaxComposition AS Bottom10Composition
FROM     CTE_Top10Interests AS T10
         INNER JOIN CTE_Bottom10Interests AS B10
             ON T10.BestInterestsRanking = B10.WorstInterestsRanking
                AND T10.month_year = B10.month_year
         INNER JOIN freshsegments.InterestMap AS IMA1
             ON T10.interest_id = IMA1.id
         INNER JOIN freshsegments.InterestMap AS IMA2
             ON B10.interest_id = IMA2.id
WHERE    T10.BestInterestsRanking <= 10
         AND B10.WorstInterestsRanking <= 10
ORDER BY T10.month_year;

-- 2. Which 5 interests had the lowest average ranking value?
-- (find the 5 interests that consistently in the top best performance)
SELECT   interest_id
       , AVG(ranking) AS AvgRankingValue
FROM     freshsegments.FilteredInterests
GROUP BY interest_id
ORDER BY AVG(ranking) ASC
OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY;

-- 3. Which 5 interests had the largest standard deviation 
-- in their percentile_ranking value?
-- Assume positive standard deviation values
-- First Method
WITH     CTE_PctDevByMonth
AS       (SELECT month_year
               , interest_id
               , percentile_ranking
               , AVG(percentile_ranking) OVER (PARTITION BY month_year) AS AvgPctRankByMonth
               , percentile_ranking - AVG(percentile_ranking) OVER (PARTITION BY month_year) AS PctDevByMonth
          FROM   freshsegments.FilteredInterests)
SELECT   interest_id
       , ROUND(SUM(PctDevByMonth), 2) AS TotalDeviation
FROM     CTE_PctDevByMonth
GROUP BY interest_id
ORDER BY SUM(PctDevByMonth) DESC
OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY;

-- Second Method (just rounding errors)
WITH     CTE_Test
AS       (SELECT month_year
               , interest_id
               , percentile_ranking
               , AVG(percentile_ranking) OVER () AS AvgPctile
               , percentile_ranking - AVG(percentile_ranking) OVER () AS StdDev
          FROM   freshsegments.FilteredInterests)
SELECT   interest_id
       , ROUND(SUM(StdDev), 2) AS TotalDeviation
FROM     CTE_Test
GROUP BY interest_id
ORDER BY SUM(StdDev) DESC
OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY;

-- 4. For the 5 interests found in the previous question
-- what was minimum and maximum percentile_ranking values 
-- for each interest and its corresponding year_month
WITH   CTE_PctDevByMonth
AS     (SELECT month_year
             , interest_id
             , percentile_ranking
             , AVG(percentile_ranking) OVER () AS AvgPctile
             , percentile_ranking - AVG(percentile_ranking) OVER () AS StdDev
        FROM   freshsegments.FilteredInterests)
,      CTE_Top5Dev
AS     (SELECT   interest_id
               , ROUND(SUM(StdDev), 2) AS TotalDeviation
        FROM     CTE_PctDevByMonth
        GROUP BY interest_id
        ORDER BY SUM(StdDev) DESC
        OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY)
,      CTE_MaxMinPctRank
AS     (SELECT FI.month_year
             , TD.interest_id
             , FI.percentile_ranking
             , MAX(FI.percentile_ranking) OVER (PARTITION BY TD.interest_id) AS MaxPctRank
             , MIN(FI.percentile_ranking) OVER (PARTITION BY TD.interest_id) AS MinPctRank
        FROM   CTE_Top5Dev AS TD
               INNER JOIN freshsegments.FilteredInterests AS FI
                   ON TD.interest_id = FI.interest_id)
SELECT MAP.month_year
     , MAP.MaxPctRank
     , IMA.interest_name
     , MIP.month_year
     , MIP.MinPctRank
FROM   (SELECT month_year
             , interest_id
             , percentile_ranking
             , MinPctRank
        FROM   CTE_MaxMinPctRank
        WHERE  percentile_ranking = MinPctRank) AS MIP
       INNER JOIN (SELECT month_year
                        , interest_id
                        , percentile_ranking
                        , MaxPctRank
                   FROM   CTE_MaxMinPctRank
                   WHERE  percentile_ranking = MaxPctRank) AS MAP
           ON MIP.interest_id = MAP.interest_id
       INNER JOIN freshsegments.InterestMap AS IMA
           ON MIP.interest_id = IMA.id;

-- 5 interests out of 5 gain huge attention from the customer base of the client
-- and all 3 represent fashion industry, especially about shoes, general clothing
-- athletic clothes and luxury retail insights.
-- 5. How would you describe our customers in this segment based off 
-- their composition and ranking values? What sort of products 
-- or services should we show to these customers and what should we avoid?
-- The client' customers in this particular segment, generally devoted their
-- attention span and interest towards contents that are about fashion and 
-- these interests' composition and index values are higher than the average number
-- of other clients, when comparing the same interests.
-- Services or interests should be avoided are religious contents as well as
-- contents related to pizza as well as vaping.
WITH   CTE_PctDevByMonth
AS     (SELECT month_year
             , interest_id
             , percentile_ranking
             , AVG(percentile_ranking) OVER () AS AvgPctile
             , percentile_ranking - AVG(percentile_ranking) OVER () AS StdDev
        FROM   freshsegments.FilteredInterests)
,      CTE_Top5Dev
AS     (SELECT   interest_id
               , ROUND(SUM(StdDev), 2) AS TotalDeviation
        FROM     CTE_PctDevByMonth
        GROUP BY interest_id
        ORDER BY SUM(StdDev) ASC
        OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY)
,      CTE_MaxMinPctRank
AS     (SELECT FI.month_year
             , TD.interest_id
             , FI.percentile_ranking
             , MAX(FI.percentile_ranking) OVER (PARTITION BY TD.interest_id) AS MaxPctRank
             , MIN(FI.percentile_ranking) OVER (PARTITION BY TD.interest_id) AS MinPctRank
        FROM   CTE_Top5Dev AS TD
               INNER JOIN freshsegments.FilteredInterests AS FI
                   ON TD.interest_id = FI.interest_id)
SELECT MAP.month_year
     , MAP.MaxPctRank
     , IMA.interest_name
     , MIP.month_year
     , MIP.MinPctRank
FROM   (SELECT month_year
             , interest_id
             , percentile_ranking
             , MinPctRank
        FROM   CTE_MaxMinPctRank
        WHERE  percentile_ranking = MinPctRank) AS MIP
       INNER JOIN (SELECT month_year
                        , interest_id
                        , percentile_ranking
                        , MaxPctRank
                   FROM   CTE_MaxMinPctRank
                   WHERE  percentile_ranking = MaxPctRank) AS MAP
           ON MIP.interest_id = MAP.interest_id
       INNER JOIN freshsegments.InterestMap AS IMA
           ON MIP.interest_id = IMA.id;