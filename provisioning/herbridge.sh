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
   [ -z "$SECRET_KEY" ]; 
then
    echo "Error: One or more required environment variables are not set in provisioning/herbridge.env"
    echo "or, this script is not being run from the root of the git repository!"
    exit 1
fi

# Set optional version number variables if not set:
# These can be overriden from deploy.env
if [ -z "$PYTHON_VERSION" ]; then
    export PYTHON_VERSION=3.9
fi
if [ -z "$INSTALL_PATH"]; then
    export INSTALL_PATH="/opt/arches/HeritageBridge"
fi
if [ -z "$SETTINGS_LOCAL_PATH"]; then
    export SETTINGS_LOCAL_PATH="${INSTALL_PATH}/herbridge/settings_local.py"
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
        git clone --depth=1 ${GIT_REPO} ${INSTALL_PATH}
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
        python -m pip install gunicorn
EOF
else echo "herbridge requirements ok"
fi

# === Install local settings ===
echo -e "$BORDER  Write local settings file \n"
if ! [[ -f $SETTINGS_LOCAL_PATH ]]; then 
    chown -R arches:arches /opt/arches
    /usr/bin/sudo -EH -u arches ${INSTALL_PATH}/ENV/bin/python <<"EOF"
import os
output_file: str = os.getenv('SETTINGS_LOCAL_PATH')
env_variables = [ 'DEBUG', 'ALLOWED_HOSTS', 'ADMIN_PW_USERNAME', 'ADMIN_PW', 'FRONTEND_AUTH_TOKEN', 'FRONTEND_AUTH_PASSWORD', 'EAMENA_TARGET', 'SECRET_KEY' ]
with open(output_file, 'w') as f:
    for v in env_variables:
        f.write(f"{v}={os.getenv(v)}\n")
print(f"Wrote {len(env_variables)} vars to {output_file}")
EOF
else echo "settings_local ok"
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


echo -e "$BORDER  Provisioning complete! \n$BORDER"
touch ${INSTALL_PATH}/.herbridge_provisioned
