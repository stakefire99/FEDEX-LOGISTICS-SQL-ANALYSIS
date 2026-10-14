-- =====================================================================
-- FedEx Logistics Optimization - SQL Analysis (MySQL)
-- Tables: Orders, Shipments, Routes, Warehouses, Delivery_Agents
-- Data size: 1,000 shipments, 20 routes, 10 warehouses
-- NOTE: transcribed from the project's query screenshots. Compare with your
-- own Workbench scripts and fix anything that differs before committing.
-- =====================================================================

-- ---------- TASK 1: DATA CLEANING & PREPARATION ----------

-- 1.2a  Count missing Delay_Hours (result: 0)
SELECT COUNT(*) AS null_delay_count
FROM Shipments
WHERE Delay_Hours IS NULL;

-- 1.2b  Fill missing Delay_Hours with the route average (no rows needed updating)
SET SQL_SAFE_UPDATES = 0;

UPDATE Shipments s
JOIN (
    SELECT Route_ID, AVG(Delay_Hours) AS avg_delay
    FROM Shipments
    WHERE Delay_Hours IS NOT NULL
    GROUP BY Route_ID
) r
ON s.Route_ID = r.Route_ID
SET s.Delay_Hours = r.avg_delay
WHERE s.Delay_Hours IS NULL;

SET SQL_SAFE_UPDATES = 1;

-- 1.3  Date validation (sample of pickup/delivery timestamps)
SELECT Pickup_Date, Delivery_Date
FROM Shipments
LIMIT 5;

-- 1.4  Flag invalid dates: delivery before pickup (result: 0 rows)
SELECT *
FROM Shipments
WHERE Delivery_Date < Pickup_Date;

-- 1.5  Referential integrity: shipments with no matching order (result: 0 rows)
SELECT s.Shipment_ID
FROM Shipments s
LEFT JOIN Orders o
  ON s.Order_ID = o.Order_ID
WHERE o.Order_ID IS NULL;

-- ---------- TASK 2: DELIVERY DELAY ANALYSIS ----------

-- 2.1  Hours between pickup and delivery per shipment
SELECT Shipment_ID,
       TIMESTAMPDIFF(HOUR, Pickup_Date, Delivery_Date) AS actual_delay_hours
FROM Shipments;

-- 2.2  Top 10 routes by average delay
SELECT Route_ID, AVG(Delay_Hours) AS avg_delay
FROM Shipments
GROUP BY Route_ID
ORDER BY avg_delay DESC
LIMIT 10;

-- 2.3  Rank shipments by delay within each warehouse
-- (reconstructed - the screenshot for this query was not in the deck)
SELECT Shipment_ID,
       Warehouse_ID,
       Delay_Hours,
       RANK() OVER (PARTITION BY Warehouse_ID ORDER BY Delay_Hours DESC) AS delay_rank
FROM Shipments;

-- 2.4  Average delay by delivery type
SELECT o.Delivery_Type, AVG(s.Delay_Hours) AS avg_delay
FROM Shipments s
JOIN Orders o ON s.Order_ID = o.Order_ID
GROUP BY o.Delivery_Type;

-- ---------- TASK 3: ROUTE OPTIMIZATION ----------

-- 3.1  Route performance: average delay and efficiency ratio (km per transit hour)
SELECT r.Route_ID,
       AVG(s.Delay_Hours) AS avg_delay,
       r.Distance_KM / r.Avg_Transit_Time_Hours AS efficiency_ratio
FROM Routes r
JOIN Shipments s ON r.Route_ID = s.Route_ID
GROUP BY r.Route_ID;

-- 3.2  Three routes with the lowest efficiency ratio
SELECT r.Route_ID,
       r.Distance_KM / r.Avg_Transit_Time_Hours AS efficiency_ratio
FROM Routes r
ORDER BY efficiency_ratio ASC
LIMIT 3;

