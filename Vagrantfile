# -*- mode: ruby -*-
# vi: set ft=ruby :

#
# This is a multi-provider vagrantfile which contains configs for Virtualbox
# and UTM (e.g. on M1 Mac). To run with a specific provider:
#
#   vagrant up --provision --provider="virtualbox"
# or:
#   vagrant up --provision --provider="utm"
#
ENV['VAGRANT_DEFAULT_PROVIDER'] ||= "virtualbox"

# Check for required plugins only when using specific providers
if ARGV.include?('--provider=utm') || ENV['VAGRANT_DEFAULT_PROVIDER'] == 'utm'
  unless Vagrant.has_plugin?("vagrant_utm")
    raise Vagrant::Errors::VagrantError.new, "vagrant_utm plugin missing. Run 'vagrant plugin install vagrant_utm'."
  end
end

if ARGV.include?('--provider=virtualbox') || ENV['VAGRANT_DEFAULT_PROVIDER'] == 'virtualbox'
  # Install vagrant-vbguest to update guest additions on box launch
  unless Vagrant.has_plugin?("vagrant-vbguest")
      raise  Vagrant::Errors::VagrantError.new, "vagrant-vbguest plugin missing. Run 'vagrant plugin install vagrant-vbguest'."
  end
end

unless Vagrant.has_plugin?("vagrant-disksize")
    raise  Vagrant::Errors::VagrantError.new, "vagrant-disksize plugin missing. Run 'vagrant plugin install vagrant-disksize'."
end


# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure("2") do |config|
  # The most common configuration options are documented and commented below.
  # For a complete reference, please see the online documentation at
  # https://docs.vagrantup.com.

  # Every Vagrant development environment requires a box. You can search for
  # boxes at https://vagrantcloud.com/search.
  # Default box for VirtualBox (may need to be overridden per-provider)
  
  # Focal 20.04 is no longer supported by PostgreSQL
  #config.vm.box = "ubuntu/focal64" # v20.04

  # Upgrade to Ubuntu 24.04: 
  # We use image "cloud-image/ubuntu-24.04", as canonical do not publish Vagrant images
  # for noble onwards due to HashiCorp's licence change... :/
  #config.vm.box = "bento/ubuntu-24.04" # Hangs on boot at systemd.network.service :(
  config.vm.box = "cloud-image/ubuntu-24.04" # May hang at GRUB (but can be passed by VM console)

  # Create a forwarded port mapping which allows access to a specific port
  # within the machine from a port on the host machine. In the example below,
  # accessing "localhost:8080" will access port 80 on the guest machine.
  # NOTE: This will enable public access to the opened port
  # config.vm.network "forwarded_port", guest: 80, host: 8080

  # Create a forwarded port mapping which allows access to a specific port
  # within the machine from a port on the host machine and only allow access
  # via 127.0.0.1 to disable public access
  # config.vm.network "forwarded_port", guest: 80, host: 8080, host_ip: "127.0.0.1"

  # NB: These ports WILL conflict with locally hosted services and docker containers running services 
  #     You should run EITHER vagrant (e.g. for server dev) OR docker desktop, not both!

  # Postgres (development)
  config.vm.network "forwarded_port", guest: 5432, host: 5432, host_ip: "127.0.0.1"

  # ElasticSearch (development)
  config.vm.network "forwarded_port", guest: 9200, host: 9200, host_ip: "127.0.0.1"
  config.vm.network "forwarded_port", guest: 9300, host: 9300, host_ip: "127.0.0.1"

  # SSH is automatically forwarded to port 2222. To forward to another location, use:
  #config.vm.network "forwarded_port", guest: 22, host: 22222, host_ip: "127.0.0.1"

  # HTTP
  config.vm.network "forwarded_port", guest: 80, host: 80, host_ip: "0.0.0.0"
  config.vm.network "forwarded_port", guest: 443, host: 443, host_ip: "0.0.0.0"

  # WSGI
  config.vm.network "forwarded_port", guest: 5000, host: 5000, host_ip: "127.0.0.1"
  config.vm.network "forwarded_port", guest: 8000, host: 8000, host_ip: "127.0.0.1"


  # Create a private network, which allows host-only access to the machine
  # using a specific IP.
  # config.vm.network "private_network", ip: "192.168.33.10"

  # Create a public network, which generally matched to bridged network.
  # Bridged networks make the machine appear as another physical device on
  # your network.
  # config.vm.network "public_network"

  # Share an additional folder to the guest VM. The first argument is
  # the path on the host to the actual folder. The second argument is
  # the path on the guest to mount the folder. And the optional third
  # argument is a set of non-required options.
  # /vagrant will be mounted by default for the current directory.
  #
  # Uncomment the below to use the directories from the host system instead
  # of copying content into the VM. The bootstrap script supports this
  # configuration and should not attempt to copy the folders.

  # MariaDB data folder:
  config.vm.synced_folder ".", "/vagrant", mount_options: ["dmode=775,fmode=777"]
  #config.vm.synced_folder "postgres-data", "/usr/local/pgsql/data"
  #config.vm.synced_folder "opt-arches", "/opt/arches", mount_options: ["dmode=775,fmode=777"]

  # Set disk size
  config.disksize.size = '20GB'

  # Provider-specific configuration so you can fine-tune various
  # backing providers for Vagrant. These expose provider-specific options.
  # Example for VirtualBox:
  #
  config.vm.provider "virtualbox" do |vb|
      # View the documentation for the provider you are using for more
      # information on available options.
      # Install vagrant-disksize to allow resizing the vagrant box disk.
      #unless Vagrant.has_plugin?("vagrant-disksize")
      #    raise  Vagrant::Errors::VagrantError.new, "vagrant-disksize plugin missing. Run 'vagrant plugin install vagrant-disksize'."
      #end

      # Disable automatic box update checking. If you disable this, then
      # boxes will only be checked for updates when the user runs
      # `vagrant box outdated`. This is not recommended.
      # config.vm.box_check_update = false

      # Display the VirtualBox GUI when booting the machine
      #vb.gui = true

      # set auto_update to false, if you do NOT want to check the correct
      # additions version when booting this machine
      config.vbguest.auto_update = false

      # Configure virtual memory allocation
      vb.memory = 8192
      vb.cpus = 2

      # ubuntu/focal64 image currently suffering from a bug which makes it slow to boot.
      # Work-around described at https://askubuntu.com/questions/1243582 
      vb.customize [ "modifyvm", :id, "--uartmode1", "file", File::NULL ]

      # Configure disk size using the plugin vagrant-disksize.
      # This is installed using vagrant plugin install vagrant-disksize
      #
      #config.disksize.size = '10GB'
  end

  # Custom configuration for utm
  config.vm.provider "utm" do |utm, override|

      # Set VM properties for UTM
      override.vm.box = "utm/ubuntu-24.04"
      utm.name = "debian_vm"
      utm.memory = 8192   # 8GB memory
      utm.cpus = 4          # 4 CPUs
      utm.directory_share_mode = "virtFS"
      #utm.directory_share_mode = "webDAV"  # Use webDAV for manual directory sharing
  end

  # Enable provisioning with a shell script. Additional provisioners such as
  # Ansible, Chef, Docker, Puppet and Salt are also available. Please see the
  # documentation for more information about their specific syntax and use.
  # config.vm.provision "shell", inline: <<-SHELL
  #   apt-get update
  #   apt-get install -y apache2
  # SHELL
  config.vm.provision "shell", path: "provisioning/bootstrap.sh"
  config.vm.provision "shell", path: "provisioning/herbridge.sh"
end
