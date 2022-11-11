#!/bin/bash
set -e

success=false
trap check_finish EXIT
check_finish() {
  if [ $success = true ]; then
    echo '>>>' success
  else
    echo "FAILED"
  fi
}

show_help() {
  cat << 'EOF'
./apply.sh [-?] [-h] [-d] [-p] (start | : ) | (end | : )
apply or destroy the resources in this example by steping into each of the terraform directories in a predfined order
-? - this message
-h - this message
-p - just print the directories that would be visited do not do anything
-d - destroy the resources in the reverse order of the apply.  Default is to apply in each directory.
     Parameters[end] and [start end] are still with respect to ascending order.

dir - apply in one directory
start | : - start directory or : to start at the beginning
end | : - end directory or : to end at the end

Examples:
./apply.sh : :;# create all resources
./apply.sh spokes_tf ;# terraform in spokes_tf
./apply.sh spokes_tf : ;# terraform in each directory in order stop after spokes_tf is executed
./apply.sh : spokes_tf ;# terraform start in first directory and stop after spokes_tf is executed
./apply.sh transit_tf spokes_tf ;# terraform in each directory in order start at transit_tf and stop after spokes_tf is executed
./apply.sh -d ;# delete all resources
./apply.sh -d : spokes_tf ;# terraform delete beginning in the spokes_tf and work backwards towards the first directory
./apply.sh -p;# show the order of apply but do not apply, same as ./apply.sh -p : :
./apply.sh -d -p : spokes_tf ;# show the order of delete by to not delete
./apply.sh -d -p;# show the order of deletion
EOF

}

all="config_tf enterprise_tf transit_tf spokes_tf test_instances_tf transit_spoke_tgw_tf enterprise_link_tf firewall_tf spokes_egress_tf all_firewall_tf all_firewall_asym_tf dns_tf vpe_transit_tf vpe_spokes_tf vpe_dns_forwarding_rules_tf"
just_print=false
apply=true

#OPTIND=1
while getopts "h?cdp" opt; do
  case "$opt" in
    h|\?)
      show_help
      exit 0
      ;;
    p)  
      just_print=true
      ;;
    d)  
      apply=false
      ;;
  esac
done
shift $((OPTIND-1))

# handle [end] or [start end]
case $# in
  0)
    if [ $just_print = true ]; then
      tf="$all"
    else
      show_help
      success=true
      exit 0
    fi
    ;;
  1) tf=$1;;
  2)
    start=$1
    stop=$2
    if [ $start = ":" ]; then
      start=$(expr "$all" : '\([^ ]*\).*')
    fi
    if [ $stop = ":" ]; then
      stop=$(expr "$all" : '.* \([^ ]*\)')
    fi
    tf=$(expr " $all " : '.*\( '"$start"' .*\)')
    tf=$(expr " $tf " : '\( .* '"$stop"'\)')
    ;;
  *) echo starting_point; exit 0;;
esac

# destroy in reverse order
if [ $apply = false ]; then
  tf=$(echo "$tf" | awk '{ for (i=NF; i>1; i--) printf("%s ",$i); print $1; }')
fi

echo directories: $tf

# print and exit if requested
if [ $just_print = true ]; then
  success=true
  exit 0
fi

for dir in $tf; do
  (
    cd $dir
    echo '>>>' "creating resources with terraform in the $dir/ directory"
    # bug https://jiracloud.swg.usma.ibm.com:8443/browse/VPN-576
    case $dir in
      enterprise_link_tf) parallelism_n=1;;
      *) parallelism_n=10;;
    esac
    
    echo '>>>' terraform init
    terraform init
    if [ $apply = true ]; then
      echo '>>>' terraform apply -parallelism=$parallelism_n -auto-approve
      terraform apply -parallelism=$parallelism_n -auto-approve
    else
      echo '>>>' terraform destroy -parallelism=$parallelism_n -auto-approve
      terraform destroy -parallelism=$parallelism_n -auto-approve
    fi
  )
done

success=true
