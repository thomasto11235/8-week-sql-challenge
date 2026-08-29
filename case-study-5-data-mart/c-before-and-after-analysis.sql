CREATE CLUSTERED COLUMNSTORE INDEX IXC_CleanWeeklySales
    ON sales.CleanWeeklySales;

-- 1. What is the total sales for the 4 weeks before and after 2020-06-15? 
-- What is the growth or reduction rate in actual values and percentage 
-- of sales?

WITH   CTE_4WeeksBeforeAndAfter
AS     (SELECT SUM(Sales) AS SalesBefore
             , (SELECT SUM(Sales)
                FROM   sales.CleanWeeklySales
                WHERE  WeekNumber BETWEEN DATEPART(week, '20200615') AND DATEPART(week, '20200615') + 3
                       AND CalendarYear = 2020) AS SalesAfter
        FROM   sales.CleanWeeklySales
        WHERE  WeekNumber BETWEEN DATEPART(week, '20200615') - 4 AND DATEPART(week, '20200615') - 1
               AND CalendarYear = 2020)
SELECT SalesAfter - SalesBefore AS SalesVariance
     , FORMAT(CAST ((SalesAfter - SalesBefore) AS FLOAT) / SalesBefore, 'P2') AS VariancePercentage
FROM   CTE_4WeeksBeforeAndAfter;

-- 2. What about the entire 12 weeks before and after?

-- As we run the above query, we know that the baseline WeekDate belongs
-- to week number 25 of year 2020, if we expand from -4 to -12 and hold
-- the year still, we see that there's only from week number 21 to 24 
-- at most (only 4 weeks). So, if we want to get 12 entire weeks, we have
-- to take another 8 weeks from the previous year 2019; however; this would
-- be hard to implement since i dont know if 8 weeks must be in consecutive order
-- or just has to be in total of 8 weeks?

WITH   CTE_12WeeksBeforeAndAfter
AS     (SELECT SUM(Sales) AS SalesBefore
             , (SELECT SUM(Sales)
                FROM   sales.CleanWeeklySales
                WHERE  WeekNumber BETWEEN DATEPART(week, '20200615') AND DATEPART(week, '20200615') + 11
                       AND CalendarYear = 2020) AS SalesAfter
        FROM   sales.CleanWeeklySales
        WHERE  WeekNumber BETWEEN DATEPART(week, '20200615') - 12 AND DATEPART(week, '20200615') - 1
               AND CalendarYear = 2020)
SELECT SalesAfter - SalesBefore AS SalesVariance
     , FORMAT(CAST ((SalesAfter - SalesBefore) AS FLOAT) / SalesBefore, 'P2') AS VariancePercentage
FROM   CTE_12WeeksBeforeAndAfter;

-- 3. How do the sale metrics for these 2 periods before and after 
-- compare with the previous years in 2018 and 2019?

-- 3.1 First, find the sales difference 4 weeks before and 4 weeks after
-- for all of the years

-- First Method

WITH   CTE_SalesByWeekNumberAndYear
AS     (SELECT   CalendarYear
               , WeekNumber
               , SUM(Sales) AS SalesByWeekNumberAndYear
        FROM     sales.CleanWeeklySales
        WHERE    WeekNumber BETWEEN 21 AND 28
                 AND CalendarYear = 2020
        GROUP BY WeekNumber, CalendarYear)
,      CTE_4WeeksSalesBeforeAndAfter
AS     (SELECT   CalendarYear
               , SUM(CASE WHEN WeekNumber BETWEEN 21 AND 24 THEN SalesByWeekNumberAndYear END) AS BeforeSalesByWeekNumberAndYear
               , SUM(CASE WHEN WeekNumber BETWEEN 25 AND 28 THEN SalesByWeekNumberAndYear END) AS AfterSalesByWeekNumberAndYear
        FROM     CTE_SalesByWeekNumberAndYear
        GROUP BY CalendarYear)
SELECT CalendarYear
     , AfterSalesByWeekNumberAndYear - BeforeSalesByWeekNumberAndYear AS SalesVariance
     , FORMAT(CAST ((AfterSalesByWeekNumberAndYear - BeforeSalesByWeekNumberAndYear) AS FLOAT) / BeforeSalesByWeekNumberAndYear, 'P2') AS VariancePercentage
FROM   CTE_4WeeksSalesBeforeAndAfter;

-- Second Method

WITH   CTE_AllYears4WeeksBeforeAndAfter
AS     (SELECT   CalendarYear
               , SUM(CASE WHEN WeekNumber BETWEEN DATEPART(week, DATEFROMPARTS(YEAR(WeekDate), 6, 15)) - 4 AND DATEPART(week, DATEFROMPARTS(YEAR(WeekDate), 6, 15)) - 1 THEN Sales END) AS SalesBefore
               , SUM(CASE WHEN WeekNumber BETWEEN DATEPART(week, DATEFROMPARTS(YEAR(WeekDate), 6, 15)) AND DATEPART(week, DATEFROMPARTS(YEAR(WeekDate), 6, 15)) + 3 THEN Sales END) AS SalesAfter
        FROM     sales.CleanWeeklySales
        GROUP BY CalendarYear)
