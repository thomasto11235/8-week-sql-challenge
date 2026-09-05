-- 1. How many unique transactions were there?
SELECT COUNT(DISTINCT TxnId) AS UniqueTransactionsCnt
FROM   balancedtree.Sales;

-- 2. What is the average unique products purchased in each transaction?
-- should have been average products purchased only
WITH     CTE_ProductsAndTransactionsCount
AS       (SELECT   TxnId
                 , SUM(Qty) AS NumberOfProductsPurchased
                 , COUNT(TxnId) OVER () AS UniqueTransactionsCnt
          FROM     balancedtree.Sales
          GROUP BY TxnId)
SELECT   ROUND(SUM(NumberOfProductsPurchased) / CAST (UniqueTransactionsCnt AS FLOAT), 0) AS AverageProductsPurchased
FROM     CTE_ProductsAndTransactionsCount
GROUP BY UniqueTransactionsCnt;

-- 3. What are the 25th, 50th and 75th percentile values for the revenue per transaction?
WITH   CTE_RevenuePerTransaction
AS     (SELECT   TxnId
               , SUM(Price * Qty) AS Revenue
        FROM     balancedtree.Sales
        GROUP BY TxnId)
SELECT DISTINCT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY Revenue DESC) OVER () AS P25HighestRevenue
              , PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY Revenue DESC) OVER () AS MedianRevenue
              , PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY Revenue DESC) OVER () AS P75HighestRevenue
FROM   CTE_RevenuePerTransaction;

-- 4. What is the average discount value per transaction?
SELECT ROUND(SUM(Price * Qty * CAST (Discount AS FLOAT) / 100) / COUNT(DISTINCT TxnId), 2) AS AvgDiscountValue
FROM   balancedtree.Sales;

-- 5. What is the percentage split of all transactions for members vs non-members?
SELECT FORMAT((SELECT COUNT(DISTINCT TxnId)
               FROM   balancedtree.Sales AS S2
               WHERE  S2.[Member] = 1) / CAST (COUNT(DISTINCT S1.TxnId) AS FLOAT), 'P2') AS MembersPct
     , FORMAT((SELECT COUNT(DISTINCT TxnId)
               FROM   balancedtree.Sales AS S3
               WHERE  S3.[Member] = 0) / CAST (COUNT(DISTINCT S1.TxnId) AS FLOAT), 'P2') AS NonMembersPct
FROM   balancedtree.Sales AS S1;

-- 6. What is the average revenue for member transactions and non-member transactions?
SELECT ROUND(CAST (SUM(CASE WHEN [Member] = 1 THEN Price * Qty END) AS FLOAT) / (SELECT COUNT(DISTINCT TxnId)
                                                                                 FROM   balancedtree.Sales), 2) AS AvgMemberRevenue
     , ROUND(CAST (SUM(CASE WHEN [Member] = 0 THEN Price * Qty END) AS FLOAT) / (SELECT COUNT(DISTINCT TxnId)
                                                                                 FROM   balancedtree.Sales), 2) AS AvgNonMemberRevenue
FROM   balancedtree.Sales;