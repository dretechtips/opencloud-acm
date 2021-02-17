#!/bin/bash

HOST=$1
BASE_DN=$2
BIND_DN=$3
BIND_PASSWORD=$4
USER_FILTER=$5
UID=$6

LDIFS=$(ldapsearch -x -b $BASE_DN -H $HOST  \
  -D $BIND_DN -w $BIND_PASSWORD "&$USER_FILTER(uid=$UID)" |  )

echo LDIFS[1]