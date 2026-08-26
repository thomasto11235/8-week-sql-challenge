/*
The Foodie-Fi team wants you to create a new payments table for the year 2020 
that includes amounts paid by each customer in the subscriptions table 
with the following requirements:

- monthly payments always occur on the same day of month as the original start_date of 
  any monthly paid plan

- upgrades from basic to monthly or pro plans are reduced by the current paid amount 
  in that month and start immediately

- upgrades from pro monthly to pro annual are paid at the end of the current billing period
  and also starts at the end of the month period

- once a customer churns they will no longer make payments
*/

-- Select all customers of all plans except trial in 2020

WITH   CTE_CustsExceptTrial
AS     (SELECT S.CustomerID
             , S.PlanID
             , P.PlanName
             , S.StartDate
             , P.Price
        FROM   Subscriptions AS S
               INNER JOIN Plans AS P
                   ON S.PlanID = P.PlanID
        WHERE  P.PlanName <> 'trial'
               AND S.StartDate >= '20200101'
               AND S.StartDate < '20210101')
,      CTE_BillingDuration
AS     (SELECT CustomerID
             , PlanID
             , PlanName
             , StartDate
             , LEAD(StartDate, 1) OVER (PARTITION BY CustomerID ORDER BY StartDate ASC) AS NextStartDate
             , LEAD(PlanName, 1) OVER (PARTITION BY CustomerID ORDER BY StartDate ASC) AS NextPlanName
             , COALESCE (DATEDIFF(month, StartDate, LEAD(StartDate, 1) OVER (PARTITION BY CustomerID ORDER BY StartDate ASC)), 0) AS DateDifference
        FROM   CTE_CustsExceptTrial)
,      CTE_BillingDurationLogic
AS     (SELECT CustomerID
             , PlanID
             , PlanName
             , StartDate
             , NextPlanName
             , NextStartDate
             , CASE
               -- Case 1: Basic to any pro plans
               WHEN (PlanName LIKE '%basic%'
                     AND NextPlanName LIKE '%pro%')
                    AND 
                    -- If the date of upgrade is higher than the date of current
                    -- billing period then customers have to pay for the current
                    -- period first, then pay for the upgrade.
                    DAY(NextStartDate) > DAY(StartDate) THEN DateDifference + 1 WHEN (PlanName LIKE '%basic%'
                                                                                      AND NextPlanName LIKE '%pro%')
                                                                                     AND 
                                                                                     -- If the date of upgrade is smaller than the date of current
                                                                                     -- billing period then customers only have to pay for the upgrade
                                                                                     -- because the upgrade is active immediately in this case
                                                                                     DAY(NextStartDate) < DAY(StartDate) THEN DateDifference
               -- Case 2: Pro monthly to Pro Annual
               WHEN PlanName LIKE 'pro monthly'
                    AND NextPlanName LIKE '%pro annual%' THEN DateDifference
               -- Case 3: monthly plan and no next plan
               WHEN PlanName LIKE '%monthly%'
                    AND NextPlanName IS NULL THEN 12 - DATEPART(month, StartDate) + 1
               -- Case 4: Any plan and next plan as churn
               WHEN PlanName IS NOT NULL
                    AND NextPlanName = 'churn' THEN DateDifference + 1 ELSE
               -- Case 5: yearly plan and no next plan
               1 END AS DateDifferenceLogic
        FROM   CTE_BillingDuration
        WHERE  PlanName <> 'churn')
,      CTE_CustsPaymentBeta
AS     (SELECT B.CustomerID
             , B.PlanID
             , B.PlanName
             , LAG(B.PlanName, 1) OVER (PARTITION BY CustomerID ORDER BY f.Result ASC) AS PreviousPlanName
             , P.Price AS AmountBeta
             , f.Result AS PaymentDate
             , ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY StartDate) AS PaymentOrder
        FROM   CTE_BillingDurationLogic AS B CROSS APPLY dbo.MTVF_DateCalculation('month', DateDifferenceLogic, StartDate) AS f
               LEFT OUTER JOIN Plans AS P
                   ON P.PlanName = B.PlanName)
SELECT CustomerID
     , PlanID
     , PlanName
     , PaymentDate
     , CASE WHEN PlanName LIKE '%pro%'
                 AND PreviousPlanName LIKE '%basic%' THEN AmountBeta - LAG(AmountBeta, 1) OVER (PARTITION BY CustomerID ORDER BY PaymentDate) ELSE AmountBeta END AS Amount
     , PaymentOrder
FROM   CTE_CustsPaymentBeta;


GO
-- MTVF Function
CREATE OR ALTER FUNCTION MTVF_DateCalculation
(@DatePart NVARCHAR (50), @Number INT, @BaseDate DATE)
RETURNS 
    @Result TABLE (
        Result DATE)
AS
BEGIN
    WITH CTE_CurrentDate
    AS   (SELECT 1 AS n
               , @BaseDate AS CurrentDate
          UNION ALL
          SELECT n + 1
               , CAST (CASE LOWER(@DatePart) WHEN 'month' THEN DATEADD(month, 1, CurrentDate) WHEN 'mm' THEN DATEADD(month, 1, CurrentDate) WHEN 'm' THEN DATEADD(month, 1, CurrentDate) WHEN 'day' THEN DATEADD(day, 1, CurrentDate) WHEN 'dd' THEN DATEADD(day, 1, CurrentDate) WHEN 'd' THEN DATEADD(day, 1, CurrentDate) WHEN 'year' THEN DATEADD(year, 1, CurrentDate) WHEN 'yyyy' THEN DATEADD(year, 1, CurrentDate) ELSE DATEADD(day, 1, CurrentDate) END AS DATE)
          FROM   CTE_CurrentDate AS C
          WHERE  n + 1 <= @Number)
    INSERT INTO @Result (Result)
    SELECT CurrentDate
    FROM   CTE_CurrentDate
    OPTION (MAXRECURSION 0);
    
    RETURN;
