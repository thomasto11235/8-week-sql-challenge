-- Which areas of the business have the highest negative impact in sales metrics 
-- performance in 2020 for the 12 week before and after period?

-- If you are confuse while reading this question, i am too!. After finished reading,
-- I thought that we had to, across all areas, choose one area that has the highest
-- negative impact in sales metric performance in 2020 for the 12 weeks before and after
-- period. If it were like that, I would have no clue how to solve since each areas has 
-- many values in it (i.e. Region has US, EU, ASIA,...) and in order to compare
-- these areas side-by-side in a tabular form, meaning we will have a GROUP BY clause
-- for every segment just to find out that the numbers will be added up to the same amount
-- as the sales in 2020 for the 12 week before and after period. So we should analyze
-- the sales metric for each segment then find the value that has the highest negative
-- impact (like US has the highest negative in the column Region).

/*
In other words, let's take an example with a small dataset containing 3 rows
Before packaging change
Sale | Region | Platform | Amount
1    | Asia   | Retail   | 100
2    | Asia   | Shopify  | 50
3    | Africa | Retail   | 200

After packaging change
Sale | Region | Platform | Before | After | Drop
1    | Asia   | Retail   | 100    | 90    | -10
2    | Asia   | Shopify  | 50     | 45    | -5
3    | Africa | Retail   | 200    | 180   | -20

Now look at each dimension's drop
Region
Asia's drop   = Sale 1 drop + Sale 2 drop
              = -$10        + -$5
              = -$15 total  (-10%)

Africa's drop = Sale 3 drop
              = -$20 total  (-10%)

Platform
Retail's drop  = Sale 1 drop + Sale 3 drop
               = -$10        + -$20
               = -$30 total  (-10%)

Shopify's drop = Sale 2 drop
               = -$5 total   (-10%)

If we pay attention closely, we see that
Sale 1's -$10 appears both in Region and Platform

Now, say, we wanr to compare Asia's sales and Retail's sales altogether:
Asia: -$15
Retail: -$30

Right away, we can see that Retail is the one who has the highest negative;
however, in both groups, sale 1 drop are there, meaning we are comparing two
different aggregations that happen to share Sale 1 and the difference of -$15
comes entirely from Sale 3 (Africa Retail, -$20) minus Sale 2 (Asia Shopify, -$5).

For this question, a valid comparison requires two groups to be mutually exclusive,
no sale should appear in both. If we compare within a dimension, this holds true

Asia   = { Sale1, Sale2 }   
Africa = { Sale3 }          
OR
Retail  = { Sale1, Sale3 }  
Shopify = { Sale2 }         

But if we cross dimensions
Asia   = { Sale1, Sale2 }
Retail = { Sale1, Sale3 }

Then the results will include sale 1 and we cannot tell whether the difference
between the two groups actually reflects a genuine performance difference or
just the weight of the shared sales pulling both numbers in the same direction 
at the same time.

In a nutshell, the comparison, in this case, only valid if the two dimensions 
-- happen to be perfectly independent, meaning no value from one dimension ever 
-- co-occurs with any value from the other dimension in the same row
*/

-- Region

WITH     CTE_SalesByWeekNumberAndYear
AS       (SELECT   CalendarYear
                 , WeekNumber
                 , Region
                 , SUM(Sales) AS SalesByWeekNumberAndYear
          FROM     sales.CleanWeeklySales
          WHERE    WeekNumber BETWEEN 13 AND 36
                   AND WeekDate BETWEEN '20200101' AND '20201231'
          GROUP BY WeekNumber, CalendarYear, Region)
,        CTE_12WeeksSalesBeforeAndAfter
AS       (SELECT   Region
                 , CalendarYear
                 , SUM(CASE WHEN WeekNumber BETWEEN 13 AND 24 THEN SalesByWeekNumberAndYear END) AS BeforeSalesByRegionAndYear
                 , SUM(CASE WHEN WeekNumber BETWEEN 25 AND 36 THEN SalesByWeekNumberAndYear END) AS AfterSalesByRegionAndYear
          FROM     CTE_SalesByWeekNumberAndYear
          GROUP BY CalendarYear, Region)
