#!/bin/bash

# ======================= WARNING =========================
# 
# This was tested on an freshly installed iRedMail server instance and standard LDAP server with a couple users.
# The script shouldn't require any heavy modifications, however slight modifications will be needed depending on the mail server specifications.
#
# ======================= USAGE ===========================

# A mail account script to sync mail accounts from main LDAP server.
#
# $ crontab -e 
# > [cron time interval] sync-mail-user.sh

# ======================= Settings ==========================

# Connection Details
LDAP_MAIN_ADDRESS=''
LDAP_MAIN_PORT=''
LDAP_MAIN_BIND_DN=''
LDAP_MAIN_BIND_PASSWORD=''
LDAP_MAIN_BASE_DN=''
LDAP_MAIN_FILTER=''
LDAP_MAIN_HOST=$LDAP_MAIN_ADDRESS:$LDAP_MAIN_PORT

LDAP_MAIL_ADDRESS=''
LDAP_MAIL_PORT=''
LDAP_MAIL_BIND_DN=''
LDAP_MAIL_BIND_PASSWORD=''
LDAP_MAIL_BASE_DN=''
LDAP_MAIL_FILTER=''
LDAP_MAIL_HOST=$LDAP_MAIL_ADDRESS:$LDAP_MAIL_PORT

# Account details
KEEP_ACCOUNT=TRUE
# IN BYTES
ACCOUNT_QUOTA=15106127360 # 15 GB
# Password Hash will be prioritized from decending order. 
# If the user doesn't have a hash matching the supported password hash, then the user will not be added. 
# For security purpose this script only supports hashes
SUPPORTED_PASSWORD_HASH=( 'SSHA512', 'BCRYPT', 'SSHA', 'CRYPT' )
IGNORE_ACCOUNTS=('postmaster@domainname.com')

## Add hooks like automatic email[SMTP email script] and automatic terminations after inactivity[attach a hook onto the log file] after these events occur
## Variables are passed in as $username, $email, $password_hash, $common_name
ON_ACCOUNT_ADD=''
ON_ACCOUNT_DEACTIVATE=''
ON_ACCOUNT_DELETE=''
ON_ACCOUNT_UPDATE=''

# Email Domain Details
# Domain Name | Examples: "marketing.example.com" & "support.example.com"
DOMAIN_NAMES=(  )
DOMAIN_NAME_MARKER="department"
DOMAIN_NAME_INDEXES=( )



# ====================== SCRIPT ======================


LDAP_MAIN_CRED="-x -H $LDAP_MAIN_HOST -D $LDAP_MAIN_BIND_DN -w $LDAP_MAIN_BIND_PASSWORD"
LDAP_MAIL_CRED="-x -H $LDAP_MAIL_HOST -D $LDAP_MAIL_BIND_DN -x -w $LDAP_MAIL_BIND_PASSWORD"

LDAP_MAIN_CRED_WBASE="$LDAP_MAIN_CRED -b $LDAP_MAIN_BASE_DN"
LDAP_MAIL_CRED_WBASE="$LDAP_MAIL_CRED -b $LDAP_MAIL_BASE_DN"

# Test connections
if [[ ! $(ldapwhoami -vvv $LDAP_MAIN_CRED) == *"0" ]]; 
  then exit 1
fi
if [[ ! $(ldapwhoami -vvv $LDAP_MAIL_CRED) == *"0" ]];
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

MAIL_USER_UIDS=$(ldapsearch $LDAP_MAIL_CRED_WBASE  | grep uid: | cut -c 6-) 

while read -r uid
do 
  # Handles account removal
  USER_LDIF=$(../function/getUserLDIF.sh $LDAP_MAIL_HOST $LDAP_MAIL_BASE_DN $LDAP_MAIL_BIND_DN \
    $LDAP_MAIL_BIND_PASSWORD $LDAP_MAIL_FILTER $uid)
  USER_DN=$( $USER_LDIF | grep dn: | sed -n '1p')
  if [[ ! $(../function/getUserLDIF.sh $LDAP_MAIN_HOST $LDAP_MAIN_BASE_DN $LDAP_MAIN_BIND_DN \
    $LDAP_MAIN_BIND_PASSWORD $LDAP_MAIN_FILTER $uid)  == *"uid:" ]]; 
  then
    if [[ $KEEP_ACCOUNT = true ]];
    # Deactivates account
    then ldapmodify $LDAP_MAIL_CRED << EOF
      dn: $USER_DN
      changeType: modify
      replace: accountStatus
      accountStatus: disabled
EOF
    # Delete account
    else ldapdelete $LDAP_MAIL_CRED "(uid=$uid)"
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
        ldapmodify $LDAP_MAIL_CRED << EOF
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
        
        ln -s $($USER_LDIF | grep homeDirectory: | sed "s/homeDirectory: //g") $HOME_DIR
        
        ldapmodify $LDAP_MAIL_CRED << EOF
          dn: $USER_DN
          changetype: modify
          replace: homeDirectory
          homeDirectory: $HOME_DIR
          replace: mailMessageStore
          mailMessageStore: $MAIL_MESSAGE_STORE
EOF
        ldapdelete $LDAP_MAIL_CRED "(mail=$uid@$DOMAIN_NAME)"
        break
      fi
    fi
  done

  # Verify that all the mail passwords matches properly. 
  MAIL_PASSWORD_HASH=../functions/getPasswordHash.sh $USER_LDIF $SUPPORTED_PASSWORD_HASH
  MAIN_PASSWORD_HASH=../functions/getPasswordHash.sh \
    $(../functions/getUserLDIF.sh $LDAP_MAIN_HOST $LDAP_MAIN_BASE_DN $LDAP_MAIN_BIND_DN $LDAP_MAIN_BIND_PASSWORD $LDAP_MAIN_FILTER $UID) $SUPPORTED_PASSWORD_HASH
  if [[ ! MAIL_PASSWORD_HASH = MAIN_PASSWORD_HASH ]]; then
    ldapmodify $LDAP_MAIL_CRED << EOF
      changetype: modify
      modify: userPassword
      userPassword: $MAIN_PASSWORD_HASH
EOF
  fi
  
done < $MAIL_USER_UIDS


# Find what is not matching on the main server and add those users
TEMP_ADD_FILE=$(mktemp)

USERS_TO_ADD='\n\n' read -ra array <<< $(ldapsearch $LDAP_MAIN_CRED_WBASE \
  "($LDAP_MAIN_FILTER(uid=*)!(|$($MAIL_USER_UIDS | sed '/s/^/(uid=/g' | sed '/s/$/)/g' | tr '\n' '')"); declare -p array;
unset USERS_TO_ADD[0]
for index in $USERS_TO_ADD; do
  USER_LDIF=$USERS_TO_ADD[index]
  USERNAME=$USER_LDIF | grep "uid:" | sed "s/uid: //g" | sed -n '1p'
  PASSWORD_HASH=../functions/getPasswordHash.sh $USER_LDIF $SUPPORTED_PASSWORD_HASH
  # Reverse for loop to set password based off priority
  COMMON_NAME=$USER_LDIF | grep "cn: " | sed "s/cn: //g" | sed -n '1p' 
  DOMAIN_NAME=$USER_LDIF | grep "mail:" # trim everything before @

  echo "\"$DOMAIN_NAME\", \"$USERNAME\, \"$PASSWORD_HASH\", \"$COMMON_NAME\",\"$ACCOUNT_QUOTA\"," >> $TEMP_ADD_FILE

  ./create-mail-users-ldap.py $TEMP_ADD_FILE
  
done

rm TEMP_ADD_FILE
