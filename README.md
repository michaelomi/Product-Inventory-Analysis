# 📊 Revenue, Profitability, & Inventory Analysis

### 🚀 Executive Summary
This project analyzes the 2023 performance of an e-commerce store, focusing on revenue, profitability, and inventory optimization. Using SQL queries, I derived insights from revenue trends, profit margins, inventory turnover, and SKU-level performance to identify strengths and areas for improvement. Recommendations are provided to enhance profitability and streamline operations.

## 1. 💰 Revenue and Profitability Analysis

### 1.1 📈 Monthly Revenue, Cost, and Profit Trends (2023)
- **Revenue Growth**: Revenue grew from $133,736 (Jan) to $328,957 (Dec), a 146% increase.
- **Profit Trend**: Profit rose from $70,124 to $170,789, maintaining a consistent 51-53% margin.
- **Peak Month**: December 2023 ($328,957 revenue, $170,789 profit) 📅.
- **Challenges**: Revenue dips in February (-14.6%) and April (-6.4%) indicate potential seasonality or operational issues ⚠️.
```sql
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
```

### 1.2 📊 Month-Over-Month Revenue Growth
- **Strong Growth**: March (33.1%), July (18.9%), October (17.0%), and December (27.7%) 🚀.
- **Declines**: February (-14.6%) and April (-6.4%) highlight seasonal or operational challenges 📉.
- **Trend**: Positive average growth in 2023, with Q4 showing significant momentum.
```sql
SELECT 
    YEAR(created_at) AS year, B.month_name,
    FORMAT((SUM(sale_price) - LAG(SUM(sale_price)) OVER (ORDER BY YEAR(created_at), MONTH(created_at))) / 
                              LAG(SUM(sale_price)) OVER (ORDER BY YEAR(created_at), MONTH(created_at)), 'P') AS MoM_growth_pct
FROM order_items A
JOIN date_dim B
    ON YEAR(A.created_at) = B.year
    AND MONTH(A.created_at) = B.month_number
GROUP BY YEAR(created_at), MONTH(created_at), B.month_name;
```

### 1.3 🏆 Profit Margin by Product Category
- **Top Categories**:
  - Clothing Sets: 62.55% (Rank 1) 👕
  - Suits: 60.48% (Rank 2) 🧥
  - Socks: 60.28% (Rank 3) 🧦
- **Insight**: High-margin categories should drive marketing and inventory strategies.
```sql
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
```

## 2. 📦 Inventory Optimization

### 2.1 ⏳ Stock Aging Analysis
- **Slow-Moving Stock**: Intimates and Jeans have the highest unsold items (>90 days) 🛒.
- **Implication**: Overstocking ties up capital, requiring targeted promotions to clear inventory.
```sql
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
```

### 2.2 📋 Stock vs. Sales Analysis
- **Key Products**:
  - Product ID 17045: 14 sold, 32 unsold (51 total stock).
  - Product ID 25547: 12 sold, 30 unsold (48 total stock).
  - Product ID 18795: 12 sold, 37 unsold (58 total stock).
- **Insight**: High unsold stock indicates overstocking or low demand for specific products 📉.
```sql
SELECT 
    product_id, 
    SUM(CASE WHEN sold_at IS NOT NULL AND YEAR(sold_at) = 2023 THEN 1 ELSE 0 END) AS total_sold_2023, 
    COUNT(CASE WHEN YEAR(created_at) < 2024 AND sold_at IS NULL THEN 1 ELSE NULL END) AS unsold_stock,
    COUNT(id) AS total_stock
FROM  inventory_items
GROUP BY product_id
ORDER BY total_sold_2023 DESC;
```

### 2.3 🔄 Inventory Turnover Ratio
- **Result**: 0.242 (low compared to industry benchmarks of 4-6).
- **Implication**: Slow inventory movement suggests inefficiencies in stock management ⚠️.
```sql
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
```

### 2.4 🔍 SKU-Level Analysis
- **Top SKUs**:
  - SKU 07E99F116B916656B3FD4F7DD58A3CBE: 15 units, $13,545 revenue, $7,246 profit, 35 days to sell 🥇.
  - SKU 7AEE26C309DEF8C5A2A076EB250B8F36: 14 units, $9,730 revenue, $6,071 profit, 31 days to sell.
  - SKU 032ABCD424B4312E7087F434EF1C0094: 14 units, $11,130 revenue, $5,776 profit, 32 days to sell.
- **Insight**: Fast-selling, high-margin SKUs should be prioritized for restocking.
```sql
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
```

## 3. 🔑 Key Insights
- **Revenue Growth**: Strong Q4 performance, with December as the peak month 📈.
- **Profitability**: Clothing Sets, Suits, and Socks drive high margins (>60%) 💸.
- **Inventory Issues**: Low turnover (0.242) and slow-moving stock (Intimates, Jeans) indicate inefficiencies 📦.
- **Seasonality**: February and April dips suggest seasonal or operational challenges 📉.
- **Top SKUs**: High-performing SKUs contribute significantly to revenue and profit 🏆.

## 4. 🛠️ Recommendations
1. **Optimize Inventory**:
   - Clear slow-moving Intimates and Jeans with promotions 🎁.
   - Reduce stock for low-demand products (e.g., Product IDs 17045, 25547).
   - Adopt just-in-time inventory to align with demand forecasts 🔄.
2. **Focus on High-Margin Categories**:
   - Prioritize Clothing Sets, Suits, and Socks for marketing and stock allocation 👕🧥🧦.
   - Develop bundled offerings to boost sales.
3. **Address Seasonal Dips**:
   - Investigate February and April declines and launch targeted campaigns 📅.
   - Start holiday promotions in September to leverage Q4 momentum 🎄.
4. **Leverage Top SKUs**:
   - Increase stock for high-performing SKUs to meet demand 🥇.
   - Use SKU data to guide product development and sourcing.
5. **Enhance Data Analytics**:
   - Implement real-time inventory and sales tracking 📊.
   - Use predictive analytics for demand forecasting 🔍.

## 5. 🎯 Conclusion
This analysis demonstrates strong revenue and profit growth in 2023, with opportunities to improve inventory efficiency and address seasonal dips. By focusing on high-margin categories and top-performing SKUs, the store can maximize profitability. This project showcases my expertise in SQL-based data analysis and strategic decision-making for e-commerce optimization.

*Analysis conducted using SQL queries on revenue, cost, profit, and inventory datasets. View the full code and queries in the [repository](https://github.com/michaelomi/Product-Inventory-Analysis/blob/main/Products%20%26%20Inventory%20Analysis.sql).*