SELECT   Region
       , BeforeSalesByRegionAndYear AS TwelveWeeksBefore
       , AfterSalesByRegionAndYear AS TwelveWeeksAfter
       , AfterSalesByRegionAndYear - BeforeSalesByRegionAndYear AS SalesVariance
       , FORMAT(CAST ((AfterSalesByRegionAndYear - BeforeSalesByRegionAndYear) AS FLOAT) / BeforeSalesByRegionAndYear, 'P2') AS VariancePercentage
FROM     CTE_12WeeksSalesBeforeAndAfter
WHERE    CAST ((AfterSalesByRegionAndYear - BeforeSalesByRegionAndYear) AS FLOAT) / BeforeSalesByRegionAndYear < 0
ORDER BY VariancePercentage DESC
OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY;

-- From this point onwards, im not gonna change column aliases again cause im lazy :)
-- Platform

WITH     CTE_SalesByWeekNumberAndYear
AS       (SELECT   CalendarYear
                 , WeekNumber
                 , [Platform]
                 , SUM(Sales) AS SalesByWeekNumberAndYear
          FROM     sales.CleanWeeklySales
          WHERE    WeekNumber BETWEEN 13 AND 36
                   AND WeekDate BETWEEN '20200101' AND '20201231'
          GROUP BY WeekNumber, CalendarYear, [Platform])
,        CTE_12WeeksSalesBeforeAndAfter
AS       (SELECT   [Platform]
                 , CalendarYear
                 , SUM(CASE WHEN WeekNumber BETWEEN 13 AND 24 THEN SalesByWeekNumberAndYear END) AS BeforeSalesByRegionAndYear
                 , SUM(CASE WHEN WeekNumber BETWEEN 25 AND 36 THEN SalesByWeekNumberAndYear END) AS AfterSalesByRegionAndYear
          FROM     CTE_SalesByWeekNumberAndYear
          GROUP BY CalendarYear, [Platform])
SELECT   [Platform]
       , BeforeSalesByRegionAndYear AS TwelveWeeksBefore
       , AfterSalesByRegionAndYear AS TwelveWeeksAfter
       , AfterSalesByRegionAndYear - BeforeSalesByRegionAndYear AS SalesVariance
       , FORMAT(CAST ((AfterSalesByRegionAndYear - BeforeSalesByRegionAndYear) AS FLOAT) / BeforeSalesByRegionAndYear, 'P2') AS VariancePercentage
FROM     CTE_12WeeksSalesBeforeAndAfter
WHERE    CAST ((AfterSalesByRegionAndYear - BeforeSalesByRegionAndYear) AS FLOAT) / BeforeSalesByRegionAndYear < 0
ORDER BY VariancePercentage DESC
OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY;

-- AgeBand

WITH     CTE_SalesByWeekNumberAndYear
AS       (SELECT   CalendarYear
                 , WeekNumber
                 , AgeBand
                 , SUM(Sales) AS SalesByWeekNumberAndYear
          FROM     sales.CleanWeeklySales
          WHERE    WeekNumber BETWEEN 13 AND 36
                   AND WeekDate BETWEEN '20200101' AND '20201231'
          GROUP BY WeekNumber, CalendarYear, AgeBand)
,        CTE_12WeeksSalesBeforeAndAfter
AS       (SELECT   AgeBand
                 , CalendarYear
                 , SUM(CASE WHEN WeekNumber BETWEEN 13 AND 24 THEN SalesByWeekNumberAndYear END) AS BeforeSalesByRegionAndYear
                 , SUM(CASE WHEN WeekNumber BETWEEN 25 AND 36 THEN SalesByWeekNumberAndYear END) AS AfterSalesByRegionAndYear
          FROM     CTE_SalesByWeekNumberAndYear
          GROUP BY CalendarYear, AgeBand)
SELECT   AgeBand
       , BeforeSalesByRegionAndYear AS TwelveWeeksBefore
       , AfterSalesByRegionAndYear AS TwelveWeeksAfter
       , AfterSalesByRegionAndYear - BeforeSalesByRegionAndYear AS SalesVariance
       , FORMAT(CAST ((AfterSalesByRegionAndYear - BeforeSalesByRegionAndYear) AS FLOAT) / BeforeSalesByRegionAndYear, 'P2') AS VariancePercentage
