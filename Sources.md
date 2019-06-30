# Map data sources #

## VicMap ##
How to populate the VicMap database.

### Download the data ###

  * Go to https://service.land.vic.gov.au/SpatialDatamart and create an account for yourself. (This is not necessary, but useful.)
  * Goto Search, and enter what you want in the "what" field. Useful things are "tr_road", tr_rail", "hy_water", "el_ground", "el_contour".
  * Select the databases you want. The useful databases (i.e. those which the scripts know how to handle) include tr_road, tr_road_infrastructure, tr_road_locality, hy_water_area_polygon, hy_water_point, hy_water_struct_area_polygon, hy_water_struct_line, hy_water_struct_point, hy_watercourse, tr_rail, tr_rail_infrastructure, el_contour.
  * Clock on "proceed to order".
  * Select the area you want the data for. ("Whole of State" could generate rather large files, but they're manageable except for things like tree_density which contain great detail.) I usually use "Local Government Area" and wherever I'm interested in at the moment. (Note that the product of the number of datasets, and the number of areas must be no more then 12.)
  * Select the buffer zone (i.e. how far outside the selected area you want data for), the format ("ESRI shapefile"), projection ("Geographicals on GDA-94") and delivery method
  * Click on "Apply to All".
  * Now click "Submit", and "Submit" again.
  * When your order is ready, you will receive an email with the link to the data, which is valid for ten days. When the servers are busy this might take up to an hour or two. For very large database (Tree density for the whole state for example) you will be given a link to an ftp site which contains the files. Make sure you download data in the correct format.

### Unpack the data, and populate the database ###

  * Find a convenient directory and download the zip files to that directory.
  * Unzip the data.
  * Work out where the .shp files have been put.
  * Create a postgresql database: "createdb maps".
  * Ensure that postgis has been installed in that database.
  * For each shp file (except for things like EXTRACT_POLYGON which simply contains the boundary of the data you have), run "shp2pqsql -a -D -s 4326 \<shapefile\> [\<tablename\>] | psql maps", except, the first time you use a particular table, use "-c" instead of "-a". The tablename is optional, but I usually create the tables as vm_\<name\> to avoid conflicts. Some of the other code assumes this.
  * Fix up some database tables. The code assumes that certain types of tables have certain columns, and they don't always exist, so you need to create those columns with a default value, usually zero: "psql maps -c 'alter table tr_road_infrastructure add column width float default 0'". [Currently unnecessary]
  * You will also need to populate the database with the postscript definitions of all the symbols (the symbols_ga table) and the mapping from Vicmap objects to those symbols (the vicmap.symbols table): "psql -d maps -f mksymbols_ga" and "psql -d maps -f mkvicmap_symbols". These will both give errors the first time they are run as they delete and then recreate tables.

## GeoScience Australia 1:250000 ##

### Download the data ###
1. If you want data for the whole country, the easiest way is to search for "geoscience australia digital topographic data". This will give you options for various scales. The 1:250000 data is best handled at the moment, but the others should also work. The 1:100000 data has certainly worked in the past.
Selecting the 1:250000 option gives a set of download links. (Usually. Refresh if necessary.) Open the "esri pgdb" link. This will download a zip file about 1.3Gb in size. Unzip it, and process the files in the Vector_data directory as below.
2. If you want data for only a small part of the country, you can download data for individual 1:250000 map sheets from data.gov.au by searching for the name of the map and selecting the correct map: '\<name\> 1:250000 GIS Dataset'. The search engine on data.gov.au has recently changed, and you will find the data most easily by searching for something like "mount young 1:250 000 gis dataset", including the double quotes. Otherwise you will need to scroll through a lot of irrelevant data before finding what you want.  An index of the maps is available on data.gov.au as "Map Sheet / Data indexes 2012 (for 1:100 000, 1:250 000 and 1:1,000,000 scale maps)". Click on "Download the file (pGDB).

If you also search for "mount young 1:250 000 topographic map" you will be able to download an image of the map. I generally use the PDF version.

### Unpack the data and populate the database ###

You can unzip the resulting file and then process the data.

There are various scripts in the import directory which can be used to process the data, which is in Microsoft's JET database format. The make_gis script show one way of doing this.

## OpenStreetMap ##
The script can utilise OSM for displaying roads.

To download the data, try getting an extract fromn the osm database from somewhere, and running something like "osm2pgsql -l -d \<database\> ~/Downloads/australia.extract.osm.pbf".

I have used http://download.geofabrik.de/australia-oceania-latest.osm.pbf to get all of Australia.