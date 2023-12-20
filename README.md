# isd-argo-agent
ability to create an isd argo agent

# pre-requisites 
vault command line  
argocd cli  
jq  
bash, sed and awk  
add secrets for ISD and agent argocds to vault   
set parameters in add-agent.sh   
add list of argocds in agentslist.txt 
# steps
run add-agent.sh 
set values in values.yaml  
run helm command  
