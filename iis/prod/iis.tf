terraform {
    required_version = ">= 0.9.0"
    backend "azure" {
        resource_group_name = "webops-prod"
        storage_account_name = "nomsstudiowebopsprod"
        container_name = "terraform"
        key = "iis-prod.terraform.tfstate"
        arm_subscription_id = "a5ddf257-3b21-4ba9-a28c-ab30f751b383"
        arm_tenant_id = "747381f4-e81f-4a43-bf68-ced6a1e14edf"
    }
}

variable "app-name" {
    type = "string"
    default = "iis-prod"
}
variable "tags" {
    type = "map"
    default {
        Service = "IIS"
        Environment = "Prod"
    }
}

resource "azurerm_resource_group" "group" {
    name = "${var.app-name}"
    location = "ukwest"
    tags = "${var.tags}"
}

resource "random_id" "session-secret" {
    byte_length = 20
}
resource "random_id" "sql-iisuser-password" {
    byte_length = 16
}

resource "azurerm_storage_account" "storage" {
    name = "${replace(var.app-name, "-", "")}storage"
    resource_group_name = "${azurerm_resource_group.group.name}"
    location = "${azurerm_resource_group.group.location}"
    account_type = "Standard_RAGRS"
    enable_blob_encryption = true

    tags = "${var.tags}"
}

variable "log-containers" {
    type = "list"
    default = ["app-logs", "web-logs", "db-logs"]
}
resource "azurerm_storage_container" "logs" {
    count = "${length(var.log-containers)}"
    name = "${var.log-containers[count.index]}"
    resource_group_name = "${azurerm_resource_group.group.name}"
    storage_account_name = "${azurerm_storage_account.storage.name}"
    container_access_type = "private"
}

resource "azurerm_key_vault" "vault" {
    name = "${var.app-name}"
    resource_group_name = "${azurerm_resource_group.group.name}"
    location = "${azurerm_resource_group.group.location}"
    sku {
        name = "standard"
    }
    tenant_id = "${var.azure_tenant_id}"

    access_policy {
        tenant_id = "${var.azure_tenant_id}"
        object_id = "${var.azure_webops_group_oid}"
        key_permissions = ["all"]
        secret_permissions = ["all"]
    }
    access_policy {
        tenant_id = "${var.azure_tenant_id}"
        object_id = "${var.azure_app_service_oid}"
        key_permissions = []
        secret_permissions = ["get"]
    }
    access_policy {
        object_id = "${var.azure_glenm_tfprod_oid}"
        tenant_id = "${var.azure_tenant_id}"
        key_permissions = []
        secret_permissions = ["get", "set"]
    }
    access_policy {
        object_id = "${var.azure_rlazzurs_tfprod_oid}"
        tenant_id = "${var.azure_tenant_id}"
        key_permissions = []
        secret_permissions = ["get", "set"]
    }

    enabled_for_deployment = false
    enabled_for_disk_encryption = false
    enabled_for_template_deployment = true

    tags = "${var.tags}"
}

module "sql" {
    source = "../../shared/modules/azure-sql"
    name = "${var.app-name}"
    resource_group = "${azurerm_resource_group.group.name}"
    location = "${azurerm_resource_group.group.location}"
    administrator_login = "iis"
    firewall_rules = [
        {
            label = "NOMS Studio office"
            start = "${var.ips["office"]}"
            end = "${var.ips["office"]}"
        },
    ]
    audit_storage_account = "${azurerm_storage_account.storage.name}"
    edition = "Standard"
    scale = "S3"
    space_gb = "250"
    collation = "Latin1_General_CS_AS"
    tags = "${var.tags}"

    db_users {
        iisuser = "${random_id.sql-iisuser-password.b64}"
    }

    setup_queries = [
        "IF SCHEMA_ID('HPA') IS NULL EXEC sp_executesql \"CREATE SCHEMA HPA\"",
        "GRANT SELECT ON SCHEMA::HPA TO iisuser",
        "GRANT SELECT ON SCHEMA::IIS TO iisuser",
        "GRANT SELECT, INSERT, DELETE ON SCHEMA::NON_IIS TO iisuser",
    ]
}

resource "azurerm_sql_firewall_rule" "app-access" {
    count = "${length(split(",", azurerm_template_deployment.webapp.outputs["ips"]))}"
    name = "Application IP ${count.index}"
    resource_group_name = "${azurerm_resource_group.group.name}"
    server_name = "${module.sql.server_name}"
    start_ip_address = "${element(split(",", azurerm_template_deployment.webapp.outputs["ips"]), count.index)}"
    end_ip_address = "${element(split(",", azurerm_template_deployment.webapp.outputs["ips"]), count.index)}"
}

