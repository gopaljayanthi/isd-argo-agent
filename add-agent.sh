#!/bin/bash

export opsmxIsdUrl="https://dev.tcb.opsmx.net"

export existPath='/gate/platformservice/v7/argo/doesExist?argoName='
export downloadPath='/gate/oes/argo/agents/'

export VAULT_MOUNT=''

#################################################### use vault kv get commands here##############################

export ISDuser=""
export ISDpassword=""
#############################################LOOP OVER ARGOCDS ##########################
rm -rf errorlist.txt 
while read argo
do
#echo working with $argo
argocdName=$(echo $argo | awk '{print $1}')
#echo working with $argocdName
argocdNS=$(echo $argo | awk '{print $2}')
argocdURL=$(echo $argo | awk '{print $3}')
argocdDesc=$(echo $argo | awk '{print $4}')
echo working with $argocdName in namespace $argocdNS with URL $argocdURL and description $argocdDesc
echo
echo checking if agent with name $argocdName exists
echo

httpCode=$( curl -s -u "$ISDuser":"$ISDpassword" -o output.json -w "%{http_code}" --cookie-jar ./cookie -X GET "$opsmxIsdUrl""$existPath""$argocdName" )
echo $httpCode is return code of the curl get command
           if [ $httpCode != "200" ]; then 
           echo ERROR could not add agent to ISD for $argocdName 
           echo ERROR could not add agent to ISD for $argocdName >> errorlist.txt 
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

authtoken=$( cat manifest.yml  | grep authtoken: | awk '{print $2}' )
#################################################### use vault kv get/put commands here##############################
#echo authtoken=$authtoken
fi 

argocduser=$(vault kv get ...........)
argocdpassword=$(vault kv get .......)

argocd login $argocdhostingressurl --username=$argocduser --password=$argocdpassword --grpc-web
argocdtoken=$(argocd account generate-token | base64  -w0)

sed -e "s@ARGOCDNAME@$argocdName@g" -e "s@TOKEN@$argocdtoken@g" -e "s@ARGOCDURL@$argocdURL@g" services.tmpl > services.yaml
export VAULT_PATH=$argocdName
vault kv put $VAULT_MOUNT/$VAULT_PATH/opsmx-profile cdIntegration="true" sourceName="$argocdName" opsmxIsdUrl="$opsmxIsdUrl" user="admin"
vault kv put $VAULT_MOUNT/$VAULT_PATH/services.yaml services.yaml=@services.yaml 
rm -rf services.yaml manifest.yaml output.json
vault kv put $VAULT_MOUNT/$VAULT_PATH/opsmx-agent-"$argocdName"-auth authtoken=$authtoken
echo
echo
echo
#break
done < argocdlist.txt
echo successfully added secrets to vault check errorlit.txt for any errors.