SELECT CalendarYear
     , SalesAfter - SalesBefore AS SalesVariance
     , FORMAT(CAST ((SalesAfter - SalesBefore) AS FLOAT) / SalesBefore, 'P2') AS VariancePercentage
FROM   CTE_AllYears4WeeksBeforeAndAfter;

-- 3.2 Next, find the sales difference 12 weeks before and 12 weeks after
-- for all of the years

-- First Method

WITH   CTE_SalesByWeekNumberAndYear
AS     (SELECT   CalendarYear
               , WeekNumber
               , SUM(Sales) AS SalesByWeekNumberAndYear
        FROM     sales.CleanWeeklySales
        WHERE    WeekNumber BETWEEN 13 AND 36
        GROUP BY WeekNumber, CalendarYear)
,      CTE_12WeeksSalesBeforeAndAfter
AS     (SELECT   CalendarYear
               , SUM(CASE WHEN WeekNumber BETWEEN 13 AND 24 THEN SalesByWeekNumberAndYear END) AS BeforeSalesByWeekNumberAndYear
               , SUM(CASE WHEN WeekNumber BETWEEN 25 AND 36 THEN SalesByWeekNumberAndYear END) AS AfterSalesByWeekNumberAndYear
        FROM     CTE_SalesByWeekNumberAndYear
        GROUP BY CalendarYear)
SELECT CalendarYear
     , AfterSalesByWeekNumberAndYear - BeforeSalesByWeekNumberAndYear AS SalesVariance
     , FORMAT(CAST ((AfterSalesByWeekNumberAndYear - BeforeSalesByWeekNumberAndYear) AS FLOAT) / BeforeSalesByWeekNumberAndYear, 'P2') AS VariancePercentage
FROM   CTE_12WeeksSalesBeforeAndAfter;

-- Second method

WITH   CTE_AllYears12WeeksBeforeAndAfter
AS     (SELECT   CalendarYear
               , SUM(CASE WHEN WeekNumber BETWEEN DATEPART(week, DATEFROMPARTS(YEAR(WeekDate), 6, 15)) - 12 AND DATEPART(week, DATEFROMPARTS(YEAR(WeekDate), 6, 15)) - 1 THEN Sales END) AS SalesBefore
               , SUM(CASE WHEN WeekNumber BETWEEN DATEPART(week, DATEFROMPARTS(YEAR(WeekDate), 6, 15)) AND DATEPART(week, DATEFROMPARTS(YEAR(WeekDate), 6, 15)) + 11 THEN Sales END) AS SalesAfter
        FROM     sales.CleanWeeklySales
        GROUP BY CalendarYear)
SELECT CalendarYear
     , SalesAfter - SalesBefore AS SalesVariance
     , FORMAT(CAST ((SalesAfter - SalesBefore) AS FLOAT) / SalesBefore, 'P2') AS VariancePercentage
FROM   CTE_AllYears12WeeksBeforeAndAfter;

SELECT DATEPART(week, '20281228')
     , DATENAME(weekday, '20280101')
     , DATENAME(weekday, '20190101');

-- Method 3

WITH   CTE_YearlyPivotPoint
AS     (SELECT   CalendarYear
               , MAX(WeekDate) AS PivotDate
               , DATEPART(week, MAX(WeekDate)) AS PivotWeekNumber
        FROM     sales.CleanWeeklySales
        WHERE    DAY(WeekDate) <= 15
                 AND MONTH(WeekDate) = 6
        GROUP BY CalendarYear)
,      CTE_StatusOfSales
AS     (SELECT CWS.CalendarYear
             , CWS.WeekDate
             , YPP.PivotDate
             , CWS.WeekNumber
             , YPP.PivotWeekNumber
             , CASE WHEN DATEPART(week, CWS.WeekDate) BETWEEN YPP.PivotWeekNumber AND YPP.PivotWeekNumber + 11 THEN 'After' WHEN DATEPART(week, CWS.WeekDate) BETWEEN YPP.PivotWeekNumber - 12 AND YPP.PivotWeekNumber - 1 THEN 'Before' ELSE NULL END AS StatusOfSales
             , CWS.Sales
        FROM   CTE_YearlyPivotPoint AS YPP
               INNER JOIN sales.CleanWeeklySales AS CWS
                   ON YPP.CalendarYear = CWS.CalendarYear)
,      CTE_PreNormalisedSales
AS     (SELECT   CalendarYear
               , PivotDate
               , COUNT(DISTINCT CASE WHEN StatusOfSales = 'Before' THEN WeekNumber END) AS WeeksBeforePivot
               , COUNT(DISTINCT CASE WHEN StatusOfSales = 'After' THEN WeekNumber END) AS WeeksAfterPivot
               , SUM(CASE WHEN StatusOfSales = 'Before' THEN Sales END) AS SalesBefore
               , SUM(CASE WHEN StatusOfSales = 'After' THEN Sales END) AS SalesAfter
        FROM     CTE_StatusOfSales
        GROUP BY CalendarYear, PivotDate)
