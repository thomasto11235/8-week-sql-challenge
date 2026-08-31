-- Create relationships

ALTER TABLE cliquebait.Events
    ADD CONSTRAINT FK_Events_CookieId FOREIGN KEY (CookieId) REFERENCES cliquebait.Users (CookieId);

ALTER TABLE cliquebait.Events
    ADD CONSTRAINT FK_Events_PageId FOREIGN KEY (PageId) REFERENCES cliquebait.PageHierarchy (PageId);

ALTER TABLE cliquebait.Events
    ADD CONSTRAINT FK_Events_EventType FOREIGN KEY (EventType) REFERENCES cliquebait.EventIdentifier (EventType);

-- Create nonclustered index on Events table

CREATE NONCLUSTERED INDEX IX_Events_EventType_VisitId_Page_id
    ON cliquebait.Events(EventType)
    INCLUDE(VisitId, PageId, SequenceNumber);

DROP INDEX IX_Events_EventType_VisitId_Page_id
    ON cliquebait.Events;

-- 1. How many users are there ?

SELECT COUNT(DISTINCT UserId) AS NumberOfUsers
FROM   cliquebait.Users;

-- 2. How many cookies does each user have on average?

SELECT ROUND(CAST (COUNT(CookieId) AS FLOAT) / COUNT(DISTINCT UserId), 2) AS AverageCookiePerUser
FROM   cliquebait.Users;

-- 3. What is the unique number of visits by all users per month?

SELECT   DATEPART(month, EventTime) AS VisitingMonth
       , COUNT(DISTINCT VisitId) AS NumberOfVisits
FROM     cliquebait.Events
GROUP BY DATEPART(month, EventTime)
ORDER BY DATEPART(month, EventTime);

-- 4. What is the number of events for each event type?

SELECT   EI.EventName
       , COUNT(E.EventType) AS NumberOfEvents
FROM     cliquebait.Events AS E
         INNER JOIN cliquebait.EventIdentifier AS EI
             ON E.EventType = EI.EventType
GROUP BY EI.EventName
ORDER BY EI.EventName;

-- 5. What is the percentage of visits which have a purchase event?

SELECT FORMAT(CAST (COUNT(DISTINCT E.VisitId) AS FLOAT) / (SELECT COUNT(DISTINCT VisitId)
                                                           FROM   cliquebait.Events), 'P2') AS PercentageOfPurchaseEvent
FROM   cliquebait.Events AS E
       INNER JOIN cliquebait.EventIdentifier AS EI
           ON E.EventType = EI.EventType
              AND EI.EventName = 'Purchase';

-- 6. What is the percentage of visits which view the checkout page 
-- but do not have a purchase event?
-- pct = number of visits that view the checkout page but do not have 
-- a purchase event / number of visits that view the checkout page
-- Method 1

WITH   CTE_PageViewVisits
AS     (SELECT E.VisitId
             , E.CookieId
             , E.PageId
             , PH.PageName
        FROM   cliquebait.Events AS E
               INNER JOIN cliquebait.PageHierarchy AS PH
                   ON E.PageId = PH.PageId
                      AND PH.PageName = 'Checkout')
,      CTE_PurchaseVisits
AS     (SELECT E.VisitId
             , E.CookieId
             , E.EventType
        FROM   cliquebait.Events AS E
               INNER JOIN cliquebait.EventIdentifier AS EI
                   ON E.EventType = EI.EventType
                      AND EI.EventName = 'Purchase')
SELECT FORMAT(CAST (COUNT(DISTINCT VisitId) AS FLOAT) / (SELECT COUNT(DISTINCT E.VisitId)
                                                         FROM   cliquebait.Events AS E
                                                         WHERE  E.PageId = 12), 'P2') AS PageViewNoPurchasePercentage
FROM   CTE_PageViewVisits AS PVV
WHERE  NOT EXISTS (SELECT *
                   FROM   CTE_PurchaseVisits AS PV
                   WHERE  PVV.VisitId = PV.VisitId);

-- Method 2

WITH   CTE_CheckOutViews
AS     (SELECT E.VisitId
        FROM   cliquebait.Events AS E
               INNER JOIN cliquebait.PageHierarchy AS PH
                   ON E.PageId = PH.PageId
                      AND PH.PageName = N'CheckOut')
,      CTE_Purchases
AS     (SELECT E.VisitId
        FROM   cliquebait.Events AS E
               INNER JOIN cliquebait.EventIdentifier AS EI
                   ON E.EventType = EI.EventType
                      AND EI.EventName = N'Purchase')
SELECT COUNT(COV.VisitId) - COUNT(P.VisitId) AS CheckOutViewOnly
     , FORMAT(CAST (COUNT(COV.VisitId) - COUNT(P.VisitId) AS FLOAT) / COUNT(COV.VisitId), 'P2') AS PctCheckOutViewOnly
FROM   CTE_CheckOutViews AS COV
       LEFT OUTER JOIN CTE_Purchases AS P
           ON COV.VisitId = P.VisitId;

-- 7. What are the top 3 pages by number of views?

