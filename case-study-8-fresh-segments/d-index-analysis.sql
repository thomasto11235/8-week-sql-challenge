-- 1. What is the top 10 interests by the average composition for each month?
WITH     CTE_AvgComposition
AS       (SELECT interest_id
               , month_year
               , composition
               , index_value
               , ROUND((composition / index_value), 2) AS AvgComposition
          FROM   freshsegments.InterestMetrics)
SELECT   DM.month_year
       , T10.interest_id
       , T10.AvgComposition
FROM     (SELECT DISTINCT month_year
          FROM   CTE_AvgComposition) AS DM CROSS APPLY (SELECT   TOP 10 interest_id
                                                                      , AvgComposition
                                                        FROM     CTE_AvgComposition AS AC
                                                        WHERE    DM.month_year = AC.month_year
                                                        ORDER BY AC.AvgComposition DESC) AS T10
ORDER BY DM.month_year ASC;

-- 2. For all of these top 10 interests - which interest appears the most often?
WITH     CTE_AvgComposition
AS       (SELECT interest_id
               , month_year
               , composition
               , index_value
               , ROUND((composition / index_value), 2) AS AvgComposition
          FROM   freshsegments.InterestMetrics)
,        CTE_Top10AvgComp
AS       (SELECT DM.month_year
               , T10.interest_id
               , T10.AvgComposition
          FROM   (SELECT DISTINCT month_year
                  FROM   CTE_AvgComposition) AS DM CROSS APPLY (SELECT   TOP 10 interest_id
                                                                              , AvgComposition
                                                                FROM     CTE_AvgComposition AS AC
                                                                WHERE    DM.month_year = AC.month_year
                                                                ORDER BY AC.AvgComposition DESC) AS T10)
SELECT   IM.interest_name
       , COUNT(*) AS Frequency
FROM     CTE_Top10AvgComp AS T10
         INNER JOIN freshsegments.InterestMap AS IM
             ON T10.interest_id = IM.id
GROUP BY IM.interest_name
ORDER BY COUNT(*) DESC
OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY;

-- 3. What is the average of the average composition for the top 10 
-- interests for each month?
WITH     CTE_AvgComposition
AS       (SELECT interest_id
               , month_year
               , composition
               , index_value
               , ROUND((composition / index_value), 2) AS AvgComposition
          FROM   freshsegments.InterestMetrics)
,        CTE_Top10AvgComp
AS       (SELECT DM.month_year
               , T10.interest_id
               , T10.AvgComposition
          FROM   (SELECT DISTINCT month_year
                  FROM   CTE_AvgComposition) AS DM CROSS APPLY (SELECT   TOP 10 interest_id
                                                                              , AvgComposition
                                                                FROM     CTE_AvgComposition AS AC
                                                                WHERE    DM.month_year = AC.month_year
                                                                ORDER BY AC.AvgComposition DESC) AS T10)
SELECT   month_year
       , AVG(AvgComposition) AS AvgOfAvg
FROM     CTE_Top10AvgComp
GROUP BY month_year;

-- 4. What is the 3 month rolling average of the max average composition value 
-- from September 2018 to August 2019 and include the previous top ranking 
-- interests in the same output shown below.
WITH     CTE_AvgCompositionRank
AS       (SELECT interest_id
               , month_year
               , composition
               , index_value
               , ROUND((composition / index_value), 2) AS AvgComposition
               , ROW_NUMBER() OVER (PARTITION BY month_year ORDER BY ROUND((composition / index_value), 2) DESC) AS RowNumber
          FROM   freshsegments.InterestMetrics)
,        CTE_CompMovingAvg
AS       (SELECT ACR.month_year
               , IMA.interest_name
               , ACR.AvgComposition AS MaxIndexComposition
               , ROUND(AVG(ACR.AvgComposition) OVER (ORDER BY ACR.month_year ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS ThreeMonthMovingAvg
               , CONCAT(LAG(IMA.interest_name, 1) OVER (ORDER BY ACR.month_year), ': ', LAG(ACR.AvgComposition, 1) OVER (ORDER BY ACR.month_year)) AS OneMonthAgo
               , CONCAT(LAG(IMA.interest_name, 2) OVER (ORDER BY ACR.month_year), ': ', LAG(ACR.AvgComposition, 2) OVER (ORDER BY ACR.month_year)) AS TwoMonthAgo
          FROM   CTE_AvgCompositionRank AS ACR
                 INNER JOIN freshsegments.InterestMap AS IMA
                     ON ACR.interest_id = IMA.id
          WHERE  ACR.RowNumber = 1
                 AND ACR.month_year IS NOT NULL)
SELECT   month_year
       , interest_name
       , MaxIndexComposition
       , ThreeMonthMovingAvg
       , OneMonthAgo
       , TwoMonthAgo
FROM     CTE_CompMovingAvg
WHERE    month_year >= '20180901'
ORDER BY month_year;


-- 5. Provide a possible reason why the max average composition might change 
-- from month to month? Could it signal something is not quite right with 
-- the overall business model for FrAesh Segments?
/*
====================================================================
COMPOSITION DECLINE ANALYSIS
====================================================================
The max average composition dropped ~70% (from 8.26 in September 
2018 to 2.73 in August 2019). This signals one of two scenarios:

1. Normal Dilution (Healthy): As the platform adds more segments 
   and tracks more customers, the composition ratio naturally 
   spreads thinner across a larger pool.

2. Signal Erosion (Problematic): The targeting quality is actively 
   weakening. Clients in mid-2019 are receiving segments roughly 
   3x less concentrated than in late 2018. The top interest 
   constantly rotating into hyper-niche categories (like "Honduran 
   Content Readers") reinforces this concern.

CONCLUSION
Total customer base size data over time is required to determine 
whether this decline represents healthy platform scaling or a 
failing core value proposition.
*/
