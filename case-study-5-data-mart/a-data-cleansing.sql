CREATE DATABASE DATAMART;


GO
USE DATAMART;


GO
CREATE SCHEMA sales;


GO
-- Create and populate table using flat file import in sql server
-- Check

SELECT WeekDate
     , Region
     , Platform
     , Segment
     , CustomerType
     , Transactions
     , Sales
FROM   sales.WeeklySales;

-- 1. Convert WeekDate to date format

UPDATE  sales.WeeklySales
    SET WeekDate = NULL
WHERE   TRY_CONVERT (DATE, WeekDate, 3) IS NULL;

UPDATE  sales.WeeklySales
    SET WeekDate = CONVERT (VARCHAR (10), CONVERT (DATE, WeekDate, 3), 120)
WHERE   WeekDate IS NOT NULL;

-- CONVERT(date, WeekDate, 3) is to change the varchar data type of the
-- WeekDate column to a date datatype which follows british date formatting
-- Why don't we replace varchar(10) with date instead, so we can save time?
-- The answer is, if we write like that, since the CONVERT function only accept
-- the date style only when the input data type is date and the output data type
-- is varchar or vice versa, therefore same datatypes will get the formatting code
-- to be ignored and so we should convert to varchar(10) first then alter to date.

ALTER TABLE sales.WeeklySales ALTER COLUMN WeekDate DATE;

-- 2. Add a WeekNumber as the second column for each WeekDate value, for example
-- any valuefrom the 1st of January to 7th of January will be 1, 8th to 14th will be 2
-- First day of the week will be Monday

SET DATEFIRST 1;

SELECT   WeekDate
       , DATENAME(weekday, WeekDate) AS WeekDayName
       , DATEPART(week, WeekDate) AS WeekNumber
FROM     sales.WeeklySales
ORDER BY WeekDate;

ALTER TABLE sales.WeeklySales
    ADD WeekNumber INT;

UPDATE  sales.WeeklySales
    SET WeekNumber = DATEPART(week, WeekDate)
WHERE   WeekDate IS NOT NULL;

-- Check
SELECT WeekDate
     , WeekNumber
FROM   sales.WeeklySales;

-- Up to this point, I realized that I was supposed to create a new table
-- and perform these operations in a single query, so im gonna do those
-- again but the above queries still remains valuable.
-- Drop the existing table, then re-import

DROP TABLE IF EXISTS sales.WeeklySales;

-- Check

SELECT *
FROM   sales.WeeklySales;

-- Create CTA
SELECT CONVERT (DATE, WeekDate, 3) AS WeekDate
     , DATEPART(week, CONVERT (DATE, WeekDate, 3)) AS WeekNumber
     , DATEPART(month, CONVERT (DATE, WeekDate, 3)) AS MonthNumber
     , DATEPART(year, CONVERT (DATE, WeekDate, 3)) AS CalendarYear
     , CASE WHEN RIGHT(Segment, 1) = '1' THEN 'Young Adults' WHEN RIGHT(Segment, 1) = '2' THEN 'Middle Aged' WHEN RIGHT(Segment, 1) IN ('3', '4') THEN 'Retirees' ELSE 'Unknown' END AS AgeBand
     , CASE WHEN LEFT(Segment, 1) = 'C' THEN 'Couples' WHEN LEFT(Segment, 1) = 'F' THEN 'Families' ELSE 'Unknown' END AS Demographic
     , CAST (Sales / Transactions AS DECIMAL (38, 2)) AS AvgTransaction
     , Region
     , Platform
     , Segment
     , CustomerType
     , Transactions
     , Sales
INTO   sales.CleanWeeklySales
FROM   sales.WeeklySales;