-- 1. What day of the week is used for each WeekDate value?

SELECT DISTINCT DATENAME(weekday, WeekDate) AS DayOfTheWeek
FROM   sales.CleanWeeklySales;

-- 2. What range of week numbers are missing from the dataset?

WITH   CTE_DateSeries
AS     (SELECT 1 AS Number
             , DATEFROMPARTS(2026, 1, 1) AS DateSeries
             , NULL AS WeekNumber
        UNION ALL
        SELECT Number + 1
             , DATEADD(day, 1, DateSeries)
             , CASE WHEN (Number + 1) % 7 = 0 THEN (Number + 1) / 7 END
        FROM   CTE_DateSeries
        WHERE  DateSeries < '20261231')
SELECT DISTINCT CS.WeekNumber
FROM   CTE_DateSeries AS CS
WHERE  NOT EXISTS (SELECT *
                   FROM   sales.CleanWeeklySales AS DS
                   WHERE  CS.WeekNumber = DS.WeekNumber)
       AND CS.WeekNumber IS NOT NULL
OPTION (MAXRECURSION 0);

-- 3. How many total transactions were there for each year in the dataset?

SELECT   YEAR(WeekDate) AS TransactionYear
       , SUM(Transactions) AS TotalTransactions
FROM     sales.CleanWeeklySales
GROUP BY YEAR(WeekDate);

-- 4. What is the total sales for each region for each month?
-- If you are using sql server, change the sales column datatype to bigint

SELECT   DATEFROMPARTS(YEAR(WeekDate), MONTH(WeekDate), 1) AS TransactionMonth
       , Region
       , SUM(Sales) AS RegionMonthlySales
FROM     sales.CleanWeeklySales
GROUP BY DATEFROMPARTS(YEAR(WeekDate), MONTH(WeekDate), 1), Region
ORDER BY DATEFROMPARTS(YEAR(WeekDate), MONTH(WeekDate), 1);

-- 5. What is the total count of transactions for each platform

SELECT   [Platform]
       , SUM(Transactions) AS TransactionsCount
FROM     sales.CleanWeeklySales
GROUP BY [Platform];

-- 6. What is the percentage of sales for Retail vs Shopify for each month?
-- Method 1

SELECT   DATEFROMPARTS(YEAR(WeekDate), MONTH(WeekDate), 1) AS TransactionMonth
       , Platform
       , SUM(Sales) AS PlatformMonthlySales
       , SUM(SUM(Sales)) OVER (PARTITION BY DATEFROMPARTS(YEAR(WeekDate), MONTH(WeekDate), 1)) AS MonthlySales
       , FORMAT(CAST (SUM(Sales) AS FLOAT) / SUM(SUM(Sales)) OVER (PARTITION BY DATEFROMPARTS(YEAR(WeekDate), MONTH(WeekDate), 1)), 'P2') AS PlatformContribution
FROM     sales.CleanWeeklySales
GROUP BY DATEFROMPARTS(YEAR(WeekDate), MONTH(WeekDate), 1), Platform
ORDER BY DATEFROMPARTS(YEAR(WeekDate), MONTH(WeekDate), 1);

-- Method 2

WITH     CTE_MonthlyPlatformSales
AS       (SELECT DATEFROMPARTS(YEAR(WeekDate), MONTH(WeekDate), 1) AS TransactionMonth
               , [Platform]
               , Sales
          FROM   sales.CleanWeeklySales)
SELECT   TransactionMonth
       , FORMAT(CAST (SUM(CASE WHEN [Platform] = 'Retail' THEN Sales ELSE 0 END) AS FLOAT) / SUM(Sales), 'P2') AS RetailMonthlySales
       , FORMAT(CAST (SUM(CASE WHEN [Platform] = 'Shopify' THEN Sales ELSE 0 END) AS FLOAT) / SUM(Sales), 'P2') AS ShopifyMonthlySales
FROM     CTE_MonthlyPlatformSales
GROUP BY TransactionMonth;

-- 7. What is the percentage of sales by demographic for each year in the dataset?

SELECT   CalendarYear
       , Demographic
       , SUM(Sales) AS SalesByYearAndDemographic
       , SUM(SUM(Sales)) OVER (PARTITION BY CalendarYear) AS YearlySales
       , FORMAT(CAST (SUM(Sales) AS FLOAT) / SUM(SUM(Sales)) OVER (PARTITION BY CalendarYear), 'P2') AS DemographicContribution
FROM     sales.CleanWeeklySales
GROUP BY CalendarYear, Demographic;

WITH     CTE_YearlyDemographicSales
AS       (SELECT CalendarYear AS TransactionYear
               , Demographic
               , Sales
          FROM   sales.CleanWeeklySales)
SELECT   TransactionYear
       , FORMAT(CAST (SUM(CASE WHEN Demographic = 'Couples' THEN Sales ELSE 0 END) AS FLOAT) / SUM(Sales), 'P2') AS CouplesYearlySales
       , FORMAT(CAST (SUM(CASE WHEN Demographic = 'Families' THEN Sales ELSE 0 END) AS FLOAT) / SUM(Sales), 'P2') AS FamiliesYearlySales
FROM     CTE_YearlyDemographicSales
GROUP BY TransactionYear;

-- Method 2
-- will be updated

-- 8. Which age_band and demographic values contribute the most to Retail sales?

SELECT   AgeBand
       , Demographic
       , SUM(Sales) AS SalesByAgeBandAndDemographic
       , SUM(SUM(Sales)) OVER () AS TotalSales
       , FORMAT(CAST (SUM(Sales) AS FLOAT) / SUM(SUM(Sales)) OVER (), 'P2') AS AgeBandAndDemographicContribution
FROM     sales.CleanWeeklySales
WHERE    [Platform] = 'Retail'
GROUP BY AgeBand, Demographic
ORDER BY CAST (SUM(Sales) AS FLOAT) / SUM(SUM(Sales)) OVER () DESC
OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY;

WITH     CTE_AgeBandAndDemographicSales
AS       (SELECT AgeBand
               , Demographic
               , Sales
          FROM   sales.CleanWeeklySales
          WHERE  [Platform] = 'Retail')
SELECT   AgeBand
       , FORMAT(CAST (SUM(CASE WHEN Demographic = 'Couples' THEN Sales ELSE 0 END) AS FLOAT) / (SELECT SUM(Sales)
                                                                                                FROM   sales.CleanWeeklySales
                                                                                                WHERE  [Platform] = 'Retail'), 'P2') AS CouplesYearlySales
       , FORMAT(CAST (SUM(CASE WHEN Demographic = 'Families' THEN Sales ELSE 0 END) AS FLOAT) / (SELECT SUM(Sales)
                                                                                                 FROM   sales.CleanWeeklySales
                                                                                                 WHERE  [Platform] = 'Retail'), 'P2') AS FamiliesYearlySales
FROM     CTE_AgeBandAndDemographicSales
GROUP BY AgeBand;

-- Method 2
-- will be updated

-- 9. Can we use the avg_transaction column to find the average transaction size 
-- for each year for Retail vs Shopify?. If not - how would you calculate it instead?

SELECT   CalendarYear
       , [Platform]
       , FORMAT(CAST (SUM(Sales) AS DECIMAL) / SUM(Transactions), 'N', 'en-us') AS AvgTransactionSizeByYearAndPlatform
FROM     sales.CleanWeeklySales
GROUP BY CalendarYear, [Platform]
ORDER BY CalendarYear, [Platform];


-- I think we cannot calculate average transaction size by year by using the 
-- AvgTransaction column because that column already calculated the average 
-- transaction size per row or per combination of (WeekDate, WeekNumber, MonthNumber, 
-- CalendarYear, AgeBand, Demographic, Region, Segment, CustomerType) so it would be 
-- inaccurate to take average of that column yearly since it will become average 
-- of average which would be quite weird. In a nutshell, I think we cannot take 
-- a row level calculation and make it a column based aggregation, it is hard to explain 
-- but hope you know what i meant. In other words, we want to calculate average 
-- transaction size by year not average of average of each combination of columns.