inventory=inventories/sample
inventoryfile=$(inventory)/hosts
testfile=tests/docker_hosts

vaultfiles=$(inventory)/group_vars/openvpn/vault.yml $(inventory)/group_vars/certauth/vault.yml
testvaultfiles=tests/group_vars/openvpn/vault.yml tests/group_vars/certauth/vault.yml

setup: pki ovpn

pki:
	ansible-playbook -i $(inventoryfile) playbooks/01-setup-pki.yml

ovpn:
	ansible-playbook -i $(inventoryfile) playbooks/02-setup-ovpn.yml

add-client:
	ansible-playbook -i $(inventoryfile) playbooks/03-add-client.yml -e "client_name=$(NAME)"

revoke-client:
	ansible-playbook -i $(inventoryfile) playbooks/03-revoke-client.yml -e "client_name=$(NAME)"

encrypt:
	ansible-vault encrypt $(vaultfiles)

decrypt:
	ansible-vault decrypt $(vaultfiles)

### For testing suite ###
encrypt-test: export ANSIBLE_VAULT_PASSWORD_FILE=tests/.test_vault_pass.txt
encrypt-test:
	ansible-vault encrypt $(testvaultfiles)

decrypt-test: export ANSIBLE_VAULT_PASSWORD_FILE=tests/.test_vault_pass.txt
decrypt-test:
	ansible-vault decrypt $(testvaultfiles)

docker-build:
	docker build --rm=true -f tests/docker/Dockerfile.centos8 -t ansible-ovpn-infra/centos:8 .
	docker build --rm=true -f tests/docker/Dockerfile.debian10 -t ansible-ovpn-infra/debian:10.4 .

docker-test: export ANSIBLE_VAULT_PASSWORD_FILE=tests/.test_vault_pass.txt
docker-test: docker-build
	docker rm -f ca ovpn ovpn-client || true
	./tests/run-containers.sh
	
	ansible-playbook -i $(testfile) playbooks/01-setup-pki.yml
	ansible-playbook -i $(testfile) playbooks/02-setup-ovpn.yml
	ansible-playbook -i $(testfile) playbooks/03-add-client.yml -e "client_name=testuser"

	mv /tmp/testuser.ovpn tests/
	docker build --rm=true -f tests/docker/Dockerfile.client.debian10 -t ansible-ovpn-infra/debian-client:10.4 .
	./tests/run-client-container.sh
	ansible-playbook -i $(testfile) --tags test tests/test-connection.yml

	ansible-playbook -i $(testfile) playbooks/03-revoke-client.yml -e "client_name=testuser"
	ansible-playbook -i $(testfile) --tags revoke tests/test-connection.yml