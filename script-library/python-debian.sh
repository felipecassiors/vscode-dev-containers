#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/microsoft/vscode-dev-containers/blob/master/script-library/docs/python.md
#
# Syntax: ./python-debian.sh [Python Version] [Python intall path] [PIPX_HOME] [non-root user] [Update rc files flag] [install tools]

PYTHON_VERSION=${1:-${PYTHON_VERSION:-"3.9.0"}}
export PYENV_ROOT=${2:-${PYENV_ROOT:-"/usr/local/share/pyenv"}}
export PIPX_HOME=${3:-${PIPX_HOME:-"/usr/local/py-utils"}}
USERNAME=${4:-"automatic"}
UPDATE_RC=${5:-"true"}
INSTALL_PYTHON_TOOLS=${6:-"true"}

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

# Determine the appropriate non-root user
if [ "${USERNAME}" = "auto" ] || [ "${USERNAME}" = "automatic" ]; then
    USERNAME=""
    POSSIBLE_USERS=("vscode" "node" "codespace" "$(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)")
    for CURRENT_USER in "${POSSIBLE_USERS[@]}"; do
        if id -u "${CURRENT_USER}" >/dev/null 2>&1; then
            USERNAME=${CURRENT_USER}
            break
        fi
    done
    if [ "${USERNAME}" = "" ]; then
        USERNAME=root
    fi
elif [ "${USERNAME}" = "none" ] || ! id -u ${USERNAME} >/dev/null 2>&1; then
    USERNAME=root
fi

updaterc() {
    if [ "${UPDATE_RC}" = "true" ]; then
        echo "Updating /etc/bash.bashrc and /etc/zsh/zshrc..."
        echo -e "$1" | tee -a /etc/bash.bashrc /etc/zsh/zshrc
    fi
}

# Function to call apt-get if needed
apt-get-update-if-needed() {
    if [ ! -d "/var/lib/apt/lists" ] || [ "$(ls /var/lib/apt/lists/ | wc -l)" = "0" ]; then
        echo "Running apt-get update..."
        apt-get update
    else
        echo "Skipping apt-get update."
    fi
}

export DEBIAN_FRONTEND=noninteractive

# Install prereqs if missing
# https://github.com/pyenv/pyenv/wiki#suggested-build-environment
PREREQ_PKGS="make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev"
# shellcheck disable=SC2086
if ! dpkg -s $PREREQ_PKGS >/dev/null 2>&1; then
    if [ ! -d "/var/lib/apt/lists" ] || [ "$(ls /var/lib/apt/lists/ | wc -l)" = "0" ]; then
        apt-get update
    fi
    apt-get -y install --no-install-recommends ${PREREQ_PKGS}
fi

bash -c "$(curl -fsSL https://github.com/pyenv/pyenv-installer/raw/master/bin/pyenv-installer)"
chown -R $USERNAME "$PYENV_ROOT"
if [ "${PYTHON_VERSION}" != "none" ]; then
    su ${USERNAME} -c "pyenv install ${PYTHON_VERSION}"
    su ${USERNAME} -c "pyenv global ${PYTHON_VERSION}"
fi
# shellcheck disable=SC2016
updaterc 'eval "$(pyenv init - )"'

# If not installing python tools, exit
if [ "${INSTALL_PYTHON_TOOLS}" != "true" ]; then
    echo "Done!"
    exit 0
fi

DEFAULT_UTILS="\
    pylint \
    flake8 \
    autopep8 \
    black \
    yapf \
    mypy \
    pydocstyle \
    pycodestyle \
    bandit \
    pipenv \
    virtualenv \
    pytest"

# Update pip
echo "Updating pip..."
python3 -m pip install --no-cache-dir --upgrade pip

# Install tools
mkdir -p "${PIPX_BIN_DIR}"
chown -R ${USERNAME} "${PIPX_HOME}" "${PIPX_BIN_DIR}"
su ${USERNAME} -c "$(
    cat <<EOF
    set -e
    echo "Installing Python tools..."
    export PIPX_HOME=${PIPX_HOME}
    export PIPX_BIN_DIR=${PIPX_BIN_DIR}
    export PYTHONUSERBASE=/tmp/pip-tmp
    export PIP_CACHE_DIR=/tmp/pip-tmp/cache
    export PATH=${PATH}
    eval "$(pyenv init - --no-rehash)"
    pip3 install --disable-pip-version-check --no-warn-script-location  --no-cache-dir --user pipx
    /tmp/pip-tmp/bin/pipx install --pip-args=--no-cache-dir pipx
    echo "${DEFAULT_UTILS}" | xargs -n 1 /tmp/pip-tmp/bin/pipx install --system-site-packages --pip-args '--no-cache-dir --force-reinstall'
    chown -R ${USERNAME} ${PIPX_HOME}
    rm -rf /tmp/pip-tmp
EOF
)"
