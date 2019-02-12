# Map data sources #

## VicMap ##
How to populate the VicMap database.

1. Download the needed data for the area of concern.

  * Go to https://service.land.vic.gov.au/SpatialDatamart and create an account for yourself. (This is not necessary, but useful.)
  * Goto Search, and enter what you want in the "what" field. Useful things are "tr_road", tr_rail", "hy_water", "el_ground", "el_contour".
  * Select the databases you want. The useful databases (i.e. those which the scripts know how to handle) include tr_road, tr_road_infrastructure, tr_road_locality, hy_water_area_polygon, hy_water_point, hy_water_struct_area_polygon, hy_water_struct_line, hy_water_struct_point, hy_watercourse, tr_rail, tr_rail_infrastructure, el_contour.
  * Clock on "proceed to order".
  * Select the area you want the data for. ("Whole of State" could generate rather large files, but they're manageable except for things like tree_density which contain great detail.) I usually use "Local Government Area" and wherever I'm interested in at the moment. (Note that the product of the number of datasets, and the number of areas must be no more then 12.)
  * Select the buffer zone (i.e. how far outside the selected area you want data for), the format ("ESRI shapefile"), projection ("Geographicals on GDA-94") and delivery method
  * Click on "Apply to All".
  * Now click "Submit", and "Submit" again.
  * When your order is ready, you will receive an email with the link to the data, which is valid for ten days. When the servers are busy this might take up to an hour or two. For very large database (Tree density for the whole state for example) you will be given a link to an ftp site which contains the files. Make sure you download data in the correct format.

2. Unpack the data, and populate the database.

  * Find a convenient directory and download the zip files to that directory.
  * Unzip the data.
  * Work out where the .shp files have been put.
  * Create a postgresql database: "createdb maps".
  * Ensure that postgis has been installed in that database.
  * For each shp file (except for things like EXTRACT_POLYGON which simply contains the boundary of the data you have), run "shp2pqsql -a -D -s 4326 \<shapefile\> [\<tablename\>] | psql maps", except, the first time you use a particular table, use "-c" instead of "-a". The tablename is optional, but I usually create the tables as vm_\<name\> to avoid conflicts. Some of the other code assumes this.
  * Fix up some database tables. The code assumes that certain types of tables have certain columns, and they don't always exist, so you need to create those columns with a default value, usually zero: "psql maps -c 'alter table tr_road_infrastructure add column width float default 0'". [Currently unnecessary]
  * You will also need to populate the database with the postscript definitions of all the symbols (the symbols_ga table) and the mapping from Vicmap objects to those symbols (the vicmap.symbols table): "psql -d maps -f mksymbols_ga" and "psql -d maps -f mkvicmap_symbols". These will both give errors the first time they are run as they delete and then recreate tables.

## GeoScience Australia 1:250000 ##
Data can be retrieved from data.gov.au by searching for the name of the map and selecting the correct map: '\<name\> 1:250000 GIS Dataset'. Click on "Download the file (pGDB). (You can also click on "Link to Map Product" and "Go to resource". This enables you to download the geoPDF version which can be displayed using any PDF viewer.

You can unzip the resulting file and then process the data. The make_gis script show one way of doing this.

## OpenStreetMap ##
The script can utilise OSM for displaying roads.

To download the data, try getting an extract fromn the osm database from somewhere, and running something like "osm2pgsql -l -d \<database\> ~/Downloads.australia.extract.osm.pbf".

I have used http://download.geofabrik.de/australia-oceania-latest.osm.pbf to get all of Australia.
