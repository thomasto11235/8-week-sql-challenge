-- 1. What are the top 3 products by total revenue before discount?
SELECT   PD.ProductName
       , SUM(S.Qty * S.Price) AS TotalRevenue
FROM     balancedtree.Sales AS S
         INNER JOIN balancedtree.ProductDetails AS PD
             ON S.ProdId = PD.ProductId
GROUP BY PD.ProductName
ORDER BY SUM(S.Qty * S.Price) DESC
OFFSET 0 ROWS FETCH NEXT 3 ROWS ONLY;

-- 2. What is the total quantity, revenue and discount for each segment?
SELECT   PD.SegmentName
       , SUM(S.Qty) AS TotalQuantity
       , SUM(S.Qty * S.Price) AS TotalRevenue
       , SUM(S.Qty * S.Price * CAST (S.Discount AS FLOAT) / 100) AS TotalDiscount
FROM     balancedtree.Sales AS S
         INNER JOIN balancedtree.ProductDetails AS PD
             ON S.ProdId = PD.ProductId
GROUP BY PD.SegmentName;

-- 3. What is the top selling product for each segment?
-- Method 1
WITH   CTE_RevenueRanking
AS     (SELECT   PD.ProductName
               , PD.SegmentName
               , SUM(S.Qty * S.Price) AS Revenue
               , RANK() OVER (PARTITION BY PD.SegmentName ORDER BY SUM(S.Qty * S.Price) DESC) AS RevenueRanking
        FROM     balancedtree.Sales AS S
                 INNER JOIN balancedtree.ProductDetails AS PD
                     ON S.ProdId = PD.ProductId
        GROUP BY PD.SegmentName, PD.ProductName)
SELECT SegmentName
     , ProductName
     , Revenue
FROM   CTE_RevenueRanking
WHERE  RevenueRanking = 1;

-- Method 2
SELECT DISTINCT D1.SegmentName
              , (SELECT   TOP 1 SUM(S.Price * S.Qty)
                 FROM     balancedtree.ProductDetails AS D2
                          INNER JOIN balancedtree.Sales AS S
                              ON D2.ProductId = S.ProdId
                 WHERE    D1.SegmentName = D2.SegmentName
                 GROUP BY D2.SegmentName, D2.ProductName) AS Revenue
FROM   balancedtree.ProductDetails AS D1;

-- 4. What is the total quantity, revenue and discount for each category?
SELECT   PD.CategoryName
       , SUM(S.Qty) AS TotalQuantity
       , SUM(S.Qty * S.Price) AS TotalRevenue
       , SUM(S.Qty * S.Price * CAST (S.Discount AS FLOAT) / 100) AS TotalDiscount
FROM     balancedtree.Sales AS S
         INNER JOIN balancedtree.ProductDetails AS PD
             ON S.ProdId = PD.ProductId
GROUP BY PD.CategoryName;

-- 5. What is the top selling product for each category?
WITH   CTE_RevenueRanking
AS     (SELECT   PD.CategoryName
               , PD.ProductName
               , SUM(S.Qty * S.Price) AS Revenue
               , RANK() OVER (PARTITION BY PD.CategoryName ORDER BY SUM(S.Qty * S.Price) DESC) AS RevenueRanking
        FROM     balancedtree.Sales AS S
                 INNER JOIN balancedtree.ProductDetails AS PD
                     ON S.ProdId = PD.ProductId
        GROUP BY PD.CategoryName, PD.ProductName)
SELECT CategoryName
     , ProductName
     , Revenue
FROM   CTE_RevenueRanking
WHERE  RevenueRanking = 1;

-- Method 2 (same as before)
-- 6. What is the percentage split of revenue by product for each segment?
SELECT   PD.SegmentName
       , PD.ProductName
       , SUM(S.Qty * S.Price) AS Revenue
       , SUM(SUM(S.Qty * S.Price)) OVER (PARTITION BY PD.SegmentName) AS SegmentRevenue
       , ROUND(SUM(S.Qty * S.Price) / CAST (SUM(SUM(S.Qty * S.Price)) OVER (PARTITION BY PD.SegmentName) AS FLOAT) * 100, 2) AS ProductPctSplit
FROM     balancedtree.Sales AS S
         INNER JOIN balancedtree.ProductDetails AS PD
             ON S.ProdId = PD.ProductId
GROUP BY PD.SegmentName, PD.ProductName;

-- 7. What is the percentage split of revenue by segment for each category?
SELECT   PD.CategoryName
       , PD.SegmentName
       , SUM(S.Qty * S.Price) AS Revenue
       , SUM(SUM(S.Qty * S.Price)) OVER (PARTITION BY PD.CategoryName) AS CategoryRevenue
       , ROUND(SUM(S.Qty * S.Price) / CAST (SUM(SUM(S.Qty * S.Price)) OVER (PARTITION BY PD.CategoryName) AS FLOAT) * 100, 2) AS SegmentPctSplit
FROM     balancedtree.Sales AS S
         INNER JOIN balancedtree.ProductDetails AS PD
             ON S.ProdId = PD.ProductId
GROUP BY PD.CategoryName, PD.SegmentName;

-- 8. What is the percentage split of total revenue by category?
SELECT   PD.CategoryName
       , SUM(S.Qty * S.Price) AS Revenue
       , SUM(SUM(S.Qty * S.Price)) OVER () AS CategoryRevenue
       , ROUND(SUM(S.Qty * S.Price) / CAST (SUM(SUM(S.Qty * S.Price)) OVER () AS FLOAT) * 100, 2) AS SegmentPctSplit
FROM     balancedtree.Sales AS S
         INNER JOIN balancedtree.ProductDetails AS PD
             ON S.ProdId = PD.ProductId
GROUP BY PD.CategoryName;

-- 9. What is the total transaction “penetration” for each product? 
-- (hint: penetration = number of transactions where at least 1 quantity of a product was purchased 
-- divided by total number of transactions)
SELECT   PD.ProductName
       , CAST (COUNT(S.TxnId) AS FLOAT) / (SELECT COUNT(DISTINCT TxnId)
                                           FROM   balancedtree.Sales AS S1) * 100 AS ProductPenetrationRate
FROM     balancedtree.Sales AS S
         INNER JOIN balancedtree.ProductDetails AS PD
             ON S.ProdId = PD.ProductId
GROUP BY PD.ProductName;

-- 10. What is the most common combination of at least 1 quantity 
-- of any 3 products in a 1 single transaction?
-- Use self joins as well as less than '<' conditions to filter out duplicates
-- to mimic combination formula where order does not matter (ABC = CBA)
WITH     CTE_Transactions
AS       (SELECT S.TxnId
               , PD.ProductName
          FROM   balancedtree.Sales AS S
                 INNER JOIN balancedtree.ProductDetails AS PD
                     ON S.ProdId = PD.ProductId)
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