#!/usr/bin/env bash
# === === Set up HeritageBridge === ===

set -e
export BORDER="\n====================================================\n\n"
export DEBIAN_FRONTEND=noninteractive
export TZ=Etc/UTC

# Import environment:
export $(grep -v '^#' /vagrant/provisioning/herbridge.env | xargs)

# Check if required environment variables are set
if [ -z "$DEBUG" ] || \
   [ -z "$ALLOWED_HOSTS" ] || \
   [ -z "$ADMIN_PW_USERNAME" ] || \
   [ -z "$ADMIN_PW" ] || \
   [ -z "$FRONTEND_AUTH_TOKEN" ] || \
   [ -z "$FRONTEND_AUTH_PASSWORD" ] || \
   [ -z "$EAMENA_TARGET" ] || \
   [ -z "$SECRET_KEY" ] || \
   [ -z "$ARCHES_CLIENT_ID" ] || \
   [ -z "$ARCHES_CLIENT_SECRET" ] || \
   [ -z "$POSTGRES_USER" ] || \
   [ -z "$POSTGRES_PASS" ] || \
   [ -z "$POSTGRES_DB" ]; 
then
    echo "Error: One or more required environment variables are not set in provisioning/herbridge.env"
    echo "or, this script is not being run from the root of the git repository!"
    exit 1
fi

if [ -z "$NODE_VERSION" ]; then
    export NVM_VERSION=0.40.3
    export NODE_VERSION=14.21.3
    export NPM_VERSION=8.14.0
fi

# Set optional version number variables if not set:
# These can be overriden from deploy.env
if [ -z "$PYTHON_VERSION" ]; then
    export PYTHON_VERSION=3.9
fi
if [ -z "$INSTALL_PATH"]; then
    export INSTALL_PATH="/opt/arches/HeritageBridge"
fi
if [ -z "$SETTINGS_FILE"]; then
    export SETTINGS_FILE="${INSTALL_PATH}/herbridge/herbridge/local_settings.py"
fi
if [ -z "$GIT_REPO"]; then
    export GIT_REPO="https://github.com/DurhamARC/HeritageBridge.git"
fi


echo -e "\n<><><><><><><><><><><> INSTALL HERITAGEBRIDGE <><><><><><><><><><><>\n"

if ! [[ -f /opt/arches/eamena/.eamena_provisioned ]]; then
    echo "Error: This script is usually run after Arches/EAMENA setup, on the same host."
    echo "If Arches deployment script has not run, this script will fail with cryptic errors... ;)"
fi

# === INSTALL PREREQUISITES ===
# === === 1) Python; Node; and ENV === ===
echo -e "$BORDER Installing prerequisites \n"
if ! dpkg-query -W -f='${Status}' libjpeg-dev | grep "ok installed"; then

    apt-get update
    apt-get install -y libjpeg-dev zlib1g-dev # Required to build Pillow/PIL
fi

# === Clone HerBridge from git ===
echo -e "$BORDER  Clone HeritageBridge \n"
if ! [[ -f ${INSTALL_PATH}/herbridge/manage.py ]]; then

    mkdir -p ${INSTALL_PATH}
    chown arches:arches ${INSTALL_PATH}
    
    /usr/bin/sudo -EH -u arches bash <<"EOF"
        # ${INSTALL_PATH} must be empty!
        git clone --single-branch --branch arches-update --depth=1 ${GIT_REPO} ${INSTALL_PATH}
EOF
else echo "clone ok"
fi

# === Create own vENV for HerBridge ===
echo -e "$BORDER Create Virtualenv in ${INSTALL_PATH} \n"
if ! [[ -x ${INSTALL_PATH}/ENV/bin/python ]]; then

    /usr/bin/sudo -EH -u arches bash <<"EOF"
        if [ -z "$PYTHON_VERSION" ]; then
            echo "\$PYTHON_VERSION is not set in environment!"
            exit 1
        fi

        cd ${INSTALL_PATH}
        python${PYTHON_VERSION} -m virtualenv --python=/usr/bin/python${PYTHON_VERSION} ENV
        source ${INSTALL_PATH}/ENV/bin/activate
        pip install -U setuptools
EOF
else echo "ok"
fi

