-- 1. How many unique nodes are there on the Data Bank system?

SELECT COUNT(DISTINCT node_id) AS UniqueNodes
FROM   customer_nodes;

-- 2. What is the number of nodes per region?

SELECT   R.region_name
       , COUNT(DISTINCT N.node_id) AS NumNodes
FROM     customer_nodes AS N
         LEFT OUTER JOIN regions AS R
             ON N.region_id = R.region_id
GROUP BY R.region_name;

-- 3. How many customers are allocated to each region?

SELECT   R.region_name
       , COUNT(DISTINCT customer_id) AS NumCusts
FROM     customer_nodes AS N
         LEFT OUTER JOIN regions AS R
             ON N.region_id = R.region_id
GROUP BY R.region_name;

-- 4. How many days on average are customers reallocated to a different node?

WITH   CTE_DurationNodeInstance
AS     (SELECT customer_id
             , region_id
             , node_id
             , start_date
             , end_date
             , DATEDIFF(day, start_date, end_date) AS Duration
        FROM   customer_nodes)
,      CTE_ContinousNodeCheck
AS     (SELECT customer_id
             , node_id
             , region_id
             , start_date
             , end_date
             , Duration
             , -- Too see if customer will stay at the current node in the next instance
               CASE WHEN LEAD(node_id, 1) OVER (PARTITION BY customer_id ORDER BY start_date ASC) = node_id
                         AND end_date = DATEADD(day, -1, LEAD(start_date, 1) OVER (PARTITION BY customer_id ORDER BY start_date ASC)) THEN 1 ELSE 0 END AS Marker
        FROM   CTE_DurationNodeInstance)
,      CTE_ContinousNodeElapsed
AS     (SELECT customer_id
             , node_id
             , region_id
             , start_date
             , end_date
             , Marker
             , Duration
               -- Marker to compensate for the elapsed time from continuous staying at a node.
             , CASE WHEN LEAD(end_date, 1) OVER (PARTITION BY customer_id ORDER BY end_date) < '9999-12-31'
                         AND LEAD(node_id, 1) OVER (PARTITION BY customer_id ORDER BY end_date) = node_id THEN Duration + Marker 
                    WHEN LEAD(end_date, 1) OVER (PARTITION BY customer_id ORDER BY end_date) <= '9999-12-31'
                         AND LEAD(node_id, 1) OVER (PARTITION BY customer_id ORDER BY end_date) <> node_id THEN Duration 
                    ELSE 0 
               END AS DaysInNode
        FROM   CTE_ContinousNodeCheck)
,      CTE_RemainRowsExclusion
AS     (SELECT customer_id
             , node_id
             , region_id
             , start_date
             , end_date
             , Duration
             , Marker
             , DaysInNode
             , (SELECT COUNT(*)
                FROM   CTE_ContinousNodeElapsed AS E2
                WHERE  E1.customer_id = E2.customer_id
                       AND E1.start_date < E2.start_date) AS NumRemainRows
             , (SELECT COUNT(*)
                FROM   CTE_ContinousNodeElapsed AS E2
                WHERE  E1.customer_id = E2.customer_id
                       AND E1.node_id = E2.node_id
                       AND E1.start_date < E2.start_date) AS NumInnerRemainRows
        FROM   CTE_ContinousNodeElapsed AS E1)
SELECT DISTINCT 
                customer_id
              , region_id
              , CONCAT(CAST (SUM(DaysInNode) OVER (PARTITION BY customer_id) * 1.0 / (COUNT(*) OVER (PARTITION BY customer_id) - SUM(Marker) OVER (PARTITION BY customer_id)) AS DECIMAL (10, 2)), '%') AS AvgReallocatedDays
FROM   CTE_RemainRowsExclusion
WHERE  NumRemainRows <> NumInnerRemainRows
       AND YEAR(end_date) <> 9999;


GO
CREATE OR ALTER VIEW VI_AvgReallocatedDays
AS
    WITH   CTE_DurationNodeInstance
    AS     (SELECT customer_id
                 , region_id
                 , node_id
                 , start_date
                 , end_date
                 , DATEDIFF(day, start_date, end_date) AS Duration
            FROM   customer_nodes)
    ,      CTE_ContinousNodeCheck
    AS     (SELECT customer_id
                 , node_id
                 , region_id
                 , start_date
                 , end_date
                 , Duration
                 , -- Too see if customer will stay at the current node in the next instance
                   CASE WHEN LEAD(node_id, 1) OVER (PARTITION BY customer_id ORDER BY start_date ASC) = node_id
                             AND end_date = DATEADD(day, -1, LEAD(start_date, 1) OVER (PARTITION BY customer_id ORDER BY start_date ASC)) THEN 1 
                        ELSE 0 
                   END AS Marker
            FROM   CTE_DurationNodeInstance)
    ,      CTE_ContinousNodeElapsed
    AS     (SELECT customer_id
                 , node_id
                 , region_id
                 , start_date
                 , end_date
                 , Marker
                 , Duration
                 , CASE WHEN LEAD(end_date, 1) OVER (PARTITION BY customer_id ORDER BY end_date) < '9999-12-31'
                             AND LEAD(node_id, 1) OVER (PARTITION BY customer_id ORDER BY end_date) = node_id THEN Duration + Marker 
                        WHEN LEAD(end_date, 1) OVER (PARTITION BY customer_id ORDER BY end_date) <= '9999-12-31'
                             AND LEAD(node_id, 1) OVER (PARTITION BY customer_id ORDER BY end_date) <> node_id THEN Duration 
                        ELSE 0 
                   END AS DaysInNode
            FROM   CTE_ContinousNodeCheck)
    ,      CTE_RemainRowsExclusion
    AS     (SELECT customer_id
                 , node_id
                 , region_id
                 , start_date
                 , end_date
                 , Duration
                 , Marker
                 , DaysInNode
                 , (SELECT COUNT(*)
                    FROM   CTE_ContinousNodeElapsed AS E2
                    WHERE  E1.customer_id = E2.customer_id
                           AND E1.start_date < E2.start_date) AS NumRemainRows
                 , (SELECT COUNT(*)
                    FROM   CTE_ContinousNodeElapsed AS E2
                    WHERE  E1.customer_id = E2.customer_id
                           AND E1.node_id = E2.node_id
                           AND E1.start_date < E2.start_date) AS NumInnerRemainRows
            FROM   CTE_ContinousNodeElapsed AS E1)
    SELECT DISTINCT customer_id
                  , region_id
                  , CAST (SUM(DaysInNode) OVER (PARTITION BY customer_id) * 1.0 / (COUNT(*) OVER (PARTITION BY customer_id) - SUM(Marker) OVER (PARTITION BY customer_id)) AS DECIMAL (10, 2)) AS AvgReallocatedDays
    FROM   CTE_RemainRowsExclusion
    WHERE  NumRemainRows <> NumInnerRemainRows
           AND YEAR(end_date) <> 9999;


GO
-- 5. What is the median, 80th and 95th percentile for this same reallocation days metric for each region?
SELECT DISTINCT R.region_name
              , PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY AvgReallocatedDays ASC) OVER (PARTITION BY A.region_id) AS FiftyPct
              , PERCENTILE_CONT(0.8) WITHIN GROUP (ORDER BY AvgReallocatedDays ASC) OVER (PARTITION BY A.region_id) AS EightyPct
              , PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY AvgReallocatedDays ASC) OVER (PARTITION BY A.region_id) AS NinetyFivePct
FROM   VI_AvgReallocatedDays AS A
       LEFT OUTER JOIN regions AS R
           ON A.region_id = R.region_id;