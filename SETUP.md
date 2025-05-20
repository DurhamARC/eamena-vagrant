# Getting Started with EAMENA (arches project)
This document contains instructions on how to build a functioning virtual
machine which contains a working copy of the EAMENA database (correct as of
06/01/25).

The following works through the steps needed to setup the virtual machine which
can be found
[here](https://github.com/eamena-project/eamena-arches-dev/blob/main/dbs/database.eamena/install/detailed_workflow_krg2.sh).
This document will explain some of the steps that were used for setting up the
working virtual machine which may contain some edits from the original build
instructions.

## Setup
Beginning by setting up a virtual machine from an ISO of Ubuntu 20.04.06 LTS,
it is necessary to **setup a sudo account**
```bash
sudo adduser arches
sudo usermod -aG sudo arches
su arches
```
and **make an arches directory in `\opt`**
```bash
sudo mkdir /opt/arches/
sudo chown arches /opt/arches
```

## Install prerequisites
The EAMENA database has several dependencies which need to be carefully built
and installed.

### 1. Python and ENV
**Virtual environments** are useful for avoiding versioning issues, so we first
install Python and setup a virtual environment **ENV** for this project
```bash
sudo apt-get update
sudo apt-get install python3-virtualenv
sudo apt-get install virtualenv
cd /opt/arches
virtualenv --python=/usr/bin/python3 ENV
source ENV/bin/activate
```
**N.B.** Remember to activate this virtual environment whenever running the
EAMENA server.

### 2. Elasticsearch
Next, install `elasticsearch`. The exact `wget` command below depends on the
architecture of the hardware, so care must be taken if user architecture
differs
```bash
cd ~
mkdir arches_install_files
cd arches_install_files
wget "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.3.3-amd64.deb" # WD local
sudo dpkg -i ./elasticsearch-8.3.3-amd64.deb
```
Before progressing, there are some security settings which need to be
overwritten in the default `elasticsearch` configuration file, i.e., *ALL* of
the **security settings** in the `/etc/elasticsearch/elasticsearch.yml`file
must be overwritten
```bash
sudo nano /etc/elasticsearch/elasticsearch.yml
```
with 
```yml
xpack.security.enabled: false
xpack.security.enrollment.enabled: false
xpack.security.transport.ssl.enabled: false
xpack.security.http.ssl:
  enabled: false
```
and finally `elasticsearch` must be restarted
```bash
sudo systemctl restart elasticsearch
```

### 3. Postgres
This is one of the most laborious parts of the build relying on significant
commands to setup **postgres**. Care must be taken when running the following:
```bash
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get install postgresql-14 postgresql-contrib-14
sudo apt-get install postgresql-14-postgis-3
sudo apt-get install postgresql-14-postgis-3-scripts
sudo -u postgres psql -d postgres -c "ALTER USER postgres with encrypted password 'postgis';"
sudo echo "*:*:*:postgres:postgis" >> ~/.pgpass
sudo chmod 600 ~/.pgpass
sudo chmod 666 /etc/postgresql/14/main/postgresql.conf
sudo chmod 666 /etc/postgresql/14/main/pg_hba.conf
sudo echo "standard_conforming_strings = off" >> /etc/postgresql/14/main/postgresql.conf
sudo echo "listen_addresses = '*'" >> /etc/postgresql/14/main/postgresql.conf
sudo echo "#TYPE   DATABASE  USER  CIDR-ADDRESS  METHOD" > /etc/postgresql/14/main/pg_hba.conf
sudo echo "local   all       all                 trust" >> /etc/postgresql/14/main/pg_hba.conf
sudo echo "host    all       all   127.0.0.1/32  trust" >> /etc/postgresql/14/main/pg_hba.conf
sudo echo "host    all       all   ::1/128       trust" >> /etc/postgresql/14/main/pg_hba.conf
sudo echo "host    all       all   0.0.0.0/0     md5" >> /etc/postgresql/14/main/pg_hba.conf
sudo service postgresql restart
sudo -u postgres psql -d postgres -c "CREATE EXTENSION postgis;"
sudo -u postgres createdb -E UTF8 -T template0 --locale=en_US.utf8 template_postgis # I had to change the locale to C.utf* after running locale -a
sudo -u postgres psql -d postgres -c "UPDATE pg_database SET datistemplate='true' WHERE datname='template_postgis'"
sudo -u postgres psql -d template_postgis -c "CREATE EXTENSION postgis;"
sudo -u postgres psql -d template_postgis -c "GRANT ALL ON geometry_columns TO PUBLIC;"
sudo -u postgres psql -d template_postgis -c "GRANT ALL ON geography_columns TO PUBLIC;"
sudo -u postgres psql -d template_postgis -c "GRANT ALL ON spatial_ref_sys TO PUBLIC;"
sudo -u postgres createdb training -T template_postgis
sudo service postgresql restart
```

### 3. NodeJS, NPM, Yarn
```bash
sudo apt-get install nodejs npm
sudo npm i -g n
sudo n 14.17.6
sudo npm i -g npm@9.6.0
sudo npm i -g yarn@1.22.19
```

### 4. Apache
Begin by installing **apache** and its dependencies
```bash
sudo apt-get update
sudo apt-get install apache2
sudo apt-get install libapache2-mod-wsgi-py3
```
 **Before proceeding** an apache configuration file is needed, named
`arches.conf` which contains:
```
<VirtualHost *:80>

        ServerAdmin ash.smith@soton.ac.uk

        DocumentRoot /opt/arches/eamena

        ErrorLog ${APACHE_LOG_DIR}/error.log
        CustomLog ${APACHE_LOG_DIR}/access.log combined

        RewriteEngine On

        Alias /static /opt/arches/media
        Alias /media /opt/arches/media
        Alias /files /opt/arches/files
        <Directory /opt/arches/eamena/eamena/static>
                Require all granted
        </Directory>
        <Directory /opt/arches/eamena/eamena/staticfiles>
                Require all granted
        </Directory>
        <Directory /opt/arches/media>
                Require all granted
        </Directory>
        <Directory /opt/arches/files>
                Require all granted
        </Directory>

        <Directory /opt/arches/eamena>

                <Files wsgi.py>
                        Require all granted
                </Files>

        </Directory>

        WSGIDaemonProcess eamena user=arches python-path=/opt/arches/eamena python-home=/opt/arches/ENV
        WSGIProcessGroup eamena
        WSGIScriptAlias / /opt/arches/eamena/eamena/wsgi.py
        WSGIPassAuthorization on

</VirtualHost>
```
to be saved in the `/etc/apache2/sites-available/` directory. Once this file
has been generated, the user can now run:
```bash
sudo a2ensite arches.conf
sudo a2dissite 000-default.conf
sudo a2enmod rewrite
sudo apache2ctl configtest
sudo systemctl restart apache2
cd /opt
sudo chmod 755 -R arches
```

### 5. Celery
To setup **Celery** begin with the following commands
```bash
sudo apt-get install rabbitmq-server
sudo apt-get install rabbit
sudo rabbitmqctl add_vhost arches
sudo rabbitmqctl add_user arches
```
The final command will prompt the user for a password in which the user should
use `5wQf3J3JRUktFRW`. Then continue with
```bash
sudo rabbitmqctl set_permissions -p arches arches ".*" ".*" ".*"
sudo systemctl restart rabbitmq-server
sudo systemctl status rabbitmq-server
sudo nano /etc/systemd/system/celery.service
```
The final command opens the `celery.service` file in which the user should copy:
```
[Unit]
Description=EAMENA Celery Broker Service
After=rabbitmq-server.service

[Service]
User=arches
Group=arches
WorkingDirectory=/opt/arches/eamena
ExecStart=/opt/arches/ENV/bin/python /opt/arches/eamena/manage.py celery start
Environment="PATH=/opt/arches/ENV/bin:$PATH"
Restart=always
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
```

## Install Arches
The initial portion of the **arches installation** is simply
```bash
sudo apt-get install python3-psycopg2
sudo apt-get install libpq-dev
python -m pip install "arches==7.3"
```

## Cloning the EAMENA project
The specific **EAMENA project** is hosted on github and can be cloned by
```bash
cd /opt/arches
git clone https://github.com/eamena-project/eamena.git
```
and so **Celery** can be started
```bash
sudo systemctl enable celery
sudo systemctl start celery
sudo systemctl status celery
```

## Remove all business data
```bash
rm /opt/arches/eamena/eamena/pkg/business_data/files/*
```

## Moving the custom `settings_local.py` file
```bash
cp <local_data_directory>/settings_local.py /opt/arches/eamena/eamena/settings_local.py
```

## Convert `System_Settings.json` file and move to relevant project folder
Beginning with the **conversion**
```bash
cd /opt/arches/eamena
python manage.py convert_json_57 -s /opt/arches/eamena/eamena/pkg/system_settings/System_Settings.json > /opt/arches/eamena/eamena/pkg/system_settings/System_Settings_conv.json
```
then replace the original settings file with the converted version
```bash
rm /opt/arches/eamena/eamena/pkg/system_settings/System_Settings.json
mkdir /opt/arches/eamena/eamena/system_settings
mv /opt/arches/eamena/eamena/pkg/system_settings/System_Settings_conv.json /opt/arches/eamena/eamena/system_settings/System_Settings.json
cp /opt/arches/eamena/eamena/system_settings/System_Settings.json /opt/arches/eamena/eamena/pkg/system_settings/System_Settings.json
```

## Lord the package
**Important!** - When running the `python manage.py ...` command below, the
user will be prompted with a `Y/N` question for whether the system should
overwrite the settings file. However, since we have just taken the time to
convert the settings file, the user should type `N` to stay using the *new*
converted settings
```bash
cd /opt/arches/eamena
python manage.py packages -o load_package -s /opt/arches/eamena/eamena/pkg/ -db
```

## Build development frontend

### Relevant data
There are three main files needed for **building the development front end**:
`package.json`, `media.tar` and `staticfiles.tar`. Beginning with the
`package.json` file
```bash
cd /opt/arches/eamena/eamena
cp <local_data_directory>/package.json package.json
```
Next the aim is to move the contents of `media.tar` into `/opt/arches/media`
and `staticfiles` into `/opt/arches/eamena/eamena/staticfiles`.

Beginning with
`/opt/arches/media`
```bash
mkdir /opt/arches/media
cd /opt/arches/media
cp <local_data_directory>/media.tar .
tar -xvf ./media.tar
```
and then `/opt/arches/eamena/eamena/staticfiles`
```bash
mkdir /opt/arches/eamena/eamena/staticfiles
cd /opt/arches/eamena/eamena/staticfiles
tar -xvf ./staticfiles.tar
```
both `media.tar` and `staticfiles.tar` can then be deleted as they are quite
large files.

### Install and run Yarn
In one terminal run the server
```bash
python /opt/arches/eamena/manage.py runserver
```
and on an a separate terminal run
```bash
cd /opt/arches/eamena/eamena
yarn install
yarn build_development
```
It should be clear looking at both of the terminals that data is being
transmitted between the two consoles

## Default values error
Once **Yarn** is installed, there is an ongoing **default value error** which
can be fixed by
```bash
cd /opt/arches/eamena
python manage.py fix_default_value
```

## Check!
Check that this error is fixed and that the server can now run
```bash
python manage.py runserver
```
Now by clicking on the localhost link provided, and accessing a Chromium based
browser, EAMENA should load up. By logging in, the user can then search the
EAMENA database, which should display a map.

**N.B.** To this point, the server should run correctly and there should be no
errors. One common error is that when accessing the settings panel of the
EAMENA webpage, this webpage produces an error message along the lines of: *a
string does not have the attribute keys*. This typically means that the
conversion step of the `System_Settings.json` file has not worked, so try these
steps again and rebuild the project via the `python manage.py packages -o
load_package -s /opt/arches/eamena/eamena/pkg/ -db` command, as above. One
simple check is to navigate to the `System_Settings.json` file and check the
length of the file; typically the unconverted file is 233 lines, whilst the
converted file is 278 lines.

## Loading grids
To then begin loading data into the EAMENA database, download the `GS.csv` and
`GS.mapping` files.
```bash
cp <local_data_directory/GS.* /home/arches/arches_install_files/>
```
Then load these files into
```bash
python manage.py packages -o import_business_data -s /home/arches/arches_install_files/GS.csv -ow overwrite
python manage.py es reindex_database
```
Rerunning the server and accessing the EAMENA database, the user can find that
this data has added in a series of grids to the map in regions of Iraq.

## Accessing server from outside the VM
Once setup the server can again be initialised by
```bash
python manage.py runserver
```
and then the command
```bash
ip addr
```
will display the VM IP address. This IP address must be added to the
`ALLOWED_HOSTS` list in the `/opt/arches/eamena/eamena/settings_local.py` file.
After this, typing the IP address into the search engine of a local web browser
(chromium based typically has been most reliable) should load the EAMENA
database. 

**However**, this access can sometimes be difficult and we have found more
success by initialising the server with
```bash
python manage.py runserver 0.0.0.0:8000
```
and inputting the VM IP address into local search engine including the port
number `:8000`
