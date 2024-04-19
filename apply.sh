#!/bin/bash
set -e

terraform=terraform

success=unknown
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
./apply.sh [-?] [-h] [-d] [-s] [-p] [-u] [-f no] (start | : ) | (end | : )
apply or destroy the resources in this example by steping into each of the terraform directories in a predfined order
-? - this message
-h - this message
-p - just print the directories that would be visited do not do anything
-d - destroy the resources in the reverse order of the apply.  Default is to apply in each directory.
     Parameters[end] and [start end] are still with respect to ascending order.  Destroy will not exit on failure.
-s - stop on destroy failure, the default is to continue
-u - just upgrade terraform and plugins to a new version, do not apply or destroy any resources
-n - no auto approve on terraform apply commands.  User must type yes at every terraform prompt - there are a lot
-r - reset terraform by removing the terraform state files in each layer.  This is very dangerous - all resources will be divorced from terraform and require manual deletion.

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

all="config_tf enterprise_tf transit_tf spokes_tf transit_spoke_tgw_tf test_instances_tf test_lbs_tf enterprise_link_tf firewall_tf transit_ingress_tf spokes_egress_tf all_firewall_tf all_firewall_asym_tf dns_tf vpe_transit_tf vpe_spokes_tf power_tf"
just_print=false
apply=true
stop_on_destroy_failure=false
terraform_upgrade=false
terraform_auto_approve="-auto-approve"
remove_state_files="false"

#OPTIND=1
while getopts "h?cdspunr" opt; do
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
    s)  
      stop_on_destroy_failure=false
      ;;
    u)  
      terraform_upgrade=true
      ;;
    n)  
      terraform_auto_approve=""
      ;;
    r)  
      remove_state_files="true"
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
if [ $apply = true ]; then
  opt=creating
else
  opt=desroying
  tf=$(echo "$tf" | awk '{ for (i=NF; i>1; i--) printf("%s ",$i); print $1; }')
fi
if [ $remove_state_files = true ]; then
  opt=removing_state_files
fi

echo directories: $tf

# print and exit if requested
if [ $just_print = true ]; then
  success=true
  exit 0
fi

if [ $terraform_upgrade = true ]; then
  terraform_upgrade_option="-upgrade"
else
  terraform_upgrade_option=""
fi


for dir in $tf; do
  (
    cd $dir
    echo '>>>' "$opt resources with $terraform in the $dir/ directory"
    if [ $opt = removing_state_files ]; then
      rm -f terraform.tfstate terraform.tfstate.backup
      continue
    fi
    # bug https://jiracloud.swg.usma.ibm.com:8443/browse/VPN-576
    case $dir in
      enterprise_link_tf|power_tf) parallelism_n=1;;
      *) parallelism_n=10;;
    esac
    
    echo '>>>' $terraform init $terraform_upgrade_option
    $terraform init $terraform_upgrade_option
    if [ $terraform_upgrade = false ]; then
      if [ $apply = true ]; then
        echo '>>>' $terraform apply -parallelism=$parallelism_n $terraform_auto_approve
        $terraform apply -parallelism=$parallelism_n $terraform_auto_approve
      else
        echo '>>>' $terraform destroy -parallelism=$parallelism_n $terraform_auto_approve
        if ! $terraform destroy -parallelism=$parallelism_n $terraform_auto_approve; then
          success=false
          echo '**************************************************'
          echo destroy failed
          echo '**************************************************'
          if [ $stop_on_destroy_failure = true ]; then
            false
          fi
        fi
      fi
    fi
  )
done

if [ $success == unknown ]; then
  success=true
fi
