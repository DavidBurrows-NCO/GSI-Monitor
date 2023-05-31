#!/bin/bash

#---------------------------------------------------------
#  rstprod.sh
#
#  Restrict data from select sensors and satellites 
#---------------------------------------------------------

# Restrict select sensors and satellites
echo "--> rstprod.sh"

export CHGRP_CMD=${CHGRP_CMD:-"chgrp ${group_name:-rstprod}"}
rlist="saphir abi_g16"

for rtype in $rlist; do
    if compgen -G "*${rtype}*" > /dev/null; then
        echo "RSTPROD IN ACTION for ${rtype}!"
        ${CHGRP_CMD} *${rtype}*
    fi

done

echo "<-- rstprod.sh"
