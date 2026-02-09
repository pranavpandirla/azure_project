# Azure E-commerce Data Pipeline - Setup Guide

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Azure Infrastructure Deployment](#azure-infrastructure-deployment)
4. [Data Factory Configuration](#data-factory-configuration)
5. [Databricks Setup](#databricks-setup)
6. [Synapse Analytics Configuration](#synapse-analytics-configuration)
7. [Data Upload and Testing](#data-upload-and-testing)
8. [Monitoring and Troubleshooting](#monitoring-and-troubleshooting)

## Prerequisites

### Required Tools
- Azure CLI (version 2.50 or later)
- Python 3.8 or later
- Git
- Code editor (VS Code recommended)

### Azure Requirements
- Active Azure subscription
- Permissions to create resources
- Sufficient quota for the following services:
  - Storage Accounts
  - Azure Data Factory
  - Azure Databricks
  - Azure Synapse Analytics
  - Azure Key Vault

### Knowledge Prerequisites
- Basic understanding of Azure services
- Familiarity with SQL
- Understanding of ETL/ELT concepts
- Basic knowledge of Python and PySpark

## Initial Setup

### 1. Clone the Repository
```bash
git clone https://github.com/yourusername/azure-ecommerce-data-pipeline.git
cd azure-ecommerce-data-pipeline
```

### 2. Install Python Dependencies
```bash
# Create virtual environment (recommended)
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### 3. Generate Sample Data
```bash
python scripts/generate_sample_data.py
```

This will create the following CSV files in the `data/` directory:
- `customers.csv` (1,000 records)
- `products.csv` (200 records)
- `orders.csv` (5,000 records)
- `order_items.csv` (variable records)

### 4. Azure CLI Login
```bash
az login
az account set --subscription "Your-Subscription-Name-or-ID"
```

## Azure Infrastructure Deployment

### 1. Set Environment Variables
```bash
export RESOURCE_GROUP="rg-ecommerce-pipeline"
export LOCATION="eastus"
export PROJECT_NAME="ecommerce"

# Optional: Set a specific subscription
export SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

### 2. Make Deployment Script Executable
```bash
cd infrastructure
chmod +x deploy.sh
```

### 3. Run Deployment
```bash
./deploy.sh
```

**Deployment Time:** Approximately 15-20 minutes

The script will create:
- Resource Group
- Storage Account (Data Lake Gen2) with containers:
  - `bronze` - Raw ingested data
  - `silver` - Cleaned data
  - `gold` - Curated analytics data
  - `raw` - Landing zone
  - `archive` - Backups
- Azure Data Factory
- Azure Databricks Workspace
- Azure Synapse Analytics Workspace
- Azure Key Vault

### 4. Save Deployment Information
The script generates a `deployment_info.txt` file with all resource names and credentials.

**Important:** Keep this file secure as it contains sensitive information.

## Data Factory Configuration

### 1. Access Data Factory Studio
```bash
# Get Data Factory portal URL
az datafactory show \
    --resource-group $RESOURCE_GROUP \
    --factory-name <your-adf-name> \
    --query "properties.publicNetworkAccess" -o tsv
```

Navigate to: https://adf.azure.com

### 2. Create Linked Services

#### Storage Account Linked Service
1. Go to **Manage** → **Linked Services** → **+ New**
2. Select **Azure Data Lake Storage Gen2**
3. Configure:
   - Name: `ls_adls_gen2`
   - Authentication: **Account key** (retrieve from Key Vault)
   - Account name: Your storage account name

#### Databricks Linked Service
1. **Manage** → **Linked Services** → **+ New**
2. Select **Azure Databricks**
3. Configure:
   - Name: `ls_databricks`
   - Authentication: **Access token**
   - Workspace URL: From Databricks workspace
   - Access token: Generate from Databricks User Settings

#### Synapse Linked Service
1. **Manage** → **Linked Services** → **+ New**
2. Select **Azure Synapse Analytics**
3. Configure:
   - Name: `ls_synapse`
   - Server name: `<synapse-workspace>.sql.azuresynapse.net`
   - Database: Create a dedicated SQL pool
   - Authentication: SQL authentication (credentials in Key Vault)

### 3. Create Datasets

For each data source/destination, create datasets:

**Raw CSV Datasets:**
- `ds_raw_customers_csv`
- `ds_raw_products_csv`
- `ds_raw_orders_csv`
- `ds_raw_order_items_csv`

**Bronze Parquet Datasets:**
- `ds_bronze_customers_parquet`
- `ds_bronze_products_parquet`
- `ds_bronze_orders_parquet`
- `ds_bronze_order_items_parquet`

### 4. Import Pipelines
1. Go to **Author** → **Pipelines**
2. Click **+** → **Import from pipeline template**
3. Upload `data_factory/pipeline_ingestion.json`
4. Update dataset references as needed

### 5. Create Triggers
```json
{
    "name": "trigger_daily_ingestion",
    "properties": {
        "type": "ScheduleTrigger",
        "typeProperties": {
            "recurrence": {
                "frequency": "Day",
                "interval": 1,
                "startTime": "2024-01-01T02:00:00Z",
                "timeZone": "UTC"
            }
        },
        "pipelines": [{
            "pipelineReference": {
                "referenceName": "pipeline_ingestion",
                "type": "PipelineReference"
            }
        }]
    }
}
```

## Databricks Setup

### 1. Access Databricks Workspace
Navigate to Azure Portal → Your Databricks Workspace → **Launch Workspace**

### 2. Create Cluster
1. Go to **Compute** → **Create Cluster**
2. Configuration:
   - Cluster name: `data-engineering-cluster`
   - Cluster mode: **Standard**
   - Databricks runtime: **13.3 LTS** or later
   - Node type: **Standard_DS3_v2** (minimum)
   - Auto-scaling: **Enable** (2-8 workers)
   - Auto-termination: **20 minutes**

### 3. Install Required Libraries
On the cluster, install:
- `delta-spark` (usually pre-installed)
- Any custom libraries from `requirements.txt`

### 4. Upload Notebooks
1. Go to **Workspace** → **Shared**
2. Click **Import**
3. Upload notebooks from `databricks/` folder:
   - `bronze_to_silver.py`
   - `silver_to_gold.py`

### 5. Configure Notebook Parameters
Update the storage paths in each notebook:
```python
bronze_path = "abfss://bronze@<your-storage-account>.dfs.core.windows.net/"
silver_path = "abfss://silver@<your-storage-account>.dfs.core.windows.net/"
gold_path = "abfss://gold@<your-storage-account>.dfs.core.windows.net/"
```

### 6. Mount Storage (Alternative Method)
```python
configs = {
    "fs.azure.account.auth.type": "OAuth",
    "fs.azure.account.oauth.provider.type": "org.apache.hadoop.fs.azurebfs.oauth2.ClientCredsTokenProvider",
    "fs.azure.account.oauth2.client.id": "<application-id>",
    "fs.azure.account.oauth2.client.secret": "<client-secret>",
    "fs.azure.account.oauth2.client.endpoint": "https://login.microsoftonline.com/<directory-id>/oauth2/token"
}

dbutils.fs.mount(
    source = "abfss://bronze@<storage-account>.dfs.core.windows.net/",
    mount_point = "/mnt/bronze",
    extra_configs = configs
)
```

## Synapse Analytics Configuration

### 1. Access Synapse Workspace
Navigate to Azure Portal → Your Synapse Workspace → **Open Synapse Studio**

### 2. Create Dedicated SQL Pool
1. Go to **Manage** → **SQL pools**
2. Click **+ New**
3. Configuration:
   - Name: `ecommerce_dw`
   - Performance level: **DW100c** (can scale up later)

### 3. Create Database Objects
1. Open **Develop** → **SQL scripts** → **+ SQL script**
2. Connect to your dedicated SQL pool
3. Execute scripts in order:
   - `synapse/create_tables.sql`
   - `synapse/create_views.sql`

### 4. Configure External Tables (Optional)
For direct querying of Data Lake:
```sql
-- Create external data source
CREATE EXTERNAL DATA SOURCE gold_data
WITH (
    LOCATION = 'abfss://gold@<storage-account>.dfs.core.windows.net/',
    CREDENTIAL = <credential-name>
);

-- Create external table
CREATE EXTERNAL TABLE ext_fact_sales
WITH (
    LOCATION = 'fact_sales/',
    DATA_SOURCE = gold_data,
    FILE_FORMAT = parquet_format
)
AS SELECT * FROM dw.Fact_Sales;
```

## Data Upload and Testing

### 1. Upload Sample Data to Raw Container
```bash
# Set storage account name
STORAGE_ACCOUNT="<your-storage-account-name>"

# Upload CSV files
az storage blob upload-batch \
    --destination raw \
    --source ./data \
    --account-name $STORAGE_ACCOUNT \
    --pattern "*.csv"
```

### 2. Test Data Factory Pipeline
1. In Data Factory Studio, open `pipeline_ingestion`
2. Click **Debug** to test the pipeline
3. Monitor execution in the **Monitor** tab
4. Verify data in Bronze container

### 3. Test Databricks Notebooks
1. Open `bronze_to_silver` notebook
2. Attach to your cluster
3. Click **Run All**
4. Verify data in Silver container

5. Open `silver_to_gold` notebook
6. Click **Run All**
7. Verify data in Gold container

### 4. Verify Data in Synapse
```sql
-- Check row counts
SELECT 'Dim_Customer' as TableName, COUNT(*) as RowCount FROM dw.Dim_Customer
UNION ALL
SELECT 'Dim_Product', COUNT(*) FROM dw.Dim_Product
UNION ALL
SELECT 'Fact_Sales', COUNT(*) FROM dw.Fact_Sales;

-- Test a view
SELECT TOP 10 * FROM dw.vw_Daily_Sales_Dashboard
ORDER BY Date DESC;
```

## Monitoring and Troubleshooting

### Data Factory Monitoring
- **Monitor** tab: View pipeline runs
- **Alerts**: Set up for pipeline failures
- **Metrics**: Track data movement

### Databricks Monitoring
- **Clusters** → **Metrics**: CPU, memory usage
- **Jobs**: Monitor notebook executions
- **Event logs**: Detailed cluster events

### Synapse Monitoring
- **Monitor** → **SQL requests**: Query performance
- **Pipeline runs**: Integration pipeline status
- **Data movement**: Track data loads

### Common Issues

#### Issue: Pipeline Fails with Authentication Error
**Solution:** 
- Verify Managed Identity has proper RBAC roles
- Check linked service credentials in Key Vault

#### Issue: Databricks Can't Access Storage
**Solution:**
- Verify storage account firewall settings
- Check Databricks workspace networking
- Ensure proper authentication configuration

#### Issue: Synapse Query Performance
**Solution:**
- Update statistics: `UPDATE STATISTICS dw.Fact_Sales`
- Check table distribution
- Review execution plan

### Performance Optimization

1. **Partitioning:**
   - Use date-based partitioning for fact tables
   - Optimize partition sizes (100MB - 1GB)

2. **Compression:**
   - Use Snappy for Parquet files
   - Enable columnstore indexes in Synapse

3. **Caching:**
   - Enable Databricks Delta cache
   - Use Synapse result-set caching

4. **Scaling:**
   - Scale Synapse SQL pool based on workload
   - Auto-scale Databricks clusters

## Next Steps

1. **Set up monitoring dashboards** in Azure Monitor
2. **Configure alerts** for pipeline failures
3. **Implement data quality checks** with Great Expectations
4. **Create Power BI reports** connected to Synapse views
5. **Set up CI/CD** with Azure DevOps or GitHub Actions
6. **Implement incremental loading** for daily updates
7. **Add data cataloging** with Azure Purview

## Resources

- [Azure Data Factory Documentation](https://docs.microsoft.com/azure/data-factory/)
- [Azure Databricks Documentation](https://docs.microsoft.com/azure/databricks/)
- [Azure Synapse Documentation](https://docs.microsoft.com/azure/synapse-analytics/)
- [Medallion Architecture](https://www.databricks.com/glossary/medallion-architecture)

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review Azure service health
3. Consult Azure documentation
4. Open an issue in the GitHub repository
