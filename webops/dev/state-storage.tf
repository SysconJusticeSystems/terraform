resource "azurerm_storage_account" "webops" {
  name = "nomsstudiowebops"
  resource_group_name = "${azurerm_resource_group.group.name}"
  location = "${azurerm_resource_group.group.location}"
  account_kind = "BlobStorage"
  account_tier = "Standard"
  account_replication_type = "GRS"
  access_tier = "Hot"
  enable_blob_encryption = true
  tags {
    Service = "WebOps"
    Environment = "Management"
  }
}

resource "azurerm_storage_container" "terraform" {
  name = "terraform"
  resource_group_name = "${azurerm_resource_group.group.name}"
  storage_account_name = "${azurerm_storage_account.webops.name}"
  container_access_type = "private"
}
