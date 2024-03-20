#!/bin/bash -x

backupGatewayPackage=$1
companyAuthCode=$2
install_disk_size=$3
ddb_disk_size=$4

echo "Running configuration scripts..."
sudo setenforce 0
sudo sed -i 's/SELINUX=enforcing/SELINUX=permissive/gI' /etc/selinux/config
sudo systemctl stop firewalld.service
sudo systemctl disable firewalld.service
sleep 30

date
lsblk

ddb_disk_name=$(lsblk -o NAME,SIZE | grep $ddb_disk_size | awk '{print $1}')
echo "DDB disk name: $ddb_disk_name"
install_disk_name=$(lsblk -o NAME,SIZE | grep $install_disk_size | awk '{print $1}')
echo "Install disk name: $install_disk_name"

echo "Check and wait for device /dev/$ddb_disk_name"
while [ ! -d /sys/block/$ddb_disk_name ]; do sleep 5; done
echo "Check and wait for device /dev/$install_disk_name"
while [ ! -d /sys/block/$install_disk_name ]; do sleep 5; done
echo "Wait for /dev/$ddb_disk_name running state"
while [ "running" != "$(cat /sys/block/$ddb_disk_name/device/state)" ]; do sleep 5; done
echo "Wait for /dev/$install_disk_name running state"
while [ "running" != "$(cat /sys/block/$install_disk_name/device/state)" ]; do sleep 5; done
date

data_size=$(($install_disk_size-15))G
ddb_size=$((ddb_disk_size - ddb_disk_size / 10))G

pvcreate /dev/$ddb_disk_name
pvcreate /dev/$install_disk_name
vgcreate  vg_metallic /dev/$install_disk_name
vgcreate  vg_metallic_2 /dev/$ddb_disk_name
lvcreate -n lv_install -L 10G vg_metallic
lvcreate -n lv_log -L 4.9G vg_metallic
lvcreate -n lv_data -L $data_size vg_metallic
lvcreate -n lv_ddb -L $ddb_size vg_metallic_2
mkdir /opt/metallic
mkdir /var/log/metallic
mkdir /var/opt/metallic_data
mkdir /var/opt/metallic_ddb
mkfs -t xfs /dev/vg_metallic/lv_install
mkfs -t xfs /dev/vg_metallic/lv_log
mkfs -t xfs /dev/vg_metallic/lv_data
mkfs -t xfs /dev/vg_metallic_2/lv_ddb
mount /dev/vg_metallic/lv_install /opt/metallic
mount /dev/vg_metallic/lv_log /var/log/metallic
mount /dev/vg_metallic/lv_data /var/opt/metallic_data
mount /dev/vg_metallic_2/lv_ddb /var/opt/metallic_ddb
echo "/dev/vg_metallic/lv_install /opt/metallic xfs defaults,nofail 0 0" | tee -a /etc/fstab
echo "/dev/vg_metallic/lv_log /var/log/metallic xfs defaults,nofail 0 0" | tee -a /etc/fstab
echo "/dev/vg_metallic/lv_data /var/opt/metallic_data xfs defaults,nofail 0 0" | tee -a /etc/fstab
echo "/dev/vg_metallic_2/lv_ddb /var/opt/metallic_ddb xfs defaults,nofail 0 0" | tee -a /etc/fstab

mkdir /tmp/metallicPkg
cd /tmp/metallicPkg
wget ${backupGatewayPackage} -q
tar -xf LinuxCloudBackupGateway64.tar

localHostname=$(curl -s -H "Metadata: true" "http://169.254.169.254/metadata/instance/compute/name?api-version=2017-08-01&format=text")
instanceid=$(curl -s -H "Metadata: true" "http://169.254.169.254/metadata/instance/compute/vmId?api-version=2017-08-01&format=text")
clientname=$localHostname-$instanceid
/tmp/metallicPkg/LinuxCloudBackupGateway64/pkg/silent_install -clientname $clientname -clienthost $localHostname -authcode ${companyAuthCode}

rm -rf /tmp/metallicPkg

mkdir /tmp/mono
cd /tmp/mono
tar xfz /opt/metallic/Base/mono.tgz
tar xfz mono/rhel8/mono-core.tgz
yum -y localinstall /tmp/mono/mono-core/*.rpm
rm -rf /tmp/mono

# chmod 0777 AzueLinuxDeploy.sh && sudo dos2unix AzueLinuxDeploy.sh && sudo ./AzueLinuxDeploy.sh "https://sredownloadcenter.blob.core.windows.net/m050/LinuxCloudBackupGateway64.tar" "3113FC08F">> logfile.txt 2>&1
