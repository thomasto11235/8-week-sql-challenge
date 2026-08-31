/*
Using a single SQL query - create a new output table which has the following 
details:

How many times was each product viewed?
How many times was each product added to cart?
How many times was each product added to a cart but not purchased (abandoned)?
How many times was each product purchased?

Additionally, create another table which further aggregates the data 
for the above points but this time for each product category instead of 
individual products.
*/
-- Table 1

WITH     CTE_EventsWithNextPurchase
AS       (SELECT VisitId
               , PageId
               , EventType
               , SequenceNumber
               , CASE WHEN EventType = 1 THEN 1 ELSE 0 END AS PageView
               , CASE WHEN EventType = 2 THEN 1 ELSE 0 END AS AddToCart
               , MIN(CASE WHEN EventType = 3 THEN 1 END) OVER (PARTITION BY VisitId ORDER BY SequenceNumber ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS NextPurchaseCheck
          FROM   cliquebait.Events
          WHERE  EventType IN (1, 2, 3))
SELECT   PH.PageName
       , SUM(EWP.PageView) AS PageView
       , SUM(EWP.AddToCart) AS AddToCart
       , SUM(CASE WHEN EWP.EventType = 2
                       AND EWP.NextPurchaseCheck IS NOT NULL THEN 1 END) AS ItemsPurchased
       , SUM(EWP.AddToCart) - SUM(CASE WHEN EWP.EventType = 2
                                            AND EWP.NextPurchaseCheck IS NOT NULL THEN 1 END) AS ItemsAbandoned
INTO     cliquebait.ProductPerformanceSummary
FROM     CTE_EventsWithNextPurchase AS EWP
         INNER JOIN cliquebait.PageHierarchy AS PH
             ON EWP.PageId = PH.PageId
WHERE    PH.ProductCategory IS NOT NULL
GROUP BY PH.PageName;

-- Table 2

WITH     CTE_EventsWithNextPurchase
AS       (SELECT VisitId
               , PageId
               , EventType
               , SequenceNumber
               , CASE WHEN EventType = 1 THEN 1 ELSE 0 END AS PageView
               , CASE WHEN EventType = 2 THEN 1 ELSE 0 END AS AddToCart
               , MIN(CASE WHEN EventType = 3 THEN 1 END) OVER (PARTITION BY VisitId ORDER BY SequenceNumber ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS NextPurchaseCheck
          FROM   cliquebait.Events
          WHERE  EventType IN (1, 2, 3))
SELECT   PH.ProductCategory
       , SUM(EWP.PageView) AS PageView
       , SUM(EWP.AddToCart) AS AddToCart
       , SUM(CASE WHEN EWP.EventType = 2
                       AND EWP.NextPurchaseCheck IS NOT NULL THEN 1 END) AS ItemsPurchased
       , SUM(EWP.AddToCart) - SUM(CASE WHEN EWP.EventType = 2
                                            AND EWP.NextPurchaseCheck IS NOT NULL THEN 1 END) AS ItemsAbandoned
INTO     cliquebait.CategoryPerformanceSummary
FROM     CTE_EventsWithNextPurchase AS EWP
         INNER JOIN cliquebait.PageHierarchy AS PH
             ON EWP.PageId = PH.PageId
WHERE    PH.ProductCategory IS NOT NULL
GROUP BY PH.ProductCategory;

/*
Use your 2 new output tables - answer the following questions:

Which product had the most views, cart adds and purchases?
Which product was most likely to be abandoned?
Which product had the highest view to purchase percentage?
What is the average conversion rate from view to cart add?
What is the average conversion rate from cart add to purchase?
*/
-- Which product had the most views, cart adds and purchases?

SELECT T0.PageName AS MostViewedProduct
     , T1.MostAddedProduct
     , T2.MostPurchasedProduct
FROM   cliquebait.ProductPerformanceSummary AS T0 
       CROSS JOIN (SELECT PageName AS MostAddedProduct
                   FROM   cliquebait.ProductPerformanceSummary
                   WHERE  AddToCart = (SELECT MAX(AddToCart)
                                       FROM   cliquebait.ProductPerformanceSummary)) AS T1 
       CROSS JOIN (SELECT PageName AS MostPurchasedProduct
                   FROM   cliquebait.ProductPerformanceSummary
                   WHERE  ItemsPurchased = (SELECT MAX(ItemsPurchased)
                                            FROM   cliquebait.ProductPerformanceSummary)) AS T2
WHERE  T0.PageView = (SELECT MAX(PageView)
                      FROM   cliquebait.ProductPerformanceSummary);

-- Which product was most likely to be abandoned?

SELECT PageName AS MostAbandonedProduct
FROM   cliquebait.ProductPerformanceSummary
WHERE  ItemsAbandoned = (SELECT MAX(ItemsAbandoned)
                         FROM   cliquebait.ProductPerformanceSummary);

-- Which product had the highest view to purchase percentage?

SELECT PageName
     , PageView
     , ItemsPurchased
FROM   (SELECT PageName
             , PageView
             , ItemsPurchased
             , ROW_NUMBER() OVER (ORDER BY ROUND(CAST (ItemsPurchased AS FLOAT) / PageView * 100, 2) DESC) AS ViewToPurchasePct
        FROM   cliquebait.ProductPerformanceSummary) AS VPP
WHERE  VPP.ViewToPurchasePct = 1;

-- What is the average conversion rate from view to cart add?

SELECT ROUND(CAST (SUM(AddToCart) AS FLOAT) / SUM(PageView) * 100, 2) AS ViewToAddPct
     , ROUND(CAST (SUM(ItemsPurchased) AS FLOAT) / SUM(AddToCart) * 100, 2) AS AddToPurchasePct
FROM   cliquebait.ProductPerformanceSummary;