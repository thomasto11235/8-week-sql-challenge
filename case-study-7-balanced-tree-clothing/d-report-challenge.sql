ALTER TABLE balancedtree.Sales
    ADD [Month] INT NULL;

UPDATE  balancedtree.Sales
    SET [Month] = MONTH(StartTxnTime)
WHERE   [Month] IS NULL;

ALTER TABLE balancedtree.Sales
    ADD [Year] INT NULL;

UPDATE  balancedtree.Sales
    SET [Year] = YEAR(StartTxnTime)
WHERE   [Year] IS NULL;

-- High-level analysis
SELECT SUM(Qty) AS TotalQuantity
     , SUM(Price * Qty) AS TotalRevenue
     , SUM(Price * Qty * CAST (Discount AS FLOAT) / 100) AS TotalDiscount
FROM   balancedtree.Sales
WHERE  StartTxnTime BETWEEN '20210101' AND '20211231';

-- Transaction analysis
WITH   CTE_TransactionAnalysis
AS     (SELECT   TxnId
               , SUM(Qty) AS Qty
               , SUM(Price * Qty) AS RevenueAmount
               , SUM(Price * Qty * CAST (Discount AS FLOAT) / 100) AS DiscountAmount
               , MAX(CASE WHEN [Member] = 1 THEN 1 ELSE 0 END) AS IsMember
               , MAX(CASE WHEN [Member] = 0 THEN 1 ELSE 0 END) AS IsNotMember
               , PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY SUM(Price * Qty) DESC) OVER () AS P25
               , PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY SUM(Price * Qty) DESC) OVER () AS Median
               , PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY SUM(Price * Qty) DESC) OVER () AS P75
        FROM     balancedtree.Sales
        WHERE    StartTxnTime BETWEEN '20210101' AND '20211231'
        GROUP BY TxnId)
SELECT COUNT(*) AS UniqueTransactionsCnt
     , SUM(Qty) / COUNT(*) AS AvgProductsPurchased
     , AVG(DiscountAmount)
     , SUM(IsMember) / CAST (COUNT(*) AS FLOAT) * 100
     , SUM(IsNotMember) / CAST (COUNT(*) AS FLOAT) * 100
     , MAX(P25)
     , MAX(Median)
     , MAX(P75)
FROM   CTE_TransactionAnalysis;

-- Create a stored procedure to generate a monthly report
-- each time it is run:

-- Section 1 and 2 can be easily displayed/grouped under
-- one table/result set since the questions in the
-- 2 sections' result are output as scalar
-- On the other hand, section 3 is quite difficult
-- to store all questions in a single result set
-- because each question answers in a different
-- granularity; hence, they are most suitable to 
-- be displayed by using one result set per question
-- for maximum readability
-- However, these questions can be partially grouped
-- using union all and hardcoded values to display
-- different granularity within a result set. 
-- For example Q2 + Q4, Q3 + Q5, Q6 + Q7 + Q8, and
-- Q1 + Q9 while Q10 is left single.
-- These combinations are suggested by AI and I have
-- run the queries and see that the 4 result sets
-- from the 4 combinations above and they are hard to intepret
-- If you have any idea on how to combine all or partially
-- but still remain the readability of the report, lmk :)


