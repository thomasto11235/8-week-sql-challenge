-- Insert data from the view into a temp table

SELECT *
INTO   #DailyBalance
FROM   VI_DailyRunningBalance
OPTION (MAXRECURSION 0);

-- No compounding interest

WITH     CTE_DailyInterest
AS       (SELECT customer_id
               , Dte
               , NetChange
               , ClosingBalance
               , -- Since we are calculating rates and percentages, the result should 
                 -- be in float rather than decimal because sometimes rates 
                 -- and percentages cannot be presented as a whole under decimal data type, 
                 -- by using float we accept a tiny rounding error, so we can represent 
                 -- it more accurately.
                 CAST (6 AS FLOAT) / 100 / 365 AS DailyInterestRate
               , CASE WHEN ClosingBalance < 0 THEN 0 ELSE ClosingBalance END * CAST (6 AS FLOAT) / 100 / 365 AS DailyInterest
          FROM   #DailyBalance)
,        CTE_BonusStorage
AS       (SELECT   customer_id
                 , DATEFROMPARTS(YEAR(Dte), MONTH(Dte), 1) AS Mth
                 , AVG(ClosingBalance) AS AvgRealTimeBalance
                 , SUM(DailyInterest) AS TotalBonusStorage
          FROM     CTE_DailyInterest
          -- Use DATEFROMPARTS to differentiate the same month but of different years
          -- , without DATEFROMPARTS, month 1 of year 1 will be aggregated together
          -- with month 1 of year 2 and so on.
          GROUP BY DATEFROMPARTS(YEAR(Dte), MONTH(Dte), 1), customer_id)
SELECT   Mth
       , COUNT(DISTINCT customer_id) AS ActiveCustomers
       , CAST (SUM(CASE WHEN AvgRealTimeBalance < 0 THEN 0 ELSE AvgRealTimeBalance END) AS DECIMAL (10, 2)) AS StandardStorageEarned
       , CAST (SUM(TotalBonusStorage) AS DECIMAL (10, 2)) AS MonthlyBonusStorage
       , CAST (((SUM(CASE WHEN AvgRealTimeBalance < 0 THEN 0 ELSE AvgRealTimeBalance END) + SUM(TotalBonusStorage))) AS DECIMAL (10, 2)) AS TotalDataOpt4
FROM     CTE_BonusStorage
GROUP BY Mth
ORDER BY Mth;

-- Compounding interest
-- The idea is to use a recursive CTE to get the previous date
-- compounding interest then multiply that by a fixed daily interest rate
-- First we write a CTE to find each customer's starting transaction date:
-- You can remove this first step CTE and use DATEFROMPARTS (Year, Month, 1)
-- on the #DailyRunning Balance at once and remove 1 CTE step.

WITH     CTE_StartDateCustomers
AS       (SELECT   customer_id
                 , MIN(Dte) AS TransactionStartDate
          FROM     #DailyBalance
          GROUP BY customer_id)
, -- Then we write a CTE to combine the previous CTE with customer
-- running balance so we can get a customer starting transaction date
-- and their closing balance, net change on that day also. And these
-- rows will serve as anchor rows in the recursive CTE
         CTE_DailyBalanceStartDate
AS       (SELECT DB.customer_id
               , DB.Dte AS TransactionDate
               , SDC.TransactionStartDate
               , DB.NetChange
               , DB.ClosingBalance
               , -- Add a fixed daily interest rate, since the annual rate is 6%
                 -- therefore the daily rate is 6% / 365
                 CAST (6 AS FLOAT) / 100 / 365 AS DailyInterestRate
          FROM   CTE_StartDateCustomers AS SDC
                 INNER JOIN #DailyBalance AS DB
                     ON SDC.customer_id = DB.customer_id)
, -- Create the recursive CTE to calculate compound interest.
-- The logic is like this: The anchor rows are the rows represent
-- each customer transaction details on their first day of transaction
-- then these rows are joined again to the daily running balance table
-- to get the next transaction date as the recursive member on the condition
-- that anchor rows must be equal to the rows of the daily running balance table
-- but less than one day and that's it for one iteration (base iteration)
-------------------------------------------------------------------------------
-- In the base iteration:
-- The anchor row is run once only, so in the anchor
-- part of the recursive CTE, we calculate both the compound balance and 
-- the daily interest for the starting transaction date of each customers
-- For the daily interest of the anchor row, just calculate like a simple interest:
-- If the balance is > 0, then balance multiplied by the daily interest rate,
-- else the daily interest = 0
-- For the Compound balance, we take daily interest + balance
-- but if we pay attention closely, we see that:
-- daily interest = balance multiplied by the daily interest rate
--, therefore, coumpound interest = balance + (balance * interest rate)
-- which can also be written as balance * (1 + interest rate)
-------------------------------------------------------------------------------
-- Then the recursive part run to invoke the next transaction date which
-- is the anchor row date plus 1 day. After that, we also calculate
-- the compound balance and daily interest for this row but with
-- a different logic. For the daily interest, here are 2 cases:
-- First, if the closing balance of this row is > 0 then we calculate
-- by adding the anchor row's compounding balance + this row's netchange
-- then multiply by the daily interest rate but if the closing balance is < 0
-- then the daily interest = 0. Most importantly, this row's closing balance
-- is equal to the anchor row's compounding balance + this row's netchange.
-- Therefore, this row compounding balance equals to:
-- (the anchor row's compounding balance + this row's netchange) x (1 + Rate)
-- Now this row will be appended to the recursive CTE besides the anchor row
-- and now called the first recursive member.
-------------------------------------------------------------------------------
-- For the remaning iterations:
-- By the next iteration, the anchor row of before will have shifted into the
-- first recursive member and ONLY the recursive part of the CTE runs not the 
-- anchor part because it is only fired once to get the base row. With the
-- recursive part being the only part that runs meaning all the calculations
-- are now being computed according to what was written in that part only.
-------------------------------------------------------------------------------
-- In a nutshell,
-- The goal is to create a CTE that for each iteration it can grab a pair of
-- yesterday's row (anchor row/ nth recursive member) and today's row 
-- (1st recursive member/ nth + 1 recursive member). Based on that we
-- can find the daily compounding interest of each row by taking the previous
-- row compounding balance plus this row net change to get this row actual
-- closing balance (with compounding interest) then multiply with a fixed rate
-- provided that the closing balance of this row is positive.
         CTE_CompoundInterest
AS       (SELECT customer_id
               , TransactionDate
               , ClosingBalance
               , CASE WHEN ClosingBalance > 0 THEN ClosingBalance * (1 + CAST (6 AS FLOAT) / 100 / 365) ELSE 0 END AS CompoundBalance
               , CASE WHEN ClosingBalance > 0 THEN ClosingBalance * DailyInterestRate ELSE 0 END AS DailyInterest
          FROM   CTE_DailyBalanceStartDate
          WHERE  TransactionDate = TransactionStartDate
          UNION ALL
          SELECT DBC.customer_id
               , DBC.TransactionDate
               , DBC.ClosingBalance
               , CASE WHEN (DBC.NetChange + CI.CompoundBalance) > 0 THEN (DBC.NetChange + CI.CompoundBalance) * (1 + DailyInterestRate) ELSE 0 END
               , CASE WHEN (DBC.NetChange + CI.CompoundBalance) > 0 THEN (DBC.NetChange + CI.CompoundBalance) * DBC.DailyInterestRate ELSE 0 END
          FROM   CTE_CompoundInterest AS CI
                 INNER JOIN CTE_DailyBalanceStartDate AS DBC
                     ON CI.customer_id = DBC.customer_id
                        AND CI.TransactionDate = DATEADD(day, -1, DBC.TransactionDate))
SELECT   customer_id
       , TransactionDate
       , ClosingBalance
       , CompoundBalance
       , DailyInterest
FROM     CTE_CompoundInterest
ORDER BY customer_id, TransactionDate
OPTION (MAXRECURSION 0);

-- This is the first idea that implements the logic

WITH     CTE_StartDateCustomers
AS       (SELECT   customer_id
                 , MIN(Dte) AS TransactionStartDate
          FROM     #DailyBalance
          GROUP BY customer_id)
,        CTE_DailyBalanceStartDate
AS       (SELECT DB.customer_id
               , DB.Dte AS TransactionDate
               , SDC.TransactionStartDate
               , DB.NetChange
               , DB.ClosingBalance
               , CAST (6 AS FLOAT) / 100 / 365 AS DailyInterestRate
          FROM   CTE_StartDateCustomers AS SDC
                 INNER JOIN #DailyBalance AS DB
                     ON SDC.customer_id = DB.customer_id)
,        CTE_CompoundInterest
AS       (SELECT customer_id
               , TransactionDate
               , ClosingBalance
               , CASE WHEN ClosingBalance > 0 THEN ClosingBalance * DailyInterestRate ELSE 0 END AS DailyInterest
          FROM   CTE_DailyBalanceStartDate
          WHERE  TransactionDate = TransactionStartDate
          UNION ALL
          SELECT DBC.customer_id
               , DBC.TransactionDate
               , DBC.ClosingBalance
               , -- This is my first lgic but it is wrong and let me show you why:
                 -- If you familiar with how a recursive CTE works then looking
                 -- at this query you will see that for each recursive step it will
                 -- return a pair of row and one of which is today's row and the other
                 -- one is yesterday's row. Today's row is the current row where we want
                 -- to calculate compounding interest on by taking today's closing balance
                 -- which is equals to the sum of yesterday's compounding balance and
                 -- today's net change to account for the compound in interest
                 -- multiply by the daily interest rate. But this is not true for
                 -- the below conditions. If today's row is Jan-2 and the anchor row
                 -- (yesterday's) is Jan-1 then the calculation is correct because
                 -- the condition is able to calculate the compound balance of yesterday
                 --; however, when Jan-2 becomes the new recursive member and find Jan-3
                 -- as its output then the result is wrong, now Jan-2 is yesterday and Jan-3
                 -- is today, the condition still computes the compound balance for Jan-2
                 -- but it doesn't take into account the interest of the anchor row (Jan-1).
                 -- Moving forward to many days later you will see the interest 
                 -- will not grow at all.
                 CASE WHEN DBC.ClosingBalance > 0
                           AND CI.ClosingBalance > 0 THEN (CI.ClosingBalance + CI.DailyInterest) * DBC.DailyInterestRate ELSE 
                   -- WHEN DBC.ClosingBalance > 0 
                        -- AND CI.ClosingBalance < 0 THEN DBC.ClosingBalance * DBC.DailyInterestRate
                 0 END
          FROM   -- These conditions are partly wrong too, mainly because there isn't any
                 -- columns that calculate compound balance of a row, therefore relies
                 -- on fixed value of closing balance and creates inaccurate computations.
                 CTE_CompoundInterest AS CI
                 INNER JOIN CTE_DailyBalanceStartDate AS DBC
                     ON CI.customer_id = DBC.customer_id
                        AND CI.TransactionDate = DATEADD(day, -1, DBC.TransactionDate))
SELECT   customer_id
       , TransactionDate
       , ClosingBalance
       , DailyInterest
FROM     CTE_CompoundInterest
ORDER BY customer_id, TransactionDate
OPTION (MAXRECURSION 0);