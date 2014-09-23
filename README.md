#Maps

Code to process free data from the Australian and Victorian (and possibly other) government web sites, and produce useful maps from that data.

##Contents

drawvic is a perl5 script to access a Postgresql database containing data available from data.vic.gov.au and generate a PostScript map of a particular area.

It's not perfect by any means, the main defect at the moment is that there are essentially no annotations on the map, and all data is displayed no matter what scale you are generating, which makes small scal maps rather crowded.

##Getting the data to make it useful

You can either go to data.vic.gov.au and navigate through SpatialData to the datasets you want, or go straight to service.land.vic.gov.au/SpatialDatamart (which is where you'll end up anyway). The advantage of the second option is that you can create an account and log in to keep track of what you have downloaded.

When you have completed the downloads you can populate the database by using shp2psgl.
