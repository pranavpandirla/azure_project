-- =====================================================
-- Azure Synapse Analytics - Table Creation Script
-- E-commerce Data Warehouse
-- =====================================================

-- Create Schema
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'dw')
BEGIN
    EXEC('CREATE SCHEMA dw')
END
GO

-- =====================================================
-- DIMENSION TABLES
-- =====================================================

-- Dim_Customer
IF OBJECT_ID('dw.Dim_Customer', 'U') IS NOT NULL
    DROP TABLE dw.Dim_Customer;
GO

CREATE TABLE dw.Dim_Customer
(
    CustomerKey BIGINT NOT NULL,
    CustomerID INT NOT NULL,
    FirstName NVARCHAR(100),
    LastName NVARCHAR(100),
    FullName NVARCHAR(200),
    Email NVARCHAR(255),
    City NVARCHAR(100),
    State NVARCHAR(50),
    ZipCode NVARCHAR(20),
    RegistrationDate DATE,
    CustomerSegment NVARCHAR(50),
    EffectiveDate DATE,
    EndDate DATE,
    IsCurrent BIT
)
WITH
(
    DISTRIBUTION = REPLICATE,
    CLUSTERED COLUMNSTORE INDEX
);
GO

-- Dim_Product
IF OBJECT_ID('dw.Dim_Product', 'U') IS NOT NULL
    DROP TABLE dw.Dim_Product;
GO

CREATE TABLE dw.Dim_Product
(
    ProductKey BIGINT NOT NULL,
    ProductID INT NOT NULL,
    ProductName NVARCHAR(255),
    Category NVARCHAR(100),
    Price DECIMAL(10, 2),
    Cost DECIMAL(10, 2),
    ProfitMargin DECIMAL(5, 2),
    PriceCategory NVARCHAR(50),
    Rating DECIMAL(2, 1)
)
WITH
(
    DISTRIBUTION = REPLICATE,
    CLUSTERED COLUMNSTORE INDEX
);
GO

-- Dim_Date
IF OBJECT_ID('dw.Dim_Date', 'U') IS NOT NULL
    DROP TABLE dw.Dim_Date;
GO

CREATE TABLE dw.Dim_Date
(
    DateKey INT NOT NULL,
    Date DATE NOT NULL,
    Year INT,
    Quarter INT,
    Month INT,
    MonthName NVARCHAR(20),
    Day INT,
    DayOfWeek INT,
    DayName NVARCHAR(20),
    WeekOfYear INT,
    IsWeekend BIT,
    IsHoliday BIT
)
WITH
(
    DISTRIBUTION = REPLICATE,
    CLUSTERED COLUMNSTORE INDEX
);
GO

-- =====================================================
-- FACT TABLES
-- =====================================================

-- Fact_Sales
IF OBJECT_ID('dw.Fact_Sales', 'U') IS NOT NULL
    DROP TABLE dw.Fact_Sales;
GO

CREATE TABLE dw.Fact_Sales
(
    SalesKey BIGINT NOT NULL,
    OrderID INT,
    CustomerKey BIGINT,
    ProductKey BIGINT,
    DateKey INT,
    OrderDateTime DATETIME2,
    QuantitySold INT,
    UnitPrice DECIMAL(10, 2),
    LineTotal DECIMAL(10, 2),
    DiscountPerItem DECIMAL(10, 2),
    PaymentMethod NVARCHAR(50),
    Status NVARCHAR(50),
    ShippingMethod NVARCHAR(50)
)
WITH
(
    DISTRIBUTION = HASH(OrderID),
    CLUSTERED COLUMNSTORE INDEX,
    PARTITION (DateKey RANGE RIGHT FOR VALUES (
        20240101, 20240201, 20240301, 20240401, 20240501, 20240601,
        20240701, 20240801, 20240901, 20241001, 20241101, 20241201,
        20250101, 20250201, 20250301, 20250401, 20250501, 20250601,
        20250701, 20250801, 20250901, 20251001, 20251101, 20251201
    ))
);
GO

-- =====================================================
-- AGGREGATE TABLES
-- =====================================================

-- Agg_Daily_Sales
IF OBJECT_ID('dw.Agg_Daily_Sales', 'U') IS NOT NULL
    DROP TABLE dw.Agg_Daily_Sales;
GO

