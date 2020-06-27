# !/usr/bin/env bash

set -e

RUN_OPTS="-d --cap-add=NET_ADMIN --device=/dev/net/tun --tmpfs /run --tmpfs /run/lock -v /sys/fs/cgroup:/sys/fs/cgroup:ro"

setup_container() {
  ssh_port=$(shuf -i 22222-44444 -n 1)
  container_id=$(docker run ${RUN_OPTS} -p $ssh_port:22 --name $3 ansible-ovpn-infra/$1:$2)
  container_ip=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' ${container_id})

  echo "$3 ansible_host=$container_ip ansible_user=docker"
}

client_container=$(setup_container "debian-client" "10.4" "ovpn-client")

sed -i 's/${openvpn_client}/'"$client_container"'/g' tests/docker_hosts