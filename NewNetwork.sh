#!/bin/bash

help() {
    echo -e "Usage:\n\n"
    echo "$0 <nome_progetto> [ INFN | UNIPD | CEDC ]"
    echo -e "\n    Crea una (sotto)rete per il <progetto>\n"
    echo "OPPURE"
    echo
    echo "$0 <nome_progetto> FIP [ INFN | UNIPD ]"
    echo -e "\n    Crea una \"wan\" per agganciare un Floating IP\n"
    exit 0
}

echo
projectname=$1
affiliation=$2
suffix="lan"
if [ "x$2" = "xFIP" ] ; then
    affiliation=$3
    suffix="wan"
fi

#Check Input
if [ "x$projectname" = "x" ] ; then
    help
fi
if [ "x$affiliation" = "x" ] ; then
    help
fi

source /root/keystone_admin-kilo.sh || ( echo "!!! Non trovo le credenziali per admin" && exit ) 

tenant_id=( $(openstack project list | egrep " ${projectname} " | cut -d'|' -f2) )
if [ "x$tenant_id" = "x" ];
then
   echo "!!! Non riconosco il progetto: $projectname"
   echo
   echo "    Forse non e' stato ancora creato?"
   echo
   exit -1
fi


case "$affiliation" in
 "INFN")  if [ "$suffix" = "lan" ] ; then
              net_pool="10.66." 
              router="router-infn"
          else
              net_pool="10.65."
              router="router01"
          fi
          dns1="192.84.143.16"
          dns2="192.84.143.31"
          dns3="192.84.143.224" 
          ;;
"UNIPD")  net_pool="10.67."
          router="router02"
          dns1="147.162.1.2"
          dns2="8.8.8.8"
          dns3="8.8.4.4" 
          ;;
 "CEDC")  net_pool="10.68."
          router="router03"
          dns1="147.162.1.2"
          dns2="8.8.8.8"
          dns3="8.8.4.4" 
          ;;
      *)  echo "???"; exit -1
esac 

# trova l'ultima network allocata
# La soluzione non e' elegante ma e' sicuramente la piu' veloce:
# creo 2 file temporanei e popolo la lista delle reti gia' occupate
# con neutron subnet-list, poi ciclo sul contenuto di questo file
# e tolgo da tutte le possibili reti (secondo file) quelle gia'
# occupate. In questo modo riesco a gestire 'buchi' nella serie
# delle reti occupate in maniera piuttosto veloce.
taken_nets=`mktemp`
allnets=`mktemp`

echo -n "Cerco le sottoreti gia' allocate... "

neutron subnet-list | grep "$net_pool" | awk '{print $6}' | sed "s/$net_pool//;s/.0\/24//" | sort -n > $taken_nets
for i in `seq 2 254`
do
   echo $i >> $allnets
done

echo "fatto."
red='\e[31;1m'
nocol='\e[0m'
echo
echo -e "Reti gia' allocate: $red"
echo

count=1
while read i
do
   sed -i /^${i}$/d $allnets
   printf "%3i " $i
   (( count += 1 ))
   [ `expr $count % 10` -eq 0 ] && echo
done < $taken_nets
echo -e $nocol
echo

net=`head -1 $allnets`

rm -f $allnets  $taken_nets

echo -e "Verra' assegnata la rete privata: $net_pool${red}$net${nocol}.0/24"
echo
echo -n "Procedo con la creazione (Y/n)? "
read ans
if [ x$ans = "x" ] ; then
    ans="Y"
fi
if [ $ans != "Y" ] ; then
    if [ $ans != "y" ] ; then
        echo "Creazione annullata."
        exit -2
    fi
fi

# set -x

   net_name=${projectname}-${affiliation}-$suffix
subnet_name=sub-${net_name}

echo "Creo la rete $net_name"
neutron net-create --tenant-id $tenant_id $net_name

echo "    Creo la sottorete $subnet_name  ==  ${net_pool}$net.0"
neutron subnet-create $net_name ${net_pool}$net.0/24 --enable-dhcp=True --name $subnet_name --tenant-id $tenant_id --dns-nameserver $dns1 --dns-nameserver $dns2 --dns-nameserver $dns3

echo "    Collego la sottorete $subnet_name al router $router"
neutron router-interface-add $router $subnet_name

echo
echo "Aggiungo admin come 'admin' del progetto"
openstack role add --project $tenant_id --user admin admin

echo "    Aggiungo SSH al security group di default per il progetto"
openstack --os-project-id $tenant_id security group rule create --proto tcp --src-ip ${net_pool}0.0/16 --dst-port 22 default

echo "    Abilito risposta al ping per il security group di default per il progetto"
openstack --os-project-id $tenant_id security group rule create --proto icmp --dst-port -1 default

echo "Tolgo admin come 'admin' del progetto"
openstack role remove --project $tenant_id --user admin admin

# set +x
echo
exit 0
