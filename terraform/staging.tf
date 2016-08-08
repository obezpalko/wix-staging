################# VARIABLES ################
variable "region" {}
variable "az" {}
variable "vpc_range" {}
variable "aus_vpn_gw" {}
variable "zone_first" { default = {} }
variable "pfsense_ami" { default = {} }
variable "main_vpc_subnet" { default = {} }
variable "grid_vpc_subnet" { default = {} }
variable "main_vpc" { default = {} }
variable "owner" {}
variable "main_chef_environment" { default = {} }
variable "grid_chef_environment" { default = {} }
variable "count" {default = "1" }

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
resource "aws_subnet" "wix-staging-internal-subnet" {
    vpc_id                  = "${aws_vpc.wix-staging.id}"
    cidr_block              = "10.100.100.0/24"
    availability_zone       = "us-west-2b"
    map_public_ip_on_launch = false
    tags {
        "Name" = "wix-staging internal subnet"
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
    ami                         = "ami-6c9a5a0c"
    count                       = "${var.count}"
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
# #Separated to null_resource to prevent recreation of the instance in case of failure
resource "null_resource" "staging-instance" {
    count = "${var.count}"
    triggers {
        staging_instance_id = "${aws_instance.staging-instance.*.id[count.index]}"
    }
    connection={
        host="${aws_instance.staging-instance.*.public_ip[count.index]}"
        user="admin"
        private_key="${file("~/.ssh/zozo.pem")}"
        port="22"
    }

    #add external ip of the pfsence node to chef iptables so it will allow access for chef
    provisioner "local-exec" {
        command = "echo ${aws_instance.staging-instance.*.public_ip[count.index]} node-${format("%02d", count.index)}.staging.wixpress.com"
    }

    provisioner "local-exec" {
        command = "knife node delete -y node-${format("%02d",count.index)}.staging.wixpress.com -c ~/chef-repo/.chef/knife.rb || echo 'Not Found'"
    }

    provisioner "local-exec" {
        command = "knife client delete -y node-${format("%02d",count.index)}.staging.wixpress.com -c ~/chef-repo/.chef/knife.rb  || echo Not Found"
    }

    # open iptables on chef
    provisioner "local-exec" {
        command = "ssh chef.wixpress.com 'sudo iptables -A INPUT -s ${aws_instance.staging-instance.*.public_ip[count.index]}/32 -p tcp -m multiport --dports 80,443 -j ACCEPT'"
    }
    provisioner "remote-exec" {
      inline = [
        "echo ${aws_instance.staging-instance.*.public_ip[count.index]} node-${format("%02d",count.index)}.staging.wixpress.com",
        "sudo sh -c 'hostname node-${format("%02d",count.index)}.staging.wixpress.com ; echo node-${format("%02d",count.index)}.staging.wixpress.com > /etc/hostname'",
        "sudo rm /etc/chef/client.pem",
        "sudo apt-get update"
      ]
    }

    provisioner "chef"  {
        #TODO need to change based on location
        skip_install = false
        environment = "staging"
        run_list = ["recipe[wix-base-minimal]", "recipe[wix-users::sysadmins]", "recipe[sudo]"]
        node_name = "node-${format("%02d",count.index)}.staging.wixpress.com"
        secret_key = "${file(".chef/data_bag_secret")}"
        server_url = "https://chef.wixpress.com/"
        validation_client_name = "chef-validator"
        validation_key = "${file(".chef/validation.pem")}"
        version = "12.11.18"
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

resource "aws_network_interface" "staging-instance-eni" {
    count             = "${var.count}"
    subnet_id         = "${aws_subnet.wix-staging-internal-subnet.id}"
    description       = "Internal network interface"
    source_dest_check = false
    attachment {
        instance     = "${element(aws_instance.staging-instance.*.id, count.index)}"
        device_index = 1
    }
}

resource "aws_route53_zone" "ptr" {
  name = "0.100.10.in-addr.arpa"
  vpc_id = "${aws_vpc.wix-staging.id}"

}
resource "aws_route53_record" "ptr" {
  count     = "${var.count}"
  name      = "${format("%s.%s.100.10.in-addr.arpa", element(split(".", element(aws_instance.staging-instance.*.private_ip,count.index)),3), element(split(".", element(aws_instance.staging-instance.*.private_ip,count.index)),2))}"
  ttl       = "300"
  type      = "PTR"
  zone_id   = "${aws_route53_zone.ptr.id}"
  records   = ["${format("node-%02d.staging.wixpress.com", count.index + 1)}"]
}


resource "aws_route53_zone" "staging" {
  name    = "staging.wixpress.com"
  vpc_id  = "${aws_vpc.wix-staging.id}"
}

resource "aws_route53_record" "staging" {
  count     = "${var.count}"
  name      = "${format("node-%02d.staging.wixpress.com", count.index + 1)}"
  ttl       = "300"
  type      = "A"
  zone_id   = "${aws_route53_zone.staging.id}"
  records   = ["${element(aws_instance.staging-instance.*.private_ip, count.index)}"]
}

# resource "aws_route53_record" "ptr-eni" {
#   count     = "${var.count}"
#   name      = "${format("%s.%s.100.10.in-addr.arpa", element(split(".", element(aws_network_interface.staging-instance-eni.*.private_ips[count.index],0)),3), element(split(".", element(aws_network_interface.staging-instance-eni.*.private_ips[count.index],0)),2))}"
#   ttl       = "300"
#   type      = "PTR"
#   zone_id   = "${aws_route53_zone.ptr.id}"
#   records   = ["${format("node-%02d-eni.staging.wixpress.com", count.index + 1)}"]
# }
# resource "aws_route53_record" "staging-eni" {
#   count     = "${var.count}"
#   name      = "${format("node-%02d-eni.staging.wixpress.com", count.index + 1)}"
#   ttl       = "300"
#   type      = "A"
#   zone_id   = "${aws_route53_zone.staging.id}"
#   records    = ["${aws_network_interface.staging-instance-eni.*.private_ips[count.index]}"]
# }

