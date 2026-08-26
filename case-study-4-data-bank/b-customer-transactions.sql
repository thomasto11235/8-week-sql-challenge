-- 1. What is the unique count and total amount for each transaction type?

SELECT   txn_type AS TransactionType
       , SUM(txn_amount) AS TtlAmount
       , COUNT(DISTINCT customer_id) AS CustsCnt
FROM     customer_transactions
GROUP BY txn_type;

-- 2. What is the average total historical deposit counts and amounts for all customers?

WITH   CTE_Deposit
AS     (SELECT   customer_id
               , COUNT(*) AS TransCnt
               , SUM(txn_amount) AS TtlAmount
        FROM     customer_transactions
        WHERE    txn_type = N'deposit'
        GROUP BY customer_id)
SELECT CAST (AVG(TransCnt * 1.0) AS DECIMAL (10, 2)) AS AvgTrans
     , CAST (AVG(TtlAmount * 1.0) AS DECIMAL (10, 2)) AS AvgAmount
FROM   CTE_Deposit;

-- 3. For each month - how many Data Bank customers make more than 1 deposit 
-- and either 1 purchase or 1 withdrawal in a single month?
-- First method


GO
CREATE OR ALTER VIEW VI_TransactionsCountByTypeAndMonth
AS
    SELECT   customer_id
           , txn_type
           , MONTH(txn_date) AS TransMonth
           , COUNT(*) AS TransCnt
    FROM     customer_transactions
    GROUP BY customer_id, txn_type, MONTH(txn_date);


GO
WITH     CTE_Deposit
AS       (SELECT customer_id
               , TransMonth
               , txn_type
               , TransCnt
          FROM   VI_TransactionsCountByTypeAndMonth
          WHERE  txn_type = N'deposit')
,        CTE_Purchase
AS       (SELECT customer_id
               , TransMonth
               , txn_type
               , TransCnt
          FROM   VI_TransactionsCountByTypeAndMonth
          WHERE  txn_type = N'purchase')
,        CTE_Withdrawal
AS       (SELECT customer_id
               , TransMonth
               , txn_type
               , TransCnt
          FROM   VI_TransactionsCountByTypeAndMonth
          WHERE  txn_type = N'withdrawal')
SELECT   D.TransMonth
       , COUNT(D.customer_id) AS CustsCnt
FROM     CTE_Deposit AS D
         LEFT OUTER JOIN CTE_Purchase AS P
             ON D.customer_id = P.customer_id
                AND D.TransMonth = P.TransMonth
         LEFT OUTER JOIN CTE_Withdrawal AS W
             ON D.customer_id = W.customer_id
                AND D.TransMonth = W.TransMonth
WHERE    D.TransCnt > 1
         AND (P.TransCnt >= 1
              OR W.TransCnt >= 1)
GROUP BY D.TransMonth
ORDER BY D.TransMonth;

-- Second method

WITH     CTE_MonthlyTransactions
AS       (SELECT   customer_id
                 , MONTH(txn_date) AS TransMth
                 , SUM(CASE WHEN txn_type = N'deposit' THEN 1 ELSE 0 END) AS Deposit
                 , SUM(CASE WHEN txn_type = N'purchase' THEN 1 ELSE 0 END) AS Purchase
                 , SUM(CASE WHEN txn_type = N'withdrawal' THEN 1 ELSE 0 END) AS Witdrawal
          FROM     customer_transactions
          GROUP BY customer_id, MONTH(txn_date))
SELECT   TransMth
       , COUNT(DISTINCT customer_id) AS NumCusts
FROM     CTE_MonthlyTransactions
WHERE    Deposit > 1
         AND (Purchase >= 1
              OR Witdrawal >= 1)
GROUP BY TransMth;

-- 4. What is the closing balance for each customer at the end of the month?
-- First Method

WITH   CTE_CustsNetChange
AS     (SELECT   customer_id
               , EOMONTH(txn_date) AS TransEndMonth
               , SUM(CASE WHEN txn_type = N'deposit' THEN txn_amount * 1.0 WHEN txn_type = N'purchase' THEN txn_amount * (-1.0) ELSE txn_amount * (-1.0) END) AS NetChange
        FROM     customer_transactions
        GROUP BY customer_id, EOMONTH(txn_date))
SELECT customer_id
     , TransEndMonth
     , NetChange
     , SUM(NetChange) OVER (PARTITION BY customer_id ORDER BY TransEndMonth ASC) AS ClosingBalance
FROM   CTE_CustsNetChange;

-- Second Method

