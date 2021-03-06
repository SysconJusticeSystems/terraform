resource "azurerm_dns_zone" "noms" {
    name = "noms.dsd.io"
    resource_group_name = "${azurerm_resource_group.group.name}"
    tags {
        Service = "WebOps"
        Environment = "Management"
    }
}

resource "azurerm_dns_zone" "hmpps" {
    name = "hmpps.dsd.io"
    resource_group_name = "${azurerm_resource_group.group.name}"
    tags {
        Service = "WebOps"
        Environment = "Management"
    }
}

resource "azurerm_dns_ns_record" "service-hmpps" {
    name = "service"
    zone_name = "${azurerm_dns_zone.hmpps.name}"
    resource_group_name = "${azurerm_resource_group.group.name}"
    ttl = "300"

    record {
        nsdname = "ns1-06.azure-dns.com."
    }
    record {
        nsdname = "ns2-06.azure-dns.net."
    }
    record {
        nsdname = "ns3-06.azure-dns.org."
    }
    record {
        nsdname = "ns4-06.azure-dns.info."
    }
    tags {
        Service = "WebOps"
        Environment = "Management"
    }
}

resource "azurerm_dns_ns_record" "digital-prisons" {
    name = "dp"
    zone_name = "${azurerm_dns_zone.hmpps.name}"
    resource_group_name = "${azurerm_resource_group.group.name}"
    ttl = "300"

    record {
        nsdname = "ns1-08.azure-dns.com."
    }
    record {
        nsdname = "ns2-08.azure-dns.net."
    }
    record {
        nsdname = "ns3-08.azure-dns.org."
    }
    record {
        nsdname = "ns4-08.azure-dns.info."
    }
    tags {
        Service = "WebOps"
        Environment = "Management"
    }
}

resource "azurerm_dns_ns_record" "wmt" {
    name = "wmt"
    zone_name = "${azurerm_dns_zone.hmpps.name}"
    resource_group_name = "${azurerm_resource_group.group.name}"
    ttl = "300"

    record {
        nsdname = "ns1-01.azure-dns.com."
    }
    record {
        nsdname = "ns2-01.azure-dns.net."
    }
    record {
        nsdname = "ns3-01.azure-dns.org."
    }
    record {
        nsdname = "ns4-01.azure-dns.info."
    }
    tags {
        Service = "WebOps"
        Environment = "Management"
    }
}

resource "azurerm_dns_ns_record" "nomis-api" {
    name = "nomis-api"
    zone_name = "${azurerm_dns_zone.hmpps.name}"
    resource_group_name = "${azurerm_resource_group.group.name}"
    ttl = "300"

    record {
        nsdname = "ns1-07.azure-dns.com."
    }
    record {
        nsdname = "ns2-07.azure-dns.net."
    }
    record {
        nsdname = "ns3-07.azure-dns.org."
    }
    record {
        nsdname = "ns4-07.azure-dns.info."
    }
    tags {
        Service = "WebOps"
        Environment = "Management"
    }
}

resource "azurerm_dns_cname_record" "search" {
    name = "search"
    zone_name = "${azurerm_dns_zone.noms.name}"
    resource_group_name = "${azurerm_resource_group.group.name}"
    ttl = "300"
    record = "search-noms-api.dsd.io"
}