GO
CREATE OR ALTER PROCEDURE balancedtree.usp_MonthlyReport
@Year INT NULL, @Month INT NULL
AS
BEGIN
    -- Section 1: High level sales analysis (Q1 to Q3)
    SELECT SUM(Qty) AS TotalQuantity
         , SUM(Price * Qty) AS TotalRevenue
         , SUM(Price * Qty * CAST (Discount AS FLOAT) / 100) AS TotalDiscount
    FROM   balancedtree.Sales
    WHERE  [Month] = @Month
           AND [Year] = @Year;
    
    -- Section 2: Transaction analysis (Q1 to Q6)
    WITH   CTE_TransactionAnalysis
    AS     (SELECT   TxnId
                   , SUM(Qty) AS Qty
                   , SUM(Price * Qty) AS RevenueAmount
                   , SUM(Price * Qty * CAST (Discount AS FLOAT) / 100) AS DiscountAmount
                   , MAX(CASE WHEN [Member] = 1 THEN 1 ELSE 0 END) AS IsMember
                   , MAX(CASE WHEN [Member] = 0 THEN 1 ELSE 0 END) AS IsNotMember
                   , PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY SUM(Price * Qty) DESC) OVER () AS P25Revenue
                   , PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY SUM(Price * Qty) DESC) OVER () AS MedianRevenue
                   , PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY SUM(Price * Qty) DESC) OVER () AS P75Revenue
            FROM     balancedtree.Sales
            WHERE    [Month] = @Month
                     AND [Year] = @Year
            GROUP BY TxnId)
    SELECT COUNT(*) AS UniqueTransactionsCnt
         , SUM(Qty) / COUNT(*) AS AvgProductsPurchased
         , MAX(P25Revenue) AS P25Revenue
         , MAX(MedianRevenue) AS MedianRevenue
         , MAX(P75Revenue) AS P75Revenue
         , ROUND(AVG(DiscountAmount), 2) AS AvgDiscountAmount
         , FORMAT(SUM(IsMember) / CAST (COUNT(*) AS FLOAT), 'P2') AS MemberTransactionsPct
         , FORMAT(SUM(IsNotMember) / CAST (COUNT(*) AS FLOAT), 'P2') AS NonMemberTransactionPct
         , ROUND(AVG(CASE WHEN IsMember = 1 THEN CAST (RevenueAmount AS FLOAT) ELSE 0 END), 2) AS AvgMemberRevenue
         , ROUND(AVG(CASE WHEN IsNotMember = 1 THEN CAST (RevenueAmount AS FLOAT) ELSE 0 END), 2) AS AvgNonMemberRevenue
    FROM   CTE_TransactionAnalysis;
    
    -- Section 3: Product analysis (a result set per question)
    -- Q1
    SELECT   PD.ProductName
           , SUM(S.Qty * S.Price) AS TotalRevenue
    FROM     balancedtree.Sales AS S
             INNER JOIN balancedtree.ProductDetails AS PD
                 ON S.ProdId = PD.ProductId
    WHERE    [Month] = @Month
             AND [Year] = @Year
    GROUP BY PD.ProductName
    ORDER BY SUM(S.Qty * S.Price) DESC
    OFFSET 0 ROWS FETCH NEXT 3 ROWS ONLY;
    
    -- Q2
    SELECT   PD.SegmentName
           , SUM(S.Qty) AS TotalQuantity
           , SUM(S.Qty * S.Price) AS TotalRevenue
           , SUM(S.Qty * S.Price * CAST (S.Discount AS FLOAT) / 100) AS TotalDiscount
    FROM     balancedtree.Sales AS S
             INNER JOIN balancedtree.ProductDetails AS PD
                 ON S.ProdId = PD.ProductId
    WHERE    [Month] = @Month
             AND [Year] = @Year
    GROUP BY PD.SegmentName;
    
    -- Q3
    WITH   CTE_RevenueRanking
    AS     (SELECT   PD.ProductName
                   , PD.SegmentName
                   , SUM(S.Qty * S.Price) AS Revenue
                   , RANK() OVER (PARTITION BY PD.SegmentName ORDER BY SUM(S.Qty * S.Price) DESC) AS RevenueRanking
            FROM     balancedtree.Sales AS S
                     INNER JOIN balancedtree.ProductDetails AS PD
                         ON S.ProdId = PD.ProductId
            WHERE    [Month] = @Month
                     AND [Year] = @Year
            GROUP BY PD.SegmentName, PD.ProductName)
    SELECT SegmentName
         , ProductName
         , Revenue
    FROM   CTE_RevenueRanking
    WHERE  RevenueRanking = 1;
    
    -- Q4
    SELECT   PD.CategoryName
           , SUM(S.Qty) AS TotalQuantity
           , SUM(S.Qty * S.Price) AS TotalRevenue
           , SUM(S.Qty * S.Price * CAST (S.Discount AS FLOAT) / 100) AS TotalDiscount
    FROM     balancedtree.Sales AS S
             INNER JOIN balancedtree.ProductDetails AS PD
                 ON S.ProdId = PD.ProductId
    WHERE    [Month] = @Month
             AND [Year] = @Year
    GROUP BY PD.CategoryName;
    
    -- Q5
    WITH   CTE_RevenueRanking
    AS     (SELECT   PD.CategoryName
                   , PD.ProductName
                   , SUM(S.Qty * S.Price) AS Revenue
                   , RANK() OVER (PARTITION BY PD.CategoryName ORDER BY SUM(S.Qty * S.Price) DESC) AS RevenueRanking
            FROM     balancedtree.Sales AS S
                     INNER JOIN balancedtree.ProductDetails AS PD
                         ON S.ProdId = PD.ProductId
            WHERE    [Month] = @Month
                     AND [Year] = @Year
            GROUP BY PD.CategoryName, PD.ProductName)
    SELECT CategoryName
         , ProductName
         , Revenue
    FROM   CTE_RevenueRanking
    WHERE  RevenueRanking = 1;
    
    -- Q6
    SELECT   PD.SegmentName
           , PD.ProductName
           , SUM(S.Qty * S.Price) AS Revenue
           , SUM(SUM(S.Qty * S.Price)) OVER (PARTITION BY PD.SegmentName) AS SegmentRevenue
           , ROUND(SUM(S.Qty * S.Price) / CAST (SUM(SUM(S.Qty * S.Price)) OVER (PARTITION BY PD.SegmentName) AS FLOAT) * 100, 2) AS ProductPctSplit
    FROM     balancedtree.Sales AS S
             INNER JOIN balancedtree.ProductDetails AS PD
                 ON S.ProdId = PD.ProductId
    WHERE    [Month] = @Month
             AND [Year] = @Year
    GROUP BY PD.SegmentName, PD.ProductName;
    
    -- Q7
    SELECT   PD.CategoryName
           , PD.SegmentName
           , SUM(S.Qty * S.Price) AS Revenue
           , SUM(SUM(S.Qty * S.Price)) OVER (PARTITION BY PD.CategoryName) AS CategoryRevenue
           , ROUND(SUM(S.Qty * S.Price) / CAST (SUM(SUM(S.Qty * S.Price)) OVER (PARTITION BY PD.CategoryName) AS FLOAT) * 100, 2) AS SegmentPctSplit
    FROM     balancedtree.Sales AS S
             INNER JOIN balancedtree.ProductDetails AS PD
                 ON S.ProdId = PD.ProductId
    WHERE    [Month] = @Month
             AND [Year] = @Year
    GROUP BY PD.CategoryName, PD.SegmentName;
    
    -- Q8
    SELECT   PD.CategoryName
           , SUM(S.Qty * S.Price) AS Revenue
           , SUM(SUM(S.Qty * S.Price)) OVER () AS CategoryRevenue
           , ROUND(SUM(S.Qty * S.Price) / CAST (SUM(SUM(S.Qty * S.Price)) OVER () AS FLOAT) * 100, 2) AS SegmentPctSplit
    FROM     balancedtree.Sales AS S
             INNER JOIN balancedtree.ProductDetails AS PD
                 ON S.ProdId = PD.ProductId
    WHERE    [Month] = @Month
             AND [Year] = @Year
    GROUP BY PD.CategoryName;
    
    -- Q9
    SELECT   PD.ProductName
           , CAST (COUNT(S.TxnId) AS FLOAT) / (SELECT COUNT(DISTINCT TxnId)
                                               FROM   balancedtree.Sales AS S1) * 100 AS ProductPenetrationRate
    FROM     balancedtree.Sales AS S
             INNER JOIN balancedtree.ProductDetails AS PD
                 ON S.ProdId = PD.ProductId
    WHERE    [Month] = @Month
             AND [Year] = @Year
    GROUP BY PD.ProductName;
    
    -- Q10
    WITH     CTE_Transactions
    AS       (SELECT S.TxnId
                   , PD.ProductName
              FROM   balancedtree.Sales AS S
                     INNER JOIN balancedtree.ProductDetails AS PD
                         ON S.ProdId = PD.ProductId
              WHERE  [Month] = @Month
                     AND [Year] = @Year)
    ,        CTE_ProductCombinations
    AS       (SELECT T1.TxnId
                   , T1.ProductName AS ProductIndex1
                   , T2.ProductName AS ProductIndex2
                   , T3.ProductName AS ProductIndex3
              FROM   CTE_Transactions AS T1
                     INNER JOIN CTE_Transactions AS T2
                         ON T1.TxnId = T2.TxnId
                            AND T1.ProductName < T2.ProductName
                     INNER JOIN CTE_Transactions AS T3
                         ON T2.TxnId = T3.TxnId
                            AND T2.ProductName < T3.ProductName)
    SELECT   TOP 1 ProductIndex1 + ', ' + ProductIndex2 + ', ' + ProductIndex3 AS Combination
                 , COUNT(*) AS Frequency
    FROM     CTE_ProductCombinations
    GROUP BY ProductIndex1, ProductIndex2, ProductIndex3
    ORDER BY COUNT(*) DESC;
END


GO
EXECUTE [balancedtree].[usp_MonthlyReport] @Year = 2021, @Month = 2;

CREATE NONCLUSTERED INDEX IX_Sales_Month_Year ON balancedtree.Sales ([Month], [Year]) INCLUDE (ProdId, Qty, Price, Discount, [Member], TxnId)