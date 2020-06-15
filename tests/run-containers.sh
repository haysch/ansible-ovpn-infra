# !/usr/bin/env bash

set -e

RUN_OPTS="-d --privileged"
CA_DISTRIBUTION="${CA_DISTRIBUTION:-centos}"
CA_VERSION="${CA_VERSION:-8}"
OPVN_DISTRIBUTION="${OPVN_DISTRIBUTION:-debian}"
OPVN_VERSION="${OPVN_VERSION:-10.4}"

setup_container() {
  container_id=$(docker run ${RUN_OPTS} --name $3 ansible-ovpn-infra/$1:$2)
  container_ip=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' ${container_id})

  echo "$3 ansible_host=$container_ip ansible_user=docker ansible_become_password=\"{{ $3_ansible_become_password }}\""
}

ca_container=$(setup_container $CA_DISTRIBUTION $CA_VERSION "ca")
ovpn_container=$(setup_container $OPVN_DISTRIBUTION $OPVN_VERSION "ovpn")

# replace ${} parameters in template file
sed -e 's/${ca_docker}/'"$ca_container"'/g' -e 's/${openvpn_docker}/'"$ovpn_container"'/g' tests/docker_hosts.template > tests/docker_hosts