WITH   CTE_CustsNetChange
AS     (SELECT   customer_id
               , EOMONTH(txn_date) AS TransEndMonth
               , SUM(CASE WHEN txn_type = N'deposit' THEN txn_amount * 1.0 WHEN txn_type = N'purchase' THEN txn_amount * (-1.0) ELSE txn_amount * (-1.0) END) AS NetChange
        FROM     customer_transactions
        GROUP BY customer_id, EOMONTH(txn_date))
,      CTE_NumberOfMonths
AS     (SELECT customer_id
             , TransEndMonth
             , NetChange
             , LEAD(TransEndMonth, 1) OVER (PARTITION BY customer_id ORDER BY TransEndMonth) AS NextTransEndMonth
             , COALESCE (DATEDIFF(month, TransEndMonth, LEAD(TransEndMonth, 1) OVER (PARTITION BY customer_id ORDER BY TransEndMonth)), 2) AS TransMonthDiff -- Replace NULL with No.2 because NULL means customers did not make any more transactions in the year
        FROM   CTE_CustsNetChange)
,      CTE_AutoFillMonths
AS     (SELECT N.customer_id
             , N.NetChange
             , M.FillDate
        FROM   CTE_NumberOfMonths AS N CROSS APPLY ITVF_MonthAutoFill(customer_id, TransEndMonth, TransMonthDiff) AS M)
SELECT M.customer_id
     , M.FillDate
     , COALESCE (N.NetChange, 0) AS NetChange
     , SUM(COALESCE (N.NetChange, 0)) OVER (PARTITION BY M.customer_id ORDER BY M.FillDate) AS ClosingBalance
FROM   CTE_AutoFillMonths AS M
       -- Using left outer join so we can see missing months between the recorded months 
       -- of transactions of a customer, missing months will have NULL values 
       -- so we use coalesce and replace them with 0 to indicate no transactions were made.
       LEFT OUTER JOIN CTE_CustsNetChange AS N
           ON M.customer_id = N.customer_id
              AND M.FillDate = N.TransEndMonth;


GO
CREATE OR ALTER FUNCTION dbo.ITVF_MonthAutoFill
(@custid INT, @basedate DATE, @number INT)
RETURNS TABLE 
AS
RETURN 
    WITH   CTE_Tally
    AS     (SELECT 1 AS n
                 , @Basedate AS FillDate
            UNION ALL
            SELECT n + 1
                 , DATEADD(month, 1, FillDate)
            FROM   CTE_Tally
            WHERE  n + 1 <= @number)
    SELECT FillDate
    FROM   CTE_Tally


-- Third method

GO
WITH     CTE_DateBounds
AS       (SELECT MIN(EOMONTH(txn_date)) AS MinEndDate
               , MAX(EOMONTH(txn_date)) AS MaxEndDate
          FROM   customer_transactions)
,        CTE_DateSeries
AS       (SELECT MinEndDate AS Mth
          FROM   CTE_DateBounds
          UNION ALL
          SELECT EOMONTH(DATEADD(month, 1, DS.Mth))
          FROM   
                 CTE_DateSeries AS DS CROSS JOIN CTE_DateBounds AS DB
          -- The recursive part of the CTE only tracks one column: Mth. But the termination condition
          -- needs max_date, which is contained in the DateBound table. So this CROSS JOIN is used as a way
          -- to pull MaxEndDate into scope along side with Mth, so the Where clause can compare them.
          -- Since using a CROSS JOIN usually increase the number of rows but it is safe in this case
          -- because DateBound is built from an aggregate query WITH NO GROUP BY which always returns
          -- exactly ONE row so no multiplication of rows, just attach the MaxEndDate from DB to every row
          -- of DS for comparison.
          -- If the DB table was created with a group by clause, the table would have been like
          -- Cat. 1 | 2020-01-31 | 2020-04-29
          -- Cat. 2 | 2020-01-31 | 2020-03-29
          -- ...
          -- Starting date (anchor) as 2020-01-31
          -- CROSS JOIN result:
          -- 2020-01-31 | 2020-04-29
          -- 2020-01-31 | 2020-03-29
          -- WHERE clause filters based on DATEADD(month, 1, DS.Mth) <= DB.MaxEndDate
          -- 2 rows passed 
          -- returns:
          -- 2020-02-29
          -- 2020-02-29
          WHERE  DATEADD(month, 1, DS.Mth) <= DB.MaxEndDate)
,        CTE_CustomerCalendar
AS       (SELECT CT.customer_id
               , DS.Mth
          FROM   CTE_DateSeries AS DS CROSS JOIN (SELECT DISTINCT customer_id
                                                  FROM   customer_transactions) AS CT)
