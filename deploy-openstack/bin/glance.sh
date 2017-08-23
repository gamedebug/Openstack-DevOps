#!/bin/bash 
#This script can help you to deploy glance of openstack

#The OpenStack Image service is central to Infrastructure-as-a-Service (IaaS) as shown in Conceptual architecture. 
#It accepts API requests for disk or server images, and metadata definitions from end users or OpenStack Compute components. 
#It also supports the storage of disk or server images on various repository types, including OpenStack Object Storage

#----------------Dependency----------------------
#       VARIABLE    and  common.sh


function glance_main(){
#this function need variable:  GLANCE_DBPASS, GLANCE_PASS

database_create glance $GLANCE_DBPASS
create_service_credentials $GLANCE_PASS glance

echo $BLUE Install openstack-glance ... $NO_COLOR
yum install openstack-glance -y  1>/dev/null
    debug "$?" "Install openstack-glance failed "

echo $BLUE copy glance-api.conf and edit it $NO_COLOR
cp -f  ./etc/controller/glance-api.conf  /etc/glance/
#change all controller as MGMT ip
sed -i "s/controller/$MGMT_IP/g"  /etc/glance/glance-api.conf
sed -i "s/GLANCE_DBPASS/$GLANCE_DBPASS/g"  /etc/glance/glance-api.conf
#change the glance password for keystone 
sed -i "s/GLANCE_PASS/$GLANCE_PASS/g"  /etc/glance/glance-api.conf
sed -i "s/RABBIT_HOSTS/$RABBIT_HOSTS/g"  /etc/glance/glance-api.conf
sed -i "s/RABBIT_PASSWORD/$RABBIT_PASS/g"  /etc/glance/glance-api.conf

echo $BLUE copy glance-registry.conf and edit it $NO_COLOR
cp -f ./etc/controller/glance-registry.conf  /etc/glance/
sed -i "s/GLANCE_DBPASS/$GLANCE_DBPASS/g"  /etc/glance/glance-registry.conf
sed -i "s/controller/$MGMT_IP/g"  /etc/glance/glance-registry.conf
sed -i "s/RABBIT_HOSTS/$RABBIT_HOSTS/g"  /etc/glance/glance-registry.conf
sed -i "s/RABBIT_PASSWORD/$RABBIT_PASS/g"   /etc/glance/glance-registry.conf
sed -i "s/GLANCE_PASS/$GLANCE_PASS/g"   /etc/glance/glance-registry.conf

#if [[ $(get_database_size glance ${GLANCE_DBPASS} | awk '{print $6}') != "NULL" ]];then
#    echo $YELLOW Skip populate glance database, since it\'s has populated   $NO_COLOR
#else
    echo $BLUE Populate the Image service database $NO_COLOR
    su -s /bin/sh -c "glance-manage db_sync" glance  1>/dev/null 2>&1
        get_database_size glance $GLANCE_DBPASS
        debug "$?" "Populate the Image service database Failed,\
execute su -s /bin/sh -c \"glance-manage db_sync\" glance or check glance.api log "
echo $GREEN Ignore the above  any deprecation messages in this output $NO_COLOR 
#fi

#Start the Image services and configure them to start when the system boots
systemctl enable openstack-glance-api.service openstack-glance-registry.service  1>/dev/null 2>&1
systemctl start openstack-glance-api.service openstack-glance-registry.service
    debug "$?"  "Start daemon openstack-glance-api openstack-glance-registry failed,Maybe you should check the conf file "
}

function verify_glance(){
cat 2>&1 <<__EOF__
$MAGENTA===================================================================
      Verify operation of the Image service using CirrOS, 
  a small Linux image that helps you test your OpenStack deployment
===================================================================
$NO_COLOR
__EOF__

source $OPENRC_DIR/admin-openrc
#wget http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img   &&
#glance image-create --name cirros --file /tmp/cirros-0.3.4-x86_64-disk.img --disk-format qcow2 --container-format bare --progress
echo $BLUE Upload the image to the Image service using the QCOW2 disk format,\
bare container format, and public visibility so all projects can access it $NO_COLOR
sleep 5
openstack image create "cirros" \
--file ./lib/cirros-0.3.4-x86_64-disk.img \
--disk-format qcow2 --container-format bare \
--public
    debug "$?" "Upload image to glance failed"

if [[  $(openstack image list | grep cirros | wc -l) -ge 1 ]];then
    echo $GREEN Upload image cirros Success $NO_COLOR
else
    debug "1" " Upload image cirros to glance Failed"
fi

}

cat 2>&1 <<__EOF__
$MAGENTA=================================================================
     Begin to deploy glance on ${YELLOW}$(hostname)${NO_COLOR}${MAGENTA} 
=================================================================
$NO_COLOR
__EOF__

glance_main
source $OPENRC_DIR/admin-openrc

if [[ $(openstack image list | grep cirros | wc -l) -ge 1 ]];then 
    echo $YELLOW Skip to verify glance $NO_COLOR
else
    verify_glance
fi

cat 2>&1 <<__EOF__
$GREEN===================================================================================

     Congratulation you finished the ${YELLOW}Glance${NO_COLOR} ${GREEN}component install 

===================================================================================
$NO_COLOR
__EOF__

