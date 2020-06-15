# !/usr/bin/env bash

set -e

RUN_OPTS="-d --privileged"

setup_container() {
  container_id=$(docker run ${RUN_OPTS} --name $3 ansible-ovpn-infra/$1:$2)
  container_ip=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' ${container_id})

  echo "$3 ansible_host=$container_ip ansible_user=docker"
}

client_container=$(setup_container "debian-client" "10.4" "ovpn-client")

sed -i 's/${openvpn_client}/'"$client_container"'/g' tests/docker_hosts