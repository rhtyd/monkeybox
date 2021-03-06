#!/bin/bash
# Recipe to deploy an advanced zone
# By Rohit Yadav <rohit@scaleninja.com>
set -e
set -x

cli=cloudmonkey
dns_ext=8.8.8.8
dns_int=192.168.1.1
gw=192.168.1.1
nmask=255.255.0.0
hpvr=KVM
pod_start=192.168.51.10
pod_end=192.168.51.250
vlan_start=192.168.50.10
vlan_end=192.168.50.250

#Put space separated host ips in following
host_ips="192.168.3.100 192.168.3.65"
host_user=root
host_passwd=password
sec_storage='nfs://192.168.1.11/export/testing/secondary-master'
prm_storage='nfs://192.168.1.11/export/testing/primary-master'
local_storage=true

$cli set profile local
$cli set username admin
$cli set password password
$cli set display default
$cli set asyncblock true

zone_id=`$cli create zone dns1=$dns_ext internaldns1=$dns_int localstorageenabled=$local_storage name=MyZone networktype=Advanced securitygroupenabled=true | grep ^id\ = | awk '{print $3}'`
echo "Created zone" $zone_id

phy_id=`$cli create physicalnetwork name=phy-network zoneid=$zone_id isolationmethods=VLAN | grep ^id\ = | awk '{print $3}'`
echo "Created physical network" $phy_id
$cli add traffictype traffictype=Management physicalnetworkid=$phy_id
echo "Added mgmt traffic"
$cli add traffictype traffictype=Public physicalnetworkid=$phy_id
echo "Added mgmt traffic"
$cli add traffictype traffictype=Guest physicalnetworkid=$phy_id
echo "Added guest traffic"

$cli update physicalnetwork state=Enabled id=$phy_id
echo "Enabled physicalnetwork"

nsp_id=`$cli list networkserviceproviders name=VirtualRouter physicalnetworkid=$phy_id | grep ^id\ = | awk '{print $3}'`
vre_id=`$cli list virtualrouterelements nspid=$nsp_id | grep ^id\ = | awk '{print $3}'`
$cli configure virtualrouterelement enabled=true id=$vre_id
$cli update networkserviceprovider state=Enabled id=$nsp_id
echo "Enabled virtual router element and network service provider"

nsp_id=`$cli list networkserviceproviders name=Internallbvm physicalnetworkid=$phy_id | grep ^id\ = | awk '{print $3}'`
ilbvm_id=`$cli list internalloadbalancerelements nspid=$nsp_id | grep ^id\ = | awk '{print $3}'`
$cli configure internalloadbalancerelement enabled=true id=$ilbvm_id
$cli update networkserviceprovider state=Enabled id=$nsp_id
echo "Enabled Internal LBVM and NSP"

nsp_id=`$cli list networkserviceproviders name=VpcVirtualRouter physicalnetworkid=$phy_id | grep ^id\ = | awk '{print $3}'`
vpcvr_id=`$cli list virtualrouterelements nspid=$nsp_id | grep ^id\ = | awk '{print $3}'`
$cli configure virtualrouterelement enabled=true id=$vpcvr_id
$cli update networkserviceprovider state=Enabled id=$nsp_id
echo "Enabled VPC VR and NSP"

pod_id=`$cli create pod name=MyPod zoneid=$zone_id gateway=$gw netmask=$nmask startip=$pod_start endip=$pod_end | grep ^id\ = | awk '{print $3}'`
echo "Created pod"

$cli create vlaniprange zoneid=$zone_id vlan=untagged gateway=$gw netmask=$nmask startip=$vlan_start endip=$vlan_end forvirtualnetwork=true
echo "Created IP ranges for instances"

$cli update physicalnetwork vlan=700-900 id=$phy_id
echo "Update physical network"

cluster_id=`$cli add cluster zoneid=$zone_id hypervisor=$hpvr clustertype=CloudManaged podid=$pod_id clustername=MyCluster | grep ^id\ = | awk '{print $3}'`
echo "Created cluster" $cluster_id

#Put loop here if more than one
for host_ip in $host_ips;
do
  $cli add host zoneid=$zone_id podid=$pod_id clusterid=$cluster_id hypervisor=$hpvr clustertype=CloudManaged username=$host_user password=$host_passwd url=http://$host_ip;
  echo "Added host" $host_ip;
done;

$cli create storagepool zoneid=$zone_id podid=$pod_id clusterid=$cluster_id name=MyNFSPrimary hypervisor=$hpvr scope=zone url=$prm_storage
echo "Added primary storage"

$cli add imagestore name=MyNFSSecondary provider=NFS zoneid=$zone_id url=$sec_storage
echo "Added secondary storage"

# general global settings
$cli update zone allocationstate=Enabled id=$zone_id
echo "Basic zone deloyment completed!"
