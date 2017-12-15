variable "env-name" {
  type    = "string"
  default = "aap-dev"
}

variable "tags" {
  type = "map"

  default {
    Service     = "AAP"
    Environment = "Dev"
  }
}

resource "random_id" "sql-app-password" {
  byte_length = 32
}

resource "random_id" "sql-ci-password" {
  byte_length = 32
}

resource "azurerm_resource_group" "group" {
  name     = "${var.env-name}"
  location = "ukwest"
  tags     = "${var.tags}"
}

resource "azurerm_storage_account" "storage" {
  name                     = "${replace(var.env-name, "-", "")}storage"
  resource_group_name      = "${azurerm_resource_group.group.name}"
  location                 = "${azurerm_resource_group.group.location}"
  account_tier             = "Standard"
  account_replication_type = "RAGRS"
  enable_blob_encryption   = true

  tags = "${var.tags}"
}

resource "azurerm_storage_container" "csv" {
  name                  = "csv"
  resource_group_name   = "${azurerm_resource_group.group.name}"
  storage_account_name  = "${azurerm_storage_account.storage.name}"
  container_access_type = "private"
}

resource "null_resource" "intermediates" {
  triggers = {
    csv_url = "${azurerm_storage_account.storage.primary_blob_endpoint}${azurerm_storage_container.csv.name}"
  }
}

data "external" "sas-url" {
  program = ["node", "../../tools/container-sas-url-cli-auth.js"]

  query {
    subscription_id = "${var.azure_subscription_id}"
    tenant_id       = "${var.azure_tenant_id}"
    resource_group  = "${azurerm_resource_group.group.name}"
    storage_account = "${azurerm_storage_account.storage.name}"
    container       = "csv"
    permissions     = "rwdl"
    start_date      = "2017-08-16T00:00:00Z"
    end_date        = "2018-08-16T00:00:00Z"
  }
}

resource "azurerm_key_vault" "vault" {
  name                = "${var.env-name}"
  resource_group_name = "${azurerm_resource_group.group.name}"
  location            = "${azurerm_resource_group.group.location}"

  sku {
    name = "standard"
  }

  tenant_id = "${var.azure_tenant_id}"

  access_policy {
    tenant_id          = "${var.azure_tenant_id}"
    object_id          = "${var.azure_webops_group_oid}"
    key_permissions    = []
    secret_permissions = "${var.azure_secret_permissions_all}"
  }

  access_policy {
    tenant_id          = "${var.azure_tenant_id}"
    object_id          = "${var.azure_app_service_oid}"
    key_permissions    = []
    secret_permissions = ["get"]
  }

  enabled_for_deployment          = false
  enabled_for_disk_encryption     = false
  enabled_for_template_deployment = true

  tags = "${var.tags}"
}

module "sql" {
  source              = "../../shared/modules/azure-sql"
  name                = "${var.env-name}"
  resource_group      = "${azurerm_resource_group.group.name}"
  location            = "${azurerm_resource_group.group.location}"
  administrator_login = "aap"

  firewall_rules = [
    {
      label = "Allow azure access"
      start = "0.0.0.0"
      end   = "0.0.0.0"
    },
    {
      label = "Open to the world"
      start = "0.0.0.0"
      end   = "255.255.255.255"
    },
  ]

  audit_storage_account = "${azurerm_storage_account.storage.name}"
  edition               = "Basic"
  collation             = "SQL_Latin1_General_CP1_CI_AS"
  tags                  = "${var.tags}"

  db_users {
    app = "${random_id.sql-app-password.b64}"
  }

