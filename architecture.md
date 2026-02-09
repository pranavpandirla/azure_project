# Azure E-commerce Data Pipeline - Architecture

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         DATA SOURCES                                     │
│                                                                          │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                │
│   │  Customers   │  │   Products   │  │    Orders    │                 │
│   │   (CSV)      │  │    (CSV)     │  │    (CSV)     │                 │
│   └──────────────┘  └──────────────┘  └──────────────┘                 │
└─────────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                    INGESTION LAYER                                       │
│                                                                          │
│                    ┌──────────────────────┐                             │
│                    │  Azure Data Factory  │                             │
│                    │  (Orchestration)     │                             │
│                    └──────────────────────┘                             │
└─────────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                 STORAGE LAYER (Data Lake Gen2)                           │
│                                                                          │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐         │
│  │   BRONZE     │  →   │   SILVER     │  →   │    GOLD      │         │
│  │   (Raw)      │      │  (Cleaned)   │      │  (Curated)   │         │
│  │              │      │              │      │              │         │
│  │ • Parquet    │      │ • Parquet    │      │ • Parquet    │         │
│  │ • Partitioned│      │ • Validated  │      │ • Star       │         │
│  │ • Immutable  │      │ • Deduped    │      │   Schema     │         │
│  └──────────────┘      └──────────────┘      └──────────────┘         │
└─────────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                 TRANSFORMATION LAYER                                     │
│                                                                          │
│                    ┌──────────────────────┐                             │
│                    │  Azure Databricks    │                             │
│                    │  (PySpark)           │                             │
│                    │                      │                             │
│                    │ • Data Cleansing     │                             │
│                    │ • Transformation     │                             │
│                    │ • Aggregation        │                             │
│                    │ • Quality Checks     │                             │
│                    └──────────────────────┘                             │
└─────────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────────┐
│               DATA WAREHOUSE LAYER                                       │
│                                                                          │
│                  ┌────────────────────────┐                             │
│                  │ Azure Synapse Analytics│                             │
│                  │                        │                             │
│                  │ Dimension Tables:      │                             │
│                  │ • Dim_Customer         │                             │
│                  │ • Dim_Product          │                             │
│                  │ • Dim_Date             │                             │
│                  │                        │                             │
│                  │ Fact Tables:           │                             │
│                  │ • Fact_Sales           │                             │
│                  │                        │                             │
│                  │ Aggregate Tables:      │                             │
│                  │ • Daily Sales          │                             │
│                  │ • Customer LTV         │                             │
│                  │ • Product Performance  │                             │
│                  └────────────────────────┘                             │
└─────────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                  ANALYTICS & BI LAYER                                    │
│                                                                          │
│                    ┌──────────────────────┐                             │
│                    │     Power BI         │                             │
│                    │                      │                             │
│                    │ • Sales Dashboards   │                             │
│                    │ • Customer Analytics │                             │
│                    │ • Product Insights   │                             │
│                    └──────────────────────┘                             │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                     SUPPORTING SERVICES                                  │
│                                                                          │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐               │
│  │  Key Vault   │   │ Azure Monitor│   │   App        │               │
│  │  (Secrets)   │   │ (Monitoring) │   │   Insights   │               │
│  └──────────────┘   └──────────────┘   └──────────────┘               │
└─────────────────────────────────────────────────────────────────────────┘
```

## Data Flow Details

### 1. Ingestion (Bronze Layer)
- **Input:** CSV files from source systems
- **Process:** 
  - Data Factory copies raw data to Bronze container
  - Minimal transformation (CSV → Parquet)
  - Metadata added (ingestion timestamp, source)
- **Output:** Raw Parquet files, partitioned by ingestion date

### 2. Transformation (Silver Layer)
- **Input:** Bronze layer Parquet files
- **Process (Databricks):**
  - Data quality checks
  - Remove duplicates
  - Handle null values
  - Standardize data types
  - Apply business rules
  - Add derived columns
- **Output:** Cleaned Parquet files, optimized schema

### 3. Aggregation (Gold Layer)
- **Input:** Silver layer Parquet files
- **Process (Databricks):**
  - Create dimension tables (SCD Type 2)
  - Build fact tables
  - Pre-calculate aggregations
  - Implement star schema
- **Output:** Analytics-ready Parquet files

### 4. Data Warehouse (Synapse)
- **Input:** Gold layer Parquet files
- **Process:**
  - Load data into Synapse tables
  - Create views for common queries
  - Implement stored procedures
  - Optimize for query performance
- **Output:** Queryable data warehouse

### 5. Analytics (Power BI)
- **Input:** Synapse views and tables
- **Process:**
  - Connect via DirectQuery or Import
  - Create measures and calculations
  - Build visualizations
  - Publish reports
- **Output:** Interactive dashboards

## Security Architecture

```
┌─────────────────────────────────────────────┐
│         Identity & Access Management        │
│                                             │
│  • Azure Active Directory                  │
│  • Managed Identities                      │
│  • RBAC (Role-Based Access Control)        │
│  • Service Principals                      │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│            Data Protection                   │
│                                             │
│  • Encryption at Rest (AES-256)            │
│  • Encryption in Transit (TLS 1.2+)        │
│  • Key Vault for Secrets                   │
│  • Private Endpoints                       │
│  • Network Security Groups                 │
└─────────────────────────────────────────────┘
```

## Monitoring & Logging

```
┌─────────────────────────────────────────────┐
│          Azure Monitor                       │
│                                             │
│  ┌──────────────┐  ┌──────────────┐        │
│  │ Metrics      │  │ Alerts       │        │
│  │ • Pipeline   │  │ • Failures   │        │
│  │ • Cluster    │  │ • Performance│        │
│  │ • Query      │  │ • Anomalies  │        │
│  └──────────────┘  └──────────────┘        │
│                                             │
│  ┌──────────────┐  ┌──────────────┐        │
│  │ Logs         │  │ Dashboards   │        │
│  │ • Activity   │  │ • Pipeline   │        │
│  │ • Diagnostic │  │ • Data Quality│       │
│  │ • Audit      │  │ • Performance│        │
│  └──────────────┘  └──────────────┘        │
└─────────────────────────────────────────────┘
```

## Key Design Principles

### 1. Medallion Architecture
- **Bronze:** Preserve raw data for auditability
- **Silver:** Provide clean, validated data
- **Gold:** Deliver business-ready analytics

### 2. Scalability
- Horizontal scaling with Databricks clusters
- Synapse scalable compute (pause/resume)
- Partitioning for parallel processing

### 3. Reliability
- Retry logic in pipelines
- Idempotent transformations
- Automated error handling

### 4. Cost Optimization
- Auto-pause for idle resources
- Lifecycle policies for storage
- Serverless options where applicable

### 5. Security
- Principle of least privilege
- Encryption everywhere
- Audit logging
- Network isolation
