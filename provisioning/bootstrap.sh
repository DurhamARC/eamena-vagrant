# Vagrant EAMENA Arches 7.3 deployment script
# Based on:
# https://github.com/eamena-project/eamena-arches-dev/blob/main/dbs/database.eamena/install/detailed_workflow_krg2.sh

set -e
export BORDER="\n====================================================\n\n"
export DEBIAN_FRONTEND=noninteractive 
export TZ=Etc/UTC

# Import environment:
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

# Set optional version number variables if not set:
# These can be overriden from deploy.env
if [ -z "$PYTHON_VERSION" ]; then
    export PYTHON_VERSION=3.9
fi
if [ -z "$ELASTICSEARCH_VERSION" ]; then
    export ELASTICSEARCH_VERSION=8.3.3
fi
if [ -z "$PSQL_VERSION" ]; then
    export PSQL_VERSION=14
fi
if [ -z "$NODE_VERSION" ]; then
    export NODE_VERSION=20.19.4
    export NPM_VERSION=10.9.3
    export YARN_VERSION=1.22.19
    # prev: 14.17.6; 9.6.0; 1.22.19
fi
if [ -z "$SETTINGS_FILE"]; then
    export SETTINGS_FILE="/opt/arches/eamena/eamena/settings_local.py"
fi

# === create an arches user ===
echo -e "$BORDER Creating Arches user and folder \n"
if ! id -nGz "arches" | grep -qzxF "sudo";
then
    # Bonus: set users' shells to bash
    usermod -s $(which bash) vagrant
    useradd -m -s $(which bash) -d /opt/arches arches
    usermod -aG sudo,vagrant,www-data arches
    echo -e '\nexport $(grep -v '^#' /vagrant/provisioning/deploy.env | xargs)' >> /opt/arches/.bashrc

    if [ -z "$ARCHES_PASSWORD" ]; then
        # If we've set a password in deploy.env, use it for arches:
        echo "Updating user password for arches"
        echo "arches:${ARCHES_PASSWORD}" | chpasswd
    fi
    
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
# === === 1) Python; Node; and ENV === ===
echo -e "$BORDER Installing prerequisites \n"
if ! dpkg-query -W -f='${Status}' virtualenv | grep "ok installed"; then

    apt-get update
    apt-get install -y python3-dev python3-virtualenv virtualenv python3-pip \
                       python3-psycopg2 libpq-dev python-is-python3 build-essential \
                       nodejs npm
fi
# Install a newer Python (to enable debugging):
if ! dpkg-query -W -f='${Status}' python${PYTHON_VERSION} | grep "ok installed"; then

    add-apt-repository -y ppa:deadsnakes/ppa
    apt-get update
    apt-get install -y python${PYTHON_VERSION}-dev python${PYTHON_VERSION} \
                       python${PYTHON_VERSION}-distutils

    # Don't mess with system python, you'll break apt...
    # I've left these lines commented here to warn future maintainers against this!
    # update-alternatives --install /usr/bin/python python /usr/bin/python$PYTHON_VERSION 1
    # update-alternatives --install /usr/bin/python3 python3 /usr/bin/python$PYTHON_VERSION 1
fi

# Provisioner runs as root. Sudo as `arches` user for venv install:
echo -e "$BORDER Create Virtualenv in /opt/arches \n"
if ! [[ -x /opt/arches/ENV/bin/python ]]; then

    /usr/bin/sudo -E -u arches bash <<"EOF"
        if [ -z "$PYTHON_VERSION" ]; then
            echo "\$PYTHON_VERSION is not set in environment!"
            exit 1
        fi

        cd /opt/arches
        python${PYTHON_VERSION} -m virtualenv --python=/usr/bin/python${PYTHON_VERSION} ENV
        source /opt/arches/ENV/bin/activate
        pip install -U setuptools
EOF
else echo "ok"
fi