  setup_queries = [
    "GRANT SELECT, INSERT, UPDATE, DELETE, ADMINISTER DATABASE BULK OPERATIONS TO app",
    <<SQL
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ;
SQL
    ,
    <<SQL
IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'storageblob_sas')
    ALTER DATABASE SCOPED CREDENTIAL storageblob_sas WITH
        IDENTITY = 'SHARED ACCESS SIGNATURE',
        SECRET = '${data.external.sas-url.result.token}';
ELSE
    CREATE DATABASE SCOPED CREDENTIAL storageblob_sas WITH
        IDENTITY = 'SHARED ACCESS SIGNATURE',
        SECRET = '${data.external.sas-url.result.token}';
SQL
    ,
    <<SQL
IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'storageblob')
    ALTER EXTERNAL DATA SOURCE storageblob SET
        LOCATION = '${null_resource.intermediates.triggers.csv_url}',
        CREDENTIAL = storageblob_sas;
ELSE
    CREATE EXTERNAL DATA SOURCE storageblob WITH (
        TYPE = BLOB_STORAGE,
        LOCATION = '${null_resource.intermediates.triggers.csv_url}',
        CREDENTIAL = storageblob_sas
    );
SQL
    ,
  ]
}

module "sql-ci" {
  source              = "../../shared/modules/azure-sql"
  name                = "${var.env-name}-ci"
  resource_group      = "${azurerm_resource_group.group.name}"
  location            = "${azurerm_resource_group.group.location}"
  administrator_login = "aapci"

  firewall_rules = [
    {
      label = "Allow azure access"
      start = "0.0.0.0"
      end   = "0.0.0.0"
    },
    {
      label = "Open to the world"
      start = "0.0.0.0"
      end   = "255.255.255.255"
    },
  ]

  audit_storage_account = "${azurerm_storage_account.storage.name}"
  edition               = "Basic"
  collation             = "SQL_Latin1_General_CP1_CI_AS"
  tags                  = "${var.tags}"

  db_users {
    ci = "${random_id.sql-ci-password.b64}"
  }

  setup_queries = [
    "GRANT SELECT, INSERT, UPDATE, DELETE, ADMINISTER DATABASE BULK OPERATIONS TO ci",
  ]
}

resource "azurerm_template_deployment" "api" {
  name                = "api"
  resource_group_name = "${azurerm_resource_group.group.name}"
  deployment_mode     = "Incremental"
  template_body       = "${file("../../shared/api-management.template.json")}"

  parameters {
    name           = "${var.env-name}"
    publisherEmail = "noms-studio-webops@digital.justice.gov.uk"
    publisherName  = "HMPPS"
    sku            = "Developer"
  }
}

resource "azurerm_dns_a_record" "api" {
  name                = "${var.env-name}"
  zone_name           = "hmpps.dsd.io"
  resource_group_name = "webops"
  ttl                 = "300"
  records             = ["${azurerm_template_deployment.api.outputs["ip"]}"]
  tags                = "${var.tags}"
}

resource "null_resource" "api-sync" {
  depends_on = ["azurerm_template_deployment.api"]

  triggers {
    swagger  = "https://${azurerm_template_deployment.viper-ssl.parameters.hostname}/api-docs"
    hostname = "${azurerm_dns_a_record.api.name}.${azurerm_dns_a_record.api.zone_name}"
  }

  provisioner "local-exec" {
    command = <<CMD
node ${path.module}/../tools/sync-api.js \
    --tenantId '${var.azure_tenant_id}' \
    --subscriptionId '${var.azure_subscription_id}' \
    --resourceGroupName '${azurerm_resource_group.group.name}' \
    --serviceName '${azurerm_template_deployment.api.parameters.name}' \
    --swaggerDefinition 'https://${azurerm_template_deployment.viper-ssl.parameters.hostname}/api-docs' \
    --path 'analytics' \
    --apiId 'analytics' \
    --username 'viper' \
    --password '${random_id.app-basic-password.b64}' \
    --keyvault '${azurerm_key_vault.vault.vault_uri}' \
    --hostname '${azurerm_dns_a_record.api.name}.${azurerm_dns_a_record.api.zone_name}'
CMD
  }
}
