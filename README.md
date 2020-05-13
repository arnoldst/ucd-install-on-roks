# ucd-install-on-roks
To get started you're going to need an openshift cluster running in the IBM cloud, and a client with kubectl, and oc installed.

The first step is to create a project, and set the service account up to be able to run UCD.
```oc new-project ucd

oc adm policy add-scc-to-group anyuid system:serviceaccounts:ucd
```

Now we need to create a database server.  The easiest thing is to use mysql.  We need to create a volume claim, the database itself and a service so that ucd can acces it.
```oc apply -f ./mysql-pvc.yaml
oc apply -f ./mysql.yaml
oc apply -f ./mysqlservice.yaml
```

Now you need to create the database for ucd to use.  Once the pods are running, exec into the mysql pod and create the database with the following.
```oc exec -it <mysql pod name> /bin/bash
mysql -u root -ppassword
CREATE USER 'ibm_ucd'@'localhost' IDENTIFIED BY 'password';
CREATE DATABASE ibm_ucd character set utf8 collate utf8_bin;
GRANT ALL ON ibm_ucd.* TO 'ibm_ucd'@'%' IDENTIFIED BY 'password' WITH GRANT OPTION;
```

Now we need to create some secrets and config maps.  There are two secrets - one to access the ucd docker images, and a second to provide the default ucd admin password and sql database passwords.  Finally there is a config map to pull down the mysql drivers.  You'll need your entitled registry key here.  I also strongly recommend you change the default passwords in the ucd DBSecret.yaml file.   You can do this by `echo -n 'your password' | base64` and putting the resulting text into the file.  As it stands this will setup a ucd server with username admin, password of admin.
```oc create secret docker-registry entitledregistry-secret --docker-username=cp --docker-password=<your entitled key goes here> --docker-server=cp.icr.io
oc patch -n ucd serviceaccount/default --type='json' -p='[{"op":"add","path":"/imagePullSecrets/-","value":{"name":"entitledregistry-secret"}}]'

oc create -f ucdDBSecret.yaml

oc create -f mysqldriverConfigMap.yaml
```

We're now ready to install the UCD server.  Review the values in myvalues.yaml before installing.  We're going to add the helm repo, and then install.
```helm repo add entitled https://raw.githubusercontent.com/IBM/charts/master/repo/entitled/
helm install myucdrelease --values myvalues.yaml entitled/ibm-ucd-prod
```

Once the pods are up and running, we need to create a route to the ucd server. Edit the ucroute.yaml, and update the route with the url of your ocp server.  Then run the following.
```oc apply -f ucdroute.yaml
```
Check you can access the ucd UI by copying the route url into a browser.  

Assuming thats all ok - we just need to do the final step.  Now you need to add an agent.
```helm install my-ucda-release --values ucdagentvalues.yaml entitled/ibm-ucda-prod
```





