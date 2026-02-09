# Databricks notebook source
# MAGIC %md
# MAGIC # Bronze to Silver Layer Transformation
# MAGIC 
# MAGIC This notebook performs data cleansing and standardization:
# MAGIC - Remove duplicates
# MAGIC - Handle null values
# MAGIC - Standardize data types
# MAGIC - Apply business rules
# MAGIC - Data quality checks

# COMMAND ----------

from pyspark.sql import SparkSession
from pyspark.sql.functions import *
from pyspark.sql.types import *
from delta.tables import *
import logging

# COMMAND ----------

# MAGIC %md
# MAGIC ## Configuration

# COMMAND ----------

# Storage paths
bronze_path = "abfss://bronze@<storage_account>.dfs.core.windows.net/"
silver_path = "abfss://silver@<storage_account>.dfs.core.windows.net/"

# Date for incremental processing
processing_date = dbutils.widgets.get("processing_date") if dbutils.widgets.get("processing_date") else current_date()

# COMMAND ----------

# MAGIC %md
# MAGIC ## Read Bronze Layer Data

# COMMAND ----------

def read_bronze_table(table_name, date=None):
    """Read data from bronze layer"""
    path = f"{bronze_path}{table_name}/"
    
    if date:
        # Incremental load
        df = spark.read.parquet(path).filter(col("ingestion_date") == date)
    else:
        # Full load
        df = spark.read.parquet(path)
    
    return df

# COMMAND ----------

# Read bronze tables
customers_bronze = read_bronze_table("customers", processing_date)
products_bronze = read_bronze_table("products", processing_date)
orders_bronze = read_bronze_table("orders", processing_date)
order_items_bronze = read_bronze_table("order_items", processing_date)

# COMMAND ----------

# MAGIC %md
# MAGIC ## Data Quality Checks

# COMMAND ----------

def check_null_values(df, table_name, critical_columns):
    """Check for null values in critical columns"""
    null_checks = []
    
    for col_name in critical_columns:
        null_count = df.filter(col(col_name).isNull()).count()
        total_count = df.count()
        null_percentage = (null_count / total_count * 100) if total_count > 0 else 0
        
        null_checks.append({
            "table": table_name,
            "column": col_name,
            "null_count": null_count,
            "total_count": total_count,
            "null_percentage": round(null_percentage, 2)
        })
    
    return null_checks

# COMMAND ----------

def check_duplicates(df, table_name, key_columns):
    """Check for duplicate records"""
    total_count = df.count()
    distinct_count = df.select(key_columns).distinct().count()
    duplicate_count = total_count - distinct_count
    
    return {
        "table": table_name,
        "total_records": total_count,
        "unique_records": distinct_count,
        "duplicate_count": duplicate_count
    }

# COMMAND ----------

# Run quality checks
print("Running Data Quality Checks...")

# Null checks
customer_null_checks = check_null_values(customers_bronze, "customers", ["customer_id", "email"])
product_null_checks = check_null_values(products_bronze, "products", ["product_id", "price"])
order_null_checks = check_null_values(orders_bronze, "orders", ["order_id", "customer_id"])

# Duplicate checks
customer_dup_check = check_duplicates(customers_bronze, "customers", ["customer_id"])
product_dup_check = check_duplicates(products_bronze, "products", ["product_id"])
order_dup_check = check_duplicates(orders_bronze, "orders", ["order_id"])

# COMMAND ----------

# MAGIC %md
# MAGIC ## Transform Customers

# COMMAND ----------

customers_silver = customers_bronze \
    .dropDuplicates(["customer_id"]) \
    .filter(col("customer_id").isNotNull()) \
    .filter(col("email").isNotNull()) \
    .withColumn("email", lower(trim(col("email")))) \
    .withColumn("full_name", concat_ws(" ", col("first_name"), col("last_name"))) \
    .withColumn("registration_year", year(col("registration_date"))) \
    .withColumn("processed_date", current_timestamp()) \
    .select(
        "customer_id",
        "first_name",
        "last_name",
        "full_name",
        "email",
        "city",
        "state",
        "zipcode",
        "registration_date",
        "registration_year",
        "customer_segment",
        "processed_date"
    )

# COMMAND ----------

# MAGIC %md
# MAGIC ## Transform Products

# COMMAND ----------

products_silver = products_bronze \
    .dropDuplicates(["product_id"]) \
    .filter(col("product_id").isNotNull()) \
    .filter(col("price") > 0) \
    .withColumn("profit_margin", 
                round((col("price") - col("cost")) / col("price") * 100, 2)) \
    .withColumn("is_in_stock", when(col("stock_quantity") > 0, True).otherwise(False)) \
    .withColumn("price_category", 
                when(col("price") < 50, "Budget")
                .when(col("price") < 200, "Mid-Range")
                .otherwise("Premium")) \
    .withColumn("processed_date", current_timestamp()) \
    .select(
        "product_id",
        "product_name",
        "category",
        "price",
        "cost",
        "profit_margin",
        "supplier_id",
        "stock_quantity",
        "is_in_stock",
        "rating",
        "price_category",
        "processed_date"
    )