FROM     CTE_12WeeksSalesBeforeAndAfter
WHERE    CAST ((AfterSalesByRegionAndYear - BeforeSalesByRegionAndYear) AS FLOAT) / BeforeSalesByRegionAndYear < 0
ORDER BY VariancePercentage DESC
OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY;

-- Demographic

WITH     CTE_SalesByWeekNumberAndYear
AS       (SELECT   CalendarYear
                 , WeekNumber
                 , Demographic
                 , SUM(Sales) AS SalesByWeekNumberAndYear
          FROM     sales.CleanWeeklySales
          WHERE    WeekNumber BETWEEN 13 AND 36
                   AND WeekDate BETWEEN '20200101' AND '20201231'
          GROUP BY WeekNumber, CalendarYear, Demographic)
,        CTE_12WeeksSalesBeforeAndAfter
AS       (SELECT   Demographic
                 , CalendarYear
                 , SUM(CASE WHEN WeekNumber BETWEEN 13 AND 24 THEN SalesByWeekNumberAndYear END) AS BeforeSalesByRegionAndYear
                 , SUM(CASE WHEN WeekNumber BETWEEN 25 AND 36 THEN SalesByWeekNumberAndYear END) AS AfterSalesByRegionAndYear
          FROM     CTE_SalesByWeekNumberAndYear
          GROUP BY CalendarYear, Demographic)
SELECT   Demographic
       , BeforeSalesByRegionAndYear AS TwelveWeeksBefore
       , AfterSalesByRegionAndYear AS TwelveWeeksAfter
       , AfterSalesByRegionAndYear - BeforeSalesByRegionAndYear AS SalesVariance
       , FORMAT(CAST ((AfterSalesByRegionAndYear - BeforeSalesByRegionAndYear) AS FLOAT) / BeforeSalesByRegionAndYear, 'P2') AS VariancePercentage
FROM     CTE_12WeeksSalesBeforeAndAfter
WHERE    CAST ((AfterSalesByRegionAndYear - BeforeSalesByRegionAndYear) AS FLOAT) / BeforeSalesByRegionAndYear < 0
ORDER BY VariancePercentage DESC
OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY;

-- CustomerType

WITH     CTE_SalesByWeekNumberAndYear
AS       (SELECT   CalendarYear
                 , WeekNumber
                 , CustomerType
                 , SUM(Sales) AS SalesByWeekNumberAndYear
          FROM     sales.CleanWeeklySales
          WHERE    WeekNumber BETWEEN 13 AND 36
                   AND WeekDate BETWEEN '20200101' AND '20201231'
          GROUP BY WeekNumber, CalendarYear, CustomerType)
,        CTE_12WeeksSalesBeforeAndAfter
AS       (SELECT   CustomerType
                 , CalendarYear
                 , SUM(CASE WHEN WeekNumber BETWEEN 13 AND 24 THEN SalesByWeekNumberAndYear END) AS BeforeSalesByRegionAndYear
                 , SUM(CASE WHEN WeekNumber BETWEEN 25 AND 36 THEN SalesByWeekNumberAndYear END) AS AfterSalesByRegionAndYear
          FROM     CTE_SalesByWeekNumberAndYear
          GROUP BY CalendarYear, CustomerType)
SELECT   CustomerType
       , BeforeSalesByRegionAndYear AS TwelveWeeksBefore
       , AfterSalesByRegionAndYear AS TwelveWeeksAfter
       , AfterSalesByRegionAndYear - BeforeSalesByRegionAndYear AS SalesVariance
       , FORMAT(CAST ((AfterSalesByRegionAndYear - BeforeSalesByRegionAndYear) AS FLOAT) / BeforeSalesByRegionAndYear, 'P2') AS VariancePercentage
FROM     CTE_12WeeksSalesBeforeAndAfter
WHERE    CAST ((AfterSalesByRegionAndYear - BeforeSalesByRegionAndYear) AS FLOAT) / BeforeSalesByRegionAndYear < 0
ORDER BY VariancePercentage DESC
OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY;