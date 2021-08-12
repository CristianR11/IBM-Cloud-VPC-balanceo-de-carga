terraform {
  required_providers {
    ibm = {
      source = "IBM-Cloud/ibm"
      version = "~> 1.12.0"
    }
  }
}

provider "ibm" {
  alias  = "south"
  region = "us-south"
}

data "ibm_resource_group" "group" {
  provider = ibm.south
  name = var.resource_group
}

data "ibm_is_ssh_key" "sshkey" {
  name = var.ssh_keyname
}


##############################################################################
# Create a VPC DALLAS
##############################################################################

resource "ibm_is_vpc" "vpc-dal" {
  provider = ibm.south
  name          = "cce-vpc-dal"
  resource_group = data.ibm_resource_group.group.id
}

##############################################################################
# Create Subnet zone DALL
##############################################################################

# Increase count to create subnets in all zones
resource "ibm_is_subnet" "cce-subnet-dal-1" {
  provider = ibm.south
  name            = "cce-subnet-dal-1"
  vpc             = ibm_is_vpc.vpc-dal.id
  zone            = "us-south-1"
  total_ipv4_address_count= "256"
  resource_group  = data.ibm_resource_group.group.id
}

# Increase count to create subnets in all zones
resource "ibm_is_subnet" "cce-subnet-dal-2" {
  provider = ibm.south
  name            = "cce-subnet-dal-2"
  vpc             = ibm_is_vpc.vpc-dal.id
  zone            = "us-south-2"
  total_ipv4_address_count= "256"
  resource_group  = data.ibm_resource_group.group.id
}

##############################################################################
# Desploy instances on DALL
##############################################################################

resource "ibm_is_instance" "cce-vsi-dal" {
  provider = ibm.south
  count    = 2
  name    = "cce-nginx-${count.index + 1}"
  image   = "r006-de4fc543-2ce1-47de-b0b8-b98556a741da"
  profile = "cx2-2x4"

  primary_network_interface {
    subnet = ibm_is_subnet.cce-subnet-dal-${count.index + 1}.id
  }

  vpc       = ibm_is_vpc.vpc-dal.id
  zone      = "us-south-${count.index + 1}"
  keys      = [ibm_is_ssh_key.cce-ssh-dal.id]
  user_data = file("./script.sh")
  resource_group = data.ibm_resource_group.group.id
}

resource "ibm_is_lb" "lb-nginx" {
  name            = "nginx-lb"
  subnets         = ibm_is_subnet.*.id
  resource_group  = data.ibm_resource_group.group.id
}

resource "ibm_is_lb_pool" "lb-nginx-pool" {
  lb                 = ibm_is_lb.lb-nginx.id
  name               = "nginx-lb-pool"
  protocol           = "http"
  algorithm          = "round_robin"
  health_delay       = "15"
  health_retries     = "2"
  health_timeout     = "5"
  health_type        = "http"
  health_monitor_url = "/"
}

resource "ibm_is_lb_listener" "lb-listener" {
  lb                   = ibm_is_lb.lb.id
  port                 = "80"
  protocol             = "http"
  default_pool         = element(split("/", ibm_is_lb_pool.lb-nginx-pool.id), 1)
}