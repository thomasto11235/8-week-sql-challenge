
-- 1. How many pizzas were ordered 

SELECT COUNT(pizza_id) AS pizzas_ordered
FROM   customer_orders;

-- 2. How many unique customer orders were made? 

SELECT COUNT(DISTINCT (order_id)) AS unique_customer_order
FROM   customer_orders;

-- 3.How many successful orders were delivered by each runner? 

SELECT   runner_id
       , COUNT(order_id) AS orders_delivered_runner
FROM     runner_orders
WHERE    cancellation IS NULL
GROUP BY runner_id;

-- 4. How many of each type of pizza was delivered? 
SELECT   c.pizza_name
       , COUNT(a.order_id) AS delivered_by_type
FROM     runner_orders AS a
         LEFT OUTER JOIN customer_orders AS b
             ON a.order_id = b.order_id
         INNER JOIN pizza_names AS c
             ON b.pizza_id = c.pizza_id
WHERE    a.cancellation IS NULL
GROUP BY c.pizza_name;

-- 5. How many Vegetarian and Meatlovers were ordered by each customer? 
-- Method 1 

SELECT a.customer_id
     , b.pizza_name
FROM   customer_orders AS a
       INNER JOIN pizza_names AS b
           ON a.pizza_id = b.pizza_id;

-- Method 2 

SELECT   customer_id
       , [Meatlovers]
       , [Vegetarian]
FROM     (SELECT a.order_id
               , a.customer_id
               , b.pizza_name
          FROM   customer_orders AS a
                 INNER JOIN pizza_names AS b
                     ON a.pizza_id = b.pizza_id) AS src PIVOT (COUNT (order_id) FOR pizza_name IN ([Meatlovers], [Vegetarian])) AS pvt
ORDER BY customer_id;

-- Method 3 - Count per pizza type

SELECT 'Pizza_ordered'
     , [Meatlovers]
     , [Vegetarian]
FROM   (SELECT a.order_id
             , b.pizza_name
        FROM   customer_orders AS a
               INNER JOIN pizza_names AS b
                   ON a.pizza_id = b.pizza_id) AS src PIVOT (COUNT (order_id) FOR pizza_name IN ([Meatlovers], [Vegetarian])) AS pvt;

-- 6. What was the maximum number of pizzas delivered in a single order? 
-- Method 1

SELECT MAX(pizza_per_order) AS max_per_order
FROM   (SELECT   a.order_id
               , COUNT(b.order_id) AS pizza_per_order
        FROM     runner_orders AS a
                 LEFT OUTER JOIN customer_orders AS b
                     ON a.order_id = b.order_id
        WHERE    a.cancellation IS NULL
        GROUP BY a.order_id) AS sub_q6;

-- Method 2

WITH   Table1
AS     (SELECT   b.order_id
               , RANK() OVER (ORDER BY COUNT(*) DESC) AS ranking
        FROM     runner_orders AS a
                 LEFT OUTER JOIN customer_orders AS b
                     ON a.order_id = b.order_id
        WHERE    a.cancellation IS NULL
        GROUP BY b.order_id, b.customer_id)
SELECT order_id
     , ranking
FROM   Table1
WHERE  ranking = 1;

-- 7. For each customer, how many delivered pizzas had at least 1 change 
-- and how many had no changes? 
-- Method 1 
-- How many pizzas had no changes for each customer 

SELECT   customer_id
       , COUNT(*) AS no_change_pizzas
FROM     runner_orders AS a
         LEFT OUTER JOIN customer_orders AS b
             ON a.order_id = b.order_id
WHERE    a.cancellation IS NULL
         AND (exclusions IS NULL
              AND extras IS NULL)
GROUP BY customer_id;


-- Method 2 
-- How many pizzas had at least one change for each customer 

SELECT   customer_id
       , COUNT(*) AS one_change_pizzas
FROM     runner_orders AS a
         LEFT OUTER JOIN customer_orders AS b
             ON a.order_id = b.order_id
WHERE    a.cancellation IS NULL
         AND (exclusions IS NOT NULL
              OR extras IS NOT NULL)
GROUP BY customer_id;

SELECT   customer_id
       , SUM(CASE WHEN exclusions IS NULL
                       AND extras IS NULL THEN 1 ELSE 0 END) AS no_change
       , SUM(CASE WHEN exclusions IS NOT NULL
                       OR extras IS NOT NULL THEN 1 ELSE 0 END) AS at_least_one_change
FROM     runner_orders AS a
         LEFT OUTER JOIN customer_orders AS b
             ON a.order_id = b.order_id
WHERE    a.cancellation IS NULL
GROUP BY customer_id;

-- 8. How many pizzas were delivered that had both exclusions and extras? 

SELECT COUNT(*) AS exclusions_and_extra
FROM   runner_orders AS a
       LEFT OUTER JOIN customer_orders AS b
           ON a.order_id = b.order_id
WHERE  a.cancellation IS NULL
       AND (exclusions IS NOT NULL
            AND extras IS NOT NULL);

-- 9. What was the total volume of pizzas ordered for each hour of the day? 

SELECT   DATETRUNC(HOUR, order_time) AS hourly
       , COUNT(*) AS volume_hourly_day
FROM     customer_orders
GROUP BY DATETRUNC(HOUR, order_time);

-- 10. What was the volume of orders for each day of the week? 

SELECT   DATETRUNC(DAY, order_time) AS daily
       , COUNT(*) AS volume_daily_week
FROM     customer_orders
GROUP BY DATETRUNC(DAY, order_time);