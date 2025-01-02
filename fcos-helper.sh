#!/bin/bash

SCRIPT_VERSION="1.1.0"
BUTANE_CFG_LOC=""
ADMIN_USER=""
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
        BUTANE_CFG="/tmp/cfg.butane"
    # if it is from http(s)
    elif [[ "${BUTANE_CFG_LOC}" == "http:"* ]]; then
        echo "Error: Downloading butane configuration file over http is unsupported as it could contain secrets."
        exit 1
    elif [[ "${BUTANE_CFG_LOC}" == "https:"* ]]; then
        curl --silent -L "${BUTANE_CFG_LOC}" -o /tmp/cfg.butane
        BUTANE_CFG="/tmp/cfg.butane"
        if [ $? != 0 ] || [ ! -f "${BUTANE_CFG}" ]; then
            echo "Error: There was an error downloading the butane configuration file."
            exit 1
        fi
    else
        echo "Error: Missing or invalid butane configuration file source. Must be a full path to the butane configuration or an https link"
        exit 1
    fi
}

fetch_butane_bin() {
    # remove url stuff to get filename. doing this complicated stuff because
    # the filename could vary based on arch
    FEDORA_KEY="$(sed -r 's@.*(fedora\.gpg)@\1@' <<< ${FEDORA_KEY_URL})"
    BUTANE_BIN="$(sed -r 's@.*(butane-.*)@\1@' <<< ${COREOS_BUTANE_BIN_URL})"
    BUTANE_ASC="${BUTANE_BIN}.asc"

    FEDORA_KEY_FS_LOC="/tmp/${FEDORA_KEY}"
    BUTANE_BIN_FS_LOC="/tmp/${BUTANE_BIN}"
    BUTANE_ASC_FS_LOC="/tmp/${BUTANE_ASC}"

    curl --silent --output-dir /tmp -L --remote-name-all "${FEDORA_KEY_URL}" \
        "${COREOS_BUTANE_BIN_URL}" "${COREOS_BUTANE_ASC_URL}"
    if [ $? != 0 ] || \
    [ ! -f "${FEDORA_KEY_FS_LOC}" ] || \
    [ ! -f "${BUTANE_BIN_FS_LOC}" ] || \
    [ ! -f "${BUTANE_ASC_FS_LOC}" ]; then
        echo "Error: There was an error downloading butane tools."
        exit 1
    fi

    gpg --quiet --import "${FEDORA_KEY_FS_LOC}"
    gpg --verify "${BUTANE_ASC_FS_LOC}" "${BUTANE_BIN_FS_LOC}" 1>&2 2>/dev/null
    if [ $? != 0 ]; then
        echo "Error: Bad signature: ${BUTANE_BIN_FS_LOC}, ${BUTANE_ASC_FS_LOC}"
        exit 1
    fi
    chmod +x "${BUTANE_BIN_FS_LOC}"
}

find_wheel_user() {
    local i=0
    local current_line

    # make sure there actually is a wheel user defined
    grep -q "\- wheel" "${BUTANE_CFG}"
    if [ $? != 0 ]; then
        echo "Error: a wheel user is not defined in ${BUTANE_CFG}"
        exit 1
    fi

    while true
    do
        # walk backward until name directive is found
        current_line="$(grep -n -B$i '\- wheel' ${BUTANE_CFG} | head -n 1)"
        if [[ "${current_line}" == *"- name: "* ]]; then
            DEFINED_WHEEL_USER="$(sed -r 's/.*- name: //' <<< ${current_line})"
            DEFINED_WHEEL_USER_LN="$(cut -d '-' -f 1 <<< ${current_line})"
            break
        # we shouldnt ever come to this but this is to
        # prevent an infinite loop
        elif [ "${i}" == 500 ]; then
            echo "Error: name directive not found!"
            exit 1
        fi
        ((i++))
    done
}

find_wheel_user_pw_hash() {
    local i=0
    local current_line

    while true
    do
        # walk forward until password_hash directive is found
        current_line=$(grep -n -A$i "\- name: ${DEFINED_WHEEL_USER}" "${BUTANE_CFG}" | grep "password_hash: " | tail -n 1)
        if [[ "${current_line}" == *"password_hash: "* ]]; then
            # capture the line number, we'll give it to sed later
            DEFINED_WHEEL_USER_PW_HASH_LN="$(cut -d '-' -f 1 <<< ${current_line})"
            break
        elif [ "${i}" == 500 ]; then
            echo "Error: password_hash directive not found!"
            return 1
        fi
        ((i++))
    done
}

