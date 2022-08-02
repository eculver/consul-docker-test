module "primary_clients" {
   source = "../../modules/clients"

   persistent_data = true
   datacenter = "primary"
   default_config = {
      "agent-conf.hcl" = local.agent_conf
   }
   default_name_prefix = "consul-client${local.cluster_id}-"
   default_networks = [docker_network.consul_primary_network.name]
   default_image = docker_image.consul.name
   extra_args = module.primary_servers.join

   clients = [
      {
         "name": "consul-primary-ui${local.cluster_id}",
         "extra_args": ["-ui"],
         "ports": {
            "http": {
               "internal": 8500,
               "external": 8500,
               "protocol": "tcp",
            },
            "dns": {
               "internal": 8600,
               "external": 8600,
               "protocol": "udp",
            },
         }
      },
      {
         // mostly defaults here - name will be consul-client${local.cluster_id}-primary-1
         // will have an agent with the socat service running along with a sidecar proxy
         // we will need to spawn an envoy image into this name space
         "name": "consul-primary-api-v1-manager${local.cluster_id}",
         "extra_args": ["-grpc-port=8502"],
         "config": {
            "agent-conf.hcl" = local.agent_conf
            "api-v1.hcl" = file("${path.module}/consul-config/api-v1.hcl")
         },
         "ports": {
            "http": {
               "internal": 8500,
               "protocol": "tcp"
            },
            "envoy-admin": {
               "internal": 19000,
               "external": 19003,
               "protocol": "tcp"
            },
         }
      },
      {
         "name": "consul-primary-web-manager${local.cluster_id}",
         "extra_args": ["-grpc-port=8502"],
         "config": {
            "agent-conf.hcl" = local.agent_conf
            "web.hcl" = file("${path.module}/consul-config/web.hcl")
         },
         "ports": {
            "http": {
               "internal": 8500,
               "protocol": "tcp"
            },
            "web-external": {
               "internal": 10000,
               "external": 10001,
               "protocol": "tcp"
            },
            "envoy-admin": {
               "internal": 19000,
               "external": 19002,
               "protocol": "tcp"
            },
         }
      },
      {
         "name": "consul-primary-gateway-manager${local.cluster_id}",
         "networks": [docker_network.consul_primary_network.name, docker_network.consul_bridge_network.name],
         "extra_args": [
            "-grpc-port=8502",
            "-bind=0.0.0.0",
            "-advertise", "{{ GetInterfaceIP \"eth0\" }}",
            "-advertise-wan", "{{ GetInterfaceIP \"eth1\" }}",
         ],
         "config": {
            "agent-conf.hcl" = local.agent_conf
         },
         "ports": {
            "http": {
               "internal": 8500,
               "protocol": "tcp"
            },
            "envoy-admin": {
               "internal": 19000,
               "external": 19001,
               "protocol": "tcp"
            }
         }
      },
      {
         "name": "consul-primary-api-v2-manager${local.cluster_id}",
         "networks": [docker_network.consul_primary_network.name],
         "extra_args": [
            "-grpc-port=8502",
            "-bind=0.0.0.0",
            "-advertise", "{{ GetInterfaceIP \"eth0\" }}",
         ],
         "config": {
            "agent-conf.hcl" = local.agent_conf
            "api-v2.hcl" = file("${path.module}/consul-config/api-v2.hcl")
         },
         "ports": {
            "http": {
               "internal": 8500,
               "protocol": "tcp"
            },
            "envoy-admin": {
               "internal": 19000,
               "external": 19004,
               "protocol": "tcp"
            }
         }
      },
   ]
}

module "primary-gateway" {
   source = "../modules/consul-envoy"

   consul_envoy_image = var.consul_envoy_image
   name = "primary-gateway${local.cluster_id}"
   consul_manager = module.primary_clients.clients[3].name
   container_network_inject = true
   mesh_gateway = true
   register = true
   expose_admin = true
   bind_addresses = {"default": "0.0.0.0:8443"}
}

resource "docker_container" "primary-api" {
   image = "nginxdemos/hello"
   name = "primary-api${local.cluster_id}"
   network_mode = "container:${module.primary_clients.clients[1].name}"
   command = []
}
module "primary-api-proxy" {
   source = "../modules/consul-envoy"

   consul_envoy_image = var.consul_envoy_image
   name = "primary-api-proxy${local.cluster_id}"
   consul_manager = module.primary_clients.clients[1].name
   sidecar_for = "api"
   expose_admin = true
}

resource "docker_container" "primary-web" {
   image = "nginxdemos/hello"
   name = "primary-web${local.cluster_id}"
   network_mode = "container:${module.primary_clients.clients[2].name}"
   command = []
}
module "primary-web-proxy" {
   source = "../modules/consul-envoy"

   consul_envoy_image = var.consul_envoy_image
   name = "primary-web-proxy${local.cluster_id}"
   consul_manager = module.primary_clients.clients[2].name
   sidecar_for = "web"
   expose_admin = true
}

resource "docker_container" "primary-api-v2" {
   image = "nginxdemos/hello"
   name = "primary-api-v2${local.cluster_id}"
   network_mode = "container:${module.primary_clients.clients[4].name}"
   command = []
}
module "primary-api-proxy-v2" {
   source = "../modules/consul-envoy"

   consul_envoy_image = var.consul_envoy_image
   name = "primary-api-proxy-v2${local.cluster_id}"
   consul_manager = module.primary_clients.clients[4].name
   sidecar_for = "api"
   expose_admin = true
}
