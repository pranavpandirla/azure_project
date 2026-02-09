-- =====================================================
-- Azure Synapse Analytics - Views Creation Script
-- Analytics Views for Business Intelligence
-- =====================================================

USE [YourDatabase]
GO

-- =====================================================
-- SALES ANALYTICS VIEWS
-- =====================================================

-- View: Sales by Customer Segment
CREATE OR ALTER VIEW dw.vw_Sales_By_Customer_Segment
AS
SELECT 
    c.CustomerSegment,
    d.Year,
    d.Month,
    d.MonthName,
    COUNT(DISTINCT f.OrderID) AS TotalOrders,
    COUNT(DISTINCT f.CustomerKey) AS UniqueCustomers,
    SUM(f.QuantitySold) AS TotalQuantity,
    ROUND(SUM(f.LineTotal), 2) AS TotalRevenue,
    ROUND(AVG(f.LineTotal), 2) AS AvgOrderValue
FROM dw.Fact_Sales f
INNER JOIN dw.Dim_Customer c ON f.CustomerKey = c.CustomerKey
INNER JOIN dw.Dim_Date d ON f.DateKey = d.DateKey
WHERE f.Status = 'Completed'
    AND c.IsCurrent = 1
GROUP BY c.CustomerSegment, d.Year, d.Month, d.MonthName;
GO

-- View: Sales by Product Category
CREATE OR ALTER VIEW dw.vw_Sales_By_Category
AS
SELECT 
    p.Category,
    d.Year,
    d.Quarter,
    COUNT(DISTINCT f.OrderID) AS TotalOrders,
    SUM(f.QuantitySold) AS TotalQuantitySold,
    ROUND(SUM(f.LineTotal), 2) AS TotalRevenue,
    ROUND(AVG(f.UnitPrice), 2) AS AvgUnitPrice,
    COUNT(DISTINCT p.ProductKey) AS UniqueProducts
FROM dw.Fact_Sales f
INNER JOIN dw.Dim_Product p ON f.ProductKey = p.ProductKey
INNER JOIN dw.Dim_Date d ON f.DateKey = d.DateKey
WHERE f.Status = 'Completed'
GROUP BY p.Category, d.Year, d.Quarter;
GO

-- View: Monthly Revenue Trend
CREATE OR ALTER VIEW dw.vw_Monthly_Revenue_Trend
AS
SELECT 
    d.Year,
    d.Month,
    d.MonthName,
    COUNT(DISTINCT f.OrderID) AS TotalOrders,
    COUNT(DISTINCT f.CustomerKey) AS UniqueCustomers,
    ROUND(SUM(f.LineTotal), 2) AS TotalRevenue,
    ROUND(AVG(f.LineTotal), 2) AS AvgOrderValue,
    ROUND(SUM(f.DiscountPerItem * f.QuantitySold), 2) AS TotalDiscounts
FROM dw.Fact_Sales f
INNER JOIN dw.Dim_Date d ON f.DateKey = d.DateKey
WHERE f.Status = 'Completed'
GROUP BY d.Year, d.Month, d.MonthName;
GO

-- View: Weekend vs Weekday Sales
CREATE OR ALTER VIEW dw.vw_Weekend_Weekday_Sales
AS
SELECT 
    d.Year,
    d.Month,
    CASE WHEN d.IsWeekend = 1 THEN 'Weekend' ELSE 'Weekday' END AS DayType,
    COUNT(DISTINCT f.OrderID) AS TotalOrders,
    ROUND(SUM(f.LineTotal), 2) AS TotalRevenue,
    ROUND(AVG(f.LineTotal), 2) AS AvgOrderValue
FROM dw.Fact_Sales f
INNER JOIN dw.Dim_Date d ON f.DateKey = d.DateKey
WHERE f.Status = 'Completed'
GROUP BY d.Year, d.Month, d.IsWeekend;
GO

-- =====================================================
-- CUSTOMER ANALYTICS VIEWS
-- =====================================================

-- View: Customer Segmentation Analysis
CREATE OR ALTER VIEW dw.vw_Customer_Segmentation
AS
SELECT 
    CustomerSegment,
    LTVSegment,
    COUNT(*) AS CustomerCount,
    ROUND(AVG(LifetimeValue), 2) AS AvgLifetimeValue,
    ROUND(SUM(LifetimeValue), 2) AS TotalRevenue,
    ROUND(AVG(TotalOrders), 0) AS AvgOrdersPerCustomer,
    ROUND(AVG(AvgOrderValue), 2) AS AvgOrderValue
FROM dw.Agg_Customer_LTV
GROUP BY CustomerSegment, LTVSegment;
GO

-- View: Top Customers
CREATE OR ALTER VIEW dw.vw_Top_Customers
AS
SELECT TOP 100
    c.CustomerID,
    c.FullName,
    c.Email,
    c.City,
    c.State,
    c.CustomerSegment,
    a.TotalOrders,
    a.LifetimeValue,
    a.AvgOrderValue,
    a.FirstOrderDate,
    a.LastOrderDate,
    a.CustomerTenureDays
FROM dw.Agg_Customer_LTV a
INNER JOIN dw.Dim_Customer c ON a.CustomerKey = c.CustomerKey
WHERE c.IsCurrent = 1
ORDER BY a.LifetimeValue DESC;
GO

-- View: Customer Retention Analysis
CREATE OR ALTER VIEW dw.vw_Customer_Retention
AS
WITH CustomerOrders AS (
    SELECT 
        c.CustomerKey,
        c.FullName,
        c.CustomerSegment,
        MIN(d.Date) AS FirstOrderDate,
        MAX(d.Date) AS LastOrderDate,
        COUNT(DISTINCT f.OrderID) AS TotalOrders,
        DATEDIFF(DAY, MIN(d.Date), MAX(d.Date)) AS DaysSinceFirstOrder,
        DATEDIFF(DAY, MAX(d.Date), GETDATE()) AS DaysSinceLastOrder
    FROM dw.Fact_Sales f
    INNER JOIN dw.Dim_Customer c ON f.CustomerKey = c.CustomerKey
    INNER JOIN dw.Dim_Date d ON f.DateKey = d.DateKey
    WHERE f.Status = 'Completed'
        AND c.IsCurrent = 1
    GROUP BY c.CustomerKey, c.FullName, c.CustomerSegment
)
SELECT 
    CustomerKey,
    FullName,
    CustomerSegment,
    FirstOrderDate,
    LastOrderDate,
    TotalOrders,
    DaysSinceFirstOrder,
    DaysSinceLastOrder,
    CASE 
        WHEN DaysSinceLastOrder <= 30 THEN 'Active'
        WHEN DaysSinceLastOrder <= 90 THEN 'At Risk'
        WHEN DaysSinceLastOrder <= 180 THEN 'Dormant'
        ELSE 'Churned'
    END AS CustomerStatus
FROM CustomerOrders;
GO

-- =====================================================
-- PRODUCT ANALYTICS VIEWS
-- =====================================================

-- View: Top Products by Revenue
CREATE OR ALTER VIEW dw.vw_Top_Products
AS
SELECT TOP 50
    p.ProductID,
    p.ProductName,
    p.Category,
    p.PriceCategory,
    a.TotalQuantitySold,
    a.TotalRevenue,
    a.NumberOfOrders,
    a.AvgSellingPrice,
    p.Rating,
    a.RevenueRank AS CategoryRank
FROM dw.Agg_Product_Performance a
INNER JOIN dw.Dim_Product p ON a.ProductKey = p.ProductKey
ORDER BY a.TotalRevenue DESC;
GO

-- View: Product Category Performance
CREATE OR ALTER VIEW dw.vw_Category_Performance
AS
SELECT 
    Category,
    Year,
    Quarter,
    SUM(TotalQuantity) AS TotalQuantitySold,
    ROUND(SUM(TotalRevenue), 2) AS TotalRevenue,
    SUM(NumberOfOrders) AS TotalOrders,
    SUM(UniqueProductsSold) AS UniqueProducts,
    ROUND(AVG(TotalRevenue / NULLIF(NumberOfOrders, 0)), 2) AS AvgRevenuePerOrder
FROM dw.Agg_Category_Performance
GROUP BY Category, Year, Quarter;
GO

