terraform {
    required_version = ">= 0.9.8"
    backend "s3" {
        bucket = "moj-studio-webops-terraform"
        key = "health-kick-stage.terraform.tfstate"
        region = "eu-west-2"
        encrypt = true
    }
}

variable "app-name" {
    type = "string"
    default = "health-kick-stage"
}
variable "tags" {
    type = "map"
    default {
        Service = "health-kick"
        Environment = "Stage"
    }
}

resource "aws_elastic_beanstalk_application" "app" {
    name = "${var.app-name}"
    description = "${var.app-name}"
}


resource "aws_elastic_beanstalk_environment" "app-env" {
    name = "${var.app-name}"
    application = "${aws_elastic_beanstalk_application.app.name}"
    solution_stack_name = "${var.elastic-beanstalk-single-docker}"
    tier = "WebServer"

    setting {
        namespace = "aws:autoscaling:launchconfiguration"
        name = "InstanceType"
        value = "t2.micro"
    }
    setting {
        namespace = "aws:autoscaling:launchconfiguration"
        name = "IamInstanceProfile"
        value = "aws-elasticbeanstalk-ec2-role"
    }
    setting {
        namespace = "aws:elasticbeanstalk:application"
        name = "Application Healthcheck URL"
        value = "/health"
    }
    setting {
        namespace = "aws:elasticbeanstalk:environment"
        name = "ServiceRole"
        value = "aws-elasticbeanstalk-service-role"
    }
    setting {
        namespace = "aws:elb:listener:443"
        name = "ListenerProtocol"
        value = "HTTPS"
    }
    setting {
        namespace = "aws:elb:listener:443"
        name = "SSLCertificateId"
        value = "${data.aws_acm_certificate.cert.arn}"
    }
    setting {
        namespace = "aws:elb:listener:443"
        name = "InstancePort"
        value = "80"
    }
    setting {
        namespace = "aws:elb:listener:443"
        name = "ListenerProtocol"
        value = "HTTPS"
    }
    setting {
        namespace = "aws:ec2:vpc"
        name = "VPCId"
        value = "${aws_vpc.vpc.id}"
    }
    setting {
        namespace = "aws:ec2:vpc"
        name = "Subnets"
        value = "${aws_subnet.private-a.id}"
    }
    setting {
        namespace = "aws:ec2:vpc"
        name = "ELBSubnets"
        value = "${aws_subnet.public-a.id}"
    }
    setting {
        namespace = "aws:ec2:vpc"
        name = "AssociatePublicIpAddress"
        value = "false"
    }
    setting {
        namespace = "aws:elasticbeanstalk:healthreporting:system"
        name = "SystemType"
        value = "enhanced"
    }
    setting {
        namespace = "aws:elasticbeanstalk:managedactions"
        name = "ManagedActionsEnabled"
        value = "true"
    }
    setting {
        namespace = "aws:elasticbeanstalk:managedactions"
        name = "PreferredStartTime"
        value = "Fri:10:00"
    }
    setting {
        namespace = "aws:elasticbeanstalk:managedactions:platformupdate"
        name = "UpdateLevel"
        value = "minor"
    }
    setting {
        namespace = "aws:elasticbeanstalk:managedactions:platformupdate"
        name = "InstanceRefreshEnabled"
        value = "true"
    }

    tags = "${var.tags}"
}

resource "azurerm_dns_cname_record" "cname" {
    name = "health-kick"
    zone_name = "hmpps.dsd.io"
    resource_group_name = "webops"
    ttl = "60"
    record = "${aws_elastic_beanstalk_environment.app-env.cname}"
}

data "aws_acm_certificate" "cert" {
  domain = "health-kick.hmpps.dsd.io"
}