resource "azurerm_template_deployment" "webapp" {
    name = "webapp"
    resource_group_name = "${azurerm_resource_group.group.name}"
    deployment_mode = "Incremental"
    template_body = "${file("../../shared/appservice.template.json")}"
    parameters {
        name = "${var.app-name}"
        service = "${var.tags["Service"]}"
        environment = "${var.tags["Environment"]}"
        workers = "2"
        sku_name = "S1"
        sku_tier = "Standard"
    }
}

data "external" "sas-url" {
    program = ["node", "../../tools/container-sas-url.js"]
    query {
        subscription_id = "${var.azure_subscription_id}"
        tenant_id = "${var.azure_tenant_id}"
        resource_group = "${azurerm_resource_group.group.name}"
        storage_account = "${azurerm_storage_account.storage.name}"
        container = "web-logs"
        permissions = "rwdl"
        start_date = "2017-05-15T00:00:00Z"
        end_date = "2217-05-15T00:00:00Z"
    }
}

resource "azurerm_template_deployment" "webapp-weblogs" {
    name = "webapp-weblogs"
    resource_group_name = "${azurerm_resource_group.group.name}"
    deployment_mode = "Incremental"
    template_body = "${file("../../shared/appservice-weblogs.template.json")}"

    parameters {
        name = "${azurerm_template_deployment.webapp.parameters.name}"
        storageSAS = "${data.external.sas-url.result.url}"
    }

    depends_on = ["azurerm_template_deployment.webapp"]
}

resource "azurerm_template_deployment" "insights" {
    name = "${var.app-name}"
    resource_group_name = "${azurerm_resource_group.group.name}"
    deployment_mode = "Incremental"
    template_body = "${file("../../shared/insights.template.json")}"
    parameters {
        name = "${azurerm_template_deployment.webapp.parameters.name}"
        location = "northeurope" // Not in UK yet
        service = "${var.tags["Service"]}"
        environment = "${var.tags["Environment"]}"
        appServiceId = "${azurerm_template_deployment.webapp.outputs["resourceId"]}"
    }
}

resource "azurerm_template_deployment" "webapp-whitelist" {
    name = "webapp-whitelist"
    resource_group_name = "${azurerm_resource_group.group.name}"
    deployment_mode = "Incremental"
    template_body = "${file("../../shared/appservice-whitelist.template.json")}"

    parameters {
        name = "${azurerm_template_deployment.webapp.parameters.name}"
        ip1 = "${var.ips["office"]}"
        ip2 = "${var.ips["quantum"]}"
        ip3 = "${var.ips["health-kick"]}"

        # DOM1 ATOS
        ip4 = "157.203.176.138"
        subnet4 = "255.255.255.254"
        ip5 = "157.203.176.140"
        ip6 = "157.203.177.190"
        subnet6 = "255.255.255.254"
        ip7 = "157.203.177.192"

        # DOM1 Vodafone NAT
        ip8 = "62.25.109.201"
        ip9 = "62.25.109.203"
        ip10 = "212.137.36.233"
        ip11 = "212.137.36.234"
    }

    depends_on = ["azurerm_template_deployment.webapp"]
}

data "external" "vault" {
    program = ["node", "../../tools/keyvault-data.js"]
    query {
        vault = "${azurerm_key_vault.vault.name}"

        client_id = "signon-client-id"
        client_secret = "signon-client-secret"

        administrators = "administrators"

        dashboard_token = "dashboard-token"
        appinsights_api_key = "appinsights-api-key"
    }
}

resource "azurerm_template_deployment" "webapp-config" {
    name = "webapp-config"
    resource_group_name = "${azurerm_resource_group.group.name}"
    deployment_mode = "Incremental"
    template_body = "${file("../webapp-config.template.json")}"

    parameters {
        name = "${azurerm_template_deployment.webapp.parameters.name}"
        DB_USER = "iisuser"
        DB_PASS = "${random_id.sql-iisuser-password.b64}"
        DB_SERVER = "${module.sql.db_server}"
        DB_NAME = "${module.sql.db_name}"
        SESSION_SECRET = "${random_id.session-secret.b64}"
        CLIENT_ID = "${data.external.vault.result.client_id}"
        CLIENT_SECRET = "${data.external.vault.result.client_secret}"
        TOKEN_HOST = "https://signon.service.justice.gov.uk"
        ADMINISTRATORS = "${data.external.vault.result.administrators}"
        APPINSIGHTS_INSTRUMENTATIONKEY = "${azurerm_template_deployment.insights.outputs["instrumentationKey"]}"
    }

    depends_on = ["azurerm_template_deployment.webapp"]
}

