#!/bin/bash

VERSION="1.0"
INSTALL_DIR="/install_hana"
INSTALL_SOURCE="/backup/HANA2"
REV="56"
SCRIPTSERVER="YES"
BASHPATH=$(realpath $(dirname "${0}"))

spinner()
{
    local pid=$1
    local delay=0.5
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf "[%c]" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b"
    done
    #printf "    \b\b\b\b"
    #echo ""
}

echo -e "HANA Install Script Ver. ${VERSION}\n"

command -v mount.cifs >/dev/null 2>&1 || { echo >&2 "CIFS Utils are required but not installed. Aborting."; exit 1; }

if [ ! "${1}" ] || [ ! "${2}" ] || [ ! "${3}" ] || [ ! "${4}" ] || [ ! "${5}" ]; then
	echo -e "Some parameters have not being specified. Please use StorageBox username and password followed by HANA parameters:\n"
	echo -e "install_hana.sh uXXXXXX password SID 00 hostname\n"
	exit 99
	
fi

if [ ! -d "${INSTALL_DIR}" ]; then
	mkdir -p "${INSTALL_DIR}"
fi

if grep -qs "${INSTALL_DIR}" /proc/mounts; then
	echo -e "StorageBox install source already mounted..."
else
	echo -e "Mounting StorageBox install source..."
	mount.cifs //"${1}".your-storagebox.de"${INSTALL_SOURCE}" "${INSTALL_DIR}" -o user="${1}",pass="${2}"
fi

echo -e "Using HANA 2.0 Rev.${REV}"
echo -e "Downloading template..."
wget -L https://raw.githubusercontent.com/christophercarrasco/install_hana/main/template_"${REV}".rsp -O /tmp/template.rsp >/dev/null 2>&1
echo -e "Generating passwords for installation..."
SAPADM_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
SYSTEM_USER_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
echo -e "Changing directory to install source path..."
cd "${INSTALL_DIR}"/Rev."${REV}"/DATA_UNITS/SAP\ HANA\ DATABASE\ 2.0\ FOR\ B1/LINX64SUSE/SAP_HANA_DATABASE/
echo -e "Executing HDBLCM. This can take a while on remote StorageBoxes..."
echo -ne "Installing => "
./hdblcm -b --sid="${3}" --number="${4}" --hostname="${5}" --component_root="${INSTALL_DIR}"/Rev."${REV}" --configfile=/tmp/template.rsp --sapadm_password="${SAPADM_PASSWORD}" --password="${PASSWORD}" --system_user_password="${SYSTEM_USER_PASSWORD}" >"${BASHPATH}"/install_hana.trc &
#sleep 1s &
spinner $!

echo -ne "Done\n"
cd /tmp
rm template.rsp

echo -e "Unmounting StorageBox install source..."
umount "${INSTALL_DIR}"
rmdir "${INSTALL_DIR}"

if [ "${SCRIPTSERVER}" == "YES" ]; then
	echo -e "Enabling 'scriptserver' for database ${3}..."
	su - "${3,,}adm" -c "hdbsql -u SYSTEM -d SYSTEMDB -p ${SYSTEM_USER_PASSWORD} \"ALTER DATABASE ${SID} ADD 'scriptserver';\"" >/dev/null 2>&1
fi

OUTPUT="
System ID:\t\t\t\t${3}
Instance Number:\t\t\t${4}
Hostname:\t\t\t\t${5}
SAP Host Agent User (sapadm) Password:\t${SAPADM_PASSWORD}
System Administrator (${3,,}adm) Password:\t${PASSWORD}
Database User (SYSTEM) Password:\t${SYSTEM_USER_PASSWORD}
"

echo -e "${OUTPUT}" >"${BASHPATH}"/install_hana.log

echo -e "\n----------------------------------------------------------"
echo -e "Installation done with the following details:"
echo -e "${OUTPUT}"
echo -e "----------------------------------------------------------\n"