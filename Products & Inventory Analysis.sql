
-- REVENUE ANALYSIS AND PROFITABILITY ANALYSIS

-- Monthly trend of revenue, cost, and profit for the past year.
SELECT MONTH(B.delivered_at) AS months,
	   ROUND(SUM((C.retail_price * A.num_of_item)),2) AS revenue,
	   ROUND(SUM((C.cost * A.num_of_item)),2) AS cost,
	   ROUND(SUM((C.retail_price * A.num_of_item) -
	   (C.cost * A.num_of_item)),2) AS profit
FROM orders A
JOIN order_items B
    ON A.order_id = B.order_id
    AND A.status = 'Complete'
JOIN products C
    ON B.product_id = C.id
WHERE YEAR(B.delivered_at) = 2023
GROUP BY YEAR(B.delivered_at), MONTH(B.delivered_at)
ORDER BY YEAR(B.delivered_at), months;


-- Month-Over-Month Revenue Growth.
SELECT 
    YEAR(created_at) AS year, B.month_name,
    FORMAT((SUM(sale_price) - LAG(SUM(sale_price)) OVER (ORDER BY YEAR(created_at), MONTH(created_at))) / 
                              LAG(SUM(sale_price)) OVER (ORDER BY YEAR(created_at), MONTH(created_at)), 'P') AS MoM_growth_pct
FROM order_items A
JOIN date_dim B
    ON YEAR(A.created_at) = B.year
    AND MONTH(A.created_at) = B.month_number
GROUP BY YEAR(created_at), MONTH(created_at), B.month_name;


--  Profit margin for each product category and Rank from highest to lowest.

WITH profit_per_order AS (
    SELECT 
        B.product_id,
        (C.retail_price * A.num_of_item) AS order_price,
        ((C.retail_price * A.num_of_item) - (C.cost * A.num_of_item)) AS profit
    FROM orders A
    JOIN order_items B ON A.order_id = B.order_id AND A.status = 'Complete'
    JOIN products C ON B.product_id = C.id
),
category_profit AS (
    SELECT 
        Y.category, 
        SUM(Z.order_price) AS total_order_price,
        SUM(Z.profit) AS total_profit
    FROM profit_per_order Z
    JOIN products Y ON Z.product_id = Y.id
    GROUP BY Y.category
)
SELECT 
    category, 
    FORMAT((total_order_price - total_profit) / total_order_price, 'P') AS profit_margin,
    DENSE_RANK() OVER (ORDER BY (total_order_price - total_profit) / total_order_price DESC) AS rank
FROM category_profit;

-- INVENTORY OPTIMIZATION

-- STOCK AGING:
-- Identify inventory items that remain unsold for more than 90 days and group them by product category

SELECT product_category, COUNT(id) AS unsold_items_count
FROM (
    SELECT product_category, id, 
	    DATEDIFF(DAY, created_at, COALESCE(sold_at, 
	    (SELECT MAX(sold_at) FROM inventory_items))) AS days_to_sale
    FROM inventory_items
) A
WHERE days_to_sale > 90
GROUP BY product_category
ORDER BY unsold_items_count DESC;

-- STOCK VS SALES ANALYSIS
SELECT 
    product_id, 
    SUM(CASE WHEN sold_at IS NOT NULL AND YEAR(sold_at) = 2023 THEN 1 ELSE 0 END) AS total_sold_2023, 
    COUNT(CASE WHEN YEAR(created_at) < 2024 AND sold_at IS NULL THEN 1 ELSE NULL END) AS unsold_stock,
    COUNT(id) AS total_stock
FROM  inventory_items
GROUP BY product_id
ORDER BY total_sold_2023 DESC;

-- INVENTORY ANALYSIS

WITH cost_of_products AS (
    -- Get the product cost for each product_id (using the first cost found)
    SELECT DISTINCT product_id, FIRST_VALUE(cost) OVER (PARTITION BY product_id ORDER BY product_id) AS product_cost
    FROM inventory_items
), 
begining_inventory_stock AS (
    -- Count the stock for each product_id at the beginning of 2023 (before it was sold)
    SELECT product_id, COUNT(id) AS stock_count
    FROM inventory_items
    WHERE YEAR(created_at) < 2023 AND sold_at IS NULL
    GROUP BY product_id
), 
ending_inventory_stock AS (
    -- Count the stock for each product_id at the end of 2023 (before it was sold)
    SELECT product_id, COUNT(id) AS stock_count
    FROM inventory_items
    WHERE YEAR(created_at) < 2024 AND sold_at IS NULL
    GROUP BY product_id
), 
begining_inventory AS (
    -- Calculate the total value of beginning inventory (stock_count * product_cost)
    SELECT B.product_id, (B.stock_count * C.product_cost) AS begining_inventory_value
    FROM cost_of_products C
    JOIN begining_inventory_stock B ON C.product_id = B.product_id
), 
ending_inventory AS (
    -- Calculate the total value of ending inventory (stock_count * product_cost)
    SELECT B.product_id, (B.stock_count * C.product_cost) AS ending_inventory_value
    FROM cost_of_products C
    JOIN ending_inventory_stock B ON C.product_id = B.product_id
), 
cost_of_goods_sold AS (
    -- Calculate the total cost of goods sold in 2023
    SELECT product_id, SUM(cost) AS total_cost
    FROM inventory_items
    WHERE YEAR(created_at) = 2023 AND sold_at IS NOT NULL
    GROUP BY product_id
)
-- Calculate the inventory turnover ratio (COGS / Average Inventory)
SELECT SUM(total_cost) / (SUM(begining_inventory_value) + SUM(ending_inventory_value) / 2) AS inven_ratio
FROM begining_inventory B
FULL OUTER JOIN ending_inventory E ON B.product_id = E.product_id
FULL OUTER JOIN cost_of_goods_sold C ON E.product_id = C.product_id;

-- SKU LEVEL ANALYSIS
SELECT 
    i.product_sku,
    COUNT(i.sold_at)  AS total_units_sold,  
    SUM(i.product_retail_price) AS total_revenue,  
    SUM(i.product_retail_price - i.cost) AS total_profit,  
    AVG(DATEDIFF(DAY, i.created_at,  i.sold_at)) AS avg_days_to_sell
FROM
    inventory_items i
WHERE 
    sold_at IS NOT NULL
GROUP BY
    i.product_sku
ORDER BY 
    total_profit DESC;