-- 3.3  Routes where more than 20% of shipments exceed the route's average transit time
-- (the screenshot was cut off after FROM Shipments s; JOIN/GROUP BY/HAVING reconstructed)
SELECT s.Route_ID,
       COUNT(*) AS total_shipments,
       SUM(CASE WHEN s.Delay_Hours > r.Avg_Transit_Time_Hours THEN 1 ELSE 0 END) AS delayed_shipments,
       ROUND(
           SUM(CASE WHEN s.Delay_Hours > r.Avg_Transit_Time_Hours THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
           2
       ) AS delay_percentage
FROM Shipments s
JOIN Routes r ON s.Route_ID = r.Route_ID
GROUP BY s.Route_ID
HAVING delay_percentage > 20
ORDER BY delay_percentage DESC;

-- ---------- TASK 4: WAREHOUSE PERFORMANCE ----------

-- 4.1  Three warehouses with the highest average delay
SELECT Warehouse_ID, AVG(Delay_Hours) AS avg_delay
FROM Shipments
GROUP BY Warehouse_ID
ORDER BY avg_delay DESC
LIMIT 3;

-- 4.2  Total vs delayed shipments per warehouse
SELECT Warehouse_ID,
       COUNT(*) AS total_shipments,
       SUM(CASE WHEN Delay_Hours > 0 THEN 1 ELSE 0 END) AS delayed_shipments
FROM Shipments
GROUP BY Warehouse_ID;

-- 4.3  Warehouses whose average delay is above the global average (CTE version)
-- (the screenshot ran this as two separate queries; the CTE combines them)
WITH warehouse_delay AS (
    SELECT Warehouse_ID, AVG(Delay_Hours) AS warehouse_avg_delay
    FROM Shipments
    GROUP BY Warehouse_ID
),
global_delay AS (
    SELECT AVG(Delay_Hours) AS global_avg_delay
    FROM Shipments
)
SELECT w.Warehouse_ID, w.warehouse_avg_delay, g.global_avg_delay
FROM warehouse_delay w
CROSS JOIN global_delay g
WHERE w.warehouse_avg_delay > g.global_avg_delay
ORDER BY w.warehouse_avg_delay DESC;

-- 4.4  Rank warehouses by on-time delivery percentage (on time = zero delay hours)
SELECT Warehouse_ID,
       ROUND(
           SUM(CASE WHEN Delay_Hours = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
           2
       ) AS on_time_percentage
FROM Shipments
GROUP BY Warehouse_ID
ORDER BY on_time_percentage DESC;

-- ---------- TASK 5: DELIVERY AGENT PERFORMANCE ----------

-- 5.1  Rank agents by on-time percentage
SELECT Agent_ID,
       ROUND(
           SUM(CASE WHEN Delay_Hours = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
           2
       ) AS on_time_percentage
FROM Shipments
GROUP BY Agent_ID
ORDER BY on_time_percentage DESC;

-- 5.2  Agents below 85% on-time delivery
SELECT *
FROM (
    SELECT Agent_ID,
           SUM(CASE WHEN Delay_Hours = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS on_time_percentage
    FROM Shipments
    GROUP BY Agent_ID
) t
WHERE on_time_percentage < 85;

-- 5.3  Top 5 and bottom 5 agents: rating and experience
-- (the screenshot was cut off after the top-5 half; bottom-5 half mirrored)
SELECT *
FROM Delivery_Agents
WHERE Agent_ID IN (
    SELECT Agent_ID FROM (
        SELECT Agent_ID
        FROM Shipments
        GROUP BY Agent_ID
        ORDER BY SUM(CASE WHEN Delay_Hours = 0 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) DESC
        LIMIT 5
    ) top_agents
)
OR Agent_ID IN (
    SELECT Agent_ID FROM (
        SELECT Agent_ID
        FROM Shipments
        GROUP BY Agent_ID
        ORDER BY SUM(CASE WHEN Delay_Hours = 0 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) ASC
        LIMIT 5
    ) bottom_agents
);

-- ---------- TASK 6: SHIPMENT TRACKING ANALYTICS ----------

-- 6.1  Latest delivery status and date per shipment
SELECT Shipment_ID, Delivery_Status, Delivery_Date
FROM Shipments;

-- 6.2  Routes with In Transit / Returned shipments
SELECT Route_ID, Delivery_Status, COUNT(*) AS count
FROM Shipments
WHERE Delivery_Status IN ('In Transit', 'Returned')
GROUP BY Route_ID, Delivery_Status;

-- 6.3  Most frequent delay reasons
SELECT Delay_Reason, COUNT(*) AS frequency
FROM Shipments
GROUP BY Delay_Reason
ORDER BY frequency DESC;

-- 6.4  Shipments delayed more than 120 hours
SELECT *
FROM Shipments
WHERE Delay_Hours > 120;

-- ---------- TASK 7: KPI REPORTING ----------

-- 7.1  Average delay per source country
SELECT r.Source_Country, AVG(s.Delay_Hours) AS avg_delay
FROM Shipments s
JOIN Routes r ON s.Route_ID = r.Route_ID
GROUP BY r.Source_Country;

-- 7.2  Overall on-time delivery percentage (result: 6.80)
SELECT ROUND(
           SUM(CASE WHEN Delay_Hours = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
           2
       ) AS on_time_delivery_percentage
FROM Shipments;

-- 7.3  Average delay per route
SELECT Route_ID, AVG(Delay_Hours) AS avg_delay
FROM Shipments
GROUP BY Route_ID;

-- 7.4  Warehouse utilization (shipments vs daily capacity)
-- Caution: this divides TOTAL shipments by capacity PER DAY, so it is not a true
-- utilization rate. Consider shipments-per-day / Capacity_per_day instead.
SELECT w.Warehouse_ID,
       ROUND(COUNT(s.Shipment_ID) * 100.0 / w.Capacity_per_day, 2) AS utilization_percentage
FROM Warehouses w
JOIN Shipments s ON w.Warehouse_ID = s.Warehouse_ID
GROUP BY w.Warehouse_ID;
