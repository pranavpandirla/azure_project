# Databricks notebook source
# MAGIC %md
# MAGIC # Silver to Gold Layer Transformation
# MAGIC 
# MAGIC This notebook creates business-level aggregations and fact/dimension tables:
# MAGIC - Fact tables for analytics
# MAGIC - Dimension tables (slowly changing dimensions)
# MAGIC - Pre-aggregated metrics
# MAGIC - Star schema modeling

# COMMAND ----------

from pyspark.sql import SparkSession
from pyspark.sql.functions import *
from pyspark.sql.window import Window
from delta.tables import *

# COMMAND ----------

# MAGIC %md
# MAGIC ## Configuration

# COMMAND ----------

# Storage paths
silver_path = "abfss://silver@<storage_account>.dfs.core.windows.net/"
gold_path = "abfss://gold@<storage_account>.dfs.core.windows.net/"

# COMMAND ----------

# MAGIC %md
# MAGIC ## Read Silver Layer Data

# COMMAND ----------

customers_silver = spark.read.format("delta").load(f"{silver_path}customers/")
products_silver = spark.read.format("delta").load(f"{silver_path}products/")
orders_silver = spark.read.format("delta").load(f"{silver_path}orders/")
order_items_silver = spark.read.format("delta").load(f"{silver_path}order_items/")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Create Dimension Tables

# COMMAND ----------

# MAGIC %md
# MAGIC ### Dim_Customer

# COMMAND ----------

dim_customer = customers_silver \
    .withColumn("customer_key", monotonically_increasing_id()) \
    .withColumn("effective_date", current_date()) \
    .withColumn("end_date", lit(None).cast("date")) \
    .withColumn("is_current", lit(True)) \
    .select(
        "customer_key",
        "customer_id",
        "first_name",
        "last_name",
        "full_name",
        "email",
        "city",
        "state",
        "zipcode",
        "registration_date",
        "customer_segment",
        "effective_date",
        "end_date",
        "is_current"
    )

# COMMAND ----------

# MAGIC %md
# MAGIC ### Dim_Product

# COMMAND ----------

dim_product = products_silver \
    .withColumn("product_key", monotonically_increasing_id()) \
    .select(
        "product_key",
        "product_id",
        "product_name",
        "category",
        "price",
        "cost",
        "profit_margin",
        "price_category",
        "rating"
    )

# COMMAND ----------

# MAGIC %md
# MAGIC ### Dim_Date

# COMMAND ----------

# Generate date dimension for the past 2 years and next 1 year
start_date = (current_date() - expr("INTERVAL 2 YEARS")).cast("date")
end_date = (current_date() + expr("INTERVAL 1 YEAR")).cast("date")

# Generate date range
date_range = spark.sql(f"""
    SELECT sequence(
        to_date('{start_date}'), 
        to_date('{end_date}'), 
        interval 1 day
    ) as date_array
""").select(explode(col("date_array")).alias("date"))

dim_date = date_range \
    .withColumn("date_key", date_format(col("date"), "yyyyMMdd").cast("int")) \
    .withColumn("year", year(col("date"))) \
    .withColumn("quarter", quarter(col("date"))) \
    .withColumn("month", month(col("date"))) \
    .withColumn("month_name", date_format(col("date"), "MMMM")) \
    .withColumn("day", dayofmonth(col("date"))) \
    .withColumn("day_of_week", dayofweek(col("date"))) \
    .withColumn("day_name", date_format(col("date"), "EEEE")) \
    .withColumn("week_of_year", weekofyear(col("date"))) \
    .withColumn("is_weekend", when(col("day_of_week").isin([1, 7]), True).otherwise(False)) \
    .withColumn("is_holiday", lit(False))  # Can be enhanced with actual holiday logic

# COMMAND ----------

# MAGIC %md
# MAGIC ## Create Fact Tables

# COMMAND ----------

# MAGIC %md
# MAGIC ### Fact_Sales

# COMMAND ----------

