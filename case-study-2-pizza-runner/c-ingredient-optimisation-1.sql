-- 1. What are the standard ingredients for each pizza?

WITH     CTE_Ingredients
AS       (SELECT r.pizza_id
               , n.pizza_name
               , value AS ToppingsNumber
          FROM   pizza_recipes AS r
                 INNER JOIN pizza_names AS n
                     ON r.pizza_id = n.pizza_id CROSS APPLY STRING_SPLIT (r.toppings, ','))
SELECT   
         pizza_name
       , STRING_AGG(CAST (topping_name AS NVARCHAR (MAX)), ', ') WITHIN GROUP (ORDER BY topping_id ASC) AS StandardIngredients
FROM     CTE_Ingredients AS i
         INNER JOIN pizza_toppings AS t
             ON i.ToppingsNumber = t.topping_id
GROUP BY pizza_name;

/*
Example of String split and agg

WITH Table2 AS (
	SELECT
			a.pizza_id,
			b.pizza_name,
			value AS toppings_number
		FROM pizza_recipes a
		JOIN pizza_names b
		ON a.pizza_id = b.pizza_id
		CROSS APPLY STRING_SPLIT(a.toppings, ',')
	)

	SELECT
		pizza_name,
		STRING_AGG(CONVERT(NVARCHAR(MAX), toppings_number), ',') 
	FROM Table2
	GROUP BY pizza_name

--
-- 2. What was the most commonly added extra? --
SELECT   TOP 1 COUNT(extras) AS most_common_extra
             , value AS extras
FROM     customer_orders CROSS APPLY STRING_SPLIT (extras, ',')
GROUP BY value
ORDER BY most_common_extra DESC;

-- 3. What was the most common exclusion? --
SELECT   TRIM(value) AS Exclusions
       , COUNT(exclusions) AS ExclusionsCount
FROM     customer_orders CROSS APPLY STRING_SPLIT (exclusions, ',')
GROUP BY value
ORDER BY ExclusionsCount DESC;
*/

/*
4. Generate an order item for each record in the customers_orders table in the format of one of the following:
	Meat Lovers
	Meat Lovers - Exclude Beef
	Meat Lovers - Extra Bacon
	Meat Lovers - Exclude Cheese, Bacon - Extra Mushroom, Peppers 
*/

-- Extras

WITH   CTE_Extra
AS     (SELECT   sub.order_id
               , sub.pizza_id
               , STRING_AGG(topping_name, ', ') AS Extras
        FROM     (SELECT DISTINCT order_id
                                , pizza_id
                                , extras
                  FROM   customer_orders AS o) AS sub CROSS APPLY STRING_SPLIT (extras, ',')
                 INNER JOIN pizza_toppings AS t
                     ON TRIM(value) = t.topping_id
                 INNER JOIN pizza_names AS n
                     ON sub.pizza_id = n.pizza_id
        GROUP BY sub.order_id, sub.pizza_id)
, 

-- Exclusisons

       CTE_Exclusions
AS     (SELECT   sub.order_id
               , sub.pizza_id
               , STRING_AGG(topping_name, ', ') AS Exclusions
        FROM     (SELECT DISTINCT order_id
                                , pizza_id
                                , exclusions
                  FROM   customer_orders AS o) AS sub CROSS APPLY STRING_SPLIT (exclusions, ',')
                 INNER JOIN pizza_toppings AS t
                     ON TRIM(value) = t.topping_id
                 INNER JOIN pizza_names AS n
                     ON sub.pizza_id = n.pizza_id
        GROUP BY sub.order_id, sub.pizza_id)

SELECT DISTINCT o.order_id
              , CONCAT(CASE WHEN n.pizza_name = 'Meatlovers' THEN 'Meat Lovers' ELSE n.pizza_name END, CASE WHEN ex.extras IS NULL THEN '' ELSE CONCAT(' - Extra ', ex.extras) END, CASE WHEN esc.exclusions IS NULL THEN '' ELSE CONCAT(' - Exclude ', esc.exclusions) END) AS order_detail
FROM   customer_orders AS o
       LEFT OUTER JOIN CTE_Extra AS ex
           ON o.order_id = ex.order_id
              AND o.pizza_id = ex.pizza_id
       LEFT OUTER JOIN CTE_Exclusions AS esc
           ON o.order_id = esc.order_id
              AND o.pizza_id = esc.pizza_id
       LEFT OUTER JOIN pizza_names AS n
           ON o.pizza_id = n.pizza_id
WHERE  (ex.extras IS NOT NULL
        AND esc.exclusions IS NOT NULL);

-- 5. Generate an alphabetically ordered comma separated ingredient list 
-- for each pizza order from the customer_orders table and 
-- add a 2x in front of any relevant ingredients
-- For example: "Meat Lovers: 2xBacon, Beef, ... , Salami" 

WITH     CTE_Exclude
AS       (SELECT   sub.order_id
                 , sub.pizza_id
                 , STRING_AGG(topping_name, ', ') AS Exclusions
                 , t.topping_id
          FROM     (SELECT DISTINCT order_id
                                  , pizza_id
                                  , exclusions
                    FROM   customer_orders AS o) AS sub CROSS APPLY STRING_SPLIT (exclusions, ',')
                   INNER JOIN pizza_toppings AS t
                       ON TRIM(value) = t.topping_id
                   INNER JOIN pizza_names AS n
                       ON sub.pizza_id = n.pizza_id
          GROUP BY sub.order_id, sub.pizza_id, t.topping_id)
