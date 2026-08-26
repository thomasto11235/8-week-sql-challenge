-- 5. Generate an alphabetically ordered comma separated ingredient list 
-- for each pizza order from the customer_orders table
-- and add a 2x in front of any relevant ingredients
-- For example: "Meat Lovers: 2xBacon, Beef, ... , Salami"

WITH     CTE_CustOrders
AS       (SELECT o.order_id
               , o.pizza_id
               , exclusions
               , extras
               , ROW_NUMBER() OVER (ORDER BY o.order_id) AS UniqueNum
          FROM   customer_orders AS o
                 INNER JOIN runner_orders AS ro
                     ON o.order_id = ro.order_id
          WHERE  ro.cancellation IS NULL)
,         CTE_A
AS       (SELECT o.order_id
               , o.pizza_id
               , r.toppings
               , exclusions
                -- Concat exclusions to official pizza toppings
               , CONCAT(toppings, CASE WHEN exclusions IS NULL THEN '' ELSE ', ' END, exclusions) AS PreFilter
               , UniqueNum
          FROM   CTE_CustOrders AS o
                 INNER JOIN pizza_recipes AS r
                     ON o.pizza_id = r.pizza_id)
,        CTE_MainList
AS       (-- Select DISTINCT "extra toppings" then add quantity of that extra topping using count
          SELECT DISTINCT order_id
                        , pizza_id
                        , TRIM(TRIM(value)) AS ExtraToppings
                        , t.topping_name
                        , COUNT(TRIM(value)) OVER (PARTITION BY TRIM(value), UniqueNum) AS Cnt
                        , CONCAT(CASE WHEN COUNT(TRIM(value)) OVER (PARTITION BY TRIM(value), UniqueNum) > 1 THEN CONCAT(COUNT(TRIM(value)) OVER (PARTITION BY TRIM(value), UniqueNum), 'x ') ELSE '' END, topping_name) AS MainList
                        , UniqueNum
          FROM   (-- Add extras to the filtered list
                  SELECT sub1.order_id
                       , sub1.pizza_id
                       , sub1.UniqueNum
                       , CONCAT(PostFilter, CASE WHEN extras IS NULL THEN '' ELSE ',' END, extras) AS FilterExtras
                  FROM   (-- Remove exclusions then aggregate the toppings list
                          SELECT   order_id
                                 , pizza_id
                                 , STRING_AGG(MidFilter, ', ') AS PostFilter
                                 , UniqueNum
                          FROM     (-- Count toppings to see exclusions
                                    SELECT order_id
                                         , pizza_id
                                         , PreFilter
                                         , UniqueNum
                                         , value AS MidFilter
                                         , COUNT(*) OVER (PARTITION BY TRIM(value), UniqueNum) AS ToppingsCount
                                    FROM   CTE_A CROSS APPLY STRING_SPLIT (PreFilter, ',')) AS sub
                          WHERE    ToppingsCount = 1
                          GROUP BY order_id, pizza_id, UniqueNum) AS sub1
                         INNER JOIN CTE_CustOrders AS o
                             ON o.order_id = sub1.order_id
                                AND o.pizza_id = sub1.pizza_id
                                AND o.UniqueNum = sub1.UniqueNum) AS sub2 CROSS APPLY STRING_SPLIT (FilterExtras, ',')
                 INNER JOIN pizza_toppings AS t
                     ON TRIM(value) = t.topping_id)
,        CTE_B
AS       (-- Aggregate strings to output a full list with qty indicator
          SELECT   order_id
                 , pizza_id
                 , STRING_AGG(MainList, ', ') AS IngredientsList
                 , UniqueNum
          FROM     CTE_MainList
          GROUP BY order_id, pizza_id, UniqueNum)
SELECT   order_id
       , pizza_id
       , STRING_AGG(Item, ', ') WITHIN GROUP (ORDER BY Split.Item) AS IngredientsList
       , UniqueNum
FROM     CTE_B CROSS APPLY 
         -- Instead of normal string_split, we cross apply the "value" from string_split
         -- to correspondent row so we can order them using within group
         (SELECT TRIM(value) AS Item
          FROM   STRING_SPLIT (IngredientsList, ',')) AS Split
GROUP BY order_id, pizza_id, UniqueNum;

-- 6. What is the total quantity of each ingredient used in all delivered pizzas 
-- sorted by most frequent first?

WITH     CTE_CustOrders
AS       (SELECT o.order_id
               , o.pizza_id
               , exclusions
               , extras
               , ROW_NUMBER() OVER (ORDER BY o.order_id) AS UniqueNum
          FROM   customer_orders AS o
                 INNER JOIN runner_orders AS ro
                     ON o.order_id = ro.order_id
          WHERE  ro.cancellation IS NULL)
,        -- Concat exclusions to official pizza toppings
         CTE_A
AS       (SELECT o.order_id
               , o.pizza_id
               , r.toppings
               , exclusions
               , CONCAT(toppings, CASE WHEN exclusions IS NULL THEN '' ELSE ', ' END, exclusions) AS PreFilter
               , UniqueNum
          FROM   CTE_CustOrders AS o
                 INNER JOIN pizza_recipes AS r
                     ON o.pizza_id = r.pizza_id)
,        CTE_MainList
AS       (-- Select DISTINCT "extra toppings" then add quantity of that extra topping using count
          SELECT order_id
               , pizza_id
               , TRIM(TRIM(value)) AS ExtraToppings
               , t.topping_name
               , COUNT(TRIM(value)) OVER (PARTITION BY TRIM(value), UniqueNum) AS Cnt
               , CONCAT(CASE WHEN COUNT(TRIM(value)) OVER (PARTITION BY TRIM(value), UniqueNum) > 1 THEN CONCAT(COUNT(TRIM(value)) OVER (PARTITION BY TRIM(value), UniqueNum), 'x ') ELSE '' END, topping_name) AS MainList
               , UniqueNum
          FROM   (-- Add extras to the filtered list
                  SELECT sub1.order_id
                       , sub1.pizza_id
                       , sub1.UniqueNum
                       , CONCAT(PostFilter, CASE WHEN extras IS NULL THEN '' ELSE ',' END, extras) AS FilterExtras
                  FROM   (-- Remove exclusions then aggregate the toppings list
                          SELECT   order_id
                                 , pizza_id
                                 , STRING_AGG(MidFilter, ', ') AS PostFilter
                                 , UniqueNum
                          FROM     (-- Count toppings to see exclusions
                                    SELECT order_id
                                         , pizza_id
                                         , PreFilter
                                         , UniqueNum
                                         , value AS MidFilter
                                         , COUNT(*) OVER (PARTITION BY TRIM(value), UniqueNum) AS ToppingsCount
                                    FROM   CTE_A CROSS APPLY STRING_SPLIT (PreFilter, ',')) AS sub
                          WHERE    ToppingsCount = 1
                          GROUP BY order_id, pizza_id, UniqueNum) AS sub1
                         INNER JOIN CTE_CustOrders AS o
                             ON o.order_id = sub1.order_id
                                AND o.pizza_id = sub1.pizza_id
                                AND o.UniqueNum = sub1.UniqueNum) AS sub2 CROSS APPLY STRING_SPLIT (FilterExtras, ',')
                 INNER JOIN pizza_toppings AS t
                     ON TRIM(value) = t.topping_id)
SELECT   topping_name
       , COUNT(*) AS Count
FROM     CTE_MainList
GROUP BY topping_name
ORDER BY COUNT(*) DESC;