# COMMAND ----------

# MAGIC %md
# MAGIC ## Transform Orders

# COMMAND ----------

orders_silver = orders_bronze \
    .dropDuplicates(["order_id"]) \
    .filter(col("order_id").isNotNull()) \
    .filter(col("customer_id").isNotNull()) \
    .withColumn("order_datetime", 
                to_timestamp(concat(col("order_date"), lit(" "), col("order_time")))) \
    .withColumn("order_year", year(col("order_date"))) \
    .withColumn("order_month", month(col("order_date"))) \
    .withColumn("order_day", dayofmonth(col("order_date"))) \
    .withColumn("order_quarter", quarter(col("order_date"))) \
    .withColumn("day_of_week", dayofweek(col("order_date"))) \
    .withColumn("is_weekend", when(col("day_of_week").isin([1, 7]), True).otherwise(False)) \
    .withColumn("processed_date", current_timestamp()) \
    .select(
        "order_id",
        "customer_id",
        "order_date",
        "order_time",
        "order_datetime",
        "order_year",
        "order_month",
        "order_day",
        "order_quarter",
        "day_of_week",
        "is_weekend",
        "subtotal",
        "discount_amount",
        "tax",
        "total_amount",
        "payment_method",
        "status",
        "shipping_method",
        "processed_date"
    )

# COMMAND ----------

# MAGIC %md
# MAGIC ## Transform Order Items

# COMMAND ----------

order_items_silver = order_items_bronze \
    .dropDuplicates(["order_id", "product_id"]) \
    .filter(col("order_id").isNotNull()) \
    .filter(col("product_id").isNotNull()) \
    .filter(col("quantity") > 0) \
    .withColumn("discount_per_item", 
                round((col("unit_price") * col("quantity") - col("total_price")) / col("quantity"), 2)) \
    .withColumn("processed_date", current_timestamp()) \
    .select(
        "order_id",
        "product_id",
        "quantity",
        "unit_price",
        "total_price",
        "discount_per_item",
        "processed_date"
    )

# COMMAND ----------

# MAGIC %md
# MAGIC ## Write to Silver Layer

# COMMAND ----------

def write_to_silver(df, table_name, partition_cols=None):
    """Write DataFrame to Silver layer using Delta format"""
    path = f"{silver_path}{table_name}/"
    
    writer = df.write.format("delta").mode("overwrite")
    
    if partition_cols:
        writer = writer.partitionBy(partition_cols)
    
    writer.option("overwriteSchema", "true") \
          .save(path)
    
    print(f"✓ Written {df.count()} records to {table_name}")

# COMMAND ----------

# Write all tables to Silver layer
write_to_silver(customers_silver, "customers")
write_to_silver(products_silver, "products")
write_to_silver(orders_silver, "orders", ["order_year", "order_month"])
write_to_silver(order_items_silver, "order_items")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Data Quality Summary

# COMMAND ----------

print("="*60)
print("DATA QUALITY SUMMARY")
print("="*60)

print("\n📊 Record Counts:")
print(f"  Customers: {customers_silver.count()}")
print(f"  Products: {products_silver.count()}")
print(f"  Orders: {orders_silver.count()}")
print(f"  Order Items: {order_items_silver.count()}")

print("\n✓ Bronze to Silver transformation completed successfully!")

# COMMAND ----------

# Create temp views for ad-hoc analysis
customers_silver.createOrReplaceTempView("customers_silver")
products_silver.createOrReplaceTempView("products_silver")
orders_silver.createOrReplaceTempView("orders_silver")
order_items_silver.createOrReplaceTempView("order_items_silver")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Sample Analysis

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Top 10 customers by total spending
# MAGIC SELECT 
# MAGIC   c.customer_id,
# MAGIC   c.full_name,
# MAGIC   c.customer_segment,
# MAGIC   COUNT(DISTINCT o.order_id) as total_orders,
# MAGIC   ROUND(SUM(o.total_amount), 2) as total_spent
# MAGIC FROM customers_silver c
# MAGIC JOIN orders_silver o ON c.customer_id = o.customer_id
# MAGIC WHERE o.status = 'Completed'
# MAGIC GROUP BY c.customer_id, c.full_name, c.customer_segment
# MAGIC ORDER BY total_spent DESC
# MAGIC LIMIT 10
