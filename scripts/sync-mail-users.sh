#!/bin/bash

# A mail account script to sync mail accounts from main LDAP server.
# This scripts requires configuration and slight modifications based off the mail server specifications.
# This was tested on an iRedMail server instance.

# Connection Details
LDAP_MAIN_ADDRESS=""
LDAP_MAIN_PORT=""
LDAP_MAIN_BIND_DN=""
LDAP_MAIN_BIND_PASSWORD=""
LDAP_MAIN_BASE_DN=""
LDAP_MAIN_FILTER=""
LDAP_MAIN_HOST=$LDAP_MAIN_ADDRESS:$LDAP_MAIN_PORT

LDAP_MAIL_ADDRESS=""
LDAP_MAIL_PORT=""
LDAP_MAIL_BIND_DN=""
LDAP_MAIL_BIND_PASSWORD=""
LDAP_MAIL_BASE_DN=""
LDAP_MAIL_FILTER=""
LDAP_MAIL_HOST=$LDAP_MAIL_ADDRESS:$LDAP_MAIL_PORT

# Account details
KEEP_ACCOUNT=TRUE
# IN BYTES
ACCOUNT_QUOTA=15106127360 # 15 GB
# Password Hash will be prioritized from decending order. 
# If the user doesn't have a hash matching the supported password hash, then the user will not be added. 
SUPPORTED_PASSWORD_HASH=( "SSHA512", "BCRYPT", "SSHA", "CRYPT" )
IGNORE_ACCOUNTS=("postmaster@domainname.com")

# Email Domain Details
# Domain Name | Examples: "marketing.example.com" & "support.example.com"
DOMAIN_NAMES=(  )
DOMAIN_NAME_MARKER="department"
DOMAIN_NAME_INDEXES=( )

# Initialization Sequence

# Test connections
if [[ ! $(ldapwhoami -vvv -H $LDAP_MAIN_HOST -D $LDAP_MAIN_BIND_DN -x -w $LDAP_MAIN_BIND_PASSWORD) == *"0" ]]; 
  then exit 1
fi
if [[ ! $(ldapwhoami -vvv -H $LDAP_MAIL_HOST -D $LDAP_MAIL_BIND_DN -x -w $LDAP_MAIL_BIND_PASSWORD) == *"0" ]];
  then exit 1
fi

