variable "azure_subscription_id" {
  type    = "string"
  default = "c27cfedb-f5e9-45e6-9642-0fad1a5c94e7"
}

variable "azure_tenant_id" {
  type    = "string"
  default = "747381f4-e81f-4a43-bf68-ced6a1e14edf"
}

variable "azure_app_service_oid" {
  type    = "string"
  default = "5b2509b1-64bd-4117-b839-9b0c2b02e02c"
}

variable "azure_webops_group_oid" {
  type    = "string"
  default = "98dc3307-f515-4717-b3c1-7174413e20b0"
}

// These AD ObjectIDs were found via `az ad sp list`
variable "azure_glenm_tf_oid" {
  type    = "string"
  default = "3763b95f-5a74-4aa9-a596-2960bf7fb799"
}

variable "azure_secret_permissions_all" {
  type = "list"

  default = [
    "backup",
    "delete",
    "get",
    "list",
    "purge",
    "recover",
    "restore",
    "set",
  ]
}