fact_sales = orders_silver \
    .join(order_items_silver, "order_id") \
    .join(dim_customer.select("customer_id", "customer_key"), "customer_id") \
    .join(dim_product.select("product_id", "product_key"), "product_id") \
    .withColumn("date_key", date_format(col("order_date"), "yyyyMMdd").cast("int")) \
    .withColumn("sales_key", monotonically_increasing_id()) \
    .select(
        "sales_key",
        "order_id",
        "customer_key",
        "product_key",
        "date_key",
        "order_datetime",
        col("quantity").alias("quantity_sold"),
        col("unit_price").alias("unit_price"),
        col("total_price").alias("line_total"),
        "discount_per_item",
        "payment_method",
        "status",
        "shipping_method"
    )

# COMMAND ----------

# MAGIC %md
# MAGIC ## Create Aggregate Tables

# COMMAND ----------

# MAGIC %md
# MAGIC ### Agg_Daily_Sales

# COMMAND ----------

agg_daily_sales = fact_sales \
    .filter(col("status") == "Completed") \
    .groupBy("date_key") \
    .agg(
        count("order_id").alias("total_orders"),
        countDistinct("customer_key").alias("unique_customers"),
        sum("quantity_sold").alias("total_quantity"),
        round(sum("line_total"), 2).alias("total_revenue"),
        round(avg("line_total"), 2).alias("avg_order_value"),
        round(sum("discount_per_item"), 2).alias("total_discounts")
    ) \
    .withColumn("date", 
                to_date(col("date_key").cast("string"), "yyyyMMdd"))

# COMMAND ----------

# MAGIC %md
# MAGIC ### Agg_Product_Performance

# COMMAND ----------

agg_product_performance = fact_sales \
    .filter(col("status") == "Completed") \
    .join(dim_product, "product_key") \
    .groupBy("product_key", "product_id", "product_name", "category") \
    .agg(
        sum("quantity_sold").alias("total_quantity_sold"),
        round(sum("line_total"), 2).alias("total_revenue"),
        count("order_id").alias("number_of_orders"),
        round(avg("unit_price"), 2).alias("avg_selling_price")
    ) \
    .withColumn("revenue_rank", 
                row_number().over(Window.partitionBy("category").orderBy(desc("total_revenue"))))

# COMMAND ----------

# MAGIC %md
# MAGIC ### Agg_Customer_Lifetime_Value

# COMMAND ----------

agg_customer_ltv = fact_sales \
    .filter(col("status") == "Completed") \
    .join(dim_customer, "customer_key") \
    .groupBy("customer_key", "customer_id", "full_name", "customer_segment") \
    .agg(
        count("order_id").alias("total_orders"),
        round(sum("line_total"), 2).alias("lifetime_value"),
        round(avg("line_total"), 2).alias("avg_order_value"),
        min("order_datetime").alias("first_order_date"),
        max("order_datetime").alias("last_order_date")
    ) \
    .withColumn("customer_tenure_days",
                datediff(col("last_order_date"), col("first_order_date"))) \
    .withColumn("ltv_segment",
                when(col("lifetime_value") >= 1000, "High Value")
                .when(col("lifetime_value") >= 500, "Medium Value")
                .otherwise("Low Value"))

# COMMAND ----------

# MAGIC %md
# MAGIC ### Agg_Category_Performance

# COMMAND ----------

agg_category_performance = fact_sales \
    .filter(col("status") == "Completed") \
    .join(dim_product, "product_key") \
    .join(dim_date, "date_key") \
    .groupBy("category", "year", "quarter") \
    .agg(
        sum("quantity_sold").alias("total_quantity"),
        round(sum("line_total"), 2).alias("total_revenue"),
        count(col("order_id")).alias("number_of_orders"),
        countDistinct("product_key").alias("unique_products_sold")
    )

# COMMAND ----------

# MAGIC %md
# MAGIC ## Write to Gold Layer

# COMMAND ----------

