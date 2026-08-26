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
-- impact for these period (like US has the highest negative in the column Region)

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


-- In a nutshell, areas are different dimensions as they are in different levels 
-- and measure different metrics so we cannot go and compare sales variance 
-- of Asia to sales variance of Retail, that would be weird.