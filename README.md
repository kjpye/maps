#Maps

Code to process free data from the Australian and Victorian
(and possibly other) government web sites, and produce useful
maps from that data.

##Contents

`mkmap` is a perl6 script to access a Postgresql database
containing data available from various sources and generate
a PostScript map of a particular area.

It's not perfect by any means, the main defect at the moment
is that there are essentially no annotations related to data except for specific annotation tables, and
all data is displayed no matter what scale you are generating,
which makes small scale maps rather crowded.

##Database

###VicMap
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
  * When your order is ready, you will receive an email with the link to the data, which is valid for ten days. When the servers are busy this might take up to an hour or two. Sometimes, for very large whole-of-state queries it will link to an ftp site containing multiple files. Download the file with the correct projection.

2. Unpack the data, and populate the database.

  * Find a convenient directory and download the zip files to that directory.
  * Unzip the data.
  * Work out where the .shp files have been put.
  * Create a postgresql database: "createdb maps".
  * Ensure that postgis has been installed in that database.
  * For each shp file (except for things like EXTRACT_POLYGON which simply
  * contains the boundary of the data you have), run "shp2psql -a -D -s 4326 <shapefile> [<tablename>] | psql maps", except, the first time you use a particular table, use "-c" instead of "-a". The tablename is optional, but I usually create the tables as vm_<name> to avoid conflicts. Some of the other code assumes this.
  * Fix up some database tables. The code assumes that certain types of tables have certain columns, and they don't always exist, so you need to create those columns with a default value, usually zero: "psql vicmap -c 'alter table tr_road_infrastructure add column width float default 0'". [Currently unnecessary]
  * You will also need to populate the database with the postscript definitions of all the symbols (the symbols_ga table) and the mapping from Vicmap objects to those symbols (the vicmap.symbols table): "psql -d vicmap -f mksymbols_ga" and "psql -d vicmap -f mkvicmap_symbols". These will both give errors the first time they are run as they delete and then recreate tables.

###GeoScience Australia 1:250000
Data can be retrieved from data.gov.au by searching for the name of the map and selecting the correct map: '<name> 1:250000 GIS Dataset'. Click on "Download the file (pGDB). (You can also click on "Link to Map Product" and "Go to resource". This enables you to download the geoPDF version which can be displayed using any PDF viewer.

You can unzip the resulting file and then process the data. The make_gis script show one way of doing this.

###OpenStreetMap
The script can utilise OSM for displaying roads.

To download the data, try getting an extract fromn the osm database from somewhere, and running something like "osm2pgsql -l -d <database> ~/Downloads.australia.extract.osm.pbf".

I have used http://download.geofabrik.de/australia-oceania-latest.osm.pbf to get all of Australia.

##Usage

`mkmap lat=dd.ddd long=ddd.ddd`

will produce PostScript on stdout (plus lots of progress information on stderr)
which has the specified latitude and longitude at the bottom left hand corner.

Each script will process ~/.mkmaprc and .mkmaprc as a list of options before
parsing the command line options. Options specified later will override earlier
options.

Other options:

`papersize=a2` -- Generate   map for a particular sized sheet of paper. Available sizes include A0-A9, B0-B9, A-E and letter (default is A3).

`orientation=portrait`

`orientation=landscape` -- default

`bleedtop=1` -- bleed the map over the top margin (default is to stop the map short of the margin with longitude and easting information repeated above the map)

`bleedright=1` -- bleed the map over the right margin (default is to stop the map short of the margin with latitude and northing information repeated to the right of the map)

`annotation="dd.ddd dd.ddd xoff yoff text"` -- print the specified text in a box at location "dd.ddd dd.ddd" offset by xoff,yoff millimetres (default 10,10), with a line from the box to the specified location. The strings "$LONG" and "$LAT" will be replaced by the latitude and longitude of the annotation.

`leftmarginwidth=m.mm` -- the width of the left margin in millimetres (default 30).

`rightmarginwidth=m.mm` -- the width of the right margin in millimetres (default 30); ignored if bleedright is specified.

`lowermarginwidth=m.mm` -- the height of the bottom margin in millimetres (default 25).

`bottommarginwidth=m.mm` -- see lowermarginwidth

`uppermarginwidth=m.mm` -- the height of the top margin in millimetres (default 25); ignored if bleedtop is specified.

`topmarginwidth=m.mm` -- see uppermarginwidth

`database=&lt;db&gt;` -- The name of the Postgresql database to use (default "vicmap")

`db=&lt;db&gt;` -- see database

`latitude=dd.ddd` -- The latitude of the lower left corner of the map in decimal degrees. Negative is south of the equator.

`lat=dd.ddd` -- see latitude

`longitude=ddd.ddd` -- The longitude of the lower left corner of the map in decimal degrees. Negative is west of Greenwich.

`long=ddd.ddd` -- see longitude

`easting=mmmmmmm` -- The easting of the lower left corner of the map in metres. zone must also be specified.

`east=mmmmmmm` -- see easting

`northing=mmmmmmm` -- The northing of the lower left corner of the map in metres. The zone must also be specified.

`north=mmmmmm` -- see northing

`zone=55H` -- The UTM zone of the map. Must be specified if eastings and northings are specified for the lower left corner, otherwise defaults to the zone of the lower left corner.

`width=15m` -- The width of the map in decimal degrees (or decimal minutes if "m" appended).

`height=15m` -- The height of the map in decimal degrees (or decimal minutes if "m" appended).

`scale=30000` -- The scale of the map. (May be specified as 1:30000 also.) Defaults to 1:25000.

`gridspacing=1000m` -- The grid spacing on the map in metres (or km if "k" is appended). Defaults to 10km.

`grid=1000m` -- see gridspacing

`graticulespacing=2.5m` -- The graticule spacing in decimal degrees (or decimal minutes if "m" appended). Defaults to 0.25.

`graticule=2.5m` -- see graticulespacing

`display=all` -- Display all possible objects (see list below). This is the default.

`display=roads` -- Display the road information. (Used after nodisplay=all.) See below for complete list of what can be displayed.

`nodisplay=all` -- Don't display anything. Usually overridden by several display=??? options.

`nodisplay=roads` -- Don't display road information.

`nofeature=???` -- Don't display a featuretype.

`symbols=Symbols_GA` -- Which symbol set to use. Defaults to Symbols_GA which is probably the only symbol set which currently works.

`property=125342` -- Display the boundary of property number 125342. Determinig property number is left as an exercise for the reader.

`file=include.cfg` -- Process the specified file as options.

##Features available

drawvic currently knows how to draw the following features, assuming the relevant data is in the database:
* vm_el_contour -- contours
* vm_el_grnd_surface_point -- spot heights
* vm_hy_water_area_polygon -- lakes, reservoirs...
* vm_hy_water_point -- small dams, springs...
* vm_hy_water_struct_area_polygon -- man-made large water features
* hy_water_struct_line -- drains, dam walls...
* hy_water_struct_point -- tanks...
* hy_watercourse -- rivers, creeks...
* lga_polygon -- local government area boundaries
* locality_polygon -- localities
* locality_name -- locality_names; auto generated from the locality information
* property -- properties
* tr_air_infra_are_polygon -- airports...
* tr_airport_infrastructure -- runways...
* tr_rail -- railway lines...
* tr_rail_infrastructure -- railway stations...
* tr_road -- roads, footpaths...
* tr_road_infrastructure -- point items associated with roads -- roundabouts, intersections...
* tree_density -- native vegetation cover
* graticule -- lines of longitude and latitude
* grid -- eastings and northings
* userannotations -- annotations specified as options
