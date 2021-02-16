#!/bin/bash

# This scripts adds basic account sync functionalitity to mail servers that uses an LDAP backend.


LDAP_MAIN_ADDRESS=""
LDAP_MAIN_PORT=""
LDAP_MAIN_BIND_DN=""
LDAP_MAIN_BIND_PASSWORD=""
LDAP_MAIN_BASE_DN=""
LDAP_MAIN_FILTER=""

LDAP_MAIL_ADDRESS=""
LDAP_MAIL_PORT=""
LDAP_MAIL_BIND_DN=""
LDAP_MAIL_BIND_PASSWORD=""
LDAP_MAIL_BASE_DN=""
LDAP_MAIL_FILTER=""

# Test connections
if [[ ! $(ldapwhoami -vvv -H $LDAP_MAIN_ADDRESS:$LDAP_MAIN_PORT -D $LDAP_MAIN_BIND_DN -x -w $LDAP_MAIN_BIND_PASSWORD) == *"0" ]]; 
  then exit 1;
if [[ ! $(ldapwhoami -vvv -H $LDAP_MAIL_ADDRESS:$LDAP_MAIL_PORT -D $LDAP_MAIL_BIND_DN -x -w $LDAP_MAIL_BIND_PASSWORD) == *"0"]]; 
  then exit 1;

# Find what is not matching on the mail servers and delete/deactivate those

MAIL_USERS_UIDS=$(ldapsearch -x -b $LDAP_MAIL_BASE_DN -H $LDAP_MAIL_ADDRESS:$LDAP_MAIL_PORT  \
  -D $LDAP_MAIL_BIND_DN -w $LDAP_MAIL_BIND_PASSWORD  | grep uid: | cut -c 6-) 

while read -r uid
do 
  if [[ ! $(ldapsearch -x -b $LDAP_MAIN_BASE_DN -H $LDAP_MAIN_ADDRESS:$LDAP_MAIN_PORT \
    -D $LDAP_MAIL_BIND_DN -w $LDAP_MAIN_BIND_PASSWORD) "(uid=$uid)" == *"uid:" ]]; 
  then ldapdelete -x -b $LDAP_MAIL_C
done < $MAIL_USERS_UIDS
  

# Find what is not matching on the main server and add those users
ADD_USERS=$(ldapsearch)
