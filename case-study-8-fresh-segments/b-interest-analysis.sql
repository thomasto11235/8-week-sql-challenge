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

-- Method 1: Top 10 and Bottom 10 interests globally
WITH   CTE_MaxComposition
AS     (SELECT   FI.interest_id
               , IM.interest_name
               , MAX(FI.composition) AS MaxComposition
        FROM     freshsegments.FilteredInterests AS FI
                 INNER JOIN freshsegments.InterestMap AS IM
                     ON FI.interest_id = IM.id
        GROUP BY FI.interest_id, IM.interest_name)
,      CTE_InterestCompositionRank
AS     (SELECT MC.interest_id
             , MC.interest_name
             , MC.MaxComposition
             , IM.month_year
        FROM   CTE_MaxComposition AS MC
               INNER JOIN freshsegments.InterestMetrics AS IM
                   ON MC.interest_id = IM.interest_id
                      AND MC.MaxComposition = IM.composition)
SELECT interest_name
     , MaxComposition
     , month_year
     , Category
FROM   ((SELECT   TOP 10 interest_name
                       , MaxComposition
                       , month_year
                       , 'Top 10' AS Category
         FROM     CTE_InterestCompositionRank AS ICR1
         ORDER BY ICR1.MaxComposition DESC)
        UNION ALL
        (SELECT   TOP 10 interest_name
                       , MaxComposition
                       , month_year
                       , 'Bottom 10' AS Category
         FROM     CTE_InterestCompositionRank
         ORDER BY MaxComposition ASC)) AS sub;

-- Method 2: Top 10 and Bottom 10 interest for each month_year

WITH       CTE_Top10Interests
AS       (SELECT month_year
               , interest_id
               , composition
               , ROW_NUMBER() OVER (PARTITION BY month_year ORDER BY composition DESC) AS BestInterestsRanking
          FROM   freshsegments.FilteredInterests)
,        CTE_Bottom10Interests
AS       (SELECT month_year
               , interest_id
               , composition
               , ROW_NUMBER() OVER (PARTITION BY month_year ORDER BY composition ASC) AS WorstInterestsRanking
          FROM   freshsegments.FilteredInterests)
SELECT   T10.month_year
       , IMA1.interest_name AS Top10Interest
       , T10.composition AS Top10Composition
       , IMA2.interest_name AS Bottom10Interest
       , B10.composition AS Bottom10Composition
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
ORDER BY T10.month_year,T10.composition DESC, B10.composition ASC;

-- 2. Which 5 interests had the lowest average ranking value?
-- (find the 5 interests that consistently in the top best performance)
SELECT   FI.interest_id
       , IMA.interest_name
       , ROUND(AVG(CAST (FI.ranking AS FLOAT)), 2) AS AvgRankingValue
FROM     freshsegments.FilteredInterests AS FI
  INNER JOIN freshsegments.InterestMap AS IMA
    ON FI.interest_id = IMA.id
GROUP BY FI.interest_id, IMA.interest_name
ORDER BY AVG(FI.ranking) ASC
OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY;

-- 3. Which 5 interests had the largest standard deviation 
-- in their percentile_ranking value?
-- Sample stdev = SUM of (each data point minus the mean of the sample)^2 
-- divided by the total data points in the sample minus 1

SELECT 
  FI.interest_id,
  IM.interest_name,
  MIN(percentile_ranking) AS MinPctRank,
  MAX(percentile_ranking) AS MaxPctRank,
  ROUND(STDEV(percentile_ranking), 2) AS StandardDeviation,
  COUNT(DISTINCT FI.month_year) AS MonthsPresent
FROM freshsegments. FilteredInterests AS FI
  INNER JOIN freshsegments. InterestMap AS IM
    ON FI.interest_id = IM.id
GROUP BY FI.interest_id, IM.interest_name
ORDER BY ROUND(STDEV(percentile_ranking), 2) DESC
OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY;

-- 4. For the 5 interests found in the previous question
-- what was minimum and maximum percentile_ranking values 
-- for each interest and its corresponding year_month?
-- Can you describe what is happening for these 5 interests?

