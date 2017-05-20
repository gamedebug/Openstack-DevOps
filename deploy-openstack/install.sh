#!/bin/bash
#author by keanlee on May 15th of 2017 

cd $(cd $(dirname $0); pwd)


README=$(cat ./README.txt)
echo $GREEN $README $NO_COLOR 
echo $GREEN This script will be deploy OpenStack on ${NO_COLOR}${YELLOW}$(cat /etc/redhat-release) $NO_COLOR

help(){
echo $MAGENTA --------Usage as below ---------  $NO_COLOR    
    echo  $BLUE sh $0 install controller $NO_COLOR  
    echo  $BLUE sh $0 install ha_proxy  $NO_COLOR
    echo  $BLUE sh $0 install compute   $NO_COLOR
 
}

if [[ $# = 0 || $# -gt 1 ]]; then 
help
exit 1
fi


#---------------keystone -----------
case $1 in
controller)
source ./bin/common.sh
mysql_configuration
source ./bin/keystone.sh
sleep 5
source ./bin/glance.sh
sleep 5
source ./bin/compute.sh controller  
;;
compute)
source ./bin/compute.sh compute
;;
*)
help
;;
esac




