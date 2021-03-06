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

* **IMPORTANT**: When running the `pki` role, the `group_vars/certauth/vault.yml` must NOT be encrypted.
* It is not possible to redo the `pki` setup after first run. The role will fail due to two things:
  * In `playbooks/roles/pki/tasks/init-pki.yml` since the pki is already initialized.
  * In `playbooks/roles/ca/tasks/build-ca.yml` since the CA is already built and will not be overwritten.
* At the moment the **openvpn** role only work for Debian 10.
* The current setup only allows for a **SINGLE** OpenVPN instance to be created and run.
* The current testing suite, using containers, does not work on Docker Desktop for Windows or MacOS, due to them not being able to route traffic to the Linux containers, as specified in the documentation. [Windows](https://docs.docker.com/docker-for-windows/networking/#i-cannot-ping-my-containers) and [MacOS](https://docs.docker.com/docker-for-mac/networking/#i-cannot-ping-my-containers).
  * **Workaround**: Test in VM running a Linux distribution.
* The ansible `synchronize` module did NOT perform as expected. It sometimes worked when testing, sometimes it work on different machines and almost never was it a reproducable output. I therefore changed to using `rsync` directly, since it allowed me to do as I wanted without the inconsistency of `synchronize`.
* Ansible also did not update the `ansible_env` dynamically when using `delegate_to` in ansible version 2.9.12, but it worked in previous versions. Thus, I added a `gather_facts` task in and after a `delegate_to`.

# Usage

## Requirements

* `ansible`
* `python3`, unless you change the interpreter to `python` in the `ansible.cfg` file.
* `make`, for using the provided `Makefile`.
* `docker`, for testing.

## Structure

* `inventories` contains a sample folder with the necessary variables and hosts.
* `playbooks` contains the playbooks, and roles, to orchestrate the machines.
  * `setup-pki.yml`:
    * `common`: common packages needed for running the OVPN and CA servers.
    * `pki`: common setup of public key infrastructure of the OVPN and CA servers.
    * `ca`: specific CA setup of EasyRSA.
  * `setup-ovpn.yml`:
    * `openvpn`: setup and configure the OVPN service.
  * `add-client.yml`:
    * `add_client`: generate client config.
  * `revoke-client.yml`: 
    * `revoke_client`: revoke client certificate.
* `Makefile` provides easier access to the different playbooks and testing suite.
* `ansible.cfg` provides some basic settings like the interpreter, default vault password file and forwarding SSH agent.

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

Create a `.vault_pass.txt`, or update `ansible.cfg` with the new vault pass path, and enter the vault pass to be used for encrypting/decrypting.

## Running the playbooks

This project makes use of `ForwardAgent` to communicating between multiple nodes, like `rsync` across two nodes without going through the mothership.
Thus, you will have to start up a `ssh-agent` and add your `id_rsa` to it.

```
eval $(ssh-agent -s)
ssh-add [inventories/<FOLDER>/id_rsa]
```

You can choose to run the playbooks by using the `ansible-playbook` directly or by using the provided `Makefile`.
If you do not want to use the `Makefile` you can consult the `Makefile` on how `ansible-playbook` is used.

If you do use the `Makefile`, remember to update the `inventory` variable to point to the correct inventory directory.

The provided `Makefile` gives access to the following targets:

| targets | description |
| ------- | ----------- |
| `pki` | initialize PKI for both OVPN and CA hosts, and build the CA. |
| `ovpn` | install and configures OpenVPN for the OVPN host. |
| `setup` | shortcut for running both the `pki` and `ovpn` targets. |
| `add-client NAME=testuser` | generate a client configuration with name *testuser*. |
| `revoke-client NAME=testuser` | revokes access for client with name *testuser*. |
| `encrypt`/`decrypt` | encrypts/decrypts the Ansible vault files at the specified location in the `vaultfiles` variable. |
| | |
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
If you generate a new ssh key, you will have to use `ssh-agent` or update the `tests/docker_hosts.template` with `ansible_ssh_private_key_file`, again place `id_rsa.pub` in `tests/` (**This is going to be described at some point), see [Setup SSH for testing](#setupsshfortesting) below.

The testing suite makes use of docker containers for easily setting up and disposing of containers when testing changes.

Three different dockerfiles are provided

* `Dockerfile.centos8` and `Dockerfile.debian10` are used for the OpenVPN and CA containers. They work for both tasks, i.e. you can use *debian10* for both the OpenVPN and CA.
* `Dockerfile.client.debian10` is used for the client container to test the OVPN connection.

The testing flow has its own `group_vars` and `host_vars` with all values filled out as needed.

`run-containers.sh` sets up the OVPN and CA containers, with the defined values in the file, and generate `docker_hosts` from the `docker_hosts.template`.

`run-client-container.sh` sets up a Debian client container to test the OVPN connection.

## Setup SSH for testing

One **important** aspect of the setup is that the `ca` and `ovpn` delegate tasks to each other, i.e. `ovpn` delegates a signing task to the `ca` machine.

For this, we use *SSH ForwardAgent*, thus you will have to ensure that the `ssh-agent` is running

```bash
eval $(ssh-agent -s)
```

### Generating or using existing keypair

Now, we have to generate or use an existing keypair that is going to be added to the `ssh-agent`.
For generating a key, use the following, which generates a keypair to the `tests/` folder.

```bash
ssh-keygen -t rsa -b 4096 -C "ansible-ovpn-test" -f tests/id_rsa
```

**Note:** The above command assumes that your current directory is **ansible-ovpn-infra**.

If you want to use an existing keypair, just copy the public key to the `tests/` folder.

### Setup usage of generated/existing keypair

To finish the setup, add the generated or existing private key to your `ssh-agent` by doing the following

```bash
ssh-add /path/to/id_rsa
```

which could be `tests/id_rsa` or wherever your private key hides. By omitting `/path/to/id_rsa` then `~/.ssh/id_rsa` will be used as default - this requires you to copy the `id_rsa.pub` to `tests/`.

## Running tests

If you just want to build the container images then run,

```bash
make docker-build
```

Otherwise run the following to execute the entire testing flow, this target depends on `docker-build`:

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
export CA_DISTRIBUTION=debian
export CA_VERSION=10.4
```

or the OVPN container (CentOS not usable as OVPN server - yet!)

```bash
export OVPN_DISTRIBUTION=centos
export OVPN_VERSION=8
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

During the development of this project, I have found that `--privileged` makes everything easier since you basically enable the container to act as it wants. However, this is not optimal since it basically kills any TTY in Debian and Ubuntu hosts (and maybe others? Have not attempted) when the `ansible-ovpn-infra/debian:10.4` image with `CMD ["/sbin/init"]` and `--privileged` run option.

The keen eyed might have seen the `gitignore` contains `tests/vagrant`.
I would be interested in setting up a test suite using Vagrant just for the sack of researching, but not sure when..
