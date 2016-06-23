################# VARIABLES ################
variable "region" {}
variable "az" {}
variable "vpc_range" {}
variable "aus_vpn_gw" {}
variable "zone_first" {
  default = {}
}
variable "pfsense_ami" {
  default = {}
}
variable "main_vpc_subnet" {
  default = {}
}
variable "grid_vpc_subnet" {
  default = {}
}
variable "main_vpc" {
  default = {}
}
variable "owner" {}

variable "main_chef_environment" {
  default = {}
}
variable "grid_chef_environment" {
  default = {}
}

################# VPC #################
resource "aws_vpc" "wix-staging" {
    cidr_block           = "10.100.0.0/16"
    enable_dns_hostnames = false
    enable_dns_support   = true
    instance_tenancy     = "default"
    tags {
        "Name" = "wix-staging"
    }
}
#####INTERNET GATEWAY##############
resource "aws_internet_gateway" "wix-staging-ig" {
    vpc_id = "${aws_vpc.wix-staging.id}"
    tags {
        "Name" = "wix-staging internet gateway"
    }
}

############# SUBNETS ##################
# this section uses another unset variable is - az for availability zone
resource "aws_subnet" "wix-staging-main-subnet" {
    vpc_id                  = "${aws_vpc.wix-staging.id}"
    cidr_block              = "10.100.0.0/24"
    availability_zone       = "us-west-2b"
    map_public_ip_on_launch = false
    tags {
        "Name" = "wix-staging subnet"
    }
}
############## SECURITY GROUPS ##############
resource "aws_security_group" "wix-staging-main-sg" {
    name        = "Main SG"
    vpc_id      = "${aws_vpc.wix-staging.id}"

    ingress {
        from_port       = 0
        to_port         = 0
        protocol        = "-1"
        cidr_blocks     = ["0.0.0.0/0"]
    }

    egress {
        from_port       = 0
        to_port         = 0
        protocol        = "-1"
        cidr_blocks     = ["0.0.0.0/0"]
    }

    tags {
        "Name" = "wix-staging-main-security-group"
    }
}
############## INSTANCES #################
resource "aws_instance" "staging-instance" {
    ami                         = "ami-b57cb8d5"
    availability_zone           = "us-west-2b"
    ebs_optimized               = "false"
    instance_type               = "m4.large"
    monitoring                  = false
    key_name                    = "zozo"
    subnet_id                   = "${aws_subnet.wix-staging-main-subnet.id}"
    vpc_security_group_ids      = ["${aws_security_group.wix-staging-main-sg.id}"]
    associate_public_ip_address = true
    #private_ip                  = "${lookup(var.grid_vpc_subnet, var.region)}${255-lookup(var.zone_first, var.az)}.254"
    source_dest_check           = 0
    #TODO remove the below comment
    disable_api_termination     = false
    root_block_device {
        volume_type           = "gp2"
        volume_size           = 200
        delete_on_termination = true
    }
    tags {
        "Name" = "staging instance"
    }
}

#Separated to null_resource to prevent recreation of the instance in case of failure
resource "null_resource" "staging-instance" {
    triggers {
        staging_instance_id = "${aws_instance.staging-instance.id}"
    }
    connection={
        host="${aws_instance.staging-instance.public_ip}"
        user="admin"
        private_key="${file("~/.ssh/zozo.pem")}"
        port="22"
    }

    #add external ip of the pfsence node to chef iptables so it will allow access for chef
    provisioner "local-exec" {
        command = "echo ${aws_instance.staging-instance.public_ip} staging0.awz.wixpress.com"
    }

    provisioner "local-exec" {
        command = "knife node delete -y staging0.awz.wixpress.com || echo 'Not Found'"
    }

    provisioner "local-exec" {
        command = "knife client delete -y staging0.awz.wixpress.com || echo Not Found"
    }

    #NOTE 
    provisioner "local-exec" {
        command = "ssh chef.wixpress.com 'sudo iptables -A INPUT -s ${aws_instance.staging-instance.public_ip}/32 -p tcp -m tcp --dport 443 -j ACCEPT'"
    }

    provisioner "chef"  {
        #TODO need to change based on location
        skip_install = false
        environment = "staging"
        run_list = ["wix-users", "wix-base"]
        node_name = "staging0.awz.wixpress.com"
        secret_key = "${file(".chef/data_bag_secret")}"
        server_url = "https://chef.wixpress.com/"
        validation_client_name = "chef-validator"
        validation_key = "${file(".chef/validation.pem")}"
        version = "12.4.1"
    }
}
###################### ROUTING TABLES ##############
resource "aws_route_table" "wix-staging-rt" {
    vpc_id     = "${aws_vpc.wix-staging.id}"

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.wix-staging-ig.id}"
    }

    propagating_vgws = []

    tags {
        "Name" = "wix-staging routing table"
    }
}
resource "aws_route_table_association" "wix-stagingdefault-route" {
    route_table_id = "${aws_route_table.wix-staging-rt.id}"
    subnet_id = "${aws_subnet.wix-staging-main-subnet.id}"
}
