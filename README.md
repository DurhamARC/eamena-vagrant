# Vagrant Configuration for EAMENA (Arches v7) Setup

This repository contains everything required to get started running the EAMENA database in a local virtual machine.

## Prerequisites

The following software is required:

 * VirtualBox (https://www.virtualbox.org/wiki/Downloads)
 * Vagrant (https://developer.hashicorp.com/vagrant/docs/installation)

## Getting Started

First, customise [./provisioning/deploy.env](./provisioning/deploy.env) with appropriate credentials.

Next, install [vagrant](https://developer.hashicorp.com/vagrant/docs/installation) and [VirtualBox](https://www.virtualbox.org/wiki/Downloads).

Finally, from the root of this repository, run `vagrant up --provision --provider="virtualbox"`.

The provisioning script will run and set up the system from zero.
