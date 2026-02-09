# Azure E-commerce Data Engineering Pipeline

## Project Description
An end-to-end data engineering solution on Azure that demonstrates ETL/ELT processes, data lake architecture, and analytics capabilities. This project simulates a real-world e-commerce analytics platform processing customer orders, product information, and generating business insights.

## Architecture Overview

```
Data Sources (CSV) 
    → Azure Data Factory (Ingestion)
    → Azure Data Lake Gen2 (Bronze/Raw Layer)
    → Azure Databricks (Transformation)
    → Azure Data Lake Gen2 (Silver/Cleaned Layer)
    → Azure Databricks (Aggregation)
    → Azure Data Lake Gen2 (Gold/Curated Layer)
    → Azure Synapse Analytics (Data Warehouse)
    → Power BI (Visualization)
```

## Tech Stack
- **Azure Data Factory**: Orchestration and data ingestion
- **Azure Data Lake Storage Gen2**: Medallion architecture (Bronze, Silver, Gold layers)
- **Azure Databricks**: Data transformation using PySpark
- **Azure Synapse Analytics**: Data warehousing and analytics
- **Azure Key Vault**: Secrets management
- **Power BI**: Visualization and reporting
- **Python**: Data generation and testing

## Features
✅ Automated data ingestion pipeline  
✅ Medallion architecture (Bronze → Silver → Gold)  
✅ Data quality checks and validation  
✅ Incremental data loading  
✅ Star schema data modeling  
✅ Performance optimization with partitioning  
✅ Monitoring and logging  
✅ Infrastructure as Code (ARM templates)  

## Project Structure
```
azure-ecommerce-data-pipeline/
├── data/                          # Sample data files
│   ├── customers.csv
│   ├── products.csv
│   └── orders.csv
├── databricks/                    # Databricks notebooks
│   ├── bronze_to_silver.py
│   ├── silver_to_gold.py
│   └── data_quality_checks.py
├── data_factory/                  # ADF pipeline definitions
│   ├── pipeline_ingestion.json
│   └── pipeline_transformation.json
├── synapse/                       # Synapse SQL scripts
│   ├── create_tables.sql
│   ├── create_views.sql
│   └── stored_procedures.sql
├── infrastructure/                # IaC templates
│   ├── deploy.sh
│   └── arm_template.json
├── scripts/                       # Utility scripts
│   ├── generate_sample_data.py
│   └── setup_environment.py
├── docs/                          # Documentation
│   ├── architecture_diagram.png
│   └── setup_guide.md
├── requirements.txt
└── README.md
```

## Prerequisites
- Azure subscription
- Azure CLI installed
- Python 3.8+
- Power BI Desktop (optional)

## Setup Instructions

### 1. Clone the Repository
```bash
git clone https://github.com/yourusername/azure-ecommerce-data-pipeline.git
cd azure-ecommerce-data-pipeline
```

### 2. Install Dependencies
```bash
pip install -r requirements.txt
```

### 3. Generate Sample Data
```bash
python scripts/generate_sample_data.py
```

### 4. Deploy Azure Infrastructure
```bash
# Login to Azure
az login

# Set variables
export RESOURCE_GROUP="rg-ecommerce-pipeline"
export LOCATION="eastus"
export SUBSCRIPTION_ID="your-subscription-id"

# Deploy resources
cd infrastructure
chmod +x deploy.sh
./deploy.sh
```

### 5. Configure Data Factory Pipelines
- Import pipeline JSON files from `data_factory/` folder
- Update linked services with your resource details
- Configure triggers for scheduled execution

### 6. Deploy Databricks Notebooks
- Upload notebooks from `databricks/` to your Databricks workspace
- Create a cluster (Standard_DS3_v2 recommended)
- Attach notebooks to the cluster

### 7. Create Synapse Objects
- Connect to Synapse workspace
- Execute scripts in `synapse/` folder in order

## Usage

### Manual Execution
1. Trigger the Data Factory pipeline `pipeline_ingestion`
2. Monitor execution in ADF monitoring tab
3. Verify data in ADLS Gen2 containers
4. Check transformed data in Synapse Analytics

### Automated Execution
- Pipelines are scheduled to run daily at 2 AM UTC
- Configure triggers in Data Factory for different schedules

## Data Flow

### Bronze Layer (Raw)
- Exact copy of source data
- Partitioned by ingestion date
- Format: CSV/Parquet

### Silver Layer (Cleaned)
- Data quality checks applied
- Standardized schema
- Deduplicated records
- Format: Parquet

### Gold Layer (Curated)
- Business-level aggregations
- Star schema dimensions and facts
- Optimized for analytics
- Format: Parquet

## Key Metrics & KPIs
- Total orders by date
- Revenue by product category
- Customer lifetime value
- Product performance analysis
- Regional sales distribution

## Monitoring & Logging
- Azure Monitor for resource metrics
- Data Factory pipeline logs
- Databricks cluster logs
- Synapse query performance

## Cost Optimization
- Auto-pause for Databricks clusters
- Lifecycle management for ADLS Gen2
- Synapse serverless pools for ad-hoc queries
- Reserved capacity for predictable workloads

## Security
- Azure Key Vault for credentials
- Managed identities for service authentication
- RBAC for access control
- Data encryption at rest and in transit

## Future Enhancements
- [ ] Real-time streaming with Event Hubs
- [ ] Machine learning integration with Azure ML
- [ ] Data cataloging with Azure Purview
- [ ] Delta Lake implementation
- [ ] CDC (Change Data Capture) implementation

## Contributing
Feel free to submit issues and pull requests.

## License
MIT License

## Contact
[Your Name] - [Your Email]  
Project Link: https://github.com/yourusername/azure-ecommerce-data-pipeline
