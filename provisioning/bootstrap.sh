# Vagrant EAMENA Arches 7.3 deployment script
# Based on:
# https://github.com/eamena-project/eamena-arches-dev/blob/main/dbs/database.eamena/install/detailed_workflow_krg2.sh

set -e
export BORDER="\n====================================================\n\n"
export DEBIAN_FRONTEND=noninteractive 
export TZ=Etc/UTC

# Import environment from hedap.env:
#export $(awk '''!/^\s*#/''' /vagrant/provisioning/deploy.env | xargs)
export $(grep -v '^#' /vagrant/provisioning/deploy.env | xargs)

if ! grep "deploy.env" /home/vagrant/.bashrc > /dev/null; then
    # Add automatic environment variable loading from deploy.envto .bashrc for vagrant and arches users
    echo -e '\nexport $(grep -v '^#' /vagrant/provisioning/deploy.env | xargs)' >> /home/vagrant/.bashrc
fi

# Check if required environment variables are set
if [ -z "$RABBITMQ_PASSWORD" ] || \
   [ -z "$CELERY_BROKER_URL" ] || \
   [ -z "$ALLOWED_HOSTS" ] || \
   [ -z "$EMAIL_HOST_USER" ] || \
   [ -z "$EMAIL_FROM_ADDRESS" ] || \
   [ -z "$EMAIL_HOST_PASSWORD" ] || \
   [ -z "$ARCHES_NAMESPACE_FOR_DATA_EXPORT" ] || \
   [ -z "$SECRET_KEY" ]; 
then
    echo "Error: One or more required environment variables are not set in provisioning/deploy.env"
    echo "or, this script is not being run from the root of the git repository!"
    exit 1
fi

# === create an arches user ===
echo -e "$BORDER Creating Arches user and folder \n"
if ! id -nGz "arches" | grep -qzxF "sudo";
then
    useradd -m -s $(which bash) -d /opt/arches arches
    usermod -aG sudo,vagrant,www-data arches
    echo -e '\nexport $(grep -v '^#' /vagrant/provisioning/deploy.env | xargs)' >> /opt/arches/.bashrc
    echo "User created"
else echo "user ok"
fi

# === make an arches folder in /opt ====
echo -e "$BORDER Create Arches Folder \n"
if ! [[ -d /opt/arches ]]; then 

    mkdir -pv /opt/arches/
    chown arches:arches /opt/arches
else echo "folder ok"
fi

# === INSTALL PREREQUISITES ===
# === === 1) Python and ENV === ===
echo -e "$BORDER Installing prerequisites \n"
if ! dpkg-query -W -f='${Status}' virtualenv | grep "ok installed"; then

    apt-get update
    apt-get install -y python3-dev python3-virtualenv virtualenv python3-pip \
                       python3-psycopg2 libpq-dev python-is-python3
fi

# Provisioner runs as root. Sudo as `arches` user for venv install:
echo -e "$BORDER Create Virtualenv in /opt/arches \n"
if ! [[ -x /opt/arches/ENV/bin/python ]]; then

    /usr/bin/sudo -i --preserve-env=BORDER -u arches bash <<"EOF"
        cd /opt/arches
        virtualenv --python=/usr/bin/python3 ENV
        source ENV/bin/activate
EOF
else echo "ok"
fi

# === === 2) Elasticsearch === ===
echo -e "$BORDER Install ElasticSearch \n"
if ! dpkg-query -W -f='${Status}' elasticsearch | grep "ok installed"; then

    cd /home/vagrant
    rm -f ./elasticsearch-8.3.3-amd64.deb # remove if download failed on previous run
    
    ARCH=`dpkg --print-architecture`
    
    if [[ -f /vagrant/arches_install_files/elasticsearch-8.3.3-$ARCH.deb ]]; then
        echo "Found local elasticsearch-8.3.3-$ARCH.deb"
        cp -v /vagrant/arches_install_files/elasticsearch-8.3.3-$ARCH.deb ./
    else
        # download the deb package
        echo "Downloading elasticsearch-8.3.3-$ARCH.deb"
        wget --no-verbose --show-progress  --progress=dot:mega \
            "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.3.3-$ARCH.deb" # WD local
    fi

    # install the deb package
    dpkg -i ./elasticsearch-8.3.3-$ARCH.deb
    # cleanup and don't download again
    cp -v ./elasticsearch-8.3.3-$ARCH.deb /vagrant/arches_install_files/
    rm ./elasticsearch-8.3.3-$ARCH.deb
else echo "elasticsearch ok"
fi
# === === === edit the elasticsearch service file, adding restart on failure === === ===
if ! grep "Restart=on-failure" /lib/systemd/system/elasticsearch.service &> /dev/null; then
    gawk -i inplace -v new='# Auto-restart on crash\nRestart=on-failure\nRestartSec=30s\n' '{print} sub(/\[Service\]/,""){print $0 new}' /lib/systemd/system/elasticsearch.service
    systemctl daemon-reload
    systemctl enable elasticsearch # not sure if required, but can't hurt
else echo "elasticsearch service ok"
fi

# === === === edit the elasticsearch configuration file, replacing security settings === === ===
echo -e "$BORDER  Performing configuration changes for elasticsearch.yml"
if ! grep -E "xpack\.security\.enabled: false" /etc/elasticsearch/elasticsearch.yml &> /dev/null; then

    # xpack.security.enabled: false
    sed -E -i 's/(xpack\.security\.enabled: )(.*)/\1false/g' /etc/elasticsearch/elasticsearch.yml
    # xpack.security.enrollment.enabled: false
    sed -E -i 's/(xpack\.security\.enrollment\.enabled: )(.*)/\1false/g' /etc/elasticsearch/elasticsearch.yml
    # xpack.security.transport.ssl.enabled: false
    sed -E -i 's/(xpack\.security\.transport\.ssl\.enabled: )(.*)/\1false/g' /etc/elasticsearch/elasticsearch.yml
    # need awk to automate multiline edits:
    # (xpack.security.transport.ssl.enabled doesn't appear to exist on my copy, instead it's:)
    # xpack.security.transport.ssl:
    #   enabled: false
    gawk -i inplace '/xpack.security.transport.ssl:/{ rl = NR + 1 } NR == rl { gsub( /true/,"false") } 1' /etc/elasticsearch/elasticsearch.yml
    # xpack.security.http.ssl:
    #   enabled: false
    gawk -i inplace '/xpack.security.http.ssl:/{ rl = NR + 1 } NR == rl { gsub( /true/,"false") } 1' /etc/elasticsearch/elasticsearch.yml

    SYSTEMD_LOG_LEVEL=debug \
        systemctl restart elasticsearch
    systemctl status elasticsearch
else echo "ok"
fi

# === === 3) Postgres === ===
echo -e "$BORDER  Installing Postgres"
if ! dpkg-query -W -f='${Status}' postgresql-14 | grep "ok installed"; then

    echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
    apt-get update
    apt-get install -y postgresql-14 postgresql-contrib-14 \
                       postgresql-14-postgis-3 postgresql-14-postgis-3-scripts
fi

echo -e "$BORDER  Configuring Postgres"
if ! grep -E "standard_conforming_strings = off" /etc/postgresql/14/main/postgresql.conf &> /dev/null &&\
   ! grep -E "#Autoconfiguration done" /etc/postgresql/14/main/pg_hba.conf &> /dev/null; then

    sudo -u postgres psql -d postgres -c "ALTER USER postgres with encrypted password 'postgis';"
    echo "*:*:*:postgres:postgis" >> ~/.pgpass

    chmod 600 ~/.pgpass
    chmod 666 /etc/postgresql/14/main/postgresql.conf
    chmod 666 /etc/postgresql/14/main/pg_hba.conf

    echo "standard_conforming_strings = off" >> /etc/postgresql/14/main/postgresql.conf
    echo "listen_addresses = '*'" >> /etc/postgresql/14/main/postgresql.conf
    echo "#TYPE   DATABASE  USER  CIDR-ADDRESS  METHOD" > /etc/postgresql/14/main/pg_hba.conf
    echo "local   all       all                 trust" >> /etc/postgresql/14/main/pg_hba.conf
    echo "host    all       all   127.0.0.1/32  trust" >> /etc/postgresql/14/main/pg_hba.conf
    echo "host    all       all   ::1/128       trust" >> /etc/postgresql/14/main/pg_hba.conf
    echo "host    all       all   0.0.0.0/0     md5" >> /etc/postgresql/14/main/pg_hba.conf
    echo "#Autoconfiguration done" >> /etc/postgresql/14/main/pg_hba.conf
    
    service postgresql restart

    /usr/bin/sudo -i --preserve-env=BORDER -u postgres bash <<"EOF"
        psql -d postgres -c "CREATE EXTENSION postgis;"
        createdb -E UTF8 -T template0 --locale=en_US.utf8 template_postgis # I had to change the locale to C.utf* after running locale -a
        psql -d postgres -c "UPDATE pg_database SET datistemplate='true' WHERE datname='template_postgis'"
        psql -d template_postgis -c "CREATE EXTENSION postgis;"
        psql -d template_postgis -c "GRANT ALL ON geometry_columns TO PUBLIC;"
        psql -d template_postgis -c "GRANT ALL ON geography_columns TO PUBLIC;"
        psql -d template_postgis -c "GRANT ALL ON spatial_ref_sys TO PUBLIC;"
        createdb training -T template_postgis
EOF
    
    createdb -h localhost -p 5432 -U postgres eamena

    service postgresql restart
else echo "ok"
fi

echo -e "$BORDER  Installing NodeJS; NPM; & Yarn"
# === === 3) NodeJS, NPM, Yarn === ===
if ! command -v npm 2>&1 >/dev/null; then

    apt-get install -y nodejs npm
else echo "npm ok"
fi

if ! npm list -g --depth=0 | grep 'yarn' 2>&1 >/dev/null; then

    # Install n (node version manager) and set node version to 14.17.6
    # Then install yarn
    set -x
    npm i -g n
    n 14.17.6
    hash -r # Reset location of npm and node in shell
    npm i -g npm@9.6.0
    npm i -g yarn@1.22.19
    set +x
else echo "yarn ok"
fi

# === === 4) Apache === ===
echo -e "$BORDER  Install apache2 and modules"
if ! dpkg-query -W -f='${Status}' apache2 | grep "ok installed"; then

    apt-get install -y apache2 libapache2-mod-wsgi-py3
fi

# === === === manually create an apache config file 'arches.conf' then run the following === === ===
echo -e "$BORDER  Create arches.conf Apache2 subsite configuration"
if ! [[ -f /etc/apache2/sites-available/arches.conf ]]; then

    set -x
    cp -v /vagrant/config/arches.conf /etc/apache2/sites-available/arches.conf
    a2ensite arches.conf
    a2dissite 000-default.conf
    a2enmod rewrite proxy proxy_http
    apache2ctl configtest
    systemctl restart apache2
    cd /opt
    chmod 755 -R arches
    set +x
else echo "ok"
fi

# === === Celery === ===
echo -e "$BORDER  Install and configure RabbitMQ"
if ! dpkg-query -W -f='${Status}' rabbit | grep "ok installed"; then

    apt-get install -y rabbitmq-server rabbit
    rabbitmqctl add_vhost arches
fi
if ! rabbitmqctl list_users | grep 'arches'; then

    # Echo password into add_user
    echo $RABBITMQ_PASSWORD | rabbitmqctl add_user arches

    rabbitmqctl set_permissions -p arches arches ".*" ".*" ".*"
    systemctl restart rabbitmq-server
    systemctl status rabbitmq-server
fi


# === INSTALL ARCHES ===
echo -e "$BORDER  Install Arches"
if ! /opt/arches/ENV/bin/python -m pip show arches >/dev/null; then

    # (moved psycopg2 libpq install to prerequisites)
    /usr/bin/sudo -i --preserve-env=BORDER -u arches bash <<"EOF"
        source /opt/arches/ENV/bin/activate
        python -m pip install "arches==7.3"
EOF
else echo "ok"
fi

# === CLONE EAMENA GIT PROJECT/PACKAGE ===
echo -e "$BORDER  Clone EAMENA"
if ! [[ -f /opt/arches/eamena/__init__.py ]]; then
    
    /usr/bin/sudo -i --preserve-env=BORDER -u arches bash <<"EOF"
        cd /opt/arches
        git clone https://github.com/eamena-project/eamena.git
EOF
else echo "clone ok"
fi

# === === Install Python requirements === ===
echo -e "$BORDER  Install Python requirements"
if ! /opt/arches/ENV/bin/python -m pip show gunicorn >/dev/null; then

    /usr/bin/sudo -i --preserve-env=BORDER -u arches bash <<"EOF"
        source /opt/arches/ENV/bin/activate
        cd /opt/arches/eamena
        python -m pip install -r requirements.txt
        python -m pip install geomet gunicorn
        echo -e "source /opt/arches/ENV/bin/activate" >> /opt/arches/.bashrc
EOF
else echo "requirements ok"
fi

# === === 5) Celery === ===
echo -e "$BORDER  Create Celery Service"
if ! [[ -f /etc/systemd/system/celery.service ]]; then

    cp -v /vagrant/config/celery.service /etc/systemd/system/celery.service
    # can now start celery
    systemctl enable celery
    systemctl start celery
    systemctl status celery
else echo "systemd celery ok"
fi

# === 7) Move files ===
echo -e "$BORDER  Move files into place"
if ! [[ -f /opt/arches/eamena/eamena/settings_local.py ]]; then 
    chown -R arches:arches /opt/arches
    /usr/bin/sudo -i --preserve-env=BORDER -u arches bash <<"EOF"

        echo === COPY template settings_local.py INTO THE PROJECT FOLDER ===
        cp -v /vagrant/arches_install_files/settings_local.py /opt/arches/eamena/eamena/settings_local.py 
EOF
else echo "settings_local ok"
fi

# === === 6) Customise settings_local.py === ===
echo -e "$BORDER  Customise settings_local.py"
if ! [[ -f /opt/arches/eamena/.settings_customised ]]; then

    set -x
    # Alter passwords in settings_local.py to match variables in deploy.env
    # test using `export $(awk '''!/^\s*#/''' /vagrant/provisioning/deploy.env | xargs)`
    # CELERY_BROKER_URL
    ESCAPED_REPLACE=$(printf '%s\n' "$CELERY_BROKER_URL" | sed -e 's/[\/&]/\\&/g')
    sed -i -E "s/^(CELERY_BROKER_URL)(.*)$/\1 = '$ESCAPED_REPLACE'/" /opt/arches/eamena/eamena/settings_local.py
    # ALLOWED_HOSTS
    sed -i -E "s/^(ALLOWED_HOSTS)(.*)$/\1 = $ALLOWED_HOSTS/" /opt/arches/eamena/eamena/settings_local.py
    # EMAIL_HOST_USER
    sed -i -E "s/^(EMAIL_HOST_USER)(.*)$/\1 = '$EMAIL_HOST_USER'/" /opt/arches/eamena/eamena/settings_local.py
    # EMAIL_FROM_ADDRESS
    sed -i -E "s/^(EMAIL_FROM_ADDRESS)(.*)$/\1 = '$EMAIL_FROM_ADDRESS'/" /opt/arches/eamena/eamena/settings_local.py
    # EMAIL_HOST_PASSWORD
    sed -i -E "s/^(EMAIL_HOST_PASSWORD)(.*)$/\1 = '$EMAIL_HOST_PASSWORD'/" /opt/arches/eamena/eamena/settings_local.py
    # ARCHES_NAMESPACE_FOR_DATA_EXPORT
    ESCAPED_REPLACE=$(printf '%s\n' "$ARCHES_NAMESPACE_FOR_DATA_EXPORT" | sed -e 's/[\/&]/\\&/g')
    sed -i -E "s/^(ARCHES_NAMESPACE_FOR_DATA_EXPORT)(.*)$/\1 = '$ESCAPED_REPLACE'/" /opt/arches/eamena/eamena/settings_local.py
    # SECRET_KEY
    sed -i -E "s/^(SECRET_KEY)(.*)$/\1 = '$SECRET_KEY'/" /opt/arches/eamena/eamena/settings_local.py
    # MAPBOX_API_KEY
    sed -i -E "s/^(MAPBOX_API_KEY)(.*)$/\1 = '$MAPBOX_API_KEY'/" /opt/arches/eamena/eamena/settings_local.py
    # DEBUG
    sed -i -E "s/^(DEBUG)(.*)$/\1 = '$DEBUG'/" /opt/arches/eamena/eamena/settings_local.py

    # done
    touch /opt/arches/eamena/.settings_customised
    set +x
else echo "settings customised ok"
fi

# === === System Settings === ===
echo -e "$BORDER  Convert and Load System Settings"
if ! [[ -d /opt/arches/eamena/eamena/system_settings ]]; then 
    /usr/bin/sudo -i --preserve-env=BORDER -u arches bash <<"EOF"
        source /opt/arches/ENV/bin/activate

        echo === DELETE ALL BUSINESS DATA ===
        rm -v /opt/arches/eamena/eamena/pkg/business_data/files/*

        echo === MOVE THE CONVERTED System_Settings.json file INTO THE PROJECT SYSTEM SETTINGS FOLDER ===
        cd /opt/arches/eamena

        python manage.py convert_json_57 -s /opt/arches/eamena/eamena/pkg/system_settings/System_Settings.json \
                        > /opt/arches/eamena/eamena/pkg/system_settings/System_Settings_conv.json

        rm -v /opt/arches/eamena/eamena/pkg/system_settings/System_Settings.json
        mkdir -v /opt/arches/eamena/eamena/system_settings
        mv -v /opt/arches/eamena/eamena/pkg/system_settings/System_Settings_conv.json /opt/arches/eamena/eamena/system_settings/System_Settings.json
        rm -v /opt/arches/eamena/eamena/system_settings/pkg/system_settings/System_Settings_conv.json
        cp -v /opt/arches/eamena/eamena/system_settings/System_Settings.json /opt/arches/eamena/eamena/pkg/system_settings/System_Settings.json
EOF
else echo "system_settings ok"
fi

if ! [[ -f /opt/arches/eamena/.system_settings_loaded ]]; then
    /usr/bin/sudo -i --preserve-env=BORDER -u arches bash <<"EOF"
        source /opt/arches/ENV/bin/activate
        cd /opt/arches/eamena

        echo === LOAD THE PACKAGE ===
        #TODO: Interactive? May need to replace with expect script
        echo "N" | python manage.py packages -o load_package -s /opt/arches/eamena/eamena/pkg/ -db
        # CHOOSE N FOR REWRITE SETTINGS AS Y WILL CREATE A PROBLEMATIC JSON SETTINGS FILE CAUSING AN ERROR AT THE SETTINGS PAGE
        touch /opt/arches/eamena/.system_settings_loaded
EOF
else echo "system_settings loaded"
fi

# === BUILD DEVELOPMENT FRONTEND ===
echo -e "$BORDER  Build Development Frontend"
if ! [[ -d /opt/arches/eamena/eamena/staticfiles ]]; then
# TODO: test a file inside staticfiles
    /usr/bin/sudo -i --preserve-env=BORDER -u arches bash <<"EOF"

        # download and extract media.tar to /opt/arches/media
        echo "Extracting media.tar.gz to /opt/arches/media"
        mkdir -p /opt/arches/files /opt/arches/media
        tar -xf /vagrant/arches_install_files/media.tar.gz -C /opt/arches/media
EOF
else echo "ok"
fi

# === === Run Django under Gunicorn (SF) === ===
# nb: I think we need this first to prevent error: "Error: read ECONNRESET" from `yarn build_development`?
echo -e "$BORDER  Create Gunicorn Service"
if ! [[ -f /etc/systemd/system/gunicorn.service ]]; then

    cp -v /vagrant/config/gunicorn.service /etc/systemd/system/gunicorn.service
    # can now start gunicorn
    systemctl enable gunicorn
    systemctl start gunicorn
    systemctl status gunicorn
else echo "systemd gunicorn ok"
fi


# === === Install and run files with Yarn === ===
echo -e "$BORDER  Install and run files with Yarn"
if ! [[ -f /opt/arches/eamena/eamena/yarn.lock ]]; then
    /usr/bin/sudo -i --preserve-env=BORDER -u arches bash <<"EOF"
        # Python ENV is needed by yarn
        source /opt/arches/ENV/bin/activate

        cd /opt/arches/eamena/eamena
        cp -v /vagrant/arches_install_files/package.json /opt/arches/eamena/eamena/package.json
        yarn --non-interactive install
        echo "=== BUILD DEVELOPMENT ==="
        yarn --non-interactive build_development || rm /opt/arches/eamena/eamena/yarn.lock
EOF
else echo "yarn ok"
fi

# === === Load grids === ===
echo -e "$BORDER  Load grids"
if ! [[ -f /opt/arches/eamena/.grids_loaded ]]; then
    /usr/bin/sudo -i --preserve-env=BORDER -u arches bash <<"EOF"
        source /opt/arches/ENV/bin/activate

        # === FIX DEFAULT VALUES ERROR ===
        cd /opt/arches/eamena
        #python manage.py migrate # ALREADY DONE IN LOAD THE PACKAGE
        python manage.py fix_default_value

        # === LOAD GRIDS ===
        # Takes approx 2 minutes to run
        python manage.py packages -o import_business_data -s /vagrant/arches_install_files/GS.csv -ow overwrite
        python manage.py es reindex_database

        # == CREATE SUPERUSER ==
        # Uses the DJANGO_* credentials in the deploy.env file
        python manage.py createsuperuser --no-input

        # === === Test it works using the backend === ===
        # upload a known working BU template (file.xlsx)
        # TODO: add file.xlsx to /vagrant
        #python /opt/arches/eamena/manage.py bu -w strict -o validate -g 34cfe98e-c2c0-11ea-9026-02e7594ce0a0 -s file.xlsx

        touch /opt/arches/eamena/.grids_loaded
EOF
else echo "grids ok"
fi

# ==
# upload database-eamena.orf.conf to /etc/apache2/sites_available
# # you may want to change ownership to arches of sites_available
# echo -e "$BORDER  Finalise Apache2 configuration"
# if ! [[ -f /etc/apache2/sites-available/database.eamena.org.conf ]]; then

#     cd /etc/apache2/sites-available
#     a2dissite *.conf
#     a2ensite arches.conf
#     a2enmod rewrite
#     apache2ctl configtest
#     systemctl restart apache2
#     cd /opt
#     chmod 755 -R arches
# else echo "ok"
# fi

# Final tests
systemctl restart apache2
curl -sL localhost:80 | grep "EAMENA v4" >/dev/null && echo "EAMENA v4 is running!"

echo -e "$BORDER  Provisioning complete! \n$BORDER"

