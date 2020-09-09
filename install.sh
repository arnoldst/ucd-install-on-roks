#!/bin/bash
if [ $# -gt  0 ]; then
echo "There are 6 environment variables that you can set to control the installation (or you can just modify the install.sh to change the default values).  The only one that is mandatory is the ENTITLED_REGISTRY_KEY, the others are optional with sensible default values.  I would strongly recommend changing the two passwords.

ENTITLED_REGISTRY_KEY - the value of your entitled registry key, this is used to pull down the ucd docker images.
NAMESPACE - the namespace that ucd will be deployed to.  If it doesnt exist, it will get created.
MYSQL_PASSWORD - the password to the mysql database.  The mysql database is not exposed outside of the cluster.
UCD_ADMIN_PASSWORD - the password to ucd.  the UCD ui is on the public internet, so I woudl strongly recommend this is 32 characters plus.  The defaul value is admin !!!
UCD_RELEASE_NAME - this is the name of the helm release for ucd, and is also used as the basis of the route to the ucd server.
UCDAGENT_RELEASE_NAME - this is the name of the helm release for the ucd agents.

Once you've set the environment variables you want to change, then you can just simply type

./install.sh

It should take about 5 minutes to install, and you will get progress information as it proceeds.";
exit 1;
fi

if [ -z "${NAMESPACE}" ]; then NAMESPACE='ucd';  fi
if [ -z "${MYSQL_PASSWORD}" ]; then MYSQL_PASSWORD='pleasechangeme123';  fi
if [ -z "${UCD_ADMIN_PASSWORD}" ]; then UCD_ADMIN_PASSWORD='admin'; fi
if [ -z "${UCD_RELEASE_NAME}" ]; then UCD_RELEASE_NAME='ucd705';  fi
if [ -z "${UCDAGENT_RELEASE_NAME}" ]; then UCDAGENT_RELEASE_NAME='ucdagent705';  fi
if [ -z "${ENTITLED_REGISTRY_KEY}" ]; then 
  echo "You must set the environment variable ENTITLED_REGISTRY_KEY to the key of your entitled registry";
  exit 1;
fi

#
# Create the project
#
echo "INFO 1/7: creating the project"
oc get project ${NAMESPACE}
if [ $? -eq 1 ]; then
  oc new-project ${NAMESPACE};
  oc adm policy add-scc-to-group anyuid system:serviceaccounts:${NAMESPACE};
else
  echo "ERROR:  Namespace ${NAMESPACE} already exists.  Please delete the namespace or try a different name.";
  exit 1
fi
echo "SUCCESS 1/7: creating the project"
#
# Create the my sql database
#
echo "INFO 2/7: creating the mysql database"
oc apply -f ./mysql-pvc.yaml
PVCStatus=`oc get pvc mysql-pvc -o=jsonpath="{@.status.phase}"`
while [ $PVCStatus != "Bound" ]
do
  echo "INFO: Waiting for PVC to bind"
  sleep 10
  PVCStatus=`oc get pvc mysql-pvc -o=jsonpath="{@.status.phase}"`
done
echo "INFO: PVC is bound."
oc apply -f ./mysql.yaml
oc apply -f ./mysqlservice.yaml
MYSQL_POD_NAME=`oc get pods | grep mysql | cut -d " " -f 1`
MYSQL_POD_STATUS=`oc get pod | grep ${MYSQL_POD_NAME} | awk '{print $3}'`
while [ $MYSQL_POD_STATUS != "Running" ]
do
   echo "INFO: Waiting for MYSQL pod to get to Running state"
   sleep 10
   MYSQL_POD_STATUS=`oc get pod | grep ${MYSQL_POD_NAME} | awk '{print $3}'`
done
sleep 20
echo "SUCCESS 2/7: MYSQL is running"
echo "Info 3/7: Configuring mysql database"
oc exec -it $MYSQL_POD_NAME -- mysql -u root -ppassword -e "CREATE USER 'ibm_ucd'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';"
oc exec -it $MYSQL_POD_NAME -- mysql -u root -ppassword -e "CREATE DATABASE ibm_ucd character set utf8 collate utf8_bin;"
oc exec -it $MYSQL_POD_NAME -- mysql -u root -ppassword -e "GRANT ALL ON ibm_ucd.* TO 'ibm_ucd'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}' WITH GRANT OPTION;"
echo "SUCCESS 3/7: MYSQL is confogured with the ucd database"
echo "INFO 4/7: Configuring secrets and config maps"
oc create secret docker-registry entitledregistry-secret --docker-username=cp --docker-password=${ENTITLED_REGISTRY_KEY} --docker-server=cp.icr.io
oc patch serviceaccount/default --type='json' -p='[{"op":"add","path":"/imagePullSecrets/-","value":{"name":"entitledregistry-secret"}}]'

UCD_PWD_BASE64=`echo ${UCD_ADMIN_PASSWORD} | base64`
MYSQL_PWD_BASE64=`echo password | base64`
oc create secret generic ucd-secrets --from-literal=dbpassword=${MYSQL_PASSWORD} --from-literal=initpassword=${UCD_ADMIN_PASSWORD}
oc create -f mysqldriverConfigMap.yaml
echo "SUCCESS 4/7: Configured secrets and config maps"

echo "INFO 5/7: Installing UCD Server"
helm repo add ibm-helm https://raw.githubusercontent.com/IBM/charts/master/repo/ibm-helm/
helm install ${UCD_RELEASE_NAME} --values myvalues.yaml entitled/ibm-ucd-prod
UCD_POD_NAME=`oc get pods | grep ${UCD_RELEASE_NAME} | cut -d " " -f 1`
UCD_POD_STATUS=`oc get pod | grep ${UCD_POD_NAME} | awk '{print $3}'`
while [ $UCD_POD_STATUS != "Running" ]
do
   echo "INFO: Waiting for UCD pod to get to Running state"
   sleep 10
   UCD_POD_STATUS=`oc get pod | grep ${UCD_POD_NAME} | awk '{print $3}'`
done
echo "SUCCESS 5/7: Installed UCD Server"

echo "INFO 6/7: Installing Route"
oc create route passthrough ucd --service=${UCD_RELEASE_NAME}-ibm-ucd-prod --port=https
echo "SUCCESS 6/7: Installing Route"

echo "INFO 7/7: Installing Agent"
helm install ${UCDAGENT_RELEASE_NAME} --values ucdagentvalues.yaml entitled/ibm-ucda-prod
UCDAGENT_POD_NAME=`oc get pods | grep ${UCDAGENT_RELEASE_NAME} | cut -d " " -f 1`
UCDAGENT_POD_STATUS=`oc get pod | grep ${UCDAGENT_POD_NAME} | awk '{print $3}'`
while [ $UCDAGENT_POD_STATUS != "Running" ]
do
   echo "INFO: Waiting for UCD Agent pod to get to Running state"
   sleep 10
   UCDAGENT_POD_STATUS=`oc get pod | grep ${UCDAGENT_POD_NAME} | awk '{print $3}'`
done
echo "SUCCESS 7/7: Installing Agent - UCD Install complete"
SERVER_ADDRESS=`oc get route ucd -o=jsonpath="{@.spec.host}"`
echo "The UCD server can be found at https://${SERVER_ADDRESS} and the credentials are admin/${UCD_ADMIN_PASSWORD}"