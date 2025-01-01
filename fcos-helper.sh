#!/bin/bash

SCRIPT_VERSION="1.0.0"
BUTANE_CFG_LOC=""
ADMIN_USER="core" # default admin account is going to be 'core'
ARCH="$(uname -m)"
COREOS_BUTANE_VER="0.23.0"
COREOS_BUTANE_BIN_URL="https://github.com/coreos/butane/releases/download/v${COREOS_BUTANE_VER}/butane-${ARCH}-unknown-linux-gnu"
COREOS_BUTANE_ASC_URL="${COREOS_BUTANE_BIN_URL}.asc"
FEDORA_KEY_URL="https://fedoraproject.org/fedora.gpg"
DONT_EDIT=""

usage() {
    echo "$(basename $0): Fedora CoreOS install helper and simple inline butane config editor"
    echo "  -n                     do not edit the butane configuration file, just convert"
    echo "  -b /full/path/to/butane/config or -b https://somewhere/config (required)"
    echo "  -u <admin username>    defaults to 'core'"
    echo "  -k <ssh-alg key>       pass key to script. can also be given as an environment"
    echo "                           variable USER_SSH_KEY or it can be read interactively"
    echo "                           can also pass from a file e.g. -k \"\$(cat key)\""
    echo "  -h                     this help"
    echo "  -v                     print version"
}

fetch_butane_cfg() {
    # if it is a file, as if from a usb drive (provide full path)
    if [[ "${BUTANE_CFG_LOC}" == "/"* ]]; then
        cp "${BUTANE_CFG_LOC}" /tmp/cfg.butane
    # if it is from http(s)
    elif [[ "${BUTANE_CFG_LOC}" == "http:"* ]]; then
        echo "Error: Downloading butane configuration file over http is unsupported as it could contain secrets."
        exit 1
    elif [[ "${BUTANE_CFG_LOC}" == "https:"* ]]; then
        curl --silent -L "${BUTANE_CFG_LOC}" -o /tmp/cfg.butane
        if [ $? != 0 ]; then
            echo "Error: There was an error downloading the butane configuration file."
            exit 1
        fi
    else
        echo "Error: Missing or invalid butane configuration file source. Must be a full path to the butane configuration or an https link"
        exit 1
    fi

    BUTANE_CFG="/tmp/cfg.butane"
}

fetch_butane_bin() {
    curl --silent --output-dir /tmp -L --remote-name-all "${FEDORA_KEY_URL}" \
        "${COREOS_BUTANE_BIN_URL}" "${COREOS_BUTANE_ASC_URL}"
    if [ $? != 0 ]; then
        echo "Error: There was an error downloading butane tools."
        exit 1
    fi
    # remove url stuff to get filename. doing this complicated stuff because
    # the filename could vary based on arch
    BUTANE_BIN="/tmp/$(sed -r 's@.*(butane-.*)@\1@' <<< ${COREOS_BUTANE_BIN_URL})"
    BUTANE_ASC="${BUTANE_BIN}".asc
    gpg --quiet --import /tmp/fedora.gpg
    gpg --verify "${BUTANE_ASC}" "${BUTANE_BIN}" 1>&2 2>/dev/null
    if [ $? != 0 ]; then
        echo "Error: Bad signature: ${BUTANE_BIN}, ${BUTANE_ASC}"
        exit 1
    fi
    chmod +x "${BUTANE_BIN}"
}

edit_butane_cfg() {
    local USER_PASSWORD CONFIRM_USER_PASSWORD
    while true
    do
        read -s -p 'Enter desired password: ' USER_PASSWORD
        echo
        read -s -p 'Confirm password: ' CONFIRM_USER_PASSWORD
        echo
        if [ "${USER_PASSWORD}" != "${CONFIRM_USER_PASSWORD}" ]; then
            echo "Passwords do not match"
            USER_PASSWORD=""
            CONFIRM_USER_PASSWORD=""
        else
            break
        fi
    done

    if [[ "${ADMIN_USER}" != "core" ]]; then
        sudo useradd -m -k /dev/null -s /bin/bash "${ADMIN_USER}"
        sed -ri "s@(- name: ).*@\1${ADMIN_USER}@" "${BUTANE_CFG}"
    fi
    # mkpasswd is not bundled in the live DVD, must use chpasswd unfortunately
    echo "${ADMIN_USER}:${USER_PASSWORD}" | sudo chpasswd -s 11 -c YESCRYPT
    grep -q password_hash "${BUTANE_CFG}"
    if [ $? != 0 ]; then
        echo "Error: password_hash is not defined in butane configuration file!"
        exit 1
    else
        local NEW_HASH="$(sudo grep -e ^${ADMIN_USER} /etc/shadow | cut -d : -f 2)"
        sed -i "s@password_hash: \$y\$.*@password_hash: ${NEW_HASH}@" "${BUTANE_CFG}"
    fi

    # you can pass USER_SSH_KEY="<key>" to the script or
    # you can pass with -k '<key>' or
    # -k "$(cat /path/to/key)" (such as on a usb) or
    # it will be read interactively here
    if [[ ${USER_SSH_KEY} != "ssh-"* ]]; then
        read -p 'Enter ssh public key (ssh-<alg> <key>): ' USER_SSH_KEY
        echo
    fi
    sed -ri "s@(- )ssh-.*@\1${USER_SSH_KEY}@" "${BUTANE_CFG}"
}

conv_butane_cfg() {
    "${BUTANE_BIN}" --pretty "${BUTANE_CFG}" > /tmp/cfg.ign
    if [ $? != 0 ]; then
        echo "Error: Butane encountered an error."
        exit 1
    fi
}

print_script_version() {
    echo "Version: ${SCRIPT_VERSION}"
}

while getopts ":hb:u:k:nv" opt; do
    case "${opt}" in
        h) usage && exit 0;;
        b) BUTANE_CFG_LOC="${OPTARG}";;
        u) ADMIN_USER="${OPTARG}";;
        k) USER_SSH_KEY="${OPTARG}";;
        n) DONT_EDIT=1;;
        v) print_script_version && exit 0;;
        \?) echo "Invalid option: -${OPTARG}" 1>&2 && usage && exit 1;;
        :) echo "Invalid option: -${OPTARG} requires an argument" 1>&2 && exit 1;;
    esac
done
shift $((OPTIND-1))

if [[ -z "${BUTANE_CFG_LOC}" ]]; then
    echo "Error: -b is required"
    exit 1
fi

if [ "${DONT_EDIT}" == "1" ]; then
    fetch_butane_cfg
    fetch_butane_bin
    conv_butane_cfg
else
    fetch_butane_cfg
    fetch_butane_bin
    edit_butane_cfg
    conv_butane_cfg
fi

echo "Ignition file created. Now run the following:"
echo "  sudo coreos-installer install /dev/<disk> -i /tmp/cfg.ign"
