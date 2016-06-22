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

/*
#Separated to null_resource to prevent recreation of the instance in case of failure
resource "null_resource" "nat-instance" {
    triggers {
        nat_instance_id = "${aws_instance.nat-instance.id}"
    }
    depends_on = ["aws_network_interface.nat-instance-eni"]

    connection={
        host="${aws_eip.nat-instance-eip.public_ip}"
        user="root"
        private_key="${file("~/.ssh/zozo.pem")}"
        port="22"
    }

    #add external ip of the pfsence node to chef iptables so it will allow access for chef
    provisioner "local-exec" {
        command = "echo ${aws_instance.nat-instance.public_ip} pfsense-${var.az}.${lookup(var.grid_chef_environment, var.region)}.wixpress.com"
    }

    provisioner "local-exec" {
        command = "knife node delete -y pfsense-${var.az}.${lookup(var.grid_chef_environment, var.region)}.wixpress.com || echo 'Not Found'"
    }

    provisioner "local-exec" {
        command = "knife client delete -y pfsense-${var.az}.${lookup(var.grid_chef_environment, var.region)}.wixpress.com || echo Not Found"
    }

    #NOTE 
    provisioner "local-exec" {
        command = "ssh chef.wixpress.com 'sudo iptables -A INPUT -s ${aws_eip.nat-instance-eip.public_ip}/32 -p tcp -m tcp --dport 443 -j ACCEPT'"
    }

    provisioner "chef"  {
        #TODO need to change based on location
        skip_install = true
        environment = "production_ccd"
        run_list = ["wix-pfsense"]
        node_name = "pfsense-${var.az}.${lookup(var.grid_chef_environment, var.region)}.wixpress.com"
        secret_key = "${file(".chef/data_bag_secret")}"
        server_url = "https://chef.wixpress.com/"
        validation_client_name = "chef-validator"
        validation_key = "${file(".chef/validation.pem")}"
        #version = "12.4.1"
    }
}
#the order here is important. it will not work after the creation of additional interface.
resource "aws_eip" "nat-instance-eip" {
  instance = "${aws_instance.nat-instance.id}"
  #network_interface = "${aws_network_interface.nat-instance-eni.id}"
  associate_with_private_ip = "${aws_instance.nat-instance.private_ip}"
  vpc      = true
}

resource "aws_network_interface" "nat-instance-eni" {
    subnet_id         = "${aws_subnet.wix-code-int-nat-subnet.id}"
    description       = "Internal network interface"
    private_ips       = ["${lookup(var.grid_vpc_subnet, var.region)}${255-1-lookup(var.zone_first, var.az)}.254"]
    security_groups   = ["${aws_security_group.NATSG.id}"]
    source_dest_check = false
    depends_on        = [ "aws_eip.nat-instance-eip", "aws_route_table.wix-code-mgmnt-docker-hosts", "aws_route_table.wix-code-ext-rt" ]
    attachment {
        instance     = "${aws_instance.nat-instance.id}"
        device_index = 1
    }
}
*/
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
/*
resource "aws_route_table" "wix-code-nat-ext-rt" {
    vpc_id  = "${aws_vpc.wix-code-docker-grid.id}"

    #TODO check if that route is neeed.
    route {
        cidr_block = "${lookup(var.main_vpc_subnet, var.region)}${var.vpc_range}"
        vpc_peering_connection_id = "${aws_vpc_peering_connection.wix-code-to-wix-aws.id}"
    }

    route {
        cidr_block = "${var.aus_vpn_gw}"
        gateway_id = "${aws_vpn_gateway.grid_to_austin_vpn_gw.id}"
    }

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.wix-code-ig.id}"
    }

    propagating_vgws = []

    tags {
        "Name" = "wix-code-nat-ext-rt-${var.region}"
    }
}

resource "aws_route_table" "wix-code-mgmnt-docker-hosts" {
    vpc_id  = "${aws_vpc.wix-code-docker-grid.id}"
    route {
        cidr_block = "${lookup(var.main_vpc_subnet, var.region)}${var.vpc_range}"
        vpc_peering_connection_id = "${aws_vpc_peering_connection.wix-code-to-wix-aws.id}"
    }

    #TODO - check if this route is used by packer 
    route {
        cidr_block = "0.0.0.0/0"
        instance_id = "${aws_instance.nat-instance.id}"
    }
    propagating_vgws = ["${aws_vpn_gateway.grid_to_austin_vpn_gw.id}"]
    tags {
        "Name" = "wix-code-mgmnt-docker-hosts ${var.region}${var.az}"
    }
}

resource "aws_route_table" "wix-code-internal-only-rt" {
    vpc_id  = "${aws_vpc.wix-code-docker-grid.id}"
    tags {
        "Name" = "wix-code-internal-only ${var.region}"
    }
}

############## ROUTE TABLE ASSOCIATION #####################
#
#TODO wrong in C zone
resource "aws_route_table_association" "wix-code-ext-rt-to-wix-code-dockers-ext-subnet" {
    route_table_id = "${aws_route_table.wix-code-ext-rt.id}"
    subnet_id = "${aws_subnet.wix-code-dockers-ext-subnet.id}"
}
resource "aws_route_table_association" "wix-code-mgmnt-docker-hosts-to-wix-code-mgmnt-subnet" {
    route_table_id = "${aws_route_table.wix-code-mgmnt-docker-hosts.id}"
    subnet_id = "${aws_subnet.wix-code-mgmnt-subnet.id}"
}
resource "aws_route_table_association" "wix-code-nat-ext-rt-to-wix-code-ext-nat" {
    route_table_id = "${aws_route_table.wix-code-nat-ext-rt.id}"
    subnet_id = "${aws_subnet.wix-code-ext-nat.id}"
}
*/
resource "aws_route_table_association" "wix-stagingdefault-route" {
    route_table_id = "${aws_route_table.wix-staging-rt.id}"
    subnet_id = "${aws_subnet.wix-staging-main-subnet.id}"
}
