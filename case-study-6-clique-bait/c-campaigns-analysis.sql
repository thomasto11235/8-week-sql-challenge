/*
Generate a table that has 1 single row for every unique visit_id record and has the following columns:

user_id
visit_id
visit_start_time: the earliest event_time for each visit
page_views: count of page views for each visit
cart_adds: count of product cart add events for each visit
purchase: 1/0 flag if a purchase event exists for each visit
campaign_name: map the visit to a campaign if the visit_start_time falls between the start_date and end_date
impression: count of ad impressions for each visit
click: count of ad clicks for each visit
(Optional column) cart_products: a comma separated text value with products added to the cart sorted by the order they were added to the cart (hint: use the sequence_number)
*/
-- Must computes the earliest visit time for each visit first
-- so we can take this to join onto the campaign table
-- If we put the window function in the SELECT clause of the same query 
-- of the join, we cannot placed that window function in the ON predicate

WITH     CTE_VisitBase
AS       (SELECT E.VisitId
               , E.CookieId
               , E.PageId
               , E.EventType
               , E.SequenceNumber
               , E.EventTime
               , MIN(E.EventTime) OVER (PARTITION BY E.VisitId) AS VisitStartTime
          FROM   cliquebait.Events AS E)
,        CTE_VisitSummary
AS       (SELECT VB.VisitId
               , U.UserId
               , VB.VisitStartTime
               , SUM(CASE WHEN VB.EventType = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY VB.VisitId) AS PageView
               , SUM(CASE WHEN VB.EventType = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY VB.VisitId) AS AddToCart
               , MAX(CASE WHEN VB.EventType = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY VB.VisitId) AS PurchaseCheck
               , COALESCE (CI.CampaignName, 'N/A') AS CampaignName
               , SUM(CASE WHEN VB.EventType = 4 THEN 1 ELSE 0 END) OVER (PARTITION BY VB.VisitId) AS Impression
               , SUM(CASE WHEN VB.EventType = 5 THEN 1 ELSE 0 END) OVER (PARTITION BY VB.VisitId) AS Clicks
               , CASE WHEN VB.EventType = 2 THEN PH.PageName END AS ProductName
               , VB.SequenceNumber
          FROM   CTE_VisitBase AS VB
                 LEFT OUTER JOIN cliquebait.Users AS U
                     ON VB.CookieId = U.CookieId
                 LEFT OUTER JOIN cliquebait.CampaignIdentifier AS CI
                     ON VB.VisitStartTime BETWEEN CI.StartDate AND CI.EndDate
                 LEFT OUTER JOIN cliquebait.PageHierarchy AS PH
                     ON VB.PageId = PH.PageId)
SELECT   VisitId
       , UserId
       , MIN(VisitStartTime) AS VisitStartTime
       , MAX(PageView) AS PageViews
       , MAX(AddToCart) AS CartAdds
       , MAX(PurchaseCheck) AS Purchases
       , MAX(CampaignName) AS CampaignName
       , MAX(Impression) AS Impressions
       , MAX(Clicks) AS Clicks
       , COALESCE (STRING_AGG(ProductName, ', ') WITHIN GROUP (ORDER BY SequenceNumber), 'N/A') AS CartProducts
INTO     cliquebait.CampaignAnalysis
FROM     CTE_VisitSummary
GROUP BY VisitId, UserId
ORDER BY VisitId;

/*
Identifying users who have received impressions during each campaign period 
and comparing each metric with other users who did not have an impression event

Does clicking on an impression lead to higher purchase rates?

What is the uplift in purchase rate when comparing users who click on a 
campaign impression versus users who do not receive an impression? 
What if we compare them with users who just an impression but do not click?

What metrics can you use to quantify the success or failure of each campaign 
compared to eachother?
*/
-- 1. Identifying users who have received impressions during each campaign period 
-- and comparing each metric with other users who did not have an impression event

WITH     CTE_ImpressionCheck
AS       (SELECT [VisitId]
               , [UserId]
               , [VisitStartTime]
               , [PageViews]
               , [CartAdds]
               , [Purchases]
               , [CampaignName]
               , [Impressions]
               , [Clicks]
               , [CartProducts]
               , CASE WHEN Impressions > 0
                           AND CampaignName <> N'N/A' THEN 'CampaignImpression' ELSE 'NoCampaignImpression' END AS ImpressionCheck
          FROM   [CLIQUEBAIT].[cliquebait].[CampaignAnalysis])
SELECT   /* CampaignName, */
         ImpressionCheck
       , COUNT(VisitId) AS VisitsCount
       , SUM(PageViews) AS TotalPageViews
       , SUM(CartAdds) AS TotalCartAdds
       , SUM(Purchases) AS TotalPurchases
       , SUM(Clicks) AS TotalClicks
       , SUM(Impressions) AS TotalImpressions
       , -- If the expression returns 0 then returns NULL for this division
         FORMAT(CAST (SUM(Clicks) AS FLOAT) / NULLIF (SUM(Impressions), 0), 'P2') AS ClickThroughRate
       , FORMAT(CAST (SUM(Purchases) AS FLOAT) / COUNT(VisitId), 'P2') AS PurchaseRate
       , -- Im not multiply by 100 because the value is large and can be misleading
         -- so i keep the calcualtion under average
         ROUND(CAST (SUM(CartAdds) AS FLOAT) / COUNT(VisitId), 2) AS AvgCartAddRate
FROM     CTE_ImpressionCheck
GROUP BY /*CampaignName,*/
ImpressionCheck
ORDER BY /*CampaignName, */
ImpressionCheck;