# === === 2) Elasticsearch === ===
echo -e "$BORDER Install ElasticSearch \n"
if ! dpkg-query -W -f='${Status}' elasticsearch | grep "ok installed"; then

    cd /home/vagrant
    ARCH=`dpkg --print-architecture`

    rm -f ./elasticsearch-$ELASTICSEARCH_VERSION-$ARCH.deb # remove if download failed on previous run
    
    if [[ -f /vagrant/arches_install_files/elasticsearch-$ELASTICSEARCH_VERSION-$ARCH.deb ]]; then
        echo "Found local elasticsearch-$ELASTICSEARCH_VERSION-$ARCH.deb"
        cp -v /vagrant/arches_install_files/elasticsearch-$ELASTICSEARCH_VERSION-$ARCH.deb ./
    else
        # download the deb package
        echo "Downloading elasticsearch-$ELASTICSEARCH_VERSION-$ARCH.deb"
        wget --no-verbose --show-progress  --progress=dot:mega \
            "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$ELASTICSEARCH_VERSION-$ARCH.deb" # WD local
    fi

    # install the deb package
    dpkg -i ./elasticsearch-$ELASTICSEARCH_VERSION-$ARCH.deb
    # cleanup and don't download again
    cp -v ./elasticsearch-$ELASTICSEARCH_VERSION-$ARCH.deb /vagrant/arches_install_files/
    rm ./elasticsearch-$ELASTICSEARCH_VERSION-$ARCH.deb
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
echo -e "$BORDER  Performing configuration changes for elasticsearch.yml \n"
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
echo -e "$BORDER  Installing Postgres \n"
if ! dpkg-query -W -f='${Status}' postgresql-${PSQL_VERSION} | grep "ok installed"; then

    # Note: Postgres deprecate support for old ubuntu versions. If hitting a 404 error here, 
    #       it's likely that the version of Ubuntu we're on is now too old.
    echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
    apt-get update

    apt-get install -y postgresql-${PSQL_VERSION} postgresql-contrib-${PSQL_VERSION} \
                       postgresql-${PSQL_VERSION}-postgis-3 postgresql-${PSQL_VERSION}-postgis-3-scripts
fi

echo -e "$BORDER  Configuring Postgres \n"
if ! grep -E "standard_conforming_strings = off" /etc/postgresql/${PSQL_VERSION}/main/postgresql.conf &> /dev/null &&\
   ! grep -E "#Autoconfiguration done" /etc/postgresql/${PSQL_VERSION}/main/pg_hba.conf &> /dev/null; then

    sudo -u postgres psql -d postgres -c "ALTER USER postgres with encrypted password 'postgis';"
    echo "*:*:*:postgres:postgis" >> ~/.pgpass

    chmod 600 ~/.pgpass
    chmod 666 /etc/postgresql/${PSQL_VERSION}/main/postgresql.conf
    chmod 666 /etc/postgresql/${PSQL_VERSION}/main/pg_hba.conf

    echo "standard_conforming_strings = off" >> /etc/postgresql/${PSQL_VERSION}/main/postgresql.conf
    echo "listen_addresses = '*'" >> /etc/postgresql/${PSQL_VERSION}/main/postgresql.conf
    echo "#TYPE   DATABASE  USER  CIDR-ADDRESS  METHOD" > /etc/postgresql/${PSQL_VERSION}/main/pg_hba.conf
    echo "local   all       all                 trust" >> /etc/postgresql/${PSQL_VERSION}/main/pg_hba.conf
    echo "host    all       all   127.0.0.1/32  trust" >> /etc/postgresql/${PSQL_VERSION}/main/pg_hba.conf
    echo "host    all       all   ::1/128       trust" >> /etc/postgresql/${PSQL_VERSION}/main/pg_hba.conf
    echo "host    all       all   0.0.0.0/0     md5" >> /etc/postgresql/${PSQL_VERSION}/main/pg_hba.conf
    echo "#Autoconfiguration done" >> /etc/postgresql/${PSQL_VERSION}/main/pg_hba.conf
    
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

# === === 4) Apache === ===
echo -e "$BORDER  Install apache2 and modules \n"
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

# === === 5) RabbitMQ === ===
echo -e "$BORDER  Install and configure RabbitMQ \n"
if ! dpkg-query -W -f='${Status}' rabbit | grep "ok installed"; then

    apt-get install -y rabbitmq-server rabbit
    rabbitmqctl add_vhost arches
fi

# Wait for RabbitMQ to start
# Fixes: Error: this command requires the 'rabbit' app to be running on the target node. Start it with 'rabbitmqctl start_app'.
timeout 60 bash -c 'while ! systemctl is-active --quiet rabbitmq-server; do echo "Waiting for RabbitMQ startup..."; sleep 5; done'

# Check user setup of 'arches' in RabbitMQ
if ! rabbitmqctl list_users | grep 'arches'; then

    # Echo password into add_user
    echo $RABBITMQ_PASSWORD | rabbitmqctl add_user arches

    rabbitmqctl set_permissions -p arches arches ".*" ".*" ".*"
    systemctl restart rabbitmq-server
    systemctl status rabbitmq-server
fi

# === CLONE EAMENA GIT PROJECT/PACKAGE ===
echo -e "$BORDER  Clone EAMENA \n"
if ! [[ -f /opt/arches/eamena/__init__.py ]]; then
    
    /usr/bin/sudo -i --preserve-env=BORDER -u arches bash <<"EOF"
        cd /opt/arches
        git clone --depth=1 https://github.com/eamena-project/eamena.git
EOF
else echo "clone ok"
fi

