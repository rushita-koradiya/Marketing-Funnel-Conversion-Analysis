USE MarketingFunnelDB;
GO

/* 1. Data check */

SELECT
    COUNT(*) AS Total_Rows,
    COUNT(DISTINCT Session_ID) AS Total_Sessions,
    SUM(CASE WHEN Session_ID IS NULL OR Event IS NULL OR [Timestamp] IS NULL
              OR Channel IS NULL OR Device IS NULL OR Region IS NULL
              OR Product_Category IS NULL OR Revenue IS NULL
        THEN 1 ELSE 0 END) AS Missing_Rows,
    SUM(CASE WHEN (Event = 'Purchase' AND Revenue <= 0)
              OR (Event <> 'Purchase' AND Revenue <> 0)
        THEN 1 ELSE 0 END) AS Invalid_Revenue_Rows
FROM dbo.funnel_events;
GO

/* 2. Views */

-- One row per session (channel, device, region from the Browse event)
CREATE OR ALTER VIEW dbo.v_session AS
SELECT
    Session_ID,
    MAX(CASE WHEN Event = 'Browse' THEN Channel END)          AS Channel,
    MAX(CASE WHEN Event = 'Browse' THEN Device END)           AS Device,
    MAX(CASE WHEN Event = 'Browse' THEN Region END)           AS Region,
    MAX(CASE WHEN Event = 'Browse' THEN [Timestamp] END)      AS Browse_Time,
    MAX(CASE WHEN Event = 'Add to Cart' THEN [Timestamp] END) AS Cart_Time,
    MAX(CASE WHEN Event = 'Checkout' THEN [Timestamp] END)    AS Checkout_Time,
    MAX(CASE WHEN Event = 'Purchase' THEN [Timestamp] END)    AS Purchase_Time,
    MAX(CASE WHEN Event = 'Browse' THEN 1 ELSE 0 END)         AS Browsed,
    MAX(CASE WHEN Event = 'Add to Cart' THEN 1 ELSE 0 END)    AS Added_To_Cart,
    MAX(CASE WHEN Event = 'Checkout' THEN 1 ELSE 0 END)       AS Checked_Out,
    MAX(CASE WHEN Event = 'Purchase' THEN 1 ELSE 0 END)       AS Purchased,
    SUM(Revenue)                                              AS Revenue
FROM dbo.funnel_events
GROUP BY Session_ID;
GO

-- One row per purchase
CREATE OR ALTER VIEW dbo.v_purchase_detail AS
SELECT
    Session_ID,
    CAST([Timestamp] AS DATE) AS Purchase_Date,
    Product_Category,
    Revenue
FROM dbo.funnel_events
WHERE Event = 'Purchase';
GO

/* 3. Funnel overview */

-- KPIs: sessions, purchases, conversion rate, cart abandonment
SELECT
    COUNT(*)           AS Total_Sessions,
    SUM(Purchased)     AS Purchases,
    CAST(100.0 * SUM(Purchased) / COUNT(*) AS DECIMAL(5,1)) AS Conversion_Rate_Pct,
    CAST(100.0 * (SUM(Added_To_Cart) - SUM(Purchased))
         / SUM(Added_To_Cart) AS DECIMAL(5,1)) AS Cart_Abandonment_Pct
FROM dbo.v_session;

-- Waterfall: sessions that did not reach the next stage
SELECT
    SUM(Browsed)       - SUM(Added_To_Cart) AS Cart_Drop,
    SUM(Added_To_Cart) - SUM(Checked_Out)   AS Checkout_Drop,
    SUM(Checked_Out)   - SUM(Purchased)     AS Payment_Drop
FROM dbo.v_session;

-- Step conversion by channel
SELECT
    Channel,
    CAST(100.0 * SUM(Added_To_Cart) / SUM(Browsed)       AS DECIMAL(5,1)) AS Browse_To_Cart_Pct,
    CAST(100.0 * SUM(Checked_Out)   / SUM(Added_To_Cart) AS DECIMAL(5,1)) AS Cart_To_Checkout_Pct,
    CAST(100.0 * SUM(Purchased)     / SUM(Checked_Out)   AS DECIMAL(5,1)) AS Checkout_To_Purchase_Pct,
    CAST(100.0 * SUM(Purchased)     / COUNT(*)           AS DECIMAL(5,1)) AS Conversion_Rate_Pct
FROM dbo.v_session
GROUP BY Channel;

-- Conversion: Device x Channel
SELECT
    Device,
    Channel,
    CAST(100.0 * SUM(Purchased) / COUNT(*) AS DECIMAL(5,1)) AS Conversion_Rate_Pct
FROM dbo.v_session
GROUP BY Device, Channel
ORDER BY Device, Channel;

-- Conversion by region
SELECT
    Region,
    CAST(100.0 * SUM(Purchased) / COUNT(*) AS DECIMAL(5,1)) AS Conversion_Rate_Pct
FROM dbo.v_session
GROUP BY Region
ORDER BY Conversion_Rate_Pct DESC;

/* 4. Segments & revenue */

-- KPIs: total revenue, average order value, revenue per session
SELECT
    SUM(Revenue)                                         AS Total_Revenue,
    CAST(SUM(Revenue) / SUM(Purchased) AS DECIMAL(10,2)) AS Average_Order_Value,
    CAST(SUM(Revenue) / COUNT(*)       AS DECIMAL(10,2)) AS Revenue_per_Session
FROM dbo.v_session;

-- Avg daily revenue growth: Oct 1-15 vs Oct 16-31
WITH Halves AS (
    SELECT
        SUM(CASE WHEN Purchase_Date <= '2025-10-15' THEN Revenue ELSE 0 END) / 15.0 AS First_Half_Avg,
        SUM(CASE WHEN Purchase_Date >  '2025-10-15' THEN Revenue ELSE 0 END) / 16.0 AS Second_Half_Avg
    FROM dbo.v_purchase_detail
)
SELECT CAST(100.0 * (Second_Half_Avg - First_Half_Avg) / First_Half_Avg AS DECIMAL(5,1))
       AS Avg_Daily_Revenue_Growth_Pct
FROM Halves;

-- Daily revenue trend
SELECT Purchase_Date, SUM(Revenue) AS Revenue
FROM dbo.v_purchase_detail
GROUP BY Purchase_Date
ORDER BY Purchase_Date;

-- Revenue by category
SELECT Product_Category, SUM(Revenue) AS Revenue
FROM dbo.v_purchase_detail
GROUP BY Product_Category
ORDER BY Revenue DESC;

-- Revenue by region
SELECT Region, SUM(Revenue) AS Revenue
FROM dbo.v_session
GROUP BY Region
ORDER BY Revenue DESC;

-- Revenue per session by channel
SELECT
    Channel,
    CAST(SUM(Revenue) / COUNT(*) AS DECIMAL(10,2)) AS Revenue_per_Session
FROM dbo.v_session
GROUP BY Channel
ORDER BY Revenue_per_Session DESC;