-- 2. Does clicking on an impression lead to higher purchase rates?
-- Impressions here mean advertisments
/*
Answer: 
Yes, campagin impressions double the purchase rate (85.01% vs. 40.54%)

Campaign users add x3 more items to cart (5.05 vs 1.66 avg items per visit)

Advertisement works well regardless of campaign period (79.84%), meaning
customers still click on campaign ads even when they are not in those
campaigns period; however, every purchase decision hereon is totally driven by
customers and not influenced by those ads because there's no promotions
for their products even when they clicked on those ads.
*/
-- 3. What is the uplift in purchase rate when comparing users who click on a 
-- campaign impression versus users who do not receive an impression? 
-- What if we compare them with users who just an impression but do not click?

WITH     CTE_ImpressionCheck
AS       (SELECT [VisitId]
               , [UserId]
               , [VisitStartTime]
               , [PageViews]
               , [CartAdds]
               , [Purchases]
               , [CampaignName]
               , [Impressions]
               , [Clicks]
               , [CartProducts]
               , CASE WHEN Impressions > 0
                           AND Clicks > 0 THEN 'CampaignImpressionInteracted' WHEN Impressions > 0
                                                                                   AND Clicks = 0 THEN 'NoCampaignImpressionInteracted' ELSE 'NoImpression' END AS ImpressionCheck
          FROM   [CLIQUEBAIT].[cliquebait].[CampaignAnalysis])
,        CTE_Metrics
AS       (SELECT   /* CampaignName,*/
                   ImpressionCheck
                 , COUNT(VisitId) AS VisitsCount
                 , SUM(PageViews) AS TotalPageViews
                 , SUM(CartAdds) AS TotalCartAdds
                 , SUM(Purchases) AS TotalPurchases
                 , SUM(Clicks) AS TotalClicks
                 , SUM(Impressions) AS TotalImpressions
                 , -- If the expression returns 0 then returns NULL for this division
                   FORMAT(CAST (SUM(Clicks) AS FLOAT) / NULLIF (SUM(Impressions), 0), 'P2') AS ClickThroughRate
                 , CAST (SUM(Purchases) AS FLOAT) / COUNT(VisitId) AS RawPurchaseRate
                 , -- Im not multiply by 100 because the value is large and can be misleading
                   -- so i keep the calcualtion under average
                   ROUND(CAST (SUM(CartAdds) AS FLOAT) / COUNT(VisitId), 2) AS AvgCartAddRate
          FROM     CTE_ImpressionCheck
          GROUP BY /*CampaignName,*/
          ImpressionCheck)
SELECT   ImpressionCheck
       , VisitsCount
       , TotalPurchases
       , FORMAT(RawPurchaseRate, 'P2') AS PurchaseRate
       , FORMAT(RawPurchaseRate - MAX(CASE WHEN ImpressionCheck = 'NoImpression' THEN RawPurchaseRate END) OVER (), 'P2') AS UpliftVsNoImpression
FROM     CTE_Metrics
ORDER BY ImpressionCheck;

/*
Users who click on a campaign impression achieved a solid 88.89% in purchase rate
while the purchase rate for users who only receive impressions but do not click 
is off by 23.65% less

Finally, users who did not receive any impression had their purchase rate sitting
at 38.69% which is 50% and 26% less compared to that of ussers who click on a campaign 
impression and users who only receive impressions respectively.
*/
/*
Why I did not use CampaignName <> 'N/A' like before, it's because of how the question
is phrased:
... when comparing users who click on a campaign impression versus 
users who do not receive an impression? 
What if we compare them with users who just an impression but do not click?

As you can see, there are 3 groups that need to be compared:
1. Users who click on a campaign impression
Case 1: Received impression and click at the same time and on 
campagin period
Case 2: Received impression and click at the same time and NOT 
on campaign period
Since this question does not rquires this group to be on 
campagin period so we take both cases for group 1 by
removing CampaignName <> 'N/A'

2. Users who just an impression but do not click
Case 1: Received impression and do not click at the same time
and on campaign period.
Case 2: Received impression and do not click at the same time
and NOT on campaign period.
Same as the case above, we take both cases

3. Users who do not receive an impression?
Just no impressions received

Overall, customers whose visits do not belong to any campaign
will be treated the same as the ones whose visits are belong
to one or more campaign. To be more specific, both case 2s
of scenario 1 and 2 has covered all for this group except
when customers in this group do not receive an impression
and which is covered by scenario 3 along with customers
who in campaign and not received any impressions.

In order for the CampaignName <> 'N/A' to be true then the question
has to be phrased as "Compare users who received impressions DURING 
a campaign period vs those who received no campaign impression"
*/
-- 4. What metrics can you use to quantify the success or failure of each campaign 
-- compared to eachother?
/*
There are 3 main metrics: Click Through Rate, Purchase Rate, Average Cart Add Rate
Click Through Rate is the main metric to show customers interactions when they
see a campaign ad, this metric is later used to know if customers prefer the
campagin or not or in other words, if they find the campaign interesting

Purchase Rate is the second metric to show customers commitment to the
campaign, they not only take interest in the campaign but they also have to 
prove by their actions (i.e. making purchases). If the first metric measures
customers interest on a campaign then this metric here measures that campaign performance

Average Cart Add Rate is used in parallel with the Purchase Rate, this also
measure the customers commitment to a campaign, but it is used to analyze 
cases where customers is intrigued with a campaign, they add a lot of
items into their cart alot but then abandon them at the end or no purchase
actions after these add to cart actions.
*/