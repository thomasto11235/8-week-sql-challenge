-- 1. How many customers has Foodie-Fi ever had?

SELECT COUNT(DISTINCT CustomerID)
FROM   Subscriptions;

-- 2. What is the monthly distribution of trial plan start_date values 
-- for our dataset - use the start of the month as the group by value

SELECT   DATETRUNC(month, StartDate) AS TrialMonth
       , COUNT(*) AS MonthlyDistribution
FROM     (SELECT s.CustomerID
               , s.PlanID
               , p.PlanName
               , s.StartDate
          FROM   Subscriptions AS s
                 INNER JOIN Plans AS p
                     ON s.PlanID = p.PlanID
          WHERE  p.PlanName = 'trial') AS TrialPlan
GROUP BY DATETRUNC(month, StartDate);

-- 3.What plan start_date values occur after the year 2020 for our dataset? 
-- Show the breakdown by count of events for each plan_name

SELECT   p.PlanName
       , COUNT(*) AS EventCount
FROM     Subscriptions AS s
         INNER JOIN Plans AS p
             ON s.PlanID = p.PlanID
WHERE    DATEPART(year, s.StartDate) > 2020
GROUP BY p.PlanName;

-- 3.1 What plan start_date values still occurs after the year 2020 for our dataset?

SELECT   PlanName
       , COUNT(*) AS EventCount
FROM     (SELECT s.CustomerID
               , s.PlanID
               , s.StartDate
               , p.PlanName
               , CASE WHEN MAX(s.StartDate) OVER (PARTITION BY s.CustomerID) = s.StartDate
                           AND p.PlanName = 'churn' THEN DATEADD(day, 0, MAX(s.StartDate) OVER (PARTITION BY s.CustomerID)) WHEN MAX(s.StartDate) OVER (PARTITION BY s.CustomerID) = s.StartDate
                                                                                                                                 AND p.PlanName = 'trial' THEN DATEADD(day, 7, MAX(s.StartDate) OVER (PARTITION BY s.CustomerID)) WHEN MAX(s.StartDate) OVER (PARTITION BY s.CustomerID) = s.StartDate
                                                                                                                                                                                                                                       AND p.PlanName = 'basic monthly' THEN DATEADD(day, 30, MAX(s.StartDate) OVER (PARTITION BY s.CustomerID)) WHEN MAX(s.StartDate) OVER (PARTITION BY s.CustomerID) = s.StartDate
                                                                                                                                                                                                                                                                                                                                                      AND p.PlanName = 'pro monthly' THEN DATEADD(day, 30, MAX(s.StartDate) OVER (PARTITION BY s.CustomerID)) WHEN MAX(s.StartDate) OVER (PARTITION BY s.CustomerID) = s.StartDate
                                                                                                                                                                                                                                                                                                                                                                                                                                                                   AND p.PlanName = 'pro annual' THEN DATEADD(day, 365, MAX(s.StartDate) OVER (PARTITION BY s.CustomerID)) ELSE NULL END AS StartDateCheck
          FROM   Subscriptions AS s
                 INNER JOIN Plans AS p
                     ON s.PlanID = p.PlanID) AS sub
WHERE    DATEPART(year, StartDateCheck) > 2020
GROUP BY PlanName;

-- 4. What is the customer count and percentage of customers who have churned 
-- rounded to 1 decimal place?. Count of customers who have churned

SELECT COUNT(*) AS ChurnCount
FROM   Subscriptions AS s
       INNER JOIN Plans AS p
           ON s.PlanID = p.PlanID
WHERE  p.PlanName = 'churn';

WITH   CTE_CustomerStats
AS     (SELECT COUNT(DISTINCT CustomerID) AS TotalCustomers
             , COUNT(DISTINCT CASE WHEN PlanID = 4 THEN CustomerID END) AS ChurnedCustomers
        FROM   Subscriptions)
SELECT ChurnedCustomers
     , CONCAT(ROUND(CAST (ChurnedCustomers AS FLOAT) / TotalCustomers * 100, 1), '%') AS ChurnRate
FROM   CTE_CustomerStats;

-- 5. How many customers have churned straight after their initial free trial 
-- what percentage is this rounded to the nearest whole number?

WITH   CTE_CountEarlyChurn
AS     (SELECT COUNT(CASE WHEN LastStatus = 4
                               AND PreviousStatus = 0 THEN CustomerID END) AS EarlyChurn
        FROM   (SELECT CustomerID
                     , PlanID AS LastStatus
                     , LAG(PlanID) OVER (PARTITION BY CustomerID ORDER BY StartDate) AS PreviousStatus
                FROM   Subscriptions) AS sub)
