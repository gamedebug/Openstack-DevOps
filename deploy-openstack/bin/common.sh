#!/bin/bash 
#This script will prepare the env for install openstack 
#Include function ntp mysql rabbitmq memcache  

# ansi colors for formatting heredoc
ESC=$(printf "\e")
GREEN="$ESC[0;32m"
NO_COLOR="$ESC[0;0m"
RED="$ESC[0;31m"
MAGENTA="$ESC[0;35m"
YELLOW="$ESC[0;33m"
BLUE="$ESC[0;34m"
WHITE="$ESC[0;37m"
#PURPLE="$ESC[0;35m"
CYAN="$ESC[0;36m"

source ./bin/VARIABLE  

function debug(){
if [[ $1 -ne 0 ]]; then 
    echo $RED ERROR:  $2 $NO_COLOR
    exit 1
fi
}



#-----------------------------yum repos configuration ---------------------------
function yum_repos(){
if [[ ! -d /etc/yum.repos.d/bak/ ]];then
    mkdir /etc/yum.repos.d/bak/
fi
mv /etc/yum.repos.d/* /etc/yum.repos.d/bak/  1>/dev/null 2>&1
cp -f ./repos/* /etc/yum.repos.d/ 2>/dev/null 
yum clean all 1>/dev/null 2>1&
echo $GREEN yum repos configuration done $NO_COLOR
}

#---------------------------initialize env ------------------------------------
function initialize_env(){
#----------------disable selinux-------------------------
cat 2>&1 <<__EOF__
$MAGENTA==========================================================
            Begin to initialize env ...
==========================================================
$NO_COLOR
__EOF__

if [[ $(cat /etc/selinux/config | sed -n '7p' | awk -F "=" '{print $2}') = "enforcing" ]];then 
     echo $BLUE Disable selinux $NO_COLOR
     sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
     echo $GREEN Disable the selinux by config file $NO_COLOR
fi    

if [[ $(getenforce) = "Enforcing" ]];then
    setenforce 0 
    echo $GREEN The current selinux Status:$NO_COLOR $YELLOW $(getenforce) $NO_COLOR 
fi

systemctl status NetworkManager 1>/dev/null 2>&1
if [[ $? = 0 ]];then
    echo $BLUE Uninstall NetworkManager $NO_COLOR
    systemctl stop NetworkManager 1>/dev/null 2>&1
    yum erase NetworkManager  -y 1>/dev/null 2>&1
fi

which firewall-cmd  1>/dev/null 2>&1 &&
echo $BLUE Uninstall firewalld $NO_COLOR
yum erase firewalld* -y 1>/dev/null 2>&1
}


function common_packages(){
echo $BLUE Install openstack-selinux and  python-openstackclient ...$NO_COLOR
#RHEL and CentOS enable SELinux by default. Install the openstack-selinux package to automatically manage security policies for OpenStack services
yum install openstack-selinux python-openstackclient -y 1>/dev/null
    debug "$?" "$RED Install openstack-selinux python-openstackclient failed $NO_COLOR"

}


#--------------------------------------ntp server --------------------------------
function ntp(){
cat 2>&1 <<__EOF__
$MAGENTA==========================================================
            Begin to delpoy ntp
==========================================================
$NO_COLOR
__EOF__
echo $BLUE Install ntp ... $NO_COLOR
yum install ntp -y  1>/dev/null
    debug "$?" "Install ntp failed, please check your yum repos"
cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
hwclock --systohc
if [[ $1 = "server" ]];then 
    cp -f ./etc/ntp.conf  /etc
    sed -i "s/NTP-SERVER-IP/$NTP_SERVER_IP/g" /etc/ntp.conf
    sed -i "s/IP-ADDR/$ALLOW_IP_RANGES/g" /etc/ntp.conf
    sed -i "s/NETMASK-ADDR/$ALLOW_IP_NETMASK/g" /etc/ntp.conf
    ntpdate ntp1.aliyun.com 1>/dev/null
else 
    sed -i "/server 0.centos.pool.ntp.org iburst/d" /etc/ntp.conf
    sed -i "/server 1.centos.pool.ntp.org iburst/d" /etc/ntp.conf
    sed -i "/server 2.centos.pool.ntp.org iburst/d" /etc/ntp.conf
    sed -i "/server 3.centos.pool.ntp.org iburst/d" /etc/ntp.conf
    sed -i "21 i server $NTP_SERVER_IP iburst " /etc/ntp.conf
    ntpdate $NTP_SERVER_IP 1>/dev/null
fi

systemctl enable ntpd.service 1>/dev/null 2>&1 && 
systemctl start ntpd.service
    debug "$?" "start ntpd.service failed "
}

#-----------------------------DNS server ----------------------------------
function dns_server(){
echo > ./resolve.conf
    cat > ./resolve.conf <<EOF
#Create this file by keanlee's script
nameserver      $DNS_SERVER 
EOF
mv -f ./resolve.conf /etc
}

#----------------------------------------mariadb install ------------------------------------------------
function mysql_configuration(){
#change password if forgot mysql password
cat 2>&1 <<__EOF__
$MAGENTA==========================================================
            Begin to delpoy Mariadb
==========================================================
$NO_COLOR
__EOF__

echo $BLUE Beginning configuration mysql for controller node on $YELLOW $(hostname) $NO_COLOR
# set the bind-address key to the management IP address of the controller node to enable access by other nodes via the management network
# refer https://docs.openstack.org/newton/install-guide-rdo/environment-sql-database.html
yum install mariadb mariadb-server python2-PyMySQL -y 1>/dev/null 
    debug "$1" "$RED Install mariadb mariadb-server python2-PyMySQL failed $NO_COLOR"   
echo > /etc/my.cnf.d/openstack.cnf
    cat > /etc/my.cnf.d/openstack.cnf <<EOF
[mysqld]
bind-address = $MGMT_IP
default-storage-engine = innodb
innodb_file_per_table
max_connections=4096
collation-server = utf8_general_ci
character-set-server = utf8
init-connect = 'SET NAMES utf8'
EOF
systemctl enable mariadb.service 1>/dev/null 2>&1 && 
systemctl start mariadb.service
sed -i '/Group=mysql/a\LimitNOFILE=65535' /usr/lib/systemd/system/mariadb.service
systemctl daemon-reload
systemctl restart mariadb.service

echo $BLUE Set admin password for mariadb... $NO_COLOR
mysql_secure_installation 1>/dev/null 2>&1 <<EOF

y
$MARIADB_PASSWORD
$MARIADB_PASSWORD
y
y
y
y
EOF

    debug "$?" "Mysql configuration failed"
echo $GREEN Finished the Mariadb install and configuration on $YELLOW $(hostname) $NO_COLOR 
}


#------------------------------------------Database size -----------------------------
function get_database_size(){
#$1 as the database name 
#$2 as the database password 
#For example get_database_size nova novadb
if [[ $# != 2 ]];then
    echo $RED This function need to two parameter $NO_COLOR
exit 1
fi

if [[ $1 = nova_api ]];then
    DB_SIZE=$(mysql -unova -p$2 -e "show databases;use information_schema;\
select concat(round(sum(DATA_LENGTH/1024/1024),2),'MB') as data from TABLES where table_schema='nova_api';" )
else
    DB_SIZE=$(mysql -u$1 -p$2 -e "show databases;use information_schema;\
select concat(round(sum(DATA_LENGTH/1024/1024),2),'MB') as data from TABLES where table_schema='$1';" )
fi

if [[ $1 = nova || $1 = nova_api  ]];then
    local NUMS=6
else
    local NUMS=5
fi

echo -n $BLUE The database $YELLOW${1}${BLUE} size is: $NO_COLOR 
echo $DB_SIZE  | awk  '{print $'$NUMS'}' 
}



#-------------------------------------database create function --------------------------
function database_create(){
#create database and user in mariadb for openstack component
#$1 is the database name (comonent name and usename) 
#$2 is password of database
DATABASE_NAME=$(mysql -uroot -p$MARIADB_PASSWORD -e "show databases" | grep $1 | wc -l)
if [[ ${DATABASE_NAME} -ge 1 ]];then 
    echo $YELLOW The database $1 exists, so skip create database $1 $NO_COLOR
else
    echo $BLUE Create $YELLOW$1$BLUE database in mariadb  $NO_COLOR
    local USER=$1
        if [[ $1 = nova_api ]];then
            USER=nova
        fi 

    mysql -uroot -p$MARIADB_PASSWORD -e "CREATE DATABASE $1;GRANT ALL PRIVILEGES ON $1.* TO '$USER'@'localhost' \
IDENTIFIED BY '$2';GRANT ALL PRIVILEGES ON $1.* TO '$USER'@'%'  IDENTIFIED BY '$2';flush privileges;"  
        debug "$?" "Create database $1 Failed "
fi
}


#-------------------------------rabbitmq install ----------------------------------------------
function rabbitmq_configuration(){
cat 2>&1 <<__EOF__
$MAGENTA==========================================================
            Begin to delpoy RabbitMQ 
==========================================================
$NO_COLOR
__EOF__

#RABBIT_P 
#Except Horizone and keystone ,each component need connect to Rabbitmq 
echo $BLUE Install rabbitmq-server ... $NO_COLOR
yum install rabbitmq-server  -y 1>/dev/null
    debug "$1" "$RED Install rabbitmq-server failed $NO_COLOR"
systemctl enable rabbitmq-server.service 1>/dev/null 2>&1 && 

if [[ $(cat /etc/hosts | grep $(hostname) | wc -l) -ge 1 ]];then 
    echo $YELLOW Skip to add host name with ip addr to hosts file $NO_COLOR
else
    echo "${MGMT_IP} $(hostname)" >>/etc/hosts
fi 

systemctl start rabbitmq-server.service
    debug "$?" "Start rabbitmq-server.service Faild, Did you edit the /etc/hosts correct ? "

if [[ ${MGMT_IP} != ${CONTROLLER_IP[0]} ]];then
    echo $BLUE Rabbitmq cluster deploy ... $NO_COLOR
    scp root@${CONTROLLER_IP[0]}:/var/lib/rabbitmq/.erlang.cookie  /var/lib/rabbitmq/   1>/dev/null  &&
    chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie
    chmod 400 /var/lib/rabbitmq/.erlang.cookie   &&
    systemctl restart rabbitmq-server.service
    rabbitmqctl stop_app   1>/dev/null  &&
    rabbitmqctl join_cluster rabbit@${CONTROLLER_HOSTNAME[0]}  1>/dev/null  &&
    rabbitmqctl start_app  1>/dev/null
    if [[ ${MGMT_IP} = ${CONTROLLER_IP[2]} ]];then 
        echo $BLUE Check the rabbitmq cluster status: $NO_COLOR
        rabbitmqctl cluster_status
    fi
else
    rabbitmqctl add_user openstack $RABBIT_PASS  1>/dev/null
    echo $BLUE Permit configuration, write, and read access for the openstack user ...$NO_COLOR
    rabbitmqctl set_permissions openstack ".*" ".*" ".*"  1>/dev/null
fi

sed -i '/Group=rabbitmq/a\LimitNOFILE=10240' /usr/lib/systemd/system/rabbitmq-server.service
systemctl daemon-reload
#rabbitmq-plugins list
#enable rabbitmq_management boot after the os boot 
#Use rabbitmq-web 
rabbitmq-plugins enable rabbitmq_management 1>/dev/null 2>&1
systemctl restart rabbitmq-server.service &&
    debug "$?" "Restart rabbitmq-server.service fail after enable rabbitmq_management "
echo $GREEN You can browse rabbitmq web via 15672 port $NO_COLOR
}



#-------------------------------memcache install ----------------------------------------------
function memcache(){
#install and configuration memecache 
#Need variable MGMT_IP
#The Identity service authentication mechanism for services uses Memcached to cache tokens. 
#The memcached service typically runs on the controller node. 
#For production deployments, we recommend enabling a combination of firewalling, authentication, and encryption to secure it.
echo $BLUE Install memcached python-memcached ... $NO_COLOR 
yum install memcached python-memcached -y 1>/dev/null
sed -i "s/127.0.0.1/$MGMT_IP/g" /etc/sysconfig/memcached
systemctl enable memcached.service   1>/dev/null 2>&1 &&
systemctl start memcached.service
    debug "$?"  "Start memcached.service failed "
}

#----------------------------create_service_credentials----------------------
function create_service_credentials(){
#This function need parameter :
#$1 is the service password 
#$2 is the service name ,example nova glance neutron cinder etc. 
#
cat 2>&1 <<__EOF__
$MAGENTA==========================================================
          Create $2 service credentials 
==========================================================
$NO_COLOR
__EOF__
#${#CONTROLLER_IP[@]} -eq 3

if [[ ${MGMT_IP} != ${CONTROLLER_IP[0]} ]];then 
    echo $YELLOW Skip to create the service credentials $NO_COLOR
else 
    echo $BLUE To create the service credentials, complete these steps: $NO_COLOR 
    source $OPENRC_DIR/admin-openrc
    echo $BLUE create the service credentials: $NO_COLOR
    echo $BLUE Create the $2  user  $NO_COLOR
    openstack user create --domain default --password $1  $2  &&

    echo $BLUE Add the admin role to the $2 user and service project $NO_COLOR
    openstack role add --project service --user $2 admin

    echo $BLUE Create the $2 service entity $NO_COLOR
    case $2 in
    glance)
        local SERVICE=Image
        local SERVICE1=image
        local PORTS=9292
        ;;
    nova)
        local SERVICE=Compute
        local SERVICE1=compute
        local PORTS=8774
        ;;
    neutron)
        local SERVICE=Networking
        local SERVICE1=network 
        local PORTS=9696
        ;;
    cinder)
        local SERVICE=Block Storage
        local PORTS=8776
        local SERVICE1=volume
        ;;
    *)
        debug "1" "The second parameter is the service name:nova glance neutron cinder etc,your $2 is unkown "
        ;;
    esac 
    sleep 2
    openstack service create --name $2 --description "OpenStack ${SERVICE}" ${SERVICE1}
        debug "$?" "openstack service $2 create failed "

    if [[ $2 = cinder ]];then 
        openstack service create --name cinderv2 --description "OpenStack ${SERVICE}" volumev2
            debug "$?" "openstack service volumev2 create failed " 
    fi

    echo $BLUE Create the ${YELLOW}$SERVICE${NO_COLOR}${BLUE} service API endpoints $NO_COLOR

    if [[ $2 = nova ]];then 
        openstack endpoint create --region RegionOne ${SERVICE1} public http://$MGMT_IP:${PORTS}/v2.1/%\(tenant_id\)s
        openstack endpoint create --region RegionOne ${SERVICE1} internal http://$MGMT_IP:${PORTS}/v2.1/%\(tenant_id\)s
        openstack endpoint create --region RegionOne ${SERVICE1} admin http://$MGMT_IP:${PORTS}/v2.1/%\(tenant_id\)s
            debug "$?" "openstack endpoint create $2 failed "

    elif [[ $2 = cinder ]];then
        openstack endpoint create --region RegionOne ${SERVICE1} public http://$MGMT_IP:${PORTS}/v1/%\(tenant_id\)s
        openstack endpoint create --region RegionOne ${SERVICE1} internal http://$MGMT_IP:${PORTS}/v1/%\(tenant_id\)s
        openstack endpoint create --region RegionOne ${SERVICE1} admin http://$MGMT_IP:${PORTS}/v1/%\(tenant_id\)s
            debug "$?" "openstack endpoint create $2 failed "

        openstack endpoint create --region RegionOne volumev2 public http://$MGMT_IP:${PORTS}/v2/%\(tenant_id\)s
        openstack endpoint create --region RegionOne volumev2 internal http://$MGMT_IP:${PORTS}/v2/%\(tenant_id\)s
        openstack endpoint create --region RegionOne volumev2 admin http://$MGMT_IP:${PORTS}/v2/%\(tenant_id\)s
            debug "$?" "openstack endpoint create $2 failed "

    else 
        openstack endpoint create --region RegionOne ${SERVICE1} public http://$MGMT_IP:${PORTS}
        openstack endpoint create --region RegionOne ${SERVICE1} internal http://$MGMT_IP:${PORTS}
        openstack endpoint create --region RegionOne ${SERVICE1} admin http://$MGMT_IP:${PORTS}
            debug "$?" "openstack endpoint create $2 failed "
    fi 
    echo $GREEN openstack ${YELLOW}$2${GREEN} endpoint create success $NO_COLOR 
fi
}