SELECT   PH.PageName
       , COUNT(E.VisitId) AS ViewsPerPage
FROM     cliquebait.Events AS E
         INNER JOIN cliquebait.PageHierarchy AS PH
             ON E.PageId = PH.PageId
         INNER JOIN cliquebait.EventIdentifier AS EI
             ON E.EventType = EI.EventType
WHERE    EI.EventName = 'Page View'
GROUP BY PH.PageName
ORDER BY COUNT(E.VisitId) DESC
OFFSET 0 ROWS FETCH NEXT 3 ROWS ONLY;

-- 8. What is the number of views and cart adds for each product category?

WITH     CTE_UnpivotProductCategory
AS       (SELECT E.VisitId
               , E.CookieId
               , E.PageId
               , EI.EventType
               , EI.EventName
               , PH.ProductCategory
          FROM   cliquebait.Events AS E
                 INNER JOIN cliquebait.PageHierarchy AS PH
                     ON E.PageId = PH.PageId
                 INNER JOIN cliquebait.EventIdentifier AS EI
                     ON E.EventType = EI.EventType)
SELECT   ProductCategory
       , SUM(CASE WHEN EventName = 'Page View' THEN 1 ELSE 0 END) AS NumberOfViews
       , SUM(CASE WHEN EventName = 'Add to Cart' THEN 1 ELSE 0 END) AS NumberOfCartAdds
FROM     CTE_UnpivotProductCategory
GROUP BY ProductCategory;

-- 9. What are the top 3 products by purchases?
-- Method 1

WITH     CTE_Purchases
AS       (SELECT DISTINCT VisitId
          FROM   cliquebait.Events
          WHERE  EventType = '3')
SELECT   PH.PageName
       , COUNT(*) AS ProductsPurchase
FROM     cliquebait.Events AS E
         INNER JOIN CTE_Purchases AS P
             ON E.VisitId = P.VisitId
         INNER JOIN cliquebait.PageHierarchy AS PH
             ON E.PageId = PH.PageId
WHERE    E.EventType = 2
GROUP BY PH.PageName
ORDER BY COUNT(*) DESC
OFFSET 0 ROWS FETCH NEXT 3 ROWS ONLY;

-- Method 2
-- If a session has multiple purchases or partial purchases
-- This query can correctly classify if a session belong to
-- fully purchased or partially purchased; however, it
-- cannot classify if a phase within a session is full
-- or partially purchased.
-- Note that a ends when a customer confirms a purchase
-- For example:
-- How many sessions had a partial purchase in phase 2
-- but a full purchase in phase 1?

WITH     CTE_ItemsInCart
AS       (SELECT E1.VisitId
               , E1.CookieId
               , E1.PageId
               , PH.PageName
               , E1.EventType
               , EI1.EventName
               , E1.SequenceNumber
               , CASE WHEN EI1.EventName = N'Add to Cart' THEN 1 WHEN EI1.EventName = N'Purchase' THEN 0 END AS ItemsInCart
          FROM   cliquebait.Events AS E1
                 INNER JOIN cliquebait.PageHierarchy AS PH
                     ON E1.PageId = PH.PageId
                 INNER JOIN cliquebait.EventIdentifier AS EI1
                     ON E1.EventType = EI1.EventType
          WHERE  EXISTS (SELECT *
                         FROM   cliquebait.Events AS E2
                                INNER JOIN cliquebait.EventIdentifier AS EI2
                                    ON E2.EventType = EI2.EventType
                         WHERE  E1.VisitId = E2.VisitId
                                AND EI2.EventName = N'Purchase'))
,        CTE_ItemsPurchasedCheck
AS       (SELECT VisitId
               , CookieId
               , PageId
               , PageName
               , EventType
               , EventName
               , SequenceNumber
               , ItemsInCart
               , CASE WHEN ItemsInCart = 0 THEN SUM(ItemsInCart) OVER (PARTITION BY VisitId ORDER BY SequenceNumber ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) END AS ItemsPurchased
               , SUM(ItemsInCart) OVER (PARTITION BY VisitId) AS ItemsPurchasedCheck
          FROM   CTE_ItemsInCart
          WHERE  ItemsInCart IS NOT NULL)
,        CTE_FullyPurchased
AS       (SELECT IPC1.VisitId
               , IPC1.CookieId
               , IPC1.PageId
               , PH.PageName
               , IPC1.EventType
               , IPC1.EventName
               , IPC1.SequenceNumber
               , IPC1.ItemsInCart
          FROM   CTE_ItemsPurchasedCheck AS IPC1
                 INNER JOIN cliquebait.PageHierarchy AS PH
                     ON IPC1.PageId = PH.PageId
          WHERE  EXISTS (SELECT *
                         FROM   CTE_ItemsPurchasedCheck AS IPC2
                         WHERE  IPC2.ItemsPurchased = IPC2.ItemsPurchasedCheck
                                AND IPC1.VisitId = IPC2.VisitId
                                AND IPC1.SequenceNumber < IPC2.SequenceNumber))
