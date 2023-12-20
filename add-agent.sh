#!/bin/bash
##############################################set these parameters####################
export opsmxIsdUrl=

export VAULT_ADDR=
export VAULT_TOKEN=
export VAULT_MOUNT=
export VAULT_PATH_ISD=

###################################
export existPath='/gate/platformservice/v7/argo/doesExist?argoName='
export downloadPath='/gate/oes/argo/agents/'

#################################################### vault commands here##############################

vault login -method=token token=$VAULT_TOKEN > /dev/null
           if [ $? -ne '0' ]; then 
           echo ERROR: could not connect to vault
           exit 1
          fi 

export ISDuser=$(vault kv get -field username $VAULT_MOUNT/$VAULT_PATH_ISD/username)
           if [ $? -ne '0' ]; then 
           echo ERROR: could not get ISDuser
           exit 1
          fi

export ISDpassword=$(vault kv get -field password $VAULT_MOUNT/$VAULT_PATH_ISD/password)
           if [ $? -ne '0' ]; then 
           echo ERROR: could not get ISDpassword
           exit 1
          fi 

#############################################LOOP OVER ARGOCDS ##########################
rm  -rf errorlist.txt 
while read argo
do

argocdName=$(echo $argo | awk '{print $1}')
argocdNS=$(echo $argo | awk '{print $2}')
argocdURL=$(echo $argo | awk '{print $3}')
argocdDesc=$(echo $argo | awk '{print $4}')

echo working with $argocdName in namespace $argocdNS with URL $argocdURL and description $argocdDesc
echo checking if agent with name $argocdName exists

httpCode=$( curl -s -u "$ISDuser":"$ISDpassword" -o output.json -w "%{http_code}" --cookie-jar ./cookie -X GET "$opsmxIsdUrl""$existPath""$argocdName" )
echo $httpCode is return code of the curl get command
           if [ $httpCode != "200" ]; then 
           echo ERROR: could not add agent to ISD for $argocdName 
           echo ERROR: could not add agent to ISD for $argocdName >> errorlist.txt 
           cat output.json >> errorlist.txt
          continue
          fi 

#echo 
exists=$(cat output.json | jq -r .argoNameExist)
#echo $exists

if [ "$exists" == "true" ]; then 
           echo $argocdName was already added
          cat output.json
          echo
          continue
else
echo adding $argocdName as agent

url="$opsmxIsdUrl""$downloadPath""${argocdName}"/manifest?isExists=true'&namespace='"${argocdNS}"'&description='"$argocdDesc"'&argoCdUrl='"$argocdURL"'&rolloutsEnabled=false&isdUrl='"${opsmxIsdUrl}"
echo $url is the url
httpCode=$( curl -s --cookie ./cookie -o manifest.yml -w "%{http_code}" $url )
echo $httpCode is return code of the curl get manifest command
           if [ $httpCode != "200" ]; then 
           echo ERROR could not get manifest for $argocdName 
           echo ERROR could not get manifest for $argocdName >> errorlist.txt 
           cat manifest.yml >> errorlist.txt
           echo 
           echo >> errorlist.txt 
          continue
          fi 

authtoken=$( cat manifest.yml  | grep authtoken: | awk '{print $2}' | base64 -d )
caCert=$( cat manifest.yml  | grep caCert64 | awk '{print $2}' )
echo CACert certificate is
echo $caCert
echo

fi 
#################################################### get argocd creds ##############################

argocduser=$(vault kv get -field username $VAULT_MOUNT/$argocdName/username)
           if [ $? -ne '0' ]; then 
           echo ERROR: could not get argocduser for $argocdName
           echo ERROR: could not get argocduser for $argocdName >> errorlist.txt
           break
          fi 
argocdpassword=$(vault kv get -field password $VAULT_MOUNT/$argocdName/password)
           if [ $? -ne '0' ]; then 
           echo ERROR: could not get argocdpassword for $argocdName
           echo ERROR: could not get argocdpassword for $argocdName >> errorlist.txt
           break
          fi 

#################################################### get argocd token ##############################

justURL=$(echo $argocdURL | sed 's@https://@@')
argocd login $justURL --username=$argocduser --password=$argocdpassword --grpc-web
           if [ $? -ne '0' ]; then 
           echo ERROR: could not login to argocd $argocdURL , check if username and password are correct
           echo >> errorlist.txt
           echo ERROR: could not login to argocd $argocdURL , check if username and password are correct >> errorlist.txt
          break
          fi 
argocdtoken=$(argocd account generate-token | base64  -w0)
           if [ $? -ne '0' ]; then 
           echo ERROR: could not generate token for $argocdURL , check if apiKey in argocd-cm configmap is enabled for $argocduser
           echo >> errorlist.txt
           echo ERROR: could not generate token for $argocdURL , check if apiKey in argocd-cm configmap is enabled for $argocduser >> errorlist.txt
          break
          fi 

#################################################### create vault secrets ##############################
sed -e "s@ARGOCDNAME@$argocdName@g" -e "s@TOKEN@$argocdtoken@g" -e "s@ARGOCDURL@$argocdURL@g" services.tmpl > services.yaml
export VAULT_PATH=$argocdName
vault kv put $VAULT_MOUNT/$VAULT_PATH/opsmx-profile cdIntegration="true" sourceName="$argocdName" opsmxIsdUrl="$opsmxIsdUrl" user="admin"
vault kv put $VAULT_MOUNT/$VAULT_PATH/services.yaml services.yaml=@services.yaml 
rm -rf services.yaml manifest.yml output.json
vault kv put $VAULT_MOUNT/$VAULT_PATH/opsmx-agent-"$argocdName"-auth authtoken=$authtoken
echo
echo
echo
echo
done < argocdlist.txt
echo successfully added secrets to vault check errorlist.txt for any errors.
