-- 1. What is the total amount each customer spent at the restaurant?

SELECT   a.customer_id
       , SUM(b.price) AS total_amount_spent
FROM     sales AS a
         INNER JOIN menu AS b
             ON a.product_id = b.product_id
GROUP BY a.customer_id;

-- 2. How many days has each customer visited the restaurant?

SELECT   customer_id
       , COUNT(DISTINCT (order_date))
FROM     sales
GROUP BY customer_id;

-- 3. What was the first item from the menu purchased by each customer?

SELECT customer_id
     , product_name
FROM   (SELECT customer_id
             , product_name
             , ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date ASC) AS first_item
        FROM   sales AS a
               INNER JOIN menu AS b
                   ON a.product_id = b.product_id) AS sub_q2
WHERE  first_item = 1;

-- 4. What is the most purchased item on the menu and how many times was it purchased by all customers?

SELECT   TOP 1 product_name
             , COUNT(*) AS times_purchased
FROM     sales AS a
         INNER JOIN menu AS b
             ON a.product_id = b.product_id
GROUP BY product_name
ORDER BY times_purchased DESC;

-- 5. Which item was the most popular for each customer?

SELECT customer_id
     , product_name
FROM   (SELECT   customer_id
               , product_name
               , RANK() OVER (PARTITION BY customer_id ORDER BY COUNT(product_name) DESC) AS popular_ranking
        FROM     sales AS a
                 INNER JOIN menu AS b
                     ON a.product_id = b.product_id
        GROUP BY customer_id, product_name) AS sub_q3
WHERE  popular_ranking = 1;

-- 6. Which item was purchased first by the customer after they became a member?

SELECT customer_id
     , product_name
FROM   (SELECT a.customer_id
             , a.order_date
             , c.product_name
             , ROW_NUMBER() OVER (PARTITION BY a.customer_id ORDER BY order_date ASC) AS after_member
        FROM   Sales AS a
               LEFT OUTER JOIN members AS b
                   ON a.customer_id = b.customer_id
               LEFT OUTER JOIN menu AS c
                   ON a.product_id = c.product_id
        WHERE  b.join_date IS NOT NULL
               AND a.order_date >= b.join_date) AS sub_q6
WHERE  after_member = 1;

-- 7. Which item was purchased just before the customer became a member?

SELECT customer_id
     , product_name
FROM   (SELECT a.customer_id
             , a.order_date
             , c.product_name
             , ROW_NUMBER() OVER (PARTITION BY a.customer_id ORDER BY order_date DESC) AS before_member
        FROM   Sales AS a
               LEFT OUTER JOIN members AS b
                   ON a.customer_id = b.customer_id
               LEFT OUTER JOIN menu AS c
                   ON a.product_id = c.product_id
        WHERE  b.join_date IS NOT NULL
               AND a.order_date < b.join_date) AS sub_q7
WHERE  before_member = 1;

-- 8. What is the total items and amount spent for each member before they became a member?

SELECT   a.customer_id
       , COUNT(*) AS total_items_before
       , SUM(price) AS amount_spent_before
FROM     Sales AS a
         LEFT OUTER JOIN members AS b
             ON a.customer_id = b.customer_id
         LEFT OUTER JOIN menu AS c
             ON a.product_id = c.product_id
WHERE    b.join_date IS NOT NULL
         AND a.order_date < b.join_date
GROUP BY a.customer_id;

-- 9.  If each $1 spent equates to 10 points and sushi has a 2x points multiplier 
-- how many points would each customer have?

SELECT   customer_id
       , SUM(CASE WHEN product_name = 'sushi' THEN price * 20 ELSE price * 10 END) AS points
FROM     sales AS a
         INNER JOIN menu AS b
             ON a.product_id = b.product_id
GROUP BY customer_id;

-- 10. In the first week after a customer joins the program 
-- (including their join date) they earn 2x points on all items, not just sushi 
-- - how many points do customer A and B have at the end of January? 

SELECT   a.customer_id
       , SUM(CASE WHEN a.order_date BETWEEN b.join_date AND DATEADD(DAY, 6, b.join_date) THEN price * 20 WHEN product_name = 'sushi' THEN price * 20 ELSE price * 10 END) AS points
FROM     Sales AS a

         LEFT OUTER JOIN members AS b 
             ON a.customer_id = b.customer_id
         LEFT OUTER JOIN menu AS c
             ON a.product_id = c.product_id
WHERE    b.join_date IS NOT NULL
         AND DATEPART(MONTH, a.order_date) = 1
GROUP BY a.customer_id; 