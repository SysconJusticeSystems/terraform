#!/usr/bin/env python3
import json, subprocess

config = json.load(open("./config.tf.json"))

backend = config["terraform"]["backend"]["azurerm"]
provider = config["provider"]["azurerm"]

subscription_params = ["--subscription", provider["subscription_id"]]

# Ensure that CLI is logged in and can access the relevant subscription
subprocess.run(
    ["az", "account", "get-access-token", *subscription_params],
    check=True, stdout=subprocess.DEVNULL
)

# Activate relevant subscription in CLI
subprocess.run(
    ["az", "account", "set", *subscription_params],
    check=True
)

# Extract storage account key for remote state
key = subprocess.run(
    ["az", "storage", "account", "keys", "list",
        "--resource-group", backend["resource_group_name"],
        "--account-name", backend["storage_account_name"],
        "--query", "[0].value",
        "--output", "tsv",
    ],
    stdout=subprocess.PIPE, encoding='utf8',
    check=True
).stdout

# Init terraform with acquired storage account key
subprocess.run(
    ["terraform", "init", "-backend-config", "access_key=%s" % key],
    check=True
)