# === === Install HeritageBridge Python requirements === ===
echo -e "$BORDER  Install Python requirements \n"
if ! ${INSTALL_PATH}/ENV/bin/python -m pip show gunicorn >/dev/null || \
   ! ${INSTALL_PATH}/ENV/bin/python -m pip show django >/dev/null; then

    /usr/bin/sudo -EH -u arches bash <<"EOF"
        source ${INSTALL_PATH}/ENV/bin/activate
        cd ${INSTALL_PATH}
        python -m pip install -r requirements.txt
        python -m pip install gunicorn whitenoise
EOF
else echo "herbridge requirements ok"
fi

# === Install settings_local.py ===
echo -e "$BORDER  Install local Django settings \n"
if ! [[ -f ${SETTINGS_FILE} ]]; then 
    chown -R arches:arches /opt/arches
    /usr/bin/sudo -i --preserve-env=SETTINGS_FILE -u arches bash <<"EOF"

        echo === COPY template settings_local.py ===
        cp -v /vagrant/arches_install_files/herbridge_settings.py ${SETTINGS_FILE}
EOF
else echo "settings_local ok"
fi


# === === Customise settings_local.py === ===
echo -e "$BORDER  Customise local Django settings \n"
if ! grep $SECRET_KEY $SETTINGS_FILE 2>&1 >/dev/null; then

    set -x
    # Alter variables in settings_local.py to match variables in herbridge.env
    sed -i -E "s/^(DEBUG)(.*)$/\1 = $DEBUG/" ${SETTINGS_FILE}
    sed -i -E "s/^(ALLOWED_HOSTS)(.*)$/\1 = $ALLOWED_HOSTS/" ${SETTINGS_FILE}
    sed -i -E "s/^(ADMIN_PW_USERNAME)(.*)$/\1 = '$ADMIN_PW_USERNAME'/" ${SETTINGS_FILE}
    sed -i -E "s/^(ADMIN_PW)(.*)$/\1 = '$ADMIN_PW'/" ${SETTINGS_FILE}
    sed -i -E "s/^(FRONTEND_AUTH_TOKEN)(.*)$/\1 = '$FRONTEND_AUTH_TOKEN'/" ${SETTINGS_FILE}
    sed -i -E "s/^(FRONTEND_AUTH_PASSWORD)(.*)$/\1 = '$FRONTEND_AUTH_PASSWORD'/" ${SETTINGS_FILE}
    ESCAPED_REPLACE=$(printf '%s\n' "$EAMENA_TARGET" | sed -e 's/[\/&]/\\&/g')
    sed -i -E "s/^(EAMENA_TARGET)(.*)$/\1 = '$ESCAPED_REPLACE'/" ${SETTINGS_FILE}
    sed -i -E "s/^(SECRET_KEY)(.*)$/\1 = '$SECRET_KEY'/" ${SETTINGS_FILE}
    sed -i -E "s/^(ARCHES_CLIENT_ID)(.*)$/\1 = '$ARCHES_CLIENT_ID'/" ${SETTINGS_FILE}
    sed -i -E "s/^(ARCHES_CLIENT_SECRET)(.*)$/\1 = '$ARCHES_CLIENT_SECRET'/" ${SETTINGS_FILE}
    sed -i -E "s/^(DATABASES\['default'\]\['USER'\])(.*)$/\1 = '$POSTGRES_USER'/" ${SETTINGS_FILE}
    ESCAPED_REPLACE=$(printf '%s\n' "$POSTGRES_PASS" | sed -e 's/[\/&]/\\&/g')
    sed -i -E "s/^(DATABASES\['default'\]\['PASSWORD'\])(.*)$/\1 = '$ESCAPED_REPLACE'/" ${SETTINGS_FILE}
    sed -i -E "s/^(DATABASES\['default'\]\['NAME'\])(.*)$/\1 = '$POSTGRES_DB'/" ${SETTINGS_FILE}

    set +x
else echo "settings customised ok"
fi

# === === Create database credentials === ===
echo -e "$BORDER  Create Postgres database and user for HerBridge \n"
if ! PGPASSWORD="$POSTGRES_PASS" psql -h localhost -U "$POSTGRES_USER" -d $POSTGRES_DB -c '\q' >/dev/null 2>&1; then

    # Create user
    /usr/bin/sudo -EH -u postgres bash <<"EOF"
        createuser -h localhost -p 5432 -U postgres $POSTGRES_USER
        psql -d postgres -c "ALTER USER $POSTGRES_USER with encrypted password '$POSTGRES_PASS';"
        createdb -h localhost -p 5432 -U postgres $POSTRES_USER $POSTGRES_DB
        psql -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE $POSTGRES_DB TO $POSTGRES_USER;"