# Make sures the domain name map is initalized properly
if [[ ! ${#DOMAIN_NAMES[@]} -eq ${#DOMAIN_NAMES_INDEX[@]} ]];
then
  echo "Please ensure that the domain name map has a correct amount of indexes"
  exit 1
fi

# Account Transfer Sequence

# Find what is not matching on the mail servers and delete/deactivate those

MAIL_USER_UIDS=$(ldapsearch -x -b $LDAP_MAIL_BASE_DN -H $LDAP_MAIL_HOST  \
  -D $LDAP_MAIL_BIND_DN -w $LDAP_MAIL_BIND_PASSWORD  | grep uid: | cut -c 6-) 

while read -r uid
do 
  # Handles account removal
  USER_LDIF=$(ldapsearch -x -b $LDAP_MAIL_BASE_DN -H $LDAP_MAIL_HOST \
      -D $LDAP_MAIL_BIND_DN -w $LDAP_MAIL_BIND_PASSWORD "(uid=$uid)")
  USER_DN=$( $USER_LDIF | grep dn: | sed -n '1p')
  if [[ ! $(ldapsearch -x -b $LDAP_MAIN_BASE_DN -H $LDAP_MAIN_HOST \
    -D $LDAP_MAIN_BIND_DN -w $LDAP_MAIN_BIND_PASSWORD "(uid=$uid)")  == *"uid:" ]]; 
  then
    if [[ $KEEP_ACCOUNT = true ]];
    # Deletes account
    then 
    # Replace the ldap query according to the mail server account specifications
    ldapmodify -x -b $LDAP_MAIL_BASE_DN -H $LDAP_MAIL_HOST -D $LDAP_MAIL_BIND_DN -x -w $LDAP_MAIL_BIND_PASSWORD << EOF
      dn: $USER_DN
      changeType: modify
      replace: accountStatus
      accountStatus: disabled
EOF
    # Deactivates account
    else ldapdelete -x -b $LDAP_MAIL_BASE_DN -H $LDAP_MAIL_HOST -D $LDAP_MAIL_BIND_DN -x -w $LDAP_MAIL_BIND_PASSWORD \
    "(uid=$uid)"
    fi 
  fi
  
  # Handles department transfer
  UID_DOMAIN_NAME_INDEX=$(ldapsearch)
  UID_DOMAIN_NAME=$(ldapsearch)
  for index in ${#DOMAIN_NAMES[@]}; do
    DOMAIN_NAME=${DOMAIN_NAMES[index]}
    DOMAIN_NAME_INDEX=${DOMAIN_NAME_INDEXES[index]}
    if [[ $UID_DOMAIN_NAME_INDEX = $DOMAIN_NAME_INDEX ]]; 
    then 
      # Begins transfer
      if [[ ! $UID_DOMAIN_NAME = $DOMAIN_NAME ]];
      then
        # Moves the account
        USER_RDN="mail=$uid@$DOMAIN_NAME"
        SUPERIOR="ou=Users,domainName=$DOMAIN_NAME,$LDAP_MAIL_BASE_DN"
        ldapmodify -x -b $LDAP_MAIL_BASE_DN -H $LDAP_MAIL_HOST -D $LDAP_MAIL_BIND_DN -x -w $LDAP_MAIL_BIND_PASSWORD << EOF
          dn: $USER_DN
          changetype: modrdn
          newrdn: $USER_RDN
          deleteoldrdn: 0
          newsuperior: $SUPERIOR
EOF
        USER_DN=$USER_RDN,$SUPERIOR
        # Section used to replace attributes pretaining to mail file storage location
        HOME_DIR=${$($USER_LDIF | grep homeDirectory: | cut -c -13)/$UID_DOMAIN_NAME/$DOMAIN_NAME}
        MAIL_MESSAGE_STORE=${$($USER_LDIF | grep mailMessageStore: | cut -c -13)/$UID_DOMAIN_NAME/$DOMAIN_NAME}
        
        # TODO: MOVE
        
        ldapmodify -x -b $LDAP_MAIL_BASE_DN -H $LDAP_MAIL_HOST -D $LDAP_MAIL_BIND_DN -x -w $LDAP_MAIL_BIND_PASSWORD << EOF
          dn: $USER_DN
          changetype: modify
          replace: homeDirectory
          homeDirectory: $HOME_DIR
          replace: mailMessageStore
          mailMessageStore: $MAIL_MESSAGE_STORE
EOF
        ldapdelete -x -b $LDAP_MAIL_BASE_DN -H $LDAP_MAIL_HOST \
          -D $LDAP_MAIL_BIND_BIND -x -w $LDAP_MAIL_BIND_PASSWORD "(mail=$uid@$DOMAIN_NAME)"
      fi
    fi
  done
done < $MAIL_USER_UIDS


    

# Find what is not matching on the main server and add those users

USERS_TO_ADD='\n\n' read -ra array <<< $(ldapsearch "((uid=*)!(|$($MAIL_USER_UIDS | sed '/s/^/(uid=/g' | sed '/s/$/)/g' | tr '\n' '')"); declare -p array;
unset USERS_TO_ADD[0]
for index in $USERS_TO_ADD; do
  USER_LDIF=$USERS_TO_ADD[index]
  USERNAME=$USER_LDIF | grep "uid:" | sed "s/uid: //g" | sed -n '1p'
  PASSWORD_HASH=$USER_LDIF | grep "userPassword" | sed "s/userPassword: //g"
  # Reverse for loop to set password based off priority
  COMMON_NAME=$USER_LDIF | grep "cn: " | sed "s/cn: //g" | sed -n '1p' 

  # Uses add script.
done




# Verify that all the mail passwords matches properly. 