SELECT EarlyChurn
     , CONCAT(ROUND(CAST (EarlyChurn AS FLOAT) / (SELECT COUNT(DISTINCT CustomerID)
                                                  FROM   Subscriptions) * 100, 0), '%') AS PctEarlyChurn
FROM   CTE_CountEarlyChurn;

-- 6. What is the number and percentage of customer plans after their initial free trial?

WITH     CTE_DateAfterTrial
AS       (-- For each customer, select the earliest date after the intial trial where
          -- they sign up for a new plan
          SELECT CustomerID
               , PlanID
               , StartDate
               , (SELECT MIN(S.StartDate)
                  FROM   Subscriptions AS S
                  WHERE  S.CustomerID = Ft.CustomerID
                         AND S.StartDate > Ft.StartDate) AS DateAfterTrial
          FROM   -- Select customers and their first initial trial 
                 (SELECT CustomerID
                       , PlanID
                       , StartDate
                  FROM   Subscriptions
                  WHERE  PlanID = 0) AS Ft)
SELECT   -- Join the earliest date after the intial trial of each customer with the table 
         --Subscriptions to see what their plan were after initial trial
         P.PlanName AS PlanAfterTrial
       , COUNT(T.CustomerID) AS CustomerCnt
       , CAST (COUNT(T.CustomerID) * 100. AS FLOAT) / (SELECT COUNT(DISTINCT S.CustomerID)
                                                       FROM   Subscriptions AS S) AS Pct
FROM     CTE_DateAfterTrial AS T
         INNER JOIN Subscriptions AS S
             ON T.DateAfterTrial = S.StartDate
                AND T.CustomerID = S.CustomerID
         INNER JOIN Plans AS P
             ON P.PlanID = S.PlanID
GROUP BY P.PlanName
ORDER BY COUNT(T.CustomerID) DESC;

-- 7. What is the customer count and percentage breakdown of all 5 plan_name values 
-- at 2020-12-31?

WITH     CTE_SubscriptionStatus
AS       (SELECT CustomerID
               , PlanID
               , StartDate
               , ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY StartDate DESC) AS Rn
          FROM   Subscriptions
          WHERE  StartDate <= '2020-12-31')
,        CTE_RecentStatus
AS       (SELECT CustomerID
               , PlanID
               , StartDate
               , Rn
          FROM   CTE_SubscriptionStatus
          WHERE  Rn = 1)
SELECT   P.PlanName
       , COUNT(RC.CustomerID) AS CustomerCnt
       , CONCAT(CAST (COUNT(RC.CustomerID) * 100. AS FLOAT) / (SELECT COUNT(DISTINCT S.CustomerID)
                                                               FROM   Subscriptions AS S), '%') AS Pct
FROM     Plans AS P
         LEFT OUTER JOIN CTE_RecentStatus AS RC
             ON P.PlanID = RC.PlanID
GROUP BY P.PlanName
ORDER BY COUNT(RC.CustomerID) DESC;

-- 8. How many customers have upgraded to an annual plan in 2020?
-- How many customers were currently active on annual plan at the end of 2020

WITH   CTE_SubscriptionStatus2020
AS     (SELECT CustomerID
             , PlanID
             , StartDate
             , ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY StartDate DESC) AS Rn
        FROM   Subscriptions
        WHERE  DATEPART(year, StartDate) = 2020)
SELECT COUNT(CustomerID) AS AnnualCustomerCnt
FROM   CTE_SubscriptionStatus2020
WHERE  Rn = 1
       AND PlanID = 3;

-- How many customers have upgraded to an annual plan in 2020?

SELECT COUNT(CustomerID) AS AnnualCustomerCnt
FROM   Subscriptions
WHERE  PlanID = 3;

-- 9. How many days on average does it take for a customer to an annual plan 
-- from the day they join Foodie-Fi?

WITH   CTE_JoinAnnualDiff
AS     (SELECT S1.CustomerID
             , S1.PlanID
             , DATEDIFF(day, S1.StartDate, (SELECT S2.StartDate
                                            FROM   Subscriptions AS S2
                                            WHERE  S1.CustomerID = S2.CustomerID
                                                   AND S2.PlanID = 3)) AS Diff
        FROM   Subscriptions AS S1
        WHERE  S1.PlanID = 0)
SELECT CAST (ROUND(AVG(Diff * 1.0), 1) AS DECIMAL (10, 1)) AS JoinAnnualAvg
FROM   CTE_JoinAnnualDiff;

-- 10. Can you further breakdown this average value into 30 day periods 
-- (i.e. 0-30 days, 31-60 days etc)

