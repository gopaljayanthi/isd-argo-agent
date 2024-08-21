#!/bin/bash
##############################################set these parameters####################
export opsmxIsdUrl=

export K8S_NAMESPACE=
export K8S_SECRET_NAME=

###################################
#export existPath='/gate/platformservice/v7/argo/doesExist?argoName='
#export downloadPath='/gate/oes/argo/agents/'

#if using gate url comment two lines above and uncomment two lines below

export existPath='/platformservice/v7/argo/doesExist?argoName='
export downloadPath='/oes/argo/agents/'

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

#############################################LOOP OVER ARGOCDS ##########################
rm -rf errorlist.txt 
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
    echo "ERROR: could not add agent to ISD for $argocdName"
    echo "ERROR: could not add agent to ISD for $argocdName" >> errorlist.txt 
    cat output.json >> errorlist.txt
    continue
fi 

exists=$(cat output.json | jq -r .argoNameExist)

if [ "$exists" == "true" ]; then 
    echo "$argocdName was already added"
    cat output.json
    echo
    continue
else
    echo "adding $argocdName as agent"

    url="$opsmxIsdUrl""$downloadPath""${argocdName}"/manifest?isExists=true'&namespace='"${argocdNS}"'&description='"$argocdDesc"'&argoCdUrl='"$argocdURL"'&rolloutsEnabled=false&isdUrl='"${opsmxIsdUrl}"
    echo "$url is the url"
    httpCode=$( curl -s --cookie ./cookie -o manifest.yml -w "%{http_code}" $url )
    echo "$httpCode is return code of the curl get manifest command"
    if [ $httpCode != "200" ]; then 
        echo "ERROR could not get manifest for $argocdName"
        echo "ERROR could not get manifest for $argocdName" >> errorlist.txt 
        cat manifest.yml >> errorlist.txt
        echo 
        echo >> errorlist.txt 
        continue
    fi 

    authtoken=$( cat manifest.yml  | grep authtoken: | awk '{print $2}' | base64 -d )
    caCert=$( cat manifest.yml  | grep caCert64 | awk '{print $2}' )
    echo "CACert certificate is"
    echo $caCert
    echo

fi 
#################################################### get argocd creds ##############################
# Retrieve ArgoCD username and password from Kubernetes secrets
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

#################################################### get argocd token ##############################
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

#################################################### create k8s secrets ##############################
sed -e "s@ARGOCDNAME@$argocdName@g" -e "s@TOKEN@$argocdtoken@g" -e "s@ARGOCDURL@$argocdURL@g" services.tmpl > services.yaml

# Store the secrets in Kubernetes
kubectl create secret generic $argocdName-secrets -n $argocdNS \
    --from-literal=cdIntegration="true" \
    --from-literal=sourceName="$argocdName" \
    --from-literal=opsmxIsdUrl="$opsmxIsdUrl" \
    --from-literal=user="admin" \
    --from-file=services.yaml=services.yaml \
    --from-literal=authtoken="$authtoken"

rm -rf services.yaml manifest.yml output.json
echo
echo
echo
echo
done < argocdlist.txt
if test -f errorlist.txt ; then   echo "Errors exist, check the file errorlist.txt"; exit 1; fi
echo "Successfully added secrets to Kubernetes."