END


GO
-- ITVF Function
CREATE OR ALTER FUNCTION ITVF_DateCalculation
(@DatePart NVARCHAR (50), @Number INT, @BaseDate DATE)
RETURNS TABLE 
AS
RETURN 
-- To safely replace MAXRECURSION 0,
-- Create a cascading CTE to generate rows without recursion
       -- 10 rows
WITH   E1
AS     (SELECT 1 AS N
        UNION ALL
        SELECT 1
        UNION ALL
        SELECT 1
        UNION ALL
        SELECT 1
        UNION ALL
        SELECT 1
        UNION ALL
        SELECT 1
        UNION ALL
        SELECT 1
        UNION ALL
        SELECT 1
        UNION ALL
        SELECT 1
        UNION ALL
        SELECT 1)
,      -- 100 rows
       E2
AS     (SELECT 1 AS N
        FROM   E1 AS A CROSS JOIN E1 AS B)
,      -- 10,000 rows
       E4
AS     (SELECT 1 AS N
        FROM   E2 AS A CROSS JOIN E2 AS B)
,      -- 100,000,000 rows 
       E8
AS     (SELECT 1 AS N
        FROM   E4 AS A CROSS JOIN E4 AS B)
,      -- Generate 0-based sequence up to @Number - 1
       Tally
AS     (SELECT TOP (COALESCE (@Number, 0)) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
        FROM   E8)
SELECT -- Calculate date
       CAST (CASE LOWER(@DatePart) WHEN 'month' THEN DATEADD(month, t.n, @BaseDate) WHEN 'mm' THEN DATEADD(month, t.n, @BaseDate) WHEN 'm' THEN DATEADD(month, t.n, @BaseDate) WHEN 'day' THEN DATEADD(day, t.n, @BaseDate) WHEN 'dd' THEN DATEADD(day, t.n, @BaseDate) WHEN 'd' THEN DATEADD(day, t.n, @BaseDate) WHEN 'year' THEN DATEADD(year, t.n, @BaseDate) WHEN 'yyyy' THEN DATEADD(year, t.n, @BaseDate) ELSE DATEADD(day, t.n, @BaseDate) END AS DATETIME2) AS Result
FROM   Tally AS t


GO
WITH   CTE_CustsExceptTrial
AS     (SELECT S.CustomerID
             , S.PlanID
             , P.PlanName
             , S.StartDate
             , P.Price
        FROM   Subscriptions AS S
               INNER JOIN Plans AS P
                   ON S.PlanID = P.PlanID
        WHERE  P.PlanName <> 'trial'
               AND S.StartDate >= '20200101'
               AND S.StartDate < '20210101')
,      CTE_BillingDuration
AS     (SELECT CustomerID
             , PlanID
             , PlanName
             , StartDate
             , LEAD(StartDate, 1) OVER (PARTITION BY CustomerID ORDER BY StartDate ASC) AS NextStartDate
             , LEAD(PlanName, 1) OVER (PARTITION BY CustomerID ORDER BY StartDate ASC) AS NextPlanName
             , COALESCE (DATEDIFF(month, StartDate, LEAD(StartDate, 1) OVER (PARTITION BY CustomerID ORDER BY StartDate ASC)), 0) AS DateDifference
        FROM   CTE_CustsExceptTrial)
,      CTE_BillingDurationLogic
AS     (SELECT CustomerID
             , PlanID
             , PlanName
             , StartDate
             , NextPlanName
             , NextStartDate
             , CASE 
               WHEN (PlanName LIKE '%basic%'
                     AND NextPlanName LIKE '%pro%')
                    AND DAY(NextStartDate) > DAY(StartDate) THEN DateDifference + 1 WHEN (PlanName LIKE '%basic%'
                                                                                      AND NextPlanName LIKE '%pro%')
                                                                                     AND DAY(NextStartDate) < DAY(StartDate) THEN DateDifference
               WHEN PlanName LIKE 'pro monthly'
                    AND NextPlanName LIKE '%pro annual%' THEN DateDifference
               WHEN PlanName LIKE '%monthly%'
                    AND NextPlanName IS NULL THEN 12 - DATEPART(month, StartDate) + 1
               WHEN PlanName IS NOT NULL
                    AND NextPlanName = 'churn' THEN DateDifference + 1 
                    ELSE 1 
               END AS DateDifferenceLogic
        FROM   CTE_BillingDuration
        WHERE  PlanName <> 'churn')
,      CTE_CustsPaymentBeta
AS     (SELECT B.CustomerID
             , B.PlanID
             , B.PlanName
             , LAG(B.PlanName, 1) OVER (PARTITION BY CustomerID ORDER BY f.Result ASC) AS PreviousPlanName
             , P.Price AS AmountBeta
             , f.Result AS PaymentDate
             , ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY StartDate) AS PaymentOrder
        FROM   CTE_BillingDurationLogic AS B CROSS APPLY dbo.ITVF_DateCalculation('month', DateDifferenceLogic, StartDate) AS f
               LEFT OUTER JOIN Plans AS P
                   ON P.PlanName = B.PlanName)
SELECT CustomerID
     , PlanID
     , PlanName
     , PaymentDate
     , CASE WHEN PlanName LIKE '%pro%'
                 AND PreviousPlanName LIKE '%basic%' THEN AmountBeta - LAG(AmountBeta, 1) OVER (PARTITION BY CustomerID ORDER BY PaymentDate) ELSE AmountBeta END AS Amount
     , PaymentOrder
FROM   CTE_CustsPaymentBeta;