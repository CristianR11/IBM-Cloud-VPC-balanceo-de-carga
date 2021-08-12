terraform {
  required_providers {
    ibm = {
      source = "IBM-Cloud/ibm"
      version = "~> 1.29.0"
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

resource "ibm_is_public_gateway" "public_gateway_dal1" {
  name = "nginx-gateway-1"
  vpc  = ibm_is_vpc.vpc-dal.id
  zone = "us-south-1"

  //User can configure timeouts
  timeouts {
    create = "90m"
  }
}

resource "ibm_is_public_gateway" "public_gateway_dal2" {
  name = "nginx-gateway-2"
  vpc  = ibm_is_vpc.vpc-dal.id
  zone = "us-south-2"

  //User can configure timeouts
  timeouts {
    create = "90m"
  }
}

# Increase count to create subnets in all zones
resource "ibm_is_subnet" "cce-subnet-dal-1" {
  provider = ibm.south
  name            = "cce-subnet-dal-1"
  vpc             = ibm_is_vpc.vpc-dal.id
  zone            = "us-south-1"
  total_ipv4_address_count= "256"
  public_gateway  = ibm_is_public_gateway.public_gateway_dal1.id
  resource_group  = data.ibm_resource_group.group.id
}

# Increase count to create subnets in all zones
resource "ibm_is_subnet" "cce-subnet-dal-2" {
  provider = ibm.south
  name            = "cce-subnet-dal-2"
  vpc             = ibm_is_vpc.vpc-dal.id
  zone            = "us-south-2"
  total_ipv4_address_count= "256"
  public_gateway  = ibm_is_public_gateway.public_gateway_dal2.id
  resource_group  = data.ibm_resource_group.group.id
}

resource "ibm_is_security_group" "security_group" {
  name           = "ngnx-lb-sg"
  vpc            = ibm_is_vpc.vpc-dal.id
  resource_group = data.ibm_resource_group.group.id
}

resource "ibm_is_security_group_rule" "security_group_rule_in" {
  group     = ibm_is_security_group.security_group.id
  direction = "inbound"
  remote    = "0.0.0.0/0"
}

resource "ibm_is_security_group_rule" "security_group_rule_out" {
  group     = ibm_is_security_group.security_group.id
  direction = "outbound"
  remote    = "0.0.0.0/0"
}

##############################################################################
# Desploy instances on DALL
##############################################################################

resource "ibm_is_instance" "cce-vsi-dal-1" {
  provider = ibm.south
  name    = "cce-nginx-1"
  image   = "r006-988caa8b-7786-49c9-aea6-9553af2b1969"
  profile = "cx2-2x4"

  primary_network_interface {
    subnet = ibm_is_subnet.cce-subnet-dal-1.id
    security_groups = [ibm_is_security_group.security_group.id]
  }

  vpc       = ibm_is_vpc.vpc-dal.id
  zone      = "us-south-1"
  keys      = [data.ibm_is_ssh_key.sshkey.id]
  user_data = file("./script.sh")
  resource_group = data.ibm_resource_group.group.id
}

resource "ibm_is_instance" "cce-vsi-dal-2" {
  provider = ibm.south
  name    = "cce-nginx-2"
  image   = "r006-988caa8b-7786-49c9-aea6-9553af2b1969"
  profile = "cx2-2x4"

  primary_network_interface {
    subnet = ibm_is_subnet.cce-subnet-dal-2.id
    security_groups = [ibm_is_security_group.security_group.id]
  }

  vpc       = ibm_is_vpc.vpc-dal.id
  zone      = "us-south-2"
  keys      = [data.ibm_is_ssh_key.sshkey.id]
  user_data = file("./script.sh")
  resource_group = data.ibm_resource_group.group.id
}

resource "ibm_is_lb" "lb-nginx" {
  name            = "nginx-lb"
  subnets         = [ibm_is_subnet.cce-subnet-dal-1.id, ibm_is_subnet.cce-subnet-dal-2.id]
  resource_group  = data.ibm_resource_group.group.id
  security_groups = [ibm_is_security_group.security_group.id]
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

resource "ibm_is_lb_pool_member" "lb-server-1" {
  lb             = ibm_is_lb.lb-nginx.id
  pool           = ibm_is_lb_pool.lb-nginx-pool.id
  port           = 80
  target_address     = ibm_is_instance.cce-vsi-dal-1.primary_network_interface[0].primary_ipv4_address
  weight         = 60
}

resource "ibm_is_lb_pool_member" "lb-server-2" {
  lb             = ibm_is_lb.lb-nginx.id
  pool           = ibm_is_lb_pool.lb-nginx-pool.id
  port           = 80
  target_address = ibm_is_instance.cce-vsi-dal-2.primary_network_interface[0].primary_ipv4_address 
  weight         = 60
}

resource "ibm_is_lb_listener" "lb-listener" {
  lb                   = ibm_is_lb.lb-nginx.id
  port                 = "80"
  protocol             = "http"
  default_pool         = element(split("/", ibm_is_lb_pool.lb-nginx-pool.id), 1)
}