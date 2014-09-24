#Maps

Code to process free data from the Australian and Victorian
(and possibly other) government web sites, and produce useful
maps from that data.

##Contents

`drawvic` is a perl5 script to access a Postgresql database
containing data available from data.vic.gov.au and generate
a PostScript map of a particular area.

`drawvic.pl6` is a perl6 version of the same script (not yet
fully debugged).

It's not perfect by any means, the main defect at the moment
is that there are essentially no annotations on the map, and
all data is displayed no matter what scale you are generating,
which makes small scale maps rather crowded.

##Usage

`drawvic lat=dd.ddd long=ddd.ddd`

will produce PostScript on stdout (plus lots of progress information on stderr)
which has the specified latitude and longitude at the bottom left hand corner.

Each script will process ~/.drawrc and .drawrc as a list of options before
parsing the command line options. Options specified later will override earlier
options.

Other options:

`papersize=a2` -- Generate   map for a particular sized sheet of paper. Available sizes include A0-A9, B0-B9, A-E and letter (default is A3).

`orientation=portrait`

`orientation=landscape` -- default

`bleedtop=1` -- bleed the map over the top margin (default is to stop the map short of the margin with longitude and easting information repeated above the map)

`bleedright=1` -- bleed the map over the right margin (default is to stop the map short of the margin with latitude and northing information repeated to the right of the map)

`annotation="dd.ddd dd.ddd xoff yoff text"` -- print the specified text in a box at location "dd.ddd dd.ddd" offset by xoff,yoff millimetres (default 10,10), with a line from the box to the specified location

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

`width=15m` -- The width of the map in decimal degrees (or decimal minutes if "m" appended).

`height=15m` -- The height of the map in decimal degrees (or decimal minutes if "m" appended).

`zone=55H` -- The UTM zone of the map. Must be specified if eastings and northings are specified for the lower left corner, otherwise defaults to the zone of the lower left corner.

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
* el_contour -- contours
* el_grnd_surface_point -- spot heights
* hy_water_area_polygon -- lakes, reservoirs...
* hy_water_point -- small dams, springs...
* hy_water_struct_area_polygon -- man-made large water features
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

##Getting the data to make it useful

You can either go to data.vic.gov.au and navigate through
SpatialData to the datasets you want, or go straight to
service.land.vic.gov.au/SpatialDatamart (which is where you'll
end up anyway). The advantage of the second option is that you
can create an account and log in to keep track of what you have
downloaded.

When you have completed the downloads you can populate the
database by using shp2psgl.