def write_to_gold(df, table_name, partition_cols=None):
    """Write DataFrame to Gold layer using Delta format"""
    path = f"{gold_path}{table_name}/"
    
    writer = df.write.format("delta").mode("overwrite")
    
    if partition_cols:
        writer = writer.partitionBy(partition_cols)
    
    writer.option("overwriteSchema", "true") \
          .save(path)
    
    print(f"✓ Written {df.count()} records to {table_name}")

# COMMAND ----------

# Write dimension tables
write_to_gold(dim_customer, "dim_customer")
write_to_gold(dim_product, "dim_product")
write_to_gold(dim_date, "dim_date", ["year", "month"])

# Write fact tables
write_to_gold(fact_sales, "fact_sales", ["date_key"])

# Write aggregate tables
write_to_gold(agg_daily_sales, "agg_daily_sales")
write_to_gold(agg_product_performance, "agg_product_performance")
write_to_gold(agg_customer_ltv, "agg_customer_ltv")
write_to_gold(agg_category_performance, "agg_category_performance", ["year"])

# COMMAND ----------

# MAGIC %md
# MAGIC ## Summary Statistics

# COMMAND ----------

print("="*60)
print("GOLD LAYER SUMMARY")
print("="*60)

print("\n📊 Dimension Tables:")
print(f"  Dim_Customer: {dim_customer.count()} records")
print(f"  Dim_Product: {dim_product.count()} records")
print(f"  Dim_Date: {dim_date.count()} records")

print("\n📈 Fact Tables:")
print(f"  Fact_Sales: {fact_sales.count()} records")

print("\n📉 Aggregate Tables:")
print(f"  Agg_Daily_Sales: {agg_daily_sales.count()} records")
print(f"  Agg_Product_Performance: {agg_product_performance.count()} records")
print(f"  Agg_Customer_LTV: {agg_customer_ltv.count()} records")
print(f"  Agg_Category_Performance: {agg_category_performance.count()} records")

print("\n✓ Silver to Gold transformation completed successfully!")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Business Insights Queries

# COMMAND ----------

# Create views for SQL analysis
dim_customer.createOrReplaceTempView("dim_customer")
dim_product.createOrReplaceTempView("dim_product")
dim_date.createOrReplaceTempView("dim_date")
fact_sales.createOrReplaceTempView("fact_sales")
agg_daily_sales.createOrReplaceTempView("agg_daily_sales")
agg_product_performance.createOrReplaceTempView("agg_product_performance")
agg_customer_ltv.createOrReplaceTempView("agg_customer_ltv")

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Top 5 Products by Revenue
# MAGIC SELECT 
# MAGIC   product_name,
# MAGIC   category,
# MAGIC   total_revenue,
# MAGIC   total_quantity_sold,
# MAGIC   number_of_orders
# MAGIC FROM agg_product_performance
# MAGIC ORDER BY total_revenue DESC
# MAGIC LIMIT 5

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Monthly Revenue Trend
# MAGIC SELECT 
# MAGIC   d.year,
# MAGIC   d.month,
# MAGIC   d.month_name,
# MAGIC   SUM(ds.total_revenue) as monthly_revenue,
# MAGIC   SUM(ds.total_orders) as monthly_orders
# MAGIC FROM agg_daily_sales ds
# MAGIC JOIN dim_date d ON ds.date_key = d.date_key
# MAGIC GROUP BY d.year, d.month, d.month_name
# MAGIC ORDER BY d.year, d.month

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Customer Segmentation Analysis
# MAGIC SELECT 
# MAGIC   customer_segment,
# MAGIC   ltv_segment,
# MAGIC   COUNT(*) as customer_count,
# MAGIC   ROUND(AVG(lifetime_value), 2) as avg_ltv,
# MAGIC   ROUND(SUM(lifetime_value), 2) as total_revenue
# MAGIC FROM agg_customer_ltv
# MAGIC GROUP BY customer_segment, ltv_segment
# MAGIC ORDER BY total_revenue DESC
