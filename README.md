# Ansible OpenVPN Infrastructure

## Introduction

**Note:** this project is based on [Digital Ocean's OpenVPN guide](https://www.digitalocean.com/community/tutorials/how-to-set-up-an-openvpn-server-on-debian-10)

This project will allow you to configure a pair of OpenVPN and certificate authority servers to avoid potential issues with key handling on a single machine, as described in the [Getting Started wiki for OpenVPN](https://community.openvpn.net/openvpn/wiki/GettingStartedwithOVPN#Configuringencryption):

> BEWARE: One common mistake when setting up a new CA is to place all the CA files on the OpenVPN server. DO NOT DO THAT! A CA requires a private key which is used for signing the certificates your clients and servers will use. If you loose control of your CA private key, you can no longer trust any certificates from this CA. Anyone with access to this CA private key can sign new certificates without your knowledge, which then can connect to your OpenVPN server without needing to modify anything on the VPN server. Place your CA files on a storage which can be offline as much as possible, only to be activated when you need to get a new certificate for a client or server.

This project therefore assumes that the OVPN and CA servers are two different entities (be it containers, VMs or even bare-metal servers!), which shows in different parts when trying to pull/push files between the servers, [i.e. in `sign-certificate.yml`](playbooks/roles/openvpn/tasks/sign-certificate.yml).
However, if you just want everything on a single machine, then just add the same settings for both the `ca` and `ovpn` entries in the `hosts` file.

In just a few minutes you will be able to have a fully functioning OpenVPN server with the ability to quickly add/revoke clients!

## Shortcomings

**Important:** At the moment, the OpenVPN server setup only works on Debian. The CentOS flow is not setup yet.

It is worth noting that this project is in a very early state, which means that a couple of known and unknown shortcomings exist.

### Known shortcomings

* It is not possible to redo the `pki` setup after first run. The role will fail due to two things:
  * In `playbooks/roles/pki/tasks/init-pki.yml` since the pki is already initialized.
  * In `playbooks/roles/ca/tasks/build-ca.yml` since the CA is already built and will not be overwritten.
* At the moment the **openvpn** role only work for Debian 10.
* The current setup only allows for a **SINGLE** OpenVPN instance to be created and run.

# Usage

## Requirements

* `ansible`
* `python3`, unless you change the interpreter to `python` in the `ansible.cfg` file.
* `make`, for using the provided `Makefile`.
* `docker`, for testing.

## Structure

* `inventories` contains a sample folder with the necessary variables and hosts.
* `playbooks` contains the playbooks, and roles, to interact with machines.
  * `setup-pki.yml`:
    * `common`: common packages needed for running the OVPN and CA servers.
    * `pki`: common setup of public key infrastructure of the OVPN and CA servers.
    * `ca`: specific CA setup of EasyRSA.
  * `setup-ovpn.yml`:
    * `openvpn`: setup and configure the OVPN service.
  * `add-client.yml`:
    * `add_client`: generate client config.
  * `revoke-client.yml`: UNDER CONSTRUCTION
* `Makefile` provides easier access to the different playbooks and testing suite.
* `ansible.cfg` provides some basic settings like the interperet, default vault password file and forwarding SSH agent.

## Setup

Before running the playbooks, you will have to copy the sample inventory folder and change a few variables.

```bash
cp -r inventories/sample inventories/NEW_FOLDER
```

Inside the `inventories/NEW_FOLDER/hosts` file you will have to enter the IP and user for the OpenVPN and CA machines.
Additionally, the become password can be entered here as well, however, it is recommended to use `--ask-become-pass` or set the become password in `group_vars` vault file.

You will also want to update the `group_vars/all.yml` and each `group_vars/<group>/vault.yml` to reflect your wanted setup.

**Note:** the OpenVPN entry has to be named `ovpn` and the CA entry has to be named `ca` as shown (**Future work:** allow for arbitrary naming?).

### Vault

The project makes use of `group_vars` vaults.
Each group contains a `vars.yml` and `vault.yml`, where `vars.yml` contains non-sensitive variables and references `vault.yml` variables, and `vault.yml` contains sensitive variables, as described in the [Ansible Best Practives](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html#variables-and-vaults).

## Running the playbooks

You can choose to run the playbooks by using the `ansible-playbook` directly or by using the provided `Makefile`.
If you do not want to use the `Makefile` you can consult the `Makefile` on how `ansible-playbook` is used.

The provided `Makefile` gives access to the following targets:

| targets | description |
| ------- | ----------- |
| `pki` | initialize PKI for both OVPN and CA hosts, and build the CA. |
| `ovpn` | install and configures OpenVPN for the OVPN host. |
| `setup` | shortcut for running both the `pki` and `ovpn` targets. |
| `add-client NAME=testuser` | generate a client configuration with name *testuser*. |
| `revoke-client NAME=testuser` | revokes access for client with name *testuser*. |
| `encrypt`/`decrypt` | encrypts/decrypts the Ansible vault files at the specified location in the `vaultfiles` variable. |
| `encrypt-test`/`decrypt-test` | encrypts/decrypts the test vaults files to mirror actual setup. |
| `docker-build` | builds the `Dockerfile.centos8` and `Dockerfile.debian10` images. |
| `docker-test` | runs the test suite as specified in [Testing](#Testing). |

Furthermore, the `Makefile` contains a few configuration variables to avoid repeating locations and flags across multiple targets:

| variables        | description |
| ---------------- | ----------- |
| `inventory`      | base inventory folder. |
| `inventoryfile`  | point it to the relative (or absolute) path of the inventory file to be used. |
| `testfile`       | the test inventory file. No need to change this unless you change the testing configuration. |
| `vaultfiles`     | point it to the relative (or absolute) path of the vault files, if any. (Default: `group_vars` vault files.) |
| `testvaultfiles` | point to the test `group_vars` vault files. |

# Testing

You will have to place your public ssh key, `id_rsa.pub`, in the `tests/` folder since it is copied to the containers upon build of container images.
If you generate a new ssh key, you will have to use `ssh-agent` or update the `tests/docker_hosts.template` with `ansible_ssh_private_key_file`, again place `id_rsa.pub` in `tests/` (**This is going to be described at some point).

The testing suite makes use of docker containers for easily setting up and disposing of containers when testing changes.

Three different dockerfiles are provided

* `Dockerfile.centos8` and `Dockerfile.debian10` are used for the OpenVPN and CA containers. They work for both tasks, i.e. you can use *debian10* for both the OpenVPN and CA.
* `Dockerfile.client.debian10` is used for the client container to test the OVPN connection.

The testing flow has its own `group_vars` and `host_vars` with all values filled out as needed.

`run-containers.sh` sets up the OVPN and CA containers, with the defined values in the file, and generate `docker_hosts` from the `docker_hosts.template`.

`run-client-container.sh` sets up a Debian client container to test the OVPN connection.

## Generate SSH key for testing

On the `TODO.md` list :-)

## Running tests

If you just want to build the container images then run,

```bash
make docker-build
```

Otherwise run the following to execute the entire testing flow, this target also depends on `docker-test`:

```bash
make docker-test
```

The flow is as follows:

* Build the container images
* Setting up the PKI and CA
* Installing and configuring OpenVPN
* Generates a client config
* Test connection in a new container

### Container images

If you want to change the images used, e.g. for the CA container, you can do the following

```bash
export CA_DISTRIBUTION="debian"
export CA_VERSION="10.4"
```

Replace **CA** with **OVPN** to change the OpenVPN container.

Distribution and version pair supported:

* `debian:10.4`
* `centos:8`

# Notes

I wanted to reduce the overall size and functionality of `group_vars/all.yml`, thus it only contain shared and non-sensitive variables.
Specific and sensitive variables are kept in their respective `group_vars/<groups>`.
Each group folder contains a `vars.yml` and `vault.yml`, where `vault.yml` should always be encrypted and `vars.yml` should contain non-secret variables and reference `vault.yml` for secret variables.
I have added `vault.yml` to `gitignore` to avoid pushing potentially unencrypted files and brute-forcing.

The keen eyed might have seen the `gitignore` contains `test/vagrant`.
I would be interested in setting up a test suite using Vagrant just for the sack of researching, but not sure when..
