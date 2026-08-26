-- Req. 1: running customer balance column that includes the impact each transaction

GO
CREATE OR ALTER VIEW dbo.VI_DailyRunningBalance
AS
    WITH   CTE_GlobalBounds
    AS     (SELECT EOMONTH(MAX(txn_date)) AS GlobalMaxDate
            FROM   customer_transactions)
    ,      CTE_DateBounds
    AS     (SELECT   customer_id
                   , MIN(txn_date) AS MinDate
                   , GlobalMaxDate AS MaxDate
            FROM     customer_transactions AS T CROSS JOIN CTE_GlobalBounds AS G
            GROUP BY customer_id, GlobalMaxDate)
    ,      CTE_DateSeries
    AS     (SELECT customer_id
                 , MinDate AS Dte
            FROM   CTE_DateBounds
            UNION ALL
            SELECT DS.customer_id
                 , DATEADD(day, 1, DS.Dte)
            FROM   CTE_DateSeries AS DS
                   INNER JOIN CTE_DateBounds AS DB
                       ON DS.customer_id = DB.customer_id
            WHERE  DATEADD(day, 1, DS.Dte) <= DB.MaxDate)
    ,      CTE_DailyNet
    AS     (SELECT   customer_id
                   , txn_date AS Dte
                   , SUM(CASE WHEN txn_type = N'deposit' THEN CAST (txn_amount AS DECIMAL (18, 2)) ELSE -CAST (txn_amount AS DECIMAL (18, 2)) END) AS NetChange
            FROM     customer_transactions
            GROUP BY customer_id, txn_date)
    ,      CTE_Combined
    AS     (SELECT DS.customer_id
                 , DS.Dte
                 , COALESCE (DN.NetChange, 0) AS NetChange
            FROM   CTE_DateSeries AS DS
                   LEFT OUTER JOIN CTE_DailyNet AS DN
                       ON DS.customer_id = DN.customer_id
                          AND DS.Dte = DN.Dte)
    SELECT customer_id
         , Dte
         , NetChange
         , SUM(NetChange) OVER (PARTITION BY customer_id ORDER BY Dte ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS ClosingBalance
    FROM   CTE_Combined;

-- Req. 2: customer balance at the end of each month

GO
CREATE OR ALTER VIEW dbo.VI_RunningBalance
AS
    WITH   CTE_DateBounds
    AS     (SELECT CAST (MIN(txn_date) AS DATE) AS MinDate
                 , CAST (MAX(txn_date) AS DATE) AS MaxDate
            FROM   customer_transactions)
    ,      CTE_MonthSeries
    AS     (SELECT MinDate AS Mth
            FROM   CTE_DateBounds
            UNION ALL
            SELECT DATEADD(month, 1, MS.Mth)
            FROM   CTE_MonthSeries AS MS CROSS JOIN CTE_DateBounds AS DB
            WHERE  DATEADD(month, 1, MS.Mth) <= DB.MaxDate)
    ,      CTE_CustomerMonths
    AS     (SELECT C.customer_id
                 , EOMONTH(M.Mth) AS Mth
            FROM   (SELECT DISTINCT (customer_id)
                    FROM   customer_transactions) AS C CROSS JOIN CTE_MonthSeries AS M)
    ,      CTE_MonthlyNet
    AS     (SELECT   customer_id
                   , EOMONTH(txn_date) AS Mth
                   , SUM(CASE WHEN txn_type = N'deposit' THEN txn_amount * 1.0 ELSE txn_amount * -1.0 END) AS NetChange
            FROM     customer_transactions
            GROUP BY customer_id, EOMONTH(txn_date))
    ,      CTE_Combined
    AS     (SELECT M.customer_id
                 , M.mth
                 , COALESCE (N.NetChange, 0) AS NetChange
            FROM   CTE_CustomerMonths AS M
                   LEFT OUTER JOIN CTE_MonthlyNet AS N
                       ON M.customer_id = N.customer_id
                          AND M.Mth = N.Mth)
    ,      CTE_RunningBalance
    AS     (SELECT customer_id
                 , Mth
                 , NetChange
                 , SUM(NetChange) OVER (PARTITION BY customer_id ORDER BY Mth ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS ClosingBalance
            FROM   CTE_Combined)
    SELECT customer_id
         , Mth
         , NetChange
         , ClosingBalance
    FROM   CTE_RunningBalance;

-- Req. 3: minimum, average and maximum values of the running balance for each customer

GO
CREATE OR ALTER VIEW dbo.VI_MinMaxAvgBalance
AS
    SELECT   customer_id
           , MIN(ClosingBalance) AS MinBalance
           , MAX(ClosingBalance) AS MaxBalance
           , AVG(ClosingBalance) AS AvgBalance
    FROM     VI_DailyRunningBalance
    GROUP BY customer_id;

-- Option 1. Data is allocated based off the amount of money at 
-- the end of the previous month

GO
CREATE OR ALTER VIEW dbo.VI_Option1
AS
    WITH   CTE_MonthlyBalance
    AS     (SELECT   Mth
                   , COUNT(DISTINCT customer_id) AS CustsCnt
                   , SUM(CASE WHEN ClosingBalance < 0 THEN 0 ELSE ClosingBalance END) AS MonthlyBalance
            FROM     dbo.VI_RunningBalance
            GROUP BY Mth)
    SELECT LAG(Mth, 1) OVER (ORDER BY Mth) AS EndPrevMth
         , DATEPART(month, Mth) AS AllocationMonth
         , CustsCnt AS ActiveCustomers
         , LAG(MonthlyBalance, 1) OVER (ORDER BY Mth) AS TotalDataOpt1
    FROM   CTE_MonthlyBalance;

/* 
============================================================================
   DATA BANK - SECTION C - OPTION 2
   "Data is allocated on the average amount of money kept in the account 
    in the previous 30 days"
 
   HOW THIS POLICY WORKS OPERATIONALLY (plain-language explanation):
 
   Once a month, on a fixed check-in day, Data Bank looks back at each
   customer's account activity over the PAST 30 DAYS, averages it out to
   smooth away any single big deposit or withdrawal, and uses that average
   to set how much cloud storage the customer keeps until the NEXT check-in.
   Nothing changes for that customer in between check-ins, no matter what
   they do with their money in the meantime - the number is only looked at
   and re-applied once a month.
   
   Check-in here is the end of a month and can be more than just that (e.g.
   middle of a month, start of a month or even weekly or daily). 

   Let's take daily as an check-in interval as an example:

   #Day | Time | DataUnits | Desc
   Day1 | 24:00| 500 (30MA)| Customer is provided with 500 of units until the next check-in
   1<->2| .... | ......... | ...
   Day2 | 24:00| -200      | Customer is provided with 0 units until the next check-in

   Two things happen at each check-in:
     1. LOOK BACK - average the last 30 days of daily balances (this is 
        what smooths out noise/spikes from any one transaction)
     2. LOCK IN   - that average becomes the storage figure, held steady
        until the next check-in recalculates it
 
   Example using real data (customer 389, whose balance grew steadily):
 
       Check-in date   30-day avg balance   Storage implication
       -------------   ------------------   ----------------------------
       2020-01-31      $186.29              small allotment
       2020-02-29      $527.90              balance nearly tripled -> 
                                             allotment grows accordingly
       2020-03-31      $929.80              continued growth -> bigger 
                                             allotment again
       2020-04-30      $1,978.63            balance nearly doubled again 
                                             -> largest allotment yet
 
   This is deliberately slow to react, in contrast to Option 3 (which 
   updates continuously/instantly with the raw balance) and even slower
   than Option 1 in a different way if the check-in interval of Option 2
   is longer (Option 1 uses a single day's raw snapshot with no smoothing, 
   while Option 2 always smooths but can be checked at any cadence - 
   see ASSUMPTION 1 below for why we specifically check monthly in this exercise).
 
   ASSUMPTIONS DOCUMENTED HERE:
 
   1. TIMING (no shift): The trailing 30-day average measured as of a given
      month-end (e.g. 2020-01-31) is reported as THAT SAME month's data 
      requirement (i.e. January's figure), not shifted forward to apply to 
      the following month.
 
      This differs from Option 1, whose wording explicitly says "at the end 
      of the PREVIOUS month" - an unambiguous instruction to lag the value 
      by one month before applying it. Option 2's wording only says "in the 
      previous 30 days," with no second layer of "...and apply that number 
      to the following month." Since the 30-day window is already inherently
      backward-looking by construction, we treat the month-end snapshot as 
      already representing that month's own requirement.
 
      ALTERNATE INTERPRETATION (not used here, but arguably also defensible):
      shift every value forward by one month, on the reasoning that Data 
      Bank can't operationally act on a "trailing 30 days as of Jan 31" 
      figure until Feb 1 at the earliest - so it would apply to February,
      not January. If this interpretation is preferred instead, replace the
      final SELECT's GROUP BY column with:
          DATEADD(MONTH, 1, Dte)
      instead of just Dte. Doing so drops January (no prior 30-day history
      exists before the dataset begins) and adds a forward-looking "May" 
      row based on April's trailing average.
 
   2. FLOOR AT ZERO: A customer with a negative trailing average cannot be
      allocated negative storage. Each customer's contribution to the 
      monthly total is floored at 0 before summing, rather than letting 
      negative balances subtract from other customers' legitimate storage
      needs.

      SELECT 
          'A' AS Customers
          , '+1000' AS Balance
      UNION ALL
      SELECT
          'B',
          '+1500'
      UNION ALL
      SELECT 
          'C',
          '-2000';
 
   3. DAILY GRANULARITY: The running balance is built at daily granularity
      (one row per customer per calendar day, from their first transaction
      through the dataset's global end-of-month) so the 30-day window is a
      true rolling calendar-day average, not an approximation based on
      monthly buckets.
   ============================================================================ */

-- Choosing the check-in interval to be the end of each month we have:

GO
CREATE OR ALTER VIEW dbo.VI_Option2
AS
    WITH     CTE_GlobalBounds
    AS       (SELECT EOMONTH(MAX(txn_date)) AS GlobalMaxDate
              FROM   customer_transactions)
    ,        CTE_DateBounds
    AS       (SELECT   customer_id
                     , MIN(txn_date) AS MinDate
                     , GlobalMaxDate AS MaxDate
              FROM     customer_transactions AS T CROSS JOIN CTE_GlobalBounds AS G
              GROUP BY customer_id, GlobalMaxDate)
    ,        CTE_DateSeries
    AS       (SELECT customer_id
                   , MinDate AS Dte
              FROM   CTE_DateBounds
              UNION ALL
              SELECT DS.customer_id
                   , DATEADD(day, 1, DS.Dte)
              FROM   CTE_DateSeries AS DS
                     INNER JOIN CTE_DateBounds AS DB
                         ON DS.customer_id = DB.customer_id
              WHERE  DATEADD(day, 1, DS.Dte) <= DB.MaxDate)
    ,        CTE_DailyNet
    AS       (SELECT   customer_id
                     , txn_date AS Dte
                     , -- Aggregate to prevent cases where a customer have 
                       -- many transactions in a day which leads to duplication of days, 
                       -- therefore cannot compute MA accurately
                       SUM(CASE WHEN txn_type = N'deposit' THEN CAST (txn_amount AS DECIMAL (18, 2)) ELSE -CAST (txn_amount AS DECIMAL (18, 2)) END) AS NetChange
              FROM     customer_transactions
              GROUP BY customer_id, txn_date)
    ,        CTE_Combined
    AS       (SELECT DS.customer_id
                   , DS.Dte
                   , COALESCE (DN.NetChange, 0) AS NetChange
              FROM   CTE_DateSeries AS DS
                     LEFT OUTER JOIN CTE_DailyNet AS DN
                         ON DS.customer_id = DN.customer_id
                            AND DS.Dte = DN.Dte)
    ,        CTE_RunningBalance
    AS       (SELECT customer_id
                   , Dte
                   , NetChange
                   , SUM(NetChange) OVER (PARTITION BY customer_id ORDER BY Dte ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS ClosingBalance
              FROM   CTE_Combined)
    ,        CTE_TrailingAvg
    AS       (SELECT customer_id
                   , Dte
                   , NetChange
                   , ClosingBalance
                   , AVG(ClosingBalance) OVER (PARTITION BY customer_id ORDER BY Dte ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS Trailing30DayAvg
              FROM   CTE_RunningBalance)
    SELECT   DATEPART(month, Dte) AS AllocationMonth
           , COUNT(DISTINCT customer_id) AS ActiveCustomers
           , LAG(CAST (SUM(CASE WHEN Trailing30DayAvg < 0 THEN 0 ELSE Trailing30DayAvg END) AS DECIMAL (10, 2))) OVER (ORDER BY DATEPART(month, Dte)) AS TotalDataOpt2
    FROM     CTE_TrailingAvg
    WHERE    Dte = EOMONTH(Dte)
    GROUP BY DATEPART(month, Dte);

-- If we choose the check-in interval to be middle of the month:


GO
WITH     CTE_TrailingAvg
AS       (SELECT customer_id
               , Dte
               , AVG(ClosingBalance) OVER (PARTITION BY customer_id ORDER BY Dte ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS Trailing30DayAvg
          FROM   VI_DailyRunningBalance)
SELECT   Dte
       , LAG(SUM(CASE WHEN Trailing30DayAvg < 0 THEN 0 ELSE Trailing30DayAvg END), 1) OVER (ORDER BY Dte) AS TotalDataOpt2
FROM     CTE_TrailingAvg
WHERE    Dte = DATEADD(day, (DAY(EOMONTH(Dte)) / 2) - 1, DATEFROMPARTS(YEAR(Dte), MONTH(Dte), 1))
GROUP BY Dte
OPTION (MAXRECURSION 0);

-- Option 3. data is updated real-time


GO
CREATE OR ALTER VIEW dbo.VI_Option3
AS
  WITH     CTE_RealTimeAvg
  AS       (SELECT   customer_id,
                     DATEPART(month, Dte) AS Mth,
                     AVG(ClosingBalance) AS AvgRealTimeBalance
            FROM     VI_DailyRunningBalance
            GROUP BY customer_id, DATEPART(month, Dte))
  SELECT   Mth AS AllocationMonth,
           COUNT(DISTINCT customer_id) AS ActiveCustomers,
           CAST (SUM(CASE WHEN AvgRealTimeBalance < 0 THEN 0 ELSE AvgRealTimeBalance END) AS DECIMAL (10, 2)) AS TotalDataOpt3
  FROM     CTE_RealTimeAvg
  GROUP BY Mth;
-- OPTION (MAXRECURSION 0)

-- Comparison between the 3 policies with Option 3 acts as a benchmark 
-- for accuracy of monthly data allocation


GO
SELECT O1.ActiveCustomers
     , O1.TotalDataOpt1
     , O2.TotalDataOpt2
     , O3.TotalDataOpt3
FROM   VI_Option1 AS O1
       INNER JOIN VI_Option2 AS O2
           ON O1.AllocationMonth = O2.AllocationMonth
       INNER JOIN VI_Option3 AS O3
           ON O1.AllocationMonth = O3.AllocationMonth
OPTION (MAXRECURSION 0);

-- The time to fetch datas from the 3 views is slow so I transfer 3 views into 3 CTAs

SELECT *
INTO   CTA_Option1
FROM   VI_Option1
OPTION (MAXRECURSION 0);

SELECT *
INTO   CTA_Option2
FROM   VI_Option2
OPTION (MAXRECURSION 0);

SELECT *
INTO   CTA_Option3
FROM   VI_Option3
OPTION (MAXRECURSION 0);

SELECT O1.ActiveCustomers
     , O1.TotalDataOpt1
     , O2.TotalDataOpt2
     , O3.TotalDataOpt3
FROM   CTA_Option1 AS O1
       INNER JOIN CTA_Option2 AS O2
           ON O1.AllocationMonth = O2.AllocationMonth
       INNER JOIN CTA_Option3 AS O3
           ON O1.AllocationMonth = O3.AllocationMonth;