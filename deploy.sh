#!/bin/bash

# =====================================================
# Azure E-commerce Data Pipeline - Infrastructure Deployment
# This script deploys all required Azure resources
# =====================================================

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# =====================================================
# CONFIGURATION
# =====================================================

print_message "Starting Azure E-commerce Data Pipeline Deployment..."

# Check if required environment variables are set
if [ -z "$RESOURCE_GROUP" ]; then
    print_error "RESOURCE_GROUP environment variable is not set"
    exit 1
fi

if [ -z "$LOCATION" ]; then
    print_error "LOCATION environment variable is not set"
    exit 1
fi

# Set default values
PROJECT_NAME="${PROJECT_NAME:-ecommerce}"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
UNIQUE_SUFFIX="${TIMESTAMP:0:8}"

# Resource names (must be globally unique for some services)
STORAGE_ACCOUNT_NAME="${PROJECT_NAME}datalake${UNIQUE_SUFFIX}"
DATABRICKS_WORKSPACE="${PROJECT_NAME}-databricks-${UNIQUE_SUFFIX}"
SYNAPSE_WORKSPACE="${PROJECT_NAME}-synapse-${UNIQUE_SUFFIX}"
DATA_FACTORY_NAME="${PROJECT_NAME}-adf-${UNIQUE_SUFFIX}"
KEY_VAULT_NAME="${PROJECT_NAME}-kv-${UNIQUE_SUFFIX}"

print_message "Configuration:"
print_message "  Resource Group: $RESOURCE_GROUP"
print_message "  Location: $LOCATION"
print_message "  Storage Account: $STORAGE_ACCOUNT_NAME"
print_message "  Databricks: $DATABRICKS_WORKSPACE"
print_message "  Synapse: $SYNAPSE_WORKSPACE"
print_message "  Data Factory: $DATA_FACTORY_NAME"
print_message "  Key Vault: $KEY_VAULT_NAME"

# =====================================================
# AZURE LOGIN CHECK
# =====================================================

print_message "Checking Azure CLI login status..."
if ! az account show &> /dev/null; then
    print_error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
print_message "Using subscription: $SUBSCRIPTION_ID"

# =====================================================
# CREATE RESOURCE GROUP
# =====================================================

print_message "Creating Resource Group..."
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --output none

print_message "✓ Resource Group created: $RESOURCE_GROUP"

# =====================================================
# CREATE STORAGE ACCOUNT (Data Lake Gen2)
# =====================================================

print_message "Creating Azure Data Lake Storage Gen2..."
az storage account create \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --hierarchical-namespace true \
    --output none

print_message "✓ Storage Account created: $STORAGE_ACCOUNT_NAME"

# Get storage account key
STORAGE_KEY=$(az storage account keys list \
    --resource-group "$RESOURCE_GROUP" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --query "[0].value" -o tsv)

# Create containers for medallion architecture
print_message "Creating storage containers (Bronze, Silver, Gold)..."
for container in bronze silver gold raw archive
do
    az storage container create \
        --name "$container" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$STORAGE_KEY" \
        --output none
    print_message "  ✓ Container created: $container"
done

# =====================================================
# CREATE KEY VAULT
# =====================================================

print_message "Creating Azure Key Vault..."
az keyvault create \
    --name "$KEY_VAULT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --output none

print_message "✓ Key Vault created: $KEY_VAULT_NAME"

# Store storage account key in Key Vault
print_message "Storing secrets in Key Vault..."
az keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "StorageAccountKey" \
    --value "$STORAGE_KEY" \
    --output none

print_message "✓ Secrets stored in Key Vault"

# =====================================================
# CREATE AZURE DATA FACTORY
# =====================================================

print_message "Creating Azure Data Factory..."
az datafactory create \
    --resource-group "$RESOURCE_GROUP" \
    --factory-name "$DATA_FACTORY_NAME" \
    --location "$LOCATION" \
    --output none

print_message "✓ Data Factory created: $DATA_FACTORY_NAME"

# =====================================================
# CREATE AZURE DATABRICKS WORKSPACE
# =====================================================

print_message "Creating Azure Databricks Workspace..."
az databricks workspace create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DATABRICKS_WORKSPACE" \
    --location "$LOCATION" \
    --sku premium \
    --output none

print_message "✓ Databricks Workspace created: $DATABRICKS_WORKSPACE"

# =====================================================
# CREATE AZURE SYNAPSE WORKSPACE
# =====================================================

print_message "Creating Azure Synapse Analytics Workspace..."

# Synapse requires a dedicated storage container
az storage container create \
    --name "synapse" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --account-key "$STORAGE_KEY" \
    --output none

