#!/bin/bash -x

db=$1
if [ -s $db ]
then
  db=defaultdb
fi

dropdb --if-exists $db
#createdb $db -T template_postgis
createdb $db
psql $db -c 'create extension postgis'
psql $db -c 'create extension postgis_topology'
psql $db -f schema.gis250k | grep -v INSERT
psql $db -f mksymbols_ga | grep -v INSERT
psql $db -f mkdisptable.ga | grep -v INSERT

for mdb in ~/maps/GA/Vector_data/*.mdb
do
#  ./add_map.sh $mdb
echo $mdb
  ./read_mdb.pl $mdb | ./ins250gis.pl --db=$db
done

#psql $db -f tracks.insertions | grep -v INSERT
psql $db -c "vacuum analyze;"
