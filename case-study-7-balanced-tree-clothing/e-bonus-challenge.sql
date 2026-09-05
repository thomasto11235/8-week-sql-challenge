-- We can solve this challenge by using a recursive cte
-- to traverse the product hierarchy first then we use
-- 3 times self joins to display the highest granularity

WITH     CTE_TraverseHierarchy
AS       (SELECT Id
               , LevelText
               , LevelName
               , 1 AS Lvl
               , ParentId
          FROM   balancedtree.ProductHierarchy
          WHERE  ParentId IS NULL
          -- AND Id = 1 
          UNION ALL
          SELECT PH.Id
               , PH.LevelText
               , PH.LevelName
               , Lvl + 1
               , TH.Id
          FROM   CTE_TraverseHierarchy AS TH
                 INNER JOIN balancedtree.ProductHierarchy AS PH
                     ON PH.ParentId = TH.Id)
,        CTE_ProductNames
AS       (SELECT TH3.LevelText + ' ' + TH2.LevelText + ' - ' + TH1.LevelText AS ProductName
               , TH1.Id AS CategoryId
               , TH2.Id AS SegmentId
               , TH3.Id AS StyleId
               , TH1.LevelText AS CategoryName
               , TH2.LevelText AS Segmentname
               , TH3.LevelText AS StyleName
          FROM   CTE_TraverseHierarchy AS TH1
                 INNER JOIN CTE_TraverseHierarchy AS TH2
                     ON TH1.Id = TH2.ParentId
                 INNER JOIN CTE_TraverseHierarchy AS TH3
                     ON TH2.Id = TH3.ParentId)
SELECT   PP.ProductId
       , PP.Price
       , PN.ProductName
       , PN.CategoryId
       , PN.SegmentId
       , PN.StyleId
       , PN.CategoryName
       , PN.Segmentname
       , PN.StyleName
FROM     CTE_ProductNames AS PN
         INNER JOIN balancedtree.ProductPrices AS PP
             ON PN.StyleId = PP.Id
ORDER BY ProductId ASC;