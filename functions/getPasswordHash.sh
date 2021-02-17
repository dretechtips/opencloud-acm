#!/bin/bash


USER_LDIF=$1
SUPPORTED_PASSWORD_HASH=$2 # PASSWORD HASHES in descending priority

$USER_LDIF | grep "userPassword" | sed "s/userPassword: //g"