resource "azurerm_template_deployment" "webapp-ssl" {
    name = "webapp-ssl"
    resource_group_name = "${azurerm_resource_group.group.name}"
    deployment_mode = "Incremental"
    template_body = "${file("../../shared/appservice-ssl.template.json")}"

    parameters {
        name = "${azurerm_template_deployment.webapp.parameters.name}"
        hostname = "${azurerm_dns_cname_record.cname.name}.${azurerm_dns_cname_record.cname.zone_name}"
        keyVaultId = "${azurerm_key_vault.vault.id}"
        keyVaultCertName = "hpaDOTserviceDOThmppsDOTdsdDOTio"
        service = "${var.tags["Service"]}"
        environment = "${var.tags["Environment"]}"
    }

    depends_on = ["azurerm_template_deployment.webapp"]
}

module "slackhook" {
    source = "../../shared/modules/slackhook"
    app_name = "${azurerm_template_deployment.webapp.parameters.name}"
    azure_subscription = "production"
    channels = ["shef_changes", "hpa"]
}

resource "azurerm_dns_cname_record" "cname" {
    name = "hpa"
    zone_name = "service.hmpps.dsd.io"
    resource_group_name = "webops-prod"
    ttl = "300"
    record = "${var.app-name}.azurewebsites.net"
    tags = "${var.tags}"
}


resource "azurerm_template_deployment" "stats-exposer" {
    name = "stats-exposer-app"
    resource_group_name = "${azurerm_resource_group.group.name}"
    deployment_mode = "Incremental"
    template_body = "${file("../../shared/appservice.template.json")}"
    parameters {
        name = "${var.app-name}-stats-exposer"
        service = "${var.tags["Service"]}"
        environment = "${var.tags["Environment"]}"
        workers = "2"
        sku_name = "S1"
        sku_tier = "Standard"
    }
}

resource "azurerm_template_deployment" "stats-expos-erconfig" {
    name = "stats-exposer-config"
    resource_group_name = "${azurerm_resource_group.group.name}"
    deployment_mode = "Incremental"
    template_body = "${file("../stats-webapp-config.template.json")}"

    parameters {
        name = "${azurerm_template_deployment.stats-exposer.parameters.name}"
        DASHBOARD_TARGET = "https://iis-monitoring.herokuapp.com"
        DASHBOARD_TOKEN = "${data.external.vault.result.dashboard_token}"
        APPINSIGHTS_APP_ID = "5595f5b0-cfb0-4af0-ac47-f46f8abc2c1e"
        APPINSIGHTS_API_KEY = "${data.external.vault.result.appinsights_api_key}"
        APPINSIGHTS_UPDATE_INTERVAL = 15
        APPINSIGHTS_QUERY_week = "traces | where timestamp > ago(7d) | where message == 'AUDIT' | summarize count() by tostring(customDimensions.key)"
        APPINSIGHTS_QUERY_today = "traces | where timestamp > startofday(now()) | where message == 'AUDIT' | summarize count() by tostring(customDimensions.key)"
    }

    depends_on = ["azurerm_template_deployment.stats-exposer"]
}

resource "azurerm_template_deployment" "stats-exposer-github" {
    name = "stats-exposer-github"
    resource_group_name = "${azurerm_resource_group.group.name}"
    deployment_mode = "Incremental"
    template_body = "${file("../../shared/appservice-scm.template.json")}"

    parameters {
        name = "${azurerm_template_deployment.stats-exposer.parameters.name}"
        repoURL = "https://github.com/noms-digital-studio/ai-stats-exposer.git"
        branch = "master"
    }

    depends_on = ["azurerm_template_deployment.stats-exposer"]
}

resource "github_repository_webhook" "stats-exposer-deploy" {
  repository = "ai-stats-exposer"

  name = "web"
  configuration {
    url = "${azurerm_template_deployment.stats-exposer-github.outputs["deployTrigger"]}?scmType=GitHub"
    content_type = "form"
    insecure_ssl = false
  }
  active = true

  events = ["push"]
}

output "advice" {
    value = [
        "Don't forget to set up the SQL instance user/schemas manually.",
        "Application Insights continuous export must also be done manually"
    ]
}
