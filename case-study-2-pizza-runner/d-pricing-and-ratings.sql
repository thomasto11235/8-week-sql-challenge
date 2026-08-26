-- 1. If a Meat Lovers pizza costs $12 and Vegetarian costs $10 
-- and there were no charges for changes - how much money has 
-- Pizza Runner made so far if there are no delivery fees?

WITH   CTE_PizzaPrice
AS     (SELECT co.order_id
             , co.pizza_id
             , CASE WHEN co.pizza_id = 1 THEN 12 ELSE 10 END AS PizzaPrice
        FROM   customer_orders AS co
               INNER JOIN runner_orders AS ro
                   ON co.order_id = ro.order_id
        WHERE  ro.cancellation IS NULL)
SELECT CONCAT('$ ', SUM(PizzaPrice)) AS TtlRevenue
FROM   CTE_PizzaPrice;

-- 2. What if there was an additional $1 charge for any pizza extras?
-- Add cheese is $1 extra

WITH   CTE_PizzaPrice
AS     (SELECT co.order_id
             , co.pizza_id
             , co.extras
             , CASE WHEN co.pizza_id = 1 THEN 12 ELSE 10 END AS PizzaPrice
        FROM   customer_orders AS co
               INNER JOIN runner_orders AS ro
                   ON co.order_id = ro.order_id
        WHERE  ro.cancellation IS NULL)
SELECT COUNT(TRIM(value)) + (SELECT SUM(PizzaPrice)
                             FROM   CTE_PizzaPrice) AS TtlRevenueToppings
FROM   CTE_PizzaPrice CROSS APPLY STRING_SPLIT (extras, ',');

-- 3. The Pizza Runner team now wants to add an additional ratings system 
-- that allows customers to rate their runner, how would you design an 
-- additional table for this new dataset - generate a schema for 
-- this new table and insert your own data for ratings for each 
-- successful customer order between 1 to 5.
/*
CREATE TABLE DeliveryRating (
	Scale int PRIMARY KEY
	, Meaning varchar(100)
	);

INSERT INTO DeliveryRating (Scale, Meaning)
VALUES 
	(1 , 'Excellent')
	, (2, 'Great')
	, (3, 'Could do better')
	, (4, 'Bad')
	, (5, 'Worst');

ALTER TABLE runner_orders
	ADD Rating int
	CONSTRAINT FK_RunnerOrders_1845581613
	FOREIGN KEY REFERENCES DeliveryRating(Scale);
	
*/

-- 4. Using your newly generated table - can you join all of the information 
-- together to form a table which has the following information for successful deliveries?
/*
    customer_id
    order_id
    runner_id
    rating
    order_time
    pickup_time
    Time between order and pickup
    Delivery duration
    Average speed
    Total number of pizzas
*/

WITH   CTE_CusPizza
AS     (SELECT   co.customer_id
               , co.order_id
               , co.order_time
               , ro.pickup_time
               , COUNT(*) AS PizzaCnt
        FROM     customer_orders AS co
                 INNER JOIN runner_orders AS ro
                     ON ro.order_id = co.order_id
        WHERE    ro.cancellation IS NULL
        GROUP BY co.customer_id, co.order_id, ro.pickup_time, co.order_time)
SELECT cp.customer_id
     , cp.order_id
     , ro.runner_id
     , ro.Rating
     , cp.order_time
     , cp.pickup_time
     , DATEDIFF(minute, cp.order_time, cp.pickup_time) AS TimeBetween
     , ro.duration
     , ro.distance
     , CAST (ROUND(ro.distance / duration * 60, 2) AS DECIMAL (10, 2)) AS AvgSpeed
     , cp.PizzaCnt
     , SUM(ro.distance) OVER ()
FROM   CTE_CusPizza AS cp
       INNER JOIN runner_orders AS ro
           ON cp.order_id = ro.order_id;

-- 6. If a Meat Lovers pizza was $12 and Vegetarian $10 fixed prices with no cost for extras 
-- and each runner is paid $0.30 per kilometre traveled - how much money does 
-- Pizza Runner have left over after these deliveries?

WITH   CTE_CusPizza
AS     (SELECT   co.customer_id
               , co.order_id
               , co.order_time
               , ro.pickup_time
               , COUNT(*) AS PizzaCnt
        FROM     customer_orders AS co
                 INNER JOIN runner_orders AS ro
                     ON ro.order_id = co.order_id
        WHERE    ro.cancellation IS NULL
        GROUP BY co.customer_id, co.order_id, ro.pickup_time, co.order_time)
,      CTE_PizzaPrice
AS     (SELECT co.order_id
             , co.pizza_id
             , co.extras
             , CASE WHEN co.pizza_id = 1 THEN 12 ELSE 10 END AS PizzaPrice
        FROM   customer_orders AS co
               INNER JOIN runner_orders AS ro
                   ON co.order_id = ro.order_id
        WHERE  ro.cancellation IS NULL)
SELECT COUNT(TRIM(value)) + (SELECT SUM(PizzaPrice)
                             FROM   CTE_PizzaPrice) - CAST (ROUND((SELECT SUM(ro.distance) * 0.30
                                                                   FROM   CTE_CusPizza AS cp
                                                                          INNER JOIN runner_orders AS ro
                                                                              ON cp.order_id = ro.order_id), 2) AS DECIMAL (10, 2)) AS FinalRevenue
FROM   CTE_PizzaPrice CROSS APPLY STRING_SPLIT (extras, ',');