WITH CTE_MinMax AS
(
SELECT 
  FI.interest_id,
  IM.interest_name,
  MIN(percentile_ranking) AS MinPctRank,
  MAX(percentile_ranking) AS MaxPctRank,
  ROUND(STDEV(percentile_ranking), 2) AS StandardDeviation,
  COUNT(DISTINCT FI.month_year) AS MonthsPresent
FROM freshsegments. FilteredInterests AS FI
  INNER JOIN freshsegments. InterestMap AS IM
    ON FI.interest_id = IM.id
GROUP BY FI.interest_id, IM.interest_name
ORDER BY ROUND(STDEV(percentile_ranking), 2) DESC
OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY
)

SELECT 
  MM.interest_id,
  MM.interest_name,
  MM.MinPctRank,
  IM2.month_year,
  MM.MaxPctRank,
  IM1.month_year
FROM CTE_MinMax AS MM
  INNER JOIN freshsegments.InterestMetrics AS IM1
    ON MM.interest_id = IM1.interest_id
      AND MM.MaxPctRank = IM1.percentile_ranking
  INNER JOIN freshsegments.InterestMetrics AS IM2
    ON MM.interest_id = IM2.interest_id
      AND MM.MinPctRank = IM2.percentile_ranking;

-- Techies: Experienced a steady 14-month decline, dropping from the 
-- 86.69th percentile in July 2018 to 7.92 by August 2019. 
-- This indicates a sustained loss of prominence as other segments grew.

-- Oregon Trip Planners: Showed clear seasonal volatility. 
-- The segment peaked during winter planning (November 2018 to February 2019) 
-- before hitting a low of 2.20 in July 2019.

-- Personalized Gift Shoppers: Demonstrated classic holiday seasonality. 
-- It peaked for Valentine's and Mother's Day (63–73% from February to April 2019) 
-- and crashed during the summer lull (under 10% in June and July).

-- 5. How would you describe our customers in this segment based off 
-- their composition and ranking values? What sort of products 
-- or services should we show to these customers and what should we avoid?
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

 /*
====================================================================
SEGMENT TRENDS
====================================================================
* Techies: Experienced a steady 14-month decline, dropping from the 
  86.69th percentile in July 2018 to 7.92 by August 2019. This 
  indicates a sustained loss of prominence as other segments grew.
  
* Oregon Trip Planners: Showed clear seasonal volatility. The 
  segment peaked during winter planning (November 2018 to February 
  2019) before hitting a low of 2.20 in July 2019.
  
* Personalized Gift Shoppers: Demonstrated classic holiday 
  seasonality. It peaked for Valentine's and Mother's Day (63–73% 
  from February to April 2019) and crashed during the summer lull 
  (under 10% in June and July).


====================================================================
AUDIENCE PROFILE & STRATEGY
====================================================================
This audience consists of busy, high-income professionals who are 
not budget-sensitive. Their top interests cluster around three core 
themes: luxury consumption, travel, and fitness. Key segments include 
"Work Comes First Travelers," luxury hotel and retail shoppers, and 
dedicated fitness enthusiasts. 

WHAT TO PROMOTE 
Focus your messaging on high-end products and experiences:
* Luxury Travel: Boutique hotels, business class flights, and 
  high-end resorts.
* Home & Lifestyle: Luxury bedding and premium furniture.
* Fitness & Wellness: Gym equipment, activity trackers, and health 
  supplements.
* Fashion & Beauty: High-end footwear and cosmetics.
* Premium Family Products: High-end kids' furniture and clothing 
  for affluent parents.

WHAT TO AVOID 
Skip mass-market and hyper-specific categories:
* Budget Items: Budget electronics and discount-focused messaging 
  will underperform with this luxury-driven group.
* Niche Entertainment: Gaming, specific sports fandoms, and niche 
  pop culture categories consistently rank at the bottom of their 
  interests.

KEY STRATEGIC SHIFT
Interest in tech and media (e.g., "Techies") declined sharply 
between July 2018 and August 2019. Marketing efforts should pivot 
away from tech-focused product placements and double down on the 
highly stable luxury, travel, and fitness categories.
*/