CREATE TABLE dw.Agg_Daily_Sales
(
    DateKey INT NOT NULL,
    Date DATE,
    TotalOrders BIGINT,
    UniqueCustomers BIGINT,
    TotalQuantity BIGINT,
    TotalRevenue DECIMAL(18, 2),
    AvgOrderValue DECIMAL(10, 2),
    TotalDiscounts DECIMAL(18, 2)
)
WITH
(
    DISTRIBUTION = ROUND_ROBIN,
    CLUSTERED COLUMNSTORE INDEX
);
GO

-- Agg_Product_Performance
IF OBJECT_ID('dw.Agg_Product_Performance', 'U') IS NOT NULL
    DROP TABLE dw.Agg_Product_Performance;
GO

CREATE TABLE dw.Agg_Product_Performance
(
    ProductKey BIGINT,
    ProductID INT,
    ProductName NVARCHAR(255),
    Category NVARCHAR(100),
    TotalQuantitySold BIGINT,
    TotalRevenue DECIMAL(18, 2),
    NumberOfOrders BIGINT,
    AvgSellingPrice DECIMAL(10, 2),
    RevenueRank INT
)
WITH
(
    DISTRIBUTION = ROUND_ROBIN,
    CLUSTERED COLUMNSTORE INDEX
);
GO

-- Agg_Customer_LTV
IF OBJECT_ID('dw.Agg_Customer_LTV', 'U') IS NOT NULL
    DROP TABLE dw.Agg_Customer_LTV;
GO

CREATE TABLE dw.Agg_Customer_LTV
(
    CustomerKey BIGINT,
    CustomerID INT,
    FullName NVARCHAR(200),
    CustomerSegment NVARCHAR(50),
    TotalOrders BIGINT,
    LifetimeValue DECIMAL(18, 2),
    AvgOrderValue DECIMAL(10, 2),
    FirstOrderDate DATETIME2,
    LastOrderDate DATETIME2,
    CustomerTenureDays INT,
    LTVSegment NVARCHAR(50)
)
WITH
(
    DISTRIBUTION = ROUND_ROBIN,
    CLUSTERED COLUMNSTORE INDEX
);
GO

-- Agg_Category_Performance
IF OBJECT_ID('dw.Agg_Category_Performance', 'U') IS NOT NULL
    DROP TABLE dw.Agg_Category_Performance;
GO

CREATE TABLE dw.Agg_Category_Performance
(
    Category NVARCHAR(100),
    Year INT,
    Quarter INT,
    TotalQuantity BIGINT,
    TotalRevenue DECIMAL(18, 2),
    NumberOfOrders BIGINT,
    UniqueProductsSold BIGINT
)
WITH
(
    DISTRIBUTION = ROUND_ROBIN,
    CLUSTERED COLUMNSTORE INDEX
);
GO

-- =====================================================
-- CREATE STATISTICS
-- =====================================================

-- Statistics on Fact_Sales
CREATE STATISTICS stat_Fact_Sales_CustomerKey ON dw.Fact_Sales(CustomerKey);
CREATE STATISTICS stat_Fact_Sales_ProductKey ON dw.Fact_Sales(ProductKey);
CREATE STATISTICS stat_Fact_Sales_DateKey ON dw.Fact_Sales(DateKey);
CREATE STATISTICS stat_Fact_Sales_OrderID ON dw.Fact_Sales(OrderID);
GO

-- Statistics on Dim_Customer
CREATE STATISTICS stat_Dim_Customer_CustomerKey ON dw.Dim_Customer(CustomerKey);
CREATE STATISTICS stat_Dim_Customer_CustomerSegment ON dw.Dim_Customer(CustomerSegment);
GO

-- Statistics on Dim_Product
CREATE STATISTICS stat_Dim_Product_ProductKey ON dw.Dim_Product(ProductKey);
CREATE STATISTICS stat_Dim_Product_Category ON dw.Dim_Product(Category);
GO

-- Statistics on Dim_Date
CREATE STATISTICS stat_Dim_Date_DateKey ON dw.Dim_Date(DateKey);
CREATE STATISTICS stat_Dim_Date_Year ON dw.Dim_Date(Year);
CREATE STATISTICS stat_Dim_Date_Month ON dw.Dim_Date(Month);
GO

PRINT 'Tables created successfully!';
GO
