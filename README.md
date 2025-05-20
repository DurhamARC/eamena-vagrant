# Vagrant Configuration for EAMENA (Arches v7) Setup

This repository contains everything required to get started running the EAMENA database in a local virtual machine.

## Prerequisites

The following software is required:

 * VirtualBox (https://www.virtualbox.org/wiki/Downloads)
 * Vagrant (https://developer.hashicorp.com/vagrant/docs/installation)

## Getting Started

Clone this repository to your machine.

You should customise [./provisioning/deploy.env](./provisioning/deploy.env) with appropriate credentials. It is a good 
idea to run `git update-index --assume-unchanged provisioning/deploy.env` to ignore any further changes to this
file, and avoid uploading credentials to git. 

Next, install [vagrant](https://developer.hashicorp.com/vagrant/docs/installation) and [VirtualBox](https://www.virtualbox.org/wiki/Downloads).

Finally, from the root of this repository, run `vagrant up --provision --provider="virtualbox"`. The provisioning 
script will run and set up the system from zero.

## Notes

Currently, VirtualBox only works with x86 instruction set machines. This is unlikely to change in future. You can
experiment with the `docker` provider instead on ARM-based (or other instruction set) systems.

The file `provisioning/bootstrap.sh` is where the magic happens. In the case of failures, this script can be re-run using the above command, and includes some naïve protection against work repetition and/or overwriting.

This script is based on work by [@ItIsJordan](https://github.com/ItIsJordan) and [@taflynn](https://github.com/taflynn/), as described in [SETUP.md](SETUP.md). The bootstraps script automates their investigative work.
