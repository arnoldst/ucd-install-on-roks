#!/bin/bash
helm delete ucd710

oc delete -f ucdDBSecret.yaml
oc delete -f mysqldriverConfigMap.yaml

oc delete -f ./mysqlservice.yaml
oc delete -f ./mysql.yaml

oc delete -f ./mysql-pvc.yaml
oc delete project ucd