EOF
else echo "postgres herbridge user ok"
fi

# === === Setup herbridge logfile === ===
echo -e "$BORDER  Create and set permissions on logfile \n"
if [ ! "$(stat -c '%U' "${INSTALL_PATH}/herbridge/herbridge.log")" = "arches" ]; then
    touch ${INSTALL_PATH}/herbridge/herbridge.log
    chmod -v +x ${INSTALL_PATH}/herbridge/herbridge.log
    chown -v arches:arches ${INSTALL_PATH}/herbridge/herbridge.log
else echo "logfile OK"
fi

# === === Run herbridge django migrations === ===
echo -e "$BORDER  Run migrations if required. Available migrations: \n"
if ${INSTALL_PATH}/ENV/bin/python ${INSTALL_PATH}/herbridge/manage.py showmigrations | grep '\[ \]'; then
    # Create extension postgis as a superuser for specific herbridge database
    sudo -u postgres psql -d $POSTGRES_DB -c "CREATE EXTENSION IF NOT EXISTS postgis;"
    /usr/bin/sudo -EH -u arches bash <<"EOF"
        source ${INSTALL_PATH}/ENV/bin/activate
        echo "Run migrations"
        cd ${INSTALL_PATH}/herbridge
        python manage.py migrate
EOF
else echo "herbridge migrations ok"
fi

# === === HeritageBridge Systemd service === ===
echo -e "$BORDER  Create HerBridge Systemd Service \n"
if ! [[ -f /etc/systemd/system/herbridge.service ]]; then

    cp -v /vagrant/config/herbridge.service /etc/systemd/system/herbridge.service
    chmod +x /etc/systemd/system/herbridge.service

    # can now start celery
    systemctl enable herbridge
    systemctl start herbridge
    systemctl status herbridge
else echo "systemd herbridge ok"
fi


# === === Install nvm: node version manager === ===
echo -e "$BORDER  Installing NVM; Node; NPM; *locally* as 'arches' user\n"
if ! [[ -d /opt/arches/.nvm ]]; then
    /usr/bin/sudo -EH -u arches bash <<"EOF"
        cd
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh | bash
        # nvm should pick up $NODE_VERSION automagically
EOF
fi

echo "ElasticSearch eats RAM. Stopping it while we build node_modules..."
systemctl stop elasticsearch

# === === Install node as local arches user === ===
/usr/bin/sudo -EH -u arches bash <<"EOF"
    set -e
    export NVM_DIR=$HOME/.nvm;
    source $NVM_DIR/nvm.sh;
    export PATH="$HOME/node_modules/.bin:$PATH"
    cd $HOME

    echo "node is $(node --version) at $(which node). Want ${NODE_VERSION}."
    echo "npm is $(npm --version) at $(which npm). Want ${NPM_VERSION}."
    
    # Node version update should not be required as nvm installs it, but to be safe...
    if ! node --version | grep "${NODE_VERSION}" >/dev/null 2>&1; then
        echo "node is the wrong version. Installing locally..."
        nvm i ${NODE_VERSION}
    fi

    if ! npm --version | grep "${NPM_VERSION}" >/dev/null 2>&1; then
        echo "npm is the wrong version. Installing locally..."
        npm install npm@${NPM_VERSION}
        echo npm is now $(npm --version)
    fi

    if ! [[ -d ${INSTALL_PATH}/herbridge/frontend/node_modules ]]; then
        echo "Installing local node modules"
        cd ${INSTALL_PATH}/herbridge/frontend
        npm i
        # runs npm run prod as postinstall script
    else
        echo "Node modules built. Remove ${INSTALL_PATH}/herbridge/frontend/node_modules to rebuild"
    fi
EOF


# === === Restart ElasticSearch. === ===
# Nom nom nom 5GB RAM... 
echo "Restarting elasticsearch..."
systemctl start elasticsearch

# Mark completed
echo -e "$BORDER  Provisioning complete! \n$BORDER"
touch ${INSTALL_PATH}/.herbridge_provisioned
