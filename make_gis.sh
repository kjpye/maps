#!/usr/bin/ksh

dropdb map250k
createdb map250k -T template_postgis
psql map250k -c 'create extension postgis'
psql map250k -c 'create extension postgis_topology'
psql map250k -f schema.gis250k | grep -v INSERT
psql map250k -f mksymbols_ga | grep -v INSERT
psql map250k -f mkdisptable.ga | grep -v INSERT

for mdb in ../../Maps/GA/mdb/?????.mdb
do
#  ./add_map.sh $mdb
echo $mdb
  ./read_mdb <$mdb | ./ins250gis.pl
done

#psql map250k -f tracks.insertions | grep -v INSERT
psql map250k -c "vacuum analyze;"