,        CTE_PartiallyPurchased
AS       (SELECT IPC1.VisitId
               , IPC1.CookieId
               , IPC1.PageId
               , PH.PageName
               , IPC1.EventType
               , IPC1.EventName
               , IPC1.SequenceNumber
               , IPC1.ItemsInCart
          FROM   CTE_ItemsPurchasedCheck AS IPC1
                 INNER JOIN cliquebait.PageHierarchy AS PH
                     ON IPC1.PageId = PH.PageId
          WHERE  EXISTS (SELECT *
                         FROM   CTE_ItemsPurchasedCheck AS IPC2
                         WHERE  IPC2.ItemsPurchased < IPC2.ItemsPurchasedCheck
                                AND IPC1.VisitId = IPC2.VisitId
                                AND IPC1.SequenceNumber < IPC2.SequenceNumber)
                 AND NOT EXISTS (SELECT *
                                 FROM   CTE_FullyPurchased AS FP
                                 WHERE  FP.VisitId = IPC1.VisitId))
SELECT   PageName
       , SUM(ItemsInCart) AS ProducstPurchase
FROM     (SELECT FP.VisitId
               , FP.PageName
               , FP.ItemsInCart
          FROM   CTE_FullyPurchased AS FP
          UNION ALL
          SELECT PP.VisitId
               , PP.PageName
               , PP.ItemsInCart
          FROM   CTE_PartiallyPurchased AS PP) AS PurchaseCheck
GROUP BY PageName
ORDER BY SUM(ItemsInCart) DESC
OFFSET 0 ROWS FETCH NEXT 3 ROWS ONLY;

-- Method 3
-- This method provides the same answer but in a more readable way
-- by using window function to capture the neearest purchase
-- after a product is added to cart. If there's a purchase
-- assign 1 else 0 then we can count as normal.

WITH     CTE_EventsWithNextPurchase
AS       (SELECT VisitId
               , PageId
               , EventType
               , SequenceNumber
               , MIN(CASE WHEN EventType = 3 THEN SequenceNumber END) OVER (PARTITION BY VisitId ORDER BY SequenceNumber ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS NextPurchaseSequence
          FROM   cliquebait.Events
          WHERE  EventType IN (2, 3))
SELECT   PH.PageName
       , COUNT(*) AS PurchaseCount
FROM     CTE_EventsWithNextPurchase AS EWP
         INNER JOIN cliquebait.PageHierarchy AS PH
             ON EWP.PageId = PH.PageId
WHERE    EWP.EventType = 2
         AND EWP.NextPurchaseSequence IS NOT NULL
GROUP BY PH.PageName
ORDER BY COUNT(*) DESC
OFFSET 0 ROWS FETCH NEXT 3 ROWS ONLY;

-- Method 4
-- This query answers the main question as well as
-- assign phase number for each phase per session
-- I created this with the help of AI, gotta say
-- this solution is brilliant.

WITH     CTE_PhaseNumberAssignment
AS       (SELECT VisitId
               , PageId
               , EventType
               , SequenceNumber
               , CASE WHEN EventType = 3 THEN 1 ELSE 0 END AS PurchaseMark
               , -- Each session starts at phase 0 and only increments when another
                 -- item is added to cart after phase 0's purchase.
                 -- Each purchase is marked as 1, let's take a customer intial
                 -- purchase as an example, the phase number for this purchase
                 -- is 0 also, in order to do that the condition must be in
                 -- unbounded preceding and 1 precdeing (not current row)
                 -- for the incrementation to work properly.
                 -- COALESCE to 0 because the first row is null and first row 
                 -- always belongs to 0 so 0 is a suitbale replacement
                 COALESCE (SUM(CASE WHEN EventType = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY VisitId ORDER BY SequenceNumber ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS PhaseNumber
          FROM   cliquebait.Events
          WHERE  EventType IN (2, 3))
,        CTE_PhaseStats
AS       (SELECT   VisitId
                 , PhaseNumber
                 , SUM(CASE WHEN EventType = 2 THEN 1 ELSE 0 END) AS ItemsAddedInPhase
                 , MAX(CASE WHEN EventType = 3 THEN 1 ELSE 0 END) AS PhaseHadPurchase
          FROM     CTE_PhaseNumberAssignment
          GROUP BY VisitId, PhaseNumber)
,        CTE_PurchasedItems
AS       (SELECT PNA.VisitId
               , PNA.PageId
               , PNA.PhaseNumber
          FROM   CTE_PhaseNumberAssignment AS PNA
                 INNER JOIN CTE_PhaseStats AS PS
                     ON PNA.VisitId = PS.VisitId
                        AND PNA.PhaseNumber = PS.PhaseNumber
          WHERE  PNA.EventType = 2
                 AND PS.PhaseHadPurchase = 1)
SELECT   PageName
       , COUNT(*) AS PurchaseCount
FROM     CTE_PurchasedItems AS [PI]
         INNER JOIN cliquebait.PageHierarchy AS PH
             ON [PI].PageId = PH.PageId
GROUP BY PH.PageName
ORDER BY COUNT(*) DESC
OFFSET 0 ROWS FETCH NEXT 3 ROWS ONLY;