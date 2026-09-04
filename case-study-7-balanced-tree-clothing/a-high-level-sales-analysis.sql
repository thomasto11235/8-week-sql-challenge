ALTER TABLE balancedtree.Sales
    ADD CONSTRAINT FK_ProdId_ProductId FOREIGN KEY (ProdId) REFERENCES balancedtree.ProductDetails (ProductId);

UPDATE  balancedtree.Sales
    SET [Member] = 'FALSE'
WHERE   [Member] = 'f';

ALTER TABLE balancedtree.Sales ALTER COLUMN [Member] BIT;

-- 1. What was the total quantity sold for all products?
SELECT   PD.ProductName
       , SUM(S.Qty) AS TotalQuantity
FROM     balancedtree.Sales AS S
         INNER JOIN balancedtree.ProductDetails AS PD
             ON S.ProdId = PD.ProductId
GROUP BY PD.ProductName
ORDER BY SUM(S.Qty) DESC;

-- 2. What is the total generated revenue for all products before discounts?
SELECT   PD.ProductName
       , SUM(S.Qty * S.Price) AS RevenueBeforeDiscount
FROM     balancedtree.Sales AS S
         INNER JOIN balancedtree.ProductDetails AS PD
             ON S.ProdId = PD.ProductId
GROUP BY PD.ProductName
ORDER BY SUM(S.Qty * S.Price) DESC;

-- 3. What was the total discount amount for all products?
SELECT   PD.ProductName
       , ROUND(SUM(S.Qty * S.Price * (CAST (S.Discount AS FLOAT) / 100)), 2) AS TotalDiscountAmount
FROM     balancedtree.Sales AS S
         INNER JOIN balancedtree.ProductDetails AS PD
             ON S.ProdId = PD.ProductId
GROUP BY PD.ProductName
ORDER BY SUM(S.Qty * S.Price * (CAST (S.Discount AS FLOAT) / 100)) DESC;