-- View: Product Profitability Analysis
CREATE OR ALTER VIEW dw.vw_Product_Profitability
AS
SELECT 
    p.ProductID,
    p.ProductName,
    p.Category,
    p.Price,
    p.Cost,
    p.ProfitMargin,
    a.TotalQuantitySold,
    a.TotalRevenue,
    ROUND((p.Price - p.Cost) * a.TotalQuantitySold, 2) AS TotalProfit
FROM dw.Dim_Product p
INNER JOIN dw.Agg_Product_Performance a ON p.ProductKey = a.ProductKey;
GO

-- =====================================================
-- OPERATIONAL VIEWS
-- =====================================================

-- View: Daily Sales Dashboard
CREATE OR ALTER VIEW dw.vw_Daily_Sales_Dashboard
AS
SELECT 
    d.Date,
    d.DayName,
    d.IsWeekend,
    ds.TotalOrders,
    ds.UniqueCustomers,
    ds.TotalQuantity,
    ds.TotalRevenue,
    ds.AvgOrderValue,
    ds.TotalDiscounts,
    ROUND((ds.TotalRevenue - ds.TotalDiscounts) / NULLIF(ds.TotalOrders, 0), 2) AS NetRevenuePerOrder
FROM dw.Agg_Daily_Sales ds
INNER JOIN dw.Dim_Date d ON ds.DateKey = d.DateKey;
GO

-- View: Payment Method Analysis
CREATE OR ALTER VIEW dw.vw_Payment_Method_Analysis
AS
SELECT 
    f.PaymentMethod,
    d.Year,
    d.Month,
    COUNT(DISTINCT f.OrderID) AS TotalOrders,
    ROUND(SUM(f.LineTotal), 2) AS TotalRevenue,
    ROUND(AVG(f.LineTotal), 2) AS AvgOrderValue
FROM dw.Fact_Sales f
INNER JOIN dw.Dim_Date d ON f.DateKey = d.DateKey
WHERE f.Status = 'Completed'
GROUP BY f.PaymentMethod, d.Year, d.Month;
GO

-- View: Geographic Sales Distribution
CREATE OR ALTER VIEW dw.vw_Geographic_Sales
AS
SELECT 
    c.State,
    c.City,
    COUNT(DISTINCT c.CustomerKey) AS TotalCustomers,
    COUNT(DISTINCT f.OrderID) AS TotalOrders,
    ROUND(SUM(f.LineTotal), 2) AS TotalRevenue,
    ROUND(AVG(f.LineTotal), 2) AS AvgOrderValue
FROM dw.Fact_Sales f
INNER JOIN dw.Dim_Customer c ON f.CustomerKey = c.CustomerKey
WHERE f.Status = 'Completed'
    AND c.IsCurrent = 1
GROUP BY c.State, c.City;
GO

-- View: Year-over-Year Comparison
CREATE OR ALTER VIEW dw.vw_YoY_Comparison
AS
WITH YearlySales AS (
    SELECT 
        d.Year,
        d.Month,
        ROUND(SUM(f.LineTotal), 2) AS MonthlyRevenue,
        COUNT(DISTINCT f.OrderID) AS MonthlyOrders
    FROM dw.Fact_Sales f
    INNER JOIN dw.Dim_Date d ON f.DateKey = d.DateKey
    WHERE f.Status = 'Completed'
    GROUP BY d.Year, d.Month
)
SELECT 
    curr.Year AS CurrentYear,
    curr.Month,
    curr.MonthlyRevenue AS CurrentRevenue,
    prev.MonthlyRevenue AS PreviousYearRevenue,
    ROUND(((curr.MonthlyRevenue - prev.MonthlyRevenue) / NULLIF(prev.MonthlyRevenue, 0)) * 100, 2) AS RevenueGrowthPct,
    curr.MonthlyOrders AS CurrentOrders,
    prev.MonthlyOrders AS PreviousYearOrders,
    ROUND(((curr.MonthlyOrders - prev.MonthlyOrders) * 1.0 / NULLIF(prev.MonthlyOrders, 0)) * 100, 2) AS OrderGrowthPct
FROM YearlySales curr
LEFT JOIN YearlySales prev ON curr.Month = prev.Month AND curr.Year = prev.Year + 1;
GO

PRINT 'Views created successfully!';
GO