,      CTE_NormalisedSales
AS     (SELECT CalendarYear
             , PivotDate
             , WeeksBeforePivot
             , WeeksAfterPivot
             , (CAST (SalesBefore AS FLOAT) / WeeksBeforePivot) * 12 AS NormalisedSalesBefore
             , (CAST (SalesAfter AS FLOAT) / WeeksAfterPivot) * 12 AS NormalisedSalesAfter
             , ((CAST (SalesAfter AS FLOAT) / WeeksAfterPivot) * 12) - ((CAST (SalesBefore AS FLOAT) / WeeksBeforePivot) * 12) AS Variance
             , (((CAST (SalesAfter AS FLOAT) / WeeksAfterPivot) * 12) - ((CAST (SalesBefore AS FLOAT) / WeeksBeforePivot) * 12)) / ((CAST (SalesBefore AS FLOAT) / WeeksBeforePivot) * 12) AS VariancePercentage
        FROM   CTE_PreNormalisedSales)
SELECT CalendarYear
     , PivotDate
     , WeeksBeforePivot
     , WeeksAfterPivot
     , CAST (ROUND(NormalisedSalesBefore, 0) AS BIGINT) AS TwelveWeeksBeforeEquivalent
     , CAST (ROUND(NormalisedSalesAfter, 0) AS BIGINT) AS TwelveWeeksAfterEquivalent
     , CAST (ROUND(Variance, 0) AS BIGINT) AS TwelveWeeksVariance
     , FORMAT(VariancePercentage, 'P2') AS TwelveWeeksPercentage
FROM   CTE_NormalisedSales;

-- Method 4

WITH   CTE_PreNormalisedSales
AS     (SELECT   CalendarYear
               , COUNT(DISTINCT CASE WHEN WeekNumber BETWEEN DATEPART(week, DATEFROMPARTS(CalendarYear, 6, 15)) - 12 AND DATEPART(week, DATEFROMPARTS(CalendarYear, 6, 15)) - 1 THEN WeekNumber END) AS WeeksBeforePivot
               , COUNT(DISTINCT CASE WHEN WeekNumber BETWEEN DATEPART(week, DATEFROMPARTS(CalendarYear, 6, 15)) AND DATEPART(week, DATEFROMPARTS(CalendarYear, 6, 15)) + 11 THEN WeekNumber END) AS WeeksAfterPivot
               , SUM(CASE WHEN WeekNumber BETWEEN DATEPART(week, DATEFROMPARTS(CalendarYear, 6, 15)) - 12 AND DATEPART(week, DATEFROMPARTS(CalendarYear, 6, 15)) - 1 THEN Sales END) AS SalesBefore
               , SUM(CASE WHEN WeekNumber BETWEEN DATEPART(week, DATEFROMPARTS(CalendarYear, 6, 15)) AND DATEPART(week, DATEFROMPARTS(CalendarYear, 6, 15)) + 11 THEN Sales END) AS SalesAfter
        FROM     sales.CleanWeeklySales
        GROUP BY CalendarYear)
,      CTE_NormalisedSales
AS     (SELECT CalendarYear
             , WeeksBeforePivot
             , WeeksAfterPivot
             , SalesBefore
             , SalesAfter
             , CAST (SalesBefore AS FLOAT) / WeeksBeforePivot * 12 AS SalesBeforeNormalised
             , CAST (SalesAfter AS FLOAT) / WeeksAfterPivot * 12 AS SalesAfterNormalised
             , (CAST (SalesAfter AS FLOAT) / WeeksAfterPivot * 12) - (CAST (SalesBefore AS FLOAT) / WeeksBeforePivot * 12) AS SalesVariance
             , ((CAST (SalesAfter AS FLOAT) / WeeksAfterPivot * 12) - (CAST (SalesBefore AS FLOAT) / WeeksBeforePivot * 12)) / (CAST (SalesBefore AS FLOAT) / WeeksBeforePivot * 12) AS SalesVariancePercentage
        FROM   CTE_PreNormalisedSales)
SELECT CalendarYear
     , WeeksBeforePivot
     , WeeksAfterPivot
     , CAST (ROUND(SalesBeforeNormalised, 0) AS BIGINT) AS TwelveWeeksBeforeEquivalent
     , CAST (ROUND(SalesAfterNormalised, 0) AS BIGINT) AS TwelveWeeksAfterEquivalent
     , CAST (ROUND(SalesVariance, 0) AS BIGINT) AS TwelveWeeksVariance
     , FORMAT(SalesVariancePercentage, 'P2') AS TwelveWeeksPercentage
FROM   CTE_NormalisedSales;