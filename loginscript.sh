#!/bin/bash
############################################## Set These Parameters ####################
export opsmxIsdUrl=https://isdargolikha5.devtcb.opsmx.org 
export K8S_NAMESPACE=isdupg
export K8S_SECRET_NAME=multiargo

###################################
export existPath='/gate/platformservice/v7/argo/doesExist?argoName='
export downloadPath='/gate/oes/argo/agents/'

############################################# Get Kubernetes Secrets ##########################
# Retrieve the username and password from the Kubernetes secret

export ISDuser=$(kubectl get secret $K8S_SECRET_NAME -n $K8S_NAMESPACE -o jsonpath='{.data.username}' | base64 --decode)
if [ $? -ne '0' ]; then 
    echo "ERROR: could not get ISDuser"
    exit 1
fi

export ISDpassword=$(kubectl get secret $K8S_SECRET_NAME -n $K8S_NAMESPACE -o jsonpath='{.data.password}' | base64 --decode)
if [ $? -ne '0' ]; then 
    echo "ERROR: could not get ISDpassword"
    exit 1
fi

############################################# Authenticate and Get Session ID ##########################
#sessionValue=$(curl -v -s -X POST "${opsmxIsdUrl}/gate/login" --data "username=${ISDuser}&password=${ISDpassword}" | grep -Fi "set-cookie" | cut -d'=' -f2 | cut -d';' -f1)
sessionValue=$(curl -i -X POST "https://isdargolikha5.devtcb.opsmx.org/gate/login" --data "username=$user1&password=Welcome@123" | grep -Fi "set-cookie" | cut -d'=' -f2 | cut -d';' -f1)

if [ -z "$sessionValue" ]; then
    echo "ERROR: Authentication failed, no session ID received"
    exit 1
fi
echo $sessionValue
############################################# LOOP OVER ARGOCDS ##########################
rm -rf errorlist.txt 
while read argo
do

argocdName=$(echo $argo | awk '{print $1}')
argocdNS=$(echo $argo | awk '{print $2}')
argocdURL=$(echo $argo | awk '{print $3}')
argocdDesc=$(echo $argo | awk '{print $4}')

echo working with $argocdName in namespace $argocdNS with URL $argocdURL and description $argocdDesc
echo checking if agent with name $argocdName exists

# Use session ID to check if agent exists
#httpCode=$(curl -s -o output.json -w "%{http_code}" --header "Cookie: SESSION=${sessionValue}" "${opsmxIsdUrl}${existPath}${argocdName}")
httpCode=$(curl -s -L -o output.json -w "%{http_code}" --header "Cookie: SESSION=${sessionValue}" "${opsmxIsdUrl}${existPath}${argocdName}") 
# -L in curl command to redirect automatically

echo $httpCode is the return code of the curl GET command
if [ $httpCode != "200" ]; then 
    echo "ERROR: could not add agent to ISD for $argocdName"
    echo "ERROR: could not add agent to ISD for $argocdName" >> errorlist.txt 
    cat output.json >> errorlist.txt
    continue
fi 
cat output.json
exists=$(cat output.json | jq -r .argoNameExist)

echo $exists
if [ "$exists" == "true" ]; then 
    echo "$argocdName was already added"
    cat output.json
    echo
    continue
else
    echo "adding $argocdName as agent"

    url="$opsmxIsdUrl""$downloadPath""${argocdName}"/manifest?isExists=true'&namespace='"${argocdNS}"'&description='"$argocdDesc"'&argoCdUrl='"$argocdURL"'&rolloutsEnabled=false&isdUrl='"${opsmxIsdUrl}"
    echo "$url is the url"
    httpCode=$( curl -L -s --header "Cookie: SESSION=${sessionValue}" -o manifest.yml -w "%{http_code}" "$url" )
    echo "$httpCode is return code of the curl GET manifest command"
    if [ $httpCode != "200" ]; then 
        echo "ERROR could not get manifest for $argocdName"
        echo "ERROR could not get manifest for $argocdName" >> errorlist.txt 
        cat manifest.yml >> errorlist.txt
        echo 
        echo >> errorlist.txt 
        continue
    fi 

    authtoken=$(grep authtoken: manifest.yml | awk '{print $2}' | base64 -d)
    caCert=$(grep caCert64 manifest.yml | awk '{print $2}')
    echo "CACert certificate is"
    echo $caCert
    echo

fi 
echo $argocdName
kubectl get secret $argocdName -n $argocdNS -o jsonpath='{.data.username}' | base64 --decode
#################################################### Get ArgoCD Creds ##############################
argocduser=$(kubectl get secret $argocdName -n $argocdNS -o jsonpath='{.data.username}' | base64 --decode)
if [ $? -ne '0' ]; then 
    echo "ERROR: could not get argocduser for $argocdName"
    echo "ERROR: could not get argocduser for $argocdName" >> errorlist.txt
    continue
fi 
argocdpassword=$(kubectl get secret $argocdName -n $argocdNS -o jsonpath='{.data.password}' | base64 --decode)
if [ $? -ne '0' ]; then 
    echo "ERROR: could not get argocdpassword for $argocdName"
    echo "ERROR: could not get argocdpassword for $argocdName" >> errorlist.txt
    continue
fi 

#################################################### Get ArgoCD Token ##############################
justURL=$(echo $argocdURL | sed 's@https://@@')
argocd login $justURL --username=$argocduser --password=$argocdpassword --grpc-web
if [ $? -ne '0' ]; then 
    echo "ERROR: could not login to argocd $argocdURL, check if username and password are correct"
    echo >> errorlist.txt
    echo "ERROR: could not login to argocd $argocdURL, check if username and password are correct" >> errorlist.txt
    continue
fi 
argocdtoken=$(argocd account generate-token | base64 -w0)
if [ $? -ne '0' ]; then 
    echo "ERROR: could not generate token for $argocdURL, check if apiKey in argocd-cm configmap is enabled for $argocduser"
    echo >> errorlist.txt
    echo "ERROR: could not generate token for $argocdURL, check if apiKey in argocd-cm configmap is enabled for $argocduser" >> errorlist.txt
    continue
fi 

#################################################### Create K8s Secrets ##############################
cat manifest.yml
rm -rf services.yaml manifest.yml output.json
echo
echo
echo
echo
done < argocdlist.txt
if test -f errorlist.txt ; then   echo "Errors exist, check the file errorlist.txt"; exit 1; fi
echo "Successfully added secrets to Kubernetes."