WITH     CTE_JoinAnnualDiff
AS       (SELECT S1.CustomerID
               , S1.PlanID
               , DATEDIFF(day, S1.StartDate, (SELECT S2.StartDate
                                              FROM   Subscriptions AS S2
                                              WHERE  S1.CustomerID = S2.CustomerID
                                                     AND S2.PlanID = 3)) AS Diff
          FROM   Subscriptions AS S1
          WHERE  S1.PlanID = 0)
SELECT   COUNT(CustomerID) AS CustomerCnt
       , -- By dividing the difference of each customer by 30 and then multiply with 30 
         -- again, we will get the nearest multiple of 30. Taking that nearest multiple 
         -- of 30 and plus 30 we can get the lower bound of the interval 
         -- which the corresponding difference lies in.
         CAST ((Diff / 30) * 30 AS VARCHAR) + ' - ' + CAST (((Diff / 30) * 30) + 30 AS VARCHAR) AS Interval
FROM     CTE_JoinAnnualDiff
WHERE    Diff IS NOT NULL
GROUP BY CAST ((Diff / 30) * 30 AS VARCHAR) + ' - ' + CAST (((Diff / 30) * 30) + 30 AS VARCHAR);

-- Disclaimer: If a customer has a diff of 60 then he will not in the range of (30 - 60)
-- but instead in (60 - 90) i.e  60 <= x < 90

-- 10. How many customers downgraded from a pro monthly to a basic monthly plan in 2020?
-- First idea:

WITH   CTE_Monthly2020
AS     (SELECT CustomerID
             , StartDate
             , PlanID
        FROM   Subscriptions
        WHERE  StartDate >= '20200101'
               AND StartDate < '20210101'
               AND PlanID = 2)
SELECT COUNT(CustomerID) AS DowngradeCount
FROM   CTE_Monthly2020 AS M
WHERE  EXISTS (SELECT *
               FROM   Subscriptions AS S
               WHERE  M.CustomerID = S.CustomerID
                      AND S.PlanID = 1);

-- This query outputs result as intended; howwver, there are still flaws in the logic
-- First, the query accounts for both upgrades and downgrades from a pro monthly plan
-- For example, customer A on a basic monthly plan in March, 2020 and he/she upgraded 
-- to a pro monthly plan in April 2022 and since we didn't mention basic monthly plan
-- must happen directly after a pro monthly plan, the query count upgrade as "downgrade"
-- But if we were to add a condition that indicate the aforementioned case:

-- Second idea:

WITH   CTE_Monthly2020
AS     (SELECT CustomerID
             , StartDate
             , PlanID
        FROM   Subscriptions
        WHERE  StartDate >= '20200101'
               AND StartDate < '20210101'
               AND PlanID = 2)
SELECT COUNT(CustomerID) AS DowngradeCount
FROM   CTE_Monthly2020 AS M
WHERE  EXISTS (SELECT *
               FROM   Subscriptions AS S
               WHERE  M.CustomerID = S.CustomerID
                      AND S.PlanID = 1
                      AND S.StartDate > M.StartDate);

-- (Continue) We still wouldn't have gotten the desired result because
-- the condition only filtered dates before the date of the outer row 
-- where they were on a pro monthly plan and the subquery did not care   
-- if in each of those dates, is directly before the current day. 
-- For example, Customer A registered a pro monthly plan in March, 2020,
-- then upgraded to an annual pro plan in April, then downgraded 
-- to a basic monthly plan in May, so in this case the subquery
-- should return nothing for the outer row because customer A wasnt
-- directly cancel their pro monthly plan to a basic montly plan.
-- So the ideal solution is to write another subquery to select
-- the row that are directly above the outer row with a pro monthly plan.

WITH   CTE_Monthly2020
AS     (-- All pro monthly plan
        SELECT CustomerID
             , StartDate
             , PlanID
        FROM   Subscriptions
        WHERE  PlanID = 2)
SELECT COUNT(CustomerID) AS DowngradeCount
FROM   CTE_Monthly2020 AS M
WHERE  -- First correlated subquery runs first to get 
       -- rows in 2020 that associated with basic montly plan
       -- that were started after the pro monthly plan of
       -- the same customer.
EXISTS (SELECT *
        FROM   Subscriptions AS S1
        WHERE  M.CustomerID = S1.CustomerID
               AND S1.PlanID = 1
               AND S1.StartDate > M.StartDate
               AND YEAR(S1.StartDate) = 2020
               AND NOT 
               -- Second subquery runs later to get rows in the middle
               -- of the outer row (rows from the first correlated subquery)
               -- and the outer row of the main query to see if a customer
               -- did directly downgrade their plan form pro monthly to basic monthly.
               EXISTS (SELECT *
                       FROM   Subscriptions AS S2
                       WHERE  S2.CustomerID = M.CustomerID
                              AND S2.StartDate > M.StartDate
                              AND S2.StartDate < S1.StartDate));