,        CTE_CustsNetChange
AS       (SELECT   customer_id
                 , EOMONTH(txn_date) AS TransEndMonth
                 , SUM(CASE WHEN txn_type = N'deposit' THEN txn_amount * 1.0 WHEN txn_type = N'purchase' THEN txn_amount * (-1.0) ELSE txn_amount * (-1.0) END) AS NetChange
          FROM     customer_transactions
          GROUP BY customer_id, EOMONTH(txn_date))
,        CTE_Combined
AS       (SELECT CC.customer_id
               , CC.Mth
               , COALESCE (NC.NetChange, 0) AS NetChange
          FROM   CTE_CustomerCalendar AS CC
                 LEFT OUTER JOIN CTE_CustsNetChange AS NC
                     ON CC.customer_id = NC.customer_id
                        AND CC.Mth = NC.TransEndMonth)
SELECT   customer_id
       , Mth
       , NetChange
       , SUM(NetChange) OVER (PARTITION BY customer_id ORDER BY Mth ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS ClosingBalance
FROM     CTE_Combined
ORDER BY customer_id, Mth;

-- 5. What is the percentage of customers who increase their closing balance 
-- by more than 5%?


GO
CREATE OR ALTER VIEW VI_CustsBalance
AS
    WITH   CTE_CustsNetChange
    AS     (SELECT   customer_id
                   , EOMONTH(txn_date) AS TransEndMonth
                   , SUM(CASE WHEN txn_type = N'deposit' THEN txn_amount * 1.0 WHEN txn_type = N'purchase' THEN txn_amount * (-1.0) ELSE txn_amount * (-1.0) END) AS NetChange
            FROM     customer_transactions
            GROUP BY customer_id, EOMONTH(txn_date))
    ,      -- Method 1: Correlated subq (CAUTION: VERY SLOW)
           CTE_NumberOfMonths
    AS     (SELECT customer_id
                 , TransEndMonth
                 , NetChange
                 , LEAD(TransEndMonth, 1) OVER (PARTITION BY customer_id ORDER BY TransEndMonth) AS NextTransEndMonth
                 , COALESCE (DATEDIFF(month, TransEndMonth, LEAD(TransEndMonth, 1) OVER (PARTITION BY customer_id ORDER BY TransEndMonth)), 2) AS TransMonthDiff
            FROM   CTE_CustsNetChange)
    ,      CTE_AutoFillMonths
    AS     (SELECT N.customer_id
                 , N.NetChange
                 , M.FillDate
            FROM   CTE_NumberOfMonths AS N CROSS APPLY ITVF_MonthAutoFill(customer_id, TransEndMonth, TransMonthDiff) AS M)
    SELECT M.customer_id
         , M.FillDate
         , COALESCE (N.NetChange, 0) AS NetChange
         , SUM(COALESCE (N.NetChange, 0)) OVER (PARTITION BY M.customer_id ORDER BY M.FillDate) AS ClosingBalance
    FROM   CTE_AutoFillMonths AS M
           LEFT OUTER JOIN CTE_CustsNetChange AS N
               ON M.customer_id = N.customer_id
                  AND M.FillDate = N.TransEndMonth;


GO
WITH     CTE_StartEndBalance
AS       (SELECT DISTINCT customer_id
                        , (SELECT C2.ClosingBalance
                           FROM   VI_CustsBalance AS C2
                           WHERE  C2.FillDate = (SELECT MIN(C3.FillDate)
                                                 FROM   VI_CustsBalance AS C3
                                                 WHERE  C1.customer_id = C3.customer_id)
                                  AND C1.customer_id = C2.customer_id) AS StartBalance
                        , (SELECT C2.ClosingBalance
                           FROM   VI_CustsBalance AS C2
                           WHERE  C2.FillDate = (SELECT MAX(C3.FillDate)
                                                 FROM   VI_CustsBalance AS C3
                                                 WHERE  C1.customer_id = C3.customer_id)
                                  AND C1.customer_id = C2.customer_id) AS EndBalance
          FROM   VI_CustsBalance AS C1)
SELECT   customer_id
       , StartBalance
       , EndBalance
       , -- Use ABS to prevent edge cases like end and start are: 
         -- both negatives, start negative and end is positive
         -- to reflect increase / decrease accurately.
         CAST (((EndBalance - StartBalance) / ABS(StartBalance)) * 100 AS DECIMAL (10, 2)) AS Diff
FROM     CTE_StartEndBalance
WHERE    ((EndBalance - StartBalance) / ABS(StartBalance)) * 100 > 5
ORDER BY customer_id;

-- Method 2


GO
CREATE OR ALTER VIEW VI_CustsBalance2
AS
    WITH   CTE_DateBounds
    AS     (SELECT MIN(EOMONTH(txn_date)) AS MinEndDate
                 , MAX(EOMONTH(txn_date)) AS MaxEndDate
            FROM   customer_transactions)
    ,      CTE_DateSeries
    AS     (SELECT MinEndDate AS Mth
            FROM   CTE_DateBounds
            UNION ALL
            SELECT EOMONTH(DATEADD(month, 1, DS.Mth))
            FROM   CTE_DateSeries AS DS CROSS JOIN CTE_DateBounds AS DB
            WHERE  DATEADD(month, 1, DS.Mth) <= DB.MaxEndDate)
    ,      CTE_CustomerCalendar
    AS     (SELECT CT.customer_id
                 , DS.Mth
            FROM   CTE_DateSeries AS DS CROSS JOIN (SELECT DISTINCT customer_id
                                                    FROM   customer_transactions) AS CT)
    ,      CTE_CustsNetChange
    AS     (SELECT   customer_id
                   , EOMONTH(txn_date) AS TransEndMonth
                   , SUM(CASE WHEN txn_type = N'deposit' THEN txn_amount * 1.0 WHEN txn_type = N'purchase' THEN txn_amount * (-1.0) ELSE txn_amount * (-1.0) END) AS NetChange
            FROM     customer_transactions
            GROUP BY customer_id, EOMONTH(txn_date))
    ,      CTE_Combined
    AS     (SELECT CC.customer_id
                 , CC.Mth
                 , COALESCE (NC.NetChange, 0) AS NetChange
            FROM   CTE_CustomerCalendar AS CC
                   LEFT OUTER JOIN CTE_CustsNetChange AS NC
                       ON CC.customer_id = NC.customer_id
                          AND CC.Mth = NC.TransEndMonth)
    SELECT customer_id
         , Mth
         , NetChange
         , SUM(NetChange) OVER (PARTITION BY customer_id ORDER BY Mth ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS ClosingBalance
         , ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY Mth) AS RowNum
    FROM   CTE_Combined;


GO
WITH     CTE_StartEndBalance
AS       (SELECT DISTINCT customer_id
                        , (SELECT C2.ClosingBalance
                           FROM   VI_CustsBalance2 AS C2
                           WHERE  C2.RowNum = (SELECT MIN(C3.RowNum)
                                               FROM   VI_CustsBalance2 AS C3)
                                  AND C2.customer_id = C1.customer_id) AS StartBalance
                        , (SELECT C2.ClosingBalance
                           FROM   VI_CustsBalance2 AS C2
                           WHERE  C2.RowNum = (SELECT MAX(C3.RowNum)
                                               FROM   VI_CustsBalance2 AS C3)
                                  AND C2.customer_id = C1.customer_id) AS EndBalance
          FROM   VI_CustsBalance2 AS C1)
SELECT   customer_id
       , StartBalance
       , EndBalance
       , CAST (((EndBalance - StartBalance) / ABS(StartBalance)) * 100 AS DECIMAL (10, 2)) AS Diff
FROM     CTE_StartEndBalance
WHERE    ((EndBalance - StartBalance) / ABS(StartBalance)) * 100 > 5
ORDER BY customer_id;

-- Third method 

WITH     CTE_FirstLastTrans
AS       (SELECT   customer_id
                 , MIN(Mth) AS FirstTrans
                 , MAX(Mth) AS LastTrans
          FROM     VI_CustsBalance2
          GROUP BY customer_id)
,        CTE_OpeningClosing
AS       (SELECT   CB.customer_id
                 , MAX(CASE WHEN CB.Mth = FL.FirstTrans THEN CB.ClosingBalance END) AS Opening
                 , MAX(CASE WHEN CB.Mth = FL.LastTrans THEN CB.ClosingBalance END) AS Closing
          FROM     VI_CustsBalance2 AS CB
                   INNER JOIN CTE_FirstLastTrans AS FL
                       ON CB.customer_id = FL.customer_id
          GROUP BY CB.customer_id)
SELECT   customer_id
       , Opening
       , Closing
       , CAST (((Closing - Opening) / ABS(Opening)) * 100 AS DECIMAL (10, 2)) AS Pct
FROM     CTE_OpeningClosing
WHERE    CAST (((Closing - Opening) / ABS(Opening)) * 100 AS DECIMAL (10, 2)) > 5
ORDER BY customer_id;