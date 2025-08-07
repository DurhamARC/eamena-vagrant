# Vagrant Configuration for EAMENA (Arches v7) Setup

This repository contains everything required to get started running the EAMENA database in a local virtual machine.

It also installs [HerBridge](https://github.com/DurhamARC/HerBridge) as a service

## Prerequisites

The following software is required:

 * VirtualBox (https://www.virtualbox.org/wiki/Downloads), or...
   * UTM on Mac OSX on Apple M* processors (https://mac.getutm.app/)
 * Vagrant (https://developer.hashicorp.com/vagrant/docs/installation)

## Getting Started

Clone this repository to your machine.

You should customise [./provisioning/deploy.env](./provisioning/deploy.env) with appropriate credentials. It is a good 
idea to run `git update-index --assume-unchanged provisioning/deploy.env` to ignore any further changes to this
file, and avoid uploading credentials to git. 

Next, install [vagrant](https://developer.hashicorp.com/vagrant/docs/installation) and [VirtualBox](https://www.virtualbox.org/wiki/Downloads).

Finally, from the root of this repository, run `vagrant up`. The provisioning 
script will run and set up the system from zero.

To re-run the provisioning script, run `vagrant up --provision`. The script will
detect what needs to be done and won't try and do everything again. This is useful
if the provisioner fails the first time.

## Notes

Currently, VirtualBox only works with x86 instruction set machines. This is unlikely to change in future. You can
experiment with the `docker` provider instead on ARM-based (or other instruction set) systems.

On Mac, the Vagrantfile includes a configuration for the `utm` provider. This
allows deployment of the system on Apple Silicon processors.

The file `provisioning/bootstrap.sh` is where the magic happens. In the case of 
failures, this script can be re-run using the above command, and includes some 
naïve protection against work repetition and/or overwriting.

This script is based on work by [@ItIsJordan](https://github.com/ItIsJordan) and [@taflynn](https://github.com/taflynn/),
as described in [SETUP.md](SETUP.md). The bootstrap script automates their investigative work.

You will need to populate `provisioning/deploy.env` with the correct environment 
variables. These are copied into the files on first boot. If they are incorrect,
you will need to manually edit the modified files in the VM, or re-create it.

## Troubleshooting

### Unresponsive or site errors

Check that the services are all running. Dependencies for the services look like this:

  * Apache2
  * Postgres
  * ElasticSearch
  * RabbitMQ
    * Celery
      * Gunicorn (Python server)

Services can be checked using the command `sudo systemctl status \<servicename\>`, where servicename is one of e.g.
`eamena`, `herbridge`, `celery`, `rabbitmq-server` and so on.

If you see a message like `A dependency job for celery.service failed. See 'journalctl -xe' for details`, a service
may have failed to start. `sudo systemctl start \<service\>` can get it running again.

### Map tiles are not displayed at `/search`

The `MAPSERVER_API_KEY` may be incorrect or un-set. Check the key in `settings_local.py` (and `deploy.env`).

