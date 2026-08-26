-- 1. How many runners signed up for each 1 week period? (i.e. week starts 2021-01-01)
-- Week starts at Monday --
SET DATEFIRST 1; 

SELECT   COUNT(*)
       , DATEPART(WEEK, registration_date)
FROM     runners
GROUP BY DATEPART(WEEK, registration_date);

-- 2. What was the average time in minutes it took for each runner to arrive 
-- at the Pizza Runner HQ to pickup the order?

SELECT   b.runner_id
       , AVG(DATEDIFF(MINUTE, a.order_time, b.pickup_time)) AS avg_arrival_time
FROM     customer_orders AS a
         INNER JOIN runner_orders AS b
             ON a.order_id = b.order_id
WHERE    b.cancellation IS NULL
GROUP BY b.runner_id;

-- 3. Is there any relationship between the number of pizzas and how long 
-- the order takes to prepare? 

WITH     Table1
AS       (SELECT   a.order_id
                 , COUNT(a.order_id) AS pizza_qty
                 , DATEDIFF(MINUTE, MAX(a.order_time), MAX(b.pickup_time)) AS prep_time_minutes
          FROM     customer_orders AS a
                   INNER JOIN runner_orders AS b
                       ON a.order_id = b.order_id
          WHERE    b.cancellation IS NULL
          GROUP BY a.order_id)
SELECT   pizza_qty
       , AVG(prep_time_minutes) AS avg_prep_time
FROM     Table1
GROUP BY pizza_qty
ORDER BY pizza_qty ASC;

-- There is a correlation between number of pizzas and their prep time

-- 4. What was the average distance travelled for each customer?
-- Replacing 'km', 'minutes' and 'min' with empty string for conversion
UPDATE runner_orders
SET distance = REPLACE(distance, 'km', '');

UPDATE runner_orders
SET duration = REPLACE(duration, 'minutes', '');

UPDATE runner_orders
SET duration = REPLACE(duration, 'mins', '');

UPDATE runner_orders
SET duration = REPLACE(duration, 'minute', '');

-- Cleaning 'null' values 

UPDATE runner_orders
SET pickup_time = NULL 
WHERE pickup_time = 'null' ;

UPDATE runner_orders
SET distance = NULL
WHERE distance = 'null' ;

UPDATE runner_orders
SET duration = NULL
WHERE duration = 'null';

-- Change distance data type to numeric

ALTER TABLE runner_orders
ALTER COLUMN distance numeric(10,2);

-- Double check

SELECT distance
FROM runner_orders
WHERE TRY_CONVERT(numeric(10,2), distance) IS NULL AND distance IS NOT NULL;

SELECT   a.customer_id
       , -- Removing leading zeros by using FORMAT with .NET G29 
         FORMAT(AVG(b.distance), 'G29') AS distance_each_customer
FROM     customer_orders AS a
         INNER JOIN runner_orders AS b
             ON a.order_id = b.order_id
WHERE    b.cancellation IS NULL
GROUP BY a.customer_id;

SELECT   a.customer_id
       , CAST (AVG(b.distance) AS FLOAT) AS distance_each_customer
FROM     customer_orders AS a
         INNER JOIN runner_orders AS b
             ON a.order_id = b.order_id
WHERE    b.cancellation IS NULL
GROUP BY a.customer_id;

-- 5. What was the difference between the longest and shortest delivery times 
-- for all orders?

ALTER TABLE runner_orders ALTER COLUMN duration NUMERIC (10, 2);

SELECT max_delivery_time
     , min_delivery_time
     , FORMAT(max_delivery_time - min_delivery_time, 'G29') AS difference_min_max
FROM   (SELECT MIN(duration) AS min_delivery_time
             , MAX(duration) AS max_delivery_time
        FROM   runner_orders) AS sub_q5;

-- 6. What was the average speed for each runner for each delivery 
-- and do you notice any trend for these values? 

WITH     Table2
AS       (SELECT   a.runner_id
                 , a.order_id
                 , COUNT(*) AS pizza_count
                 , CAST (AVG(a.distance / a.duration * 60) AS NUMERIC (10, 2)) AS speed_km_h
          FROM     runner_orders AS a
                   INNER JOIN customer_orders AS b
                       ON a.order_id = b.order_id
          WHERE    a.cancellation IS NULL
          GROUP BY runner_id, a.order_id)
SELECT   runner_id
       , CAST (AVG(speed_km_h) AS NUMERIC (10, 2)) AS avg_spd_runner
FROM     Table2
GROUP BY runner_id;

-- Runner 1 has the lowest avg speed among other runners while runner 2 
-- has the highest avg speed 

-- 7. What is the successful delivery percentage for each runner? 

SELECT   runner_id
       , SUM(100 * CASE WHEN cancellation IS NULL THEN 1 ELSE 0 END) / COUNT(*) AS success_delivery_rate
FROM     runner_orders
GROUP BY runner_id;