find_wheel_user_ssh_key() { 
    local i=0
    local current_line

    while true
    do
        # walk forward until ssh key is found
        current_line=$(grep -n -A$i "\- name: ${DEFINED_WHEEL_USER}" "${BUTANE_CFG}" | grep "\- ssh-" | tail -n 1)
        if [[ "${current_line}" == *"- ssh-"* ]]; then
            # capture the line number, we'll give it to sed later
            DEFINED_WHEEL_USER_SSH_KEY_LN="$(cut -d '-' -f 1 <<< ${current_line})"
            break
        elif [ "${i}" == 500 ]; then
            echo "Error: ssh key not found!"
            return 1
        fi
        ((i++))
    done
}

setup_new_admin_user() {
    if [[ "${ADMIN_USER}" != "${DEFINED_WHEEL_USER}" ]]; then
        sudo useradd -m -k /dev/null -s /bin/bash "${ADMIN_USER}"
        sed -ri "s@(- name: )${DEFINED_WHEEL_USER}@\1${ADMIN_USER}@" "${BUTANE_CFG}"
    else
        echo "Notice: The name you've chosen is already defined as the wheel user. Doing nothing."
    fi

    # check if DEFINED_WHEEL_USER even exists in /etc/shadow on the live DVD
    # usually people will choose 'core' in their butane configs
    # but we'll still check since the user has not indicated that they want
    # to use any other admin username
    sudo grep -qe ^"${DEFINED_WHEEL_USER}" /etc/shadow
    if [ $? != 0 ]; then
        sudo useradd -m -k /dev/null -s /bin/bash "${DEFINED_WHEEL_USER}"
    fi
}

setup_admin_password() {
    local user_password confirm_user_password

    while true
    do
        read -s -p 'Enter desired password: ' user_password
        echo
        read -s -p 'Confirm password: ' confirm_user_password
        echo
        if [ "${user_password}" != "${confirm_user_password}" ]; then
            echo "Passwords do not match"
            user_password=""
            confirm_user_password=""
        else
            break
        fi
    done

    # mkpasswd is not bundled in the live DVD, must use chpasswd unfortunately
    if [ ! -z "${ADMIN_USER}" ] && [ "${ADMIN_USER}" != "${DEFINED_WHEEL_USER}" ]; then
        echo "${ADMIN_USER}:${user_password}" | sudo chpasswd -s 11 -c YESCRYPT
        local new_hash="$(sudo grep -e ^${ADMIN_USER} /etc/shadow | cut -d : -f 2)"
        sed -i "${DEFINED_WHEEL_USER_PW_HASH_LN} s@password_hash: \$y\$.*@password_hash: ${new_hash}@" "${BUTANE_CFG}"
    else
        echo "${DEFINED_WHEEL_USER}:${user_password}" | sudo chpasswd -s 11 -c YESCRYPT
        local new_hash="$(sudo grep -e ^${DEFINED_WHEEL_USER} /etc/shadow | cut -d : -f 2)"
        sed -i "${DEFINED_WHEEL_USER_PW_HASH_LN} s@password_hash: \$y\$.*@password_hash: ${new_hash}@" "${BUTANE_CFG}"
    fi
}

setup_ssh_keys() {
    if [[ ${USER_SSH_KEY} != "ssh-"* ]]; then
        read -p 'Enter ssh public key (ssh-<alg> <key>): ' USER_SSH_KEY
        echo
    fi
    sed -ri "${DEFINED_WHEEL_USER_SSH_KEY_LN} s@(- )ssh-.*@\1${USER_SSH_KEY}@" "${BUTANE_CFG}"
}

edit_butane_cfg() {
    find_wheel_user
    find_wheel_user_pw_hash
    RET_FROM_fn_find_wheel_user_pw_hash="$?"
    find_wheel_user_ssh_key
    RET_FROM_fn_find_wheel_user_ssh_key="$?"

    # user wants to replace admin username
    if [ ! -z "${ADMIN_USER}" ]; then
        setup_new_admin_user
    fi

    # if a password is found for admin, we'll replace it
    if [ "${RET_FROM_fn_find_wheel_user_pw_hash}" == 0 ] && [ ! -z "${DEFINED_WHEEL_USER_PW_HASH_LN}" ]; then
        setup_admin_password
    fi

    # if an ssh key is found for admin, we'll replace it
    if [ "${RET_FROM_fn_find_wheel_user_ssh_key}" == 0 ] && [ ! -z "${DEFINED_WHEEL_USER_SSH_KEY_LN}" ]; then
        setup_ssh_keys
    fi
}

conv_butane_cfg() {
    "${BUTANE_BIN_FS_LOC}" --pretty "${BUTANE_CFG}" > /tmp/cfg.ign
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