,        CTE_Recipes
AS       (SELECT o.order_id
               , o.pizza_id
               , n.pizza_name
               , r.toppings
               , t.topping_id
          FROM   customer_orders AS o
                 INNER JOIN pizza_names AS n
                     ON o.pizza_id = n.pizza_id
                 INNER JOIN pizza_recipes AS r
                     ON o.pizza_id = r.pizza_id CROSS APPLY STRING_SPLIT (r.toppings, ',')
                 INNER JOIN pizza_toppings AS t
                     ON TRIM(value) = t.topping_id)
,        CTE_Recipes2
AS       (SELECT r.order_id
               , r.pizza_id
               , r.pizza_name
               , r.topping_id
               , e.topping_id AS Flag
          FROM   CTE_Recipes AS r
                 LEFT OUTER JOIN CTE_Exclude AS e
                     ON r.order_id = e.order_id
                        AND r.pizza_id = e.pizza_id
                        AND r.topping_id = e.topping_id)
,        CTE_Recipes3
AS       (SELECT order_id
               , pizza_id
               , topping_id
          FROM   CTE_Recipes2
          WHERE  Flag IS NULL
          UNION ALL
          SELECT sub.order_id
               , sub.pizza_id
               , t.topping_id
          FROM   (SELECT DISTINCT order_id
                                , pizza_id
                                , extras
                  FROM   customer_orders AS o) AS sub CROSS APPLY STRING_SPLIT (extras, ',')
                 INNER JOIN pizza_toppings AS t
                     ON TRIM(value) = t.topping_id
                 INNER JOIN pizza_names AS n
                     ON sub.pizza_id = n.pizza_id)
,        CTE_Recipes4
AS       (SELECT   order_id
                 , pizza_id
                 , r.topping_id
                 , COUNT(r.topping_id) AS ToppingCount
                 , t.topping_name
                 , CASE WHEN COUNT(r.topping_id) > 1 THEN CONCAT(COUNT(r.topping_id), 'x ', topping_name) ELSE topping_name END AS Multiplier
          FROM     CTE_Recipes3 AS r
                   INNER JOIN pizza_toppings AS t
                       ON r.topping_id = t.topping_id
          GROUP BY order_id, pizza_id, r.topping_id, t.topping_name)
SELECT   order_id
       , r.pizza_id
       , pizza_name
       , CASE WHEN pizza_name = 'Meatlovers' THEN CONCAT('Meat Lovers: ', STRING_AGG(Multiplier, ', ') WITHIN GROUP (ORDER BY Multiplier ASC)) ELSE CONCAT(pizza_name, ': ', STRING_AGG(Multiplier, ', ') WITHIN GROUP (ORDER BY Multiplier ASC)) END AS DelimiterList
FROM     CTE_Recipes4 AS r
         INNER JOIN pizza_names AS n
             ON r.pizza_id = n.pizza_id
GROUP BY order_id, r.pizza_id, pizza_name;

-- 6. What is the total quantity of each ingredient used in all delivered pizzas 
-- sorted by most frequent first?

WITH     CTE_Exclude
AS       (SELECT   sub.order_id
                 , sub.pizza_id
                 , STRING_AGG(topping_name, ', ') AS Exclusions
                 , t.topping_id
          FROM     (SELECT DISTINCT order_id
                                  , pizza_id
                                  , exclusions
                    FROM   customer_orders AS o) AS sub CROSS APPLY STRING_SPLIT (exclusions, ',')
                   INNER JOIN pizza_toppings AS t
                       ON TRIM(value) = t.topping_id
                   INNER JOIN pizza_names AS n
                       ON sub.pizza_id = n.pizza_id
          GROUP BY sub.order_id, sub.pizza_id, t.topping_id)
,        CTE_Recipes
AS       (SELECT o.order_id
               , o.pizza_id
               , n.pizza_name
               , r.toppings
               , t.topping_id
          FROM   customer_orders AS o
                 INNER JOIN pizza_names AS n
                     ON o.pizza_id = n.pizza_id
                 INNER JOIN pizza_recipes AS r
                     ON o.pizza_id = r.pizza_id CROSS APPLY STRING_SPLIT (r.toppings, ',')
                 INNER JOIN pizza_toppings AS t
                     ON TRIM(value) = t.topping_id)
,        CTE_Recipes2
AS       (SELECT r.order_id
               , r.pizza_id
               , r.pizza_name
               , r.topping_id
               , e.topping_id AS Flag
          FROM   CTE_Recipes AS r
                 LEFT OUTER JOIN CTE_Exclude AS e
                     ON r.order_id = e.order_id
                        AND r.pizza_id = e.pizza_id
                        AND r.topping_id = e.topping_id)
,        CTE_Recipes3
AS       (SELECT order_id
               , pizza_id
               , topping_id
          FROM   CTE_Recipes2
          WHERE  Flag IS NULL
          UNION ALL
          SELECT sub.order_id
               , sub.pizza_id
               , t.topping_id
          FROM   (SELECT DISTINCT order_id
                                , pizza_id
                                , extras
                  FROM   customer_orders AS o) AS sub CROSS APPLY STRING_SPLIT (extras, ',')
                 INNER JOIN pizza_toppings AS t
                     ON TRIM(value) = t.topping_id
                 INNER JOIN pizza_names AS n
                     ON sub.pizza_id = n.pizza_id)
SELECT   r.topping_id
       , t.topping_name
       , COUNT(r.topping_id) AS ToppingsFrequency
FROM     CTE_Recipes3 AS r
         INNER JOIN runner_orders AS ro
             ON r.order_id = ro.order_id
         INNER JOIN pizza_toppings AS t
             ON r.topping_id = t.topping_id
WHERE    ro.cancellation IS NULL
GROUP BY r.topping_id, t.topping_name
ORDER BY COUNT(r.topping_id) DESC;