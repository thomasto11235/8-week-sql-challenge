-- Rank all the things (Ranking of products bought after customers registered 
-- as a member by order date). Which product was bought first after a customer 
-- became a member?

WITH   table1
AS     (SELECT a.customer_id
             , a.order_date
             , c.product_name
             , c.price
             , CASE WHEN a.order_date >= b.join_date THEN 'Y' ELSE 'N' END AS if_member
        FROM   Sales AS a
               LEFT OUTER JOIN members AS b
                   ON a.customer_id = b.customer_id
               LEFT OUTER JOIN menu AS c
                   ON a.product_id = c.product_id)
SELECT customer_id
     , order_date
     , product_name
     , price
     , if_member
     , CASE WHEN if_member = 'Y' THEN RANK() OVER (PARTITION BY customer_id, if_member ORDER BY order_date ASC) ELSE NULL END AS ranking
FROM   Table1;