# === 6) INSTALL ARCHES/EAMENA ===
echo -e "$BORDER  Install Arches and EAMENA Python requirements \n"
if ! /opt/arches/ENV/bin/python -m pip show gunicorn >/dev/null; then

    /usr/bin/sudo -i --preserve-env=BORDER -u arches bash <<"EOF"
        source /opt/arches/ENV/bin/activate
        cd /opt/arches/eamena
        python -m pip install "arches==7.3"    # Still required? It's in requirements.txt...
        python -m pip install -r requirements.txt
        python -m pip install geomet gunicorn
        echo -e "source /opt/arches/ENV/bin/activate" >> /opt/arches/.bashrc
EOF
else echo "requirements ok"
fi

# === === Celery service === ===
echo -e "$BORDER  Create Arches Celery Service \n"
if ! [[ -f /etc/systemd/system/celery.service ]]; then

    cp -v /vagrant/config/celery.service /etc/systemd/system/celery.service
    # can now start celery
    systemctl enable celery
    systemctl start celery
    systemctl status celery
else echo "systemd celery ok"
fi

# === Install settings_local.py ===
echo -e "$BORDER  Install settings_local.py \n"
if ! [[ -f ${SETTINGS_FILE} ]]; then 
    chown -R arches:arches /opt/arches
    /usr/bin/sudo -EH -u arches bash <<"EOF"

        echo === COPY template settings_local.py INTO THE PROJECT FOLDER ===
        cp -v /vagrant/arches_install_files/settings_local.py ${SETTINGS_FILE}
EOF
else echo "settings_local ok"
fi

# === === Customise settings_local.py === ===
echo -e "$BORDER  Customise settings_local.py \n"
if ! grep $SECRET_KEY ${SETTINGS_FILE} 2>&1 >/dev/null; then

    set -x
    # Alter passwords in settings_local.py to match variables in deploy.env
    # test using `export $(awk '''!/^\s*#/''' /vagrant/provisioning/deploy.env | xargs)`
    ESCAPED_REPLACE=$(printf '%s\n' "$CELERY_BROKER_URL" | sed -e 's/[\/&]/\\&/g')
    sed -i -E "s/^(CELERY_BROKER_URL)(.*)$/\1 = '$ESCAPED_REPLACE'/" ${SETTINGS_FILE}
    sed -i -E "s/^(ALLOWED_HOSTS)(.*)$/\1 = $ALLOWED_HOSTS/" ${SETTINGS_FILE}
    sed -i -E "s/^(EMAIL_HOST_USER)(.*)$/\1 = '$EMAIL_HOST_USER'/" ${SETTINGS_FILE}
    sed -i -E "s/^(EMAIL_FROM_ADDRESS)(.*)$/\1 = '$EMAIL_FROM_ADDRESS'/" ${SETTINGS_FILE}
    sed -i -E "s/^(EMAIL_HOST_PASSWORD)(.*)$/\1 = '$EMAIL_HOST_PASSWORD'/" ${SETTINGS_FILE}
    ESCAPED_REPLACE=$(printf '%s\n' "$ARCHES_NAMESPACE_FOR_DATA_EXPORT" | sed -e 's/[\/&]/\\&/g')
    sed -i -E "s/^(ARCHES_NAMESPACE_FOR_DATA_EXPORT)(.*)$/\1 = '$ESCAPED_REPLACE'/" ${SETTINGS_FILE}
    sed -i -E "s/^(SECRET_KEY)(.*)$/\1 = '$SECRET_KEY'/" ${SETTINGS_FILE}
    sed -i -E "s/^(MAPBOX_API_KEY)(.*)$/\1 = '$MAPBOX_API_KEY'/" ${SETTINGS_FILE}
    sed -i -E "s/^(DEBUG)(.*)$/\1 = $DEBUG/" ${SETTINGS_FILE}

    # done
    set +x
else echo "settings customised ok"
fi

# === === System Settings === ===
echo -e "$BORDER  Convert and Load System Settings \n"
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
        echo "N" | python manage.py packages -o load_package -s /opt/arches/eamena/eamena/pkg/ -db
        # CHOOSE N FOR REWRITE SETTINGS AS Y WILL CREATE A PROBLEMATIC JSON SETTINGS FILE CAUSING AN ERROR AT THE SETTINGS PAGE
        touch /opt/arches/eamena/.system_settings_loaded
EOF
else echo "system_settings loaded"
fi

# === BUILD DEVELOPMENT FRONTEND ===
echo -e "$BORDER  Copy Frontend files \n"
if ! [[ -d /opt/arches/media ]]; then
# TODO: test a file inside staticfiles
    /usr/bin/sudo -i --preserve-env=BORDER -u arches bash <<"EOF"

        # download and extract media.tar to /opt/arches/media
        echo "Extracting media.tar.gz to /opt/arches/media"
        mkdir -p /opt/arches/files /opt/arches/media
        tar -xf /vagrant/arches_install_files/media.tar.gz -C /opt/arches/media
EOF
else echo "ok"
fi

# === === Run EAMENA under Gunicorn === ===
# We need this first to prevent error: "Error: read ECONNRESET" from `yarn build_development`
echo -e "$BORDER  Create EAMENA Gunicorn Service \n"
if ! [[ -f /etc/systemd/system/eamena.service ]]; then

    cp -v /vagrant/config/eamena.service /etc/systemd/system/eamena.service
    chmod +x /etc/systemd/system/eamena.service

    # can now start eamena
    systemctl enable eamena
    systemctl start eamena
    systemctl status eamena
else echo "EAMENA installed into systemd ok"
fi

echo -e "$BORDER  Installing NodeJS; NPM; & Yarn \n"
# === === NodeJS, NPM, Yarn === ===
pkgs() { npm list -g --depth=0; }
if ! node --version | grep "${NODE_VERSION}" || 
   ! pkgs | grep "npm@${NPM_VERSION}" ||
   ! pkgs | grep "yarn@${YARN_VERSION}"; then

    # Install n (node version manager) and set node version to $NODE_VERSION
    # Then install yarn
    set -x
    npm i -g n
    n $NODE_VERSION
    hash -r # Reset location of npm and node in shell
    npm i -g npm@${NPM_VERSION}
    npm i -g yarn@${YARN_VERSION}
    set +x
else echo "node/npm/yarn ok"
fi

# === === Install and run files with Yarn === ===
echo -e "$BORDER  Install and run files with Yarn \n"
if ! [[ -f /opt/arches/eamena/eamena/yarn.lock ]]; then
    /usr/bin/sudo -i --preserve-env=BORDER -u arches bash <<"EOF"
        # Python ENV is needed by yarn
        set -e
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
echo -e "$BORDER  Load grids \n"
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

        # === === Test it works using the backend === ===
        # upload a known working BU template (file.xlsx)
        # TODO: add file.xlsx to /vagrant
        #python /opt/arches/eamena/manage.py bu -w strict -o validate -g 34cfe98e-c2c0-11ea-9026-02e7594ce0a0 -s file.xlsx

        touch /opt/arches/eamena/.grids_loaded
EOF
else echo "grids ok"
fi

# === === Create superusers === ===
echo -e "$BORDER  Create EAMENA superusers \n"
if ! [[ -f /opt/arches/eamena/eamena/management/commands/list_users.py ]]; then
    cp -v /vagrant/config/django_commands/*.py /opt/arches/eamena/eamena/management/commands
    chown --no-dereference arches:arches /opt/arches/eamena/eamena/management/commands/*.py
else echo "management scripts ok"
fi 

if ! [[ -z "${DJANGO_SUPERUSER_LIST}" ]]; then
    /usr/bin/sudo -EH -u arches bash <<"EOF"
        source /opt/arches/ENV/bin/activate
        cd /opt/arches/eamena

        FIRST_USER=$(echo $DJANGO_SUPERUSER_LIST | cut -f1 -d':')
        USERS="$(python manage.py list_users 2>/dev/null)"
        echo -e "available users: $USERS"

        if ! echo $USERS | grep $FIRST_USER; then
            echo "Creating users..."
            DJANGO_GROUPS="$(python manage.py list_groups 2>/dev/null)"
            DJANGO_PERMISSIONS="$(python manage.py list_permissions 2>/dev/null)"
            echo "Groups available: $DJANGO_GROUPS"
            echo "Permissions available: ${DJANGO_PERMISSIONS:0:30}... [truncated length ${#DJANGO_PERMISSIONS} total]"
            python manage.py make_superusers "${DJANGO_SUPERUSER_LIST}" "${DJANGO_GROUPS}" "${DJANGO_PERMISSIONS}"
            python manage.py clear_perm_cache
        fi
EOF
else echo "environment does not define \$DJANGO_SUPERUSER_LIST, nothing to do."
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

timeout 60 bash -c 'while ! systemctl is-active --quiet eamena; do echo "Waiting for EAMENA startup..."; sleep 5; done'

# Final tests for EAMENA
if ! curl -sL localhost:80 | grep "EAMENA v4" >/dev/null; then
    echo -e "EAMENA doesn't seem to be running. Something went wrong." >&2
    echo -e "Use \`vagrant ssh\` to log in and examine the system." >&2
    echo -e "\nUseful commands:" >&2
    echo -e "    sudo systemctl status apache2" >&2
    echo -e "    sudo systemctl status eamena" >&2
    echo -e "    sudo journalctl -exu eamena" >&2
    echo -e "\nThen, re-run this script using \`vagrant up --provision\`" >&2
    exit 1
else echo -e "\nEAMENA v4 is running!"
fi

echo -e "$BORDER  Provisioning complete! \n$BORDER"
touch /opt/arches/eamena/.eamena_provisioned
