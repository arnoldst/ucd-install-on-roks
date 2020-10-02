To get started you're going to need an openshift cluster running in the IBM cloud, and a client with oc installed.  Clone this repo as it has a number of yaml files that you can just run.  There are now two options to install UCD, one is to run the script, which is the quickest and easiest way.  The second way is a more step by step approach - which is useful if you need to understand how to do the install, or you need to make significant changes.


# Automated Instructions to install Urbancode Deploy(UCD) on IBM's Redhat Openshift Kubernetes Service (ROKS)
There are 6 environment variables that you can set to control the installation (or you can just modify the install.sh to change the default values).  The only one that is mandatory is the ENTITLED_REGISTRY_KEY, the others are optional with sensible default values.  I would strongly recommend changing the two passwords.

- ENTITLED_REGISTRY_KEY - the value of your entitled registry key, this is used to pull down the ucd docker images.
- NAMESPACE - the namespace that ucd will be deployed to.  If it doesnt exist, it will get created.
- MYSQL_PASSWORD - the password to the mysql database.  The mysql database is not exposed outside of the cluster.
- UCD_ADMIN_PASSWORD - the password to ucd.  the UCD ui is on the public internet, so I woudl strongly recommend this is 32 characters plus.  The defaul value is admin !!!
- UCD_RELEASE_NAME - this is the name of the helm release for ucd, and is also used as the basis of the route to the ucd server.
- UCDAGENT_RELEASE_NAME - this is the name of the helm release for the ucd agents.

Once you've set the environment variables you want to change, then you can just simply type

```
./install.sh
```

It should take about 5 minutes to install, and you will get progress information as it proceeds.  At the end, the script will output the route and credentials for your ucd server.

# Manual instructions to install Urbancode Deploy(UCD) on IBM's Redhat Openshift Kubernetes Service (ROKS)

The first step is to create a project, and set the service account up to be able to run UCD.

```
oc new-project ucd

oc adm policy add-scc-to-group anyuid system:serviceaccounts:ucd
```

Now we need to create a database server.  The easiest thing is to use mysql.  We need to create a volume claim, the database itself and a service so that ucd can acces it.

```
oc apply -f ./mysql-pvc.yaml
oc apply -f ./mysql.yaml
oc apply -f ./mysqlservice.yaml
```

Now you need to create the database for ucd to use.  Once the pods are running, exec into the mysql pod and create the database with the following.

```
oc exec -it <mysql pod name> /bin/bash
mysql -u root -ppassword
CREATE USER 'ibm_ucd'@'localhost' IDENTIFIED BY 'password';
CREATE DATABASE ibm_ucd character set utf8 collate utf8_bin;
GRANT ALL ON ibm_ucd.* TO 'ibm_ucd'@'%' IDENTIFIED BY 'password' WITH GRANT OPTION;
```

Now we need to create some secrets and config maps.  There are two secrets - one to access the ucd docker images, and a second to provide the default ucd admin password and sql database passwords.  Finally there is a config map to pull down the mysql drivers.  You'll need your entitled registry key here.  I also strongly recommend you change the default passwords in the ucd DBSecret.yaml file.   You can do this by `echo -n 'your password' | base64` and putting the resulting text into the file.  As it stands this will setup a ucd server with username admin, password of admin.

```
oc create secret docker-registry entitledregistry-secret --docker-username=cp --docker-password=<your entitled key goes here> --docker-server=cp.icr.io
oc patch -n ucd serviceaccount/default --type='json' -p='[{"op":"add","path":"/imagePullSecrets/-","value":{"name":"entitledregistry-secret"}}]'

oc create -f ucdDBSecret.yaml

oc create -f mysqldriverConfigMap.yaml
```

We're now ready to install the UCD server.  Review the values in myvalues.yaml before installing.  We're going to add the helm repo, and then install.

```
helm repo add entitled https://raw.githubusercontent.com/IBM/charts/master/repo/entitled
helm install myucdrelease --values myvalues.yaml ibm-helm/ibm-ucd-prod/
```

Once the pods are up and running, we need to create a route to the ucd server. Edit the ucroute.yaml, and update the route with the url of your ocp server.  Then run the following.

```
oc apply -f ucdroute.yaml
```

Check you can access the ucd UI by copying the route url into a browser.  

Assuming thats all ok - we just need to do the final step.  Now you need to add an agent.

```
helm install my-ucda-release --values ucdagentvalues.yaml ibm-helm/ibm-ucda-prod
```

And thats it all completed.