# Create Synapse workspace
SYNAPSE_SQL_ADMIN_USER="sqladmin"
SYNAPSE_SQL_ADMIN_PASSWORD="ComplexPass@$(date +%s)!"

az synapse workspace create \
    --name "$SYNAPSE_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --storage-account "$STORAGE_ACCOUNT_NAME" \
    --file-system "synapse" \
    --sql-admin-login-user "$SYNAPSE_SQL_ADMIN_USER" \
    --sql-admin-login-password "$SYNAPSE_SQL_ADMIN_PASSWORD" \
    --output none

print_message "✓ Synapse Workspace created: $SYNAPSE_WORKSPACE"

# Store Synapse credentials in Key Vault
az keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "SynapseSqlAdminUser" \
    --value "$SYNAPSE_SQL_ADMIN_USER" \
    --output none

az keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "SynapseSqlAdminPassword" \
    --value "$SYNAPSE_SQL_ADMIN_PASSWORD" \
    --output none

# Allow Azure services through Synapse firewall
print_message "Configuring Synapse firewall rules..."
az synapse workspace firewall-rule create \
    --name AllowAllAzureIPs \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --start-ip-address 0.0.0.0 \
    --end-ip-address 0.0.0.0 \
    --output none

# =====================================================
# CONFIGURE MANAGED IDENTITIES AND RBAC
# =====================================================

print_message "Configuring Managed Identities and RBAC..."

# Get Data Factory Managed Identity
ADF_IDENTITY=$(az datafactory show \
    --resource-group "$RESOURCE_GROUP" \
    --factory-name "$DATA_FACTORY_NAME" \
    --query identity.principalId -o tsv)

# Grant Data Factory Storage Blob Data Contributor role
az role assignment create \
    --assignee "$ADF_IDENTITY" \
    --role "Storage Blob Data Contributor" \
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME" \
    --output none

print_message "✓ RBAC configured for Data Factory"

# =====================================================
# DEPLOYMENT SUMMARY
# =====================================================

print_message ""
print_message "=============================================="
print_message "Deployment Complete!"
print_message "=============================================="
print_message ""
print_message "Resource Group: $RESOURCE_GROUP"
print_message "Location: $LOCATION"
print_message ""
print_message "Resources Created:"
print_message "  • Storage Account: $STORAGE_ACCOUNT_NAME"
print_message "  • Data Factory: $DATA_FACTORY_NAME"
print_message "  • Databricks: $DATABRICKS_WORKSPACE"
print_message "  • Synapse: $SYNAPSE_WORKSPACE"
print_message "  • Key Vault: $KEY_VAULT_NAME"
print_message ""
print_message "Next Steps:"
print_message "  1. Upload sample data to the 'raw' container"
print_message "  2. Import Data Factory pipelines from data_factory/ folder"
print_message "  3. Upload Databricks notebooks from databricks/ folder"
print_message "  4. Create Synapse tables using synapse/create_tables.sql"
print_message "  5. Configure linked services in Data Factory"
print_message ""
print_message "Synapse Credentials (stored in Key Vault):"
print_message "  Username: $SYNAPSE_SQL_ADMIN_USER"
print_message "  Password: Stored in Key Vault secret 'SynapseSqlAdminPassword'"
print_message ""
print_message "To retrieve the Synapse password:"
print_message "  az keyvault secret show --vault-name $KEY_VAULT_NAME --name SynapseSqlAdminPassword --query value -o tsv"
print_message ""

# Save deployment info to file
cat > deployment_info.txt <<EOF
Azure E-commerce Data Pipeline - Deployment Information
Generated: $(date)

Resource Group: $RESOURCE_GROUP
Location: $LOCATION
Subscription ID: $SUBSCRIPTION_ID

Resources:
  Storage Account: $STORAGE_ACCOUNT_NAME
  Data Factory: $DATA_FACTORY_NAME
  Databricks Workspace: $DATABRICKS_WORKSPACE
  Synapse Workspace: $SYNAPSE_WORKSPACE
  Key Vault: $KEY_VAULT_NAME

Synapse SQL Admin:
  Username: $SYNAPSE_SQL_ADMIN_USER
  Password: (See Key Vault)

Storage Containers:
  - bronze (raw ingested data)
  - silver (cleaned data)
  - gold (curated analytics)
  - raw (initial landing zone)
  - archive (historical backups)
  - synapse (Synapse workspace files)

Next Steps:
  1. Upload data: az storage blob upload-batch -d raw --account-name $STORAGE_ACCOUNT_NAME -s ./data/
  2. Configure Data Factory linked services
  3. Import and configure Databricks notebooks
  4. Execute Synapse table creation scripts
  5. Set up pipeline triggers in Data Factory
EOF

print_message "Deployment information saved to: deployment_info.txt"
print_message ""
print_message "Happy data engineering! 🚀"
