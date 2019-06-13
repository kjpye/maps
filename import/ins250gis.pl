#!/usr/bin/perl -w

use DBI;
use strict;

use POSIX;

my $db = shift // 'map250k';
my $prefix = shift // 'ga_';

use vars qw(%table);
%table = (AerialCableway => 'line',
	  AircraftFacilityPoints => 'point',
	  Annotations => 'area',
	  BarrierPoints => 'point',
	  BenchMarks => 'point',
	  Bores => 'point',
	  BuildingAreas => 'area',
	  BuildingPoints => 'point',
	  BuiltUpAreas => 'area',
	  CanalAreas => 'area',
	  CanalLines => 'line',
	  CartographicLines => 'line',
	  CartographicPoints => 'point',
	  Caves => 'point',
	  CemeteryAreas => 'area',
	  CemeteryPoints => 'point',
	  ClearedLines => 'line',
	  Contours => 'path',
	  Conveyors => 'line',
	  Craters => 'area',
	  CultivatedAreas => 'area',
	  DamWalls => 'line',
	  DeformationAreas => 'area',
	  Discontinuities => 'line',
	  Fences => 'line',
	  FerryRouteLines => 'line',
	  Flats => 'area',
	  FootTracks => 'line',
	  ForeshoreFlats => 'area',
	  FrameworkBoundaries => 'line',
	  GraticuleAnnotations => 'area',
	  Graticules => 'line',
	  GridAnnotations => 'area',
	  Grids => 'line',
	  Homesteads => 'point',
	  HorizontalControlPoints => 'point',
	  Islands => 'area',
	  Lakes => 'area',
	  LargeAreaFeatures => 'area',
	  Locations => 'point',
	  Locks => 'point',
	  Mainlands => 'area',
	  MarineHazardAreas => 'area',
	  MarineHazardPoints => 'point',
	  MarineInfrastructureLines => 'line',
	  MarineInfrastructurePoints => 'point',
	  MineAreas => 'area',
	  MinePoints => 'point',
	  NativeVegetationAreas => 'area',
	  PetroleumWells => 'point',
	  Pinnacles => 'point',
	  Pipelines => 'line',
	  PlaceNames => 'point',
	  PondageAreas => 'area',
	  PopulatedPlaces => 'point',
	  PowerLines => 'line',
	  ProhibitedAreas => 'area',
	  RailwayBridgePoints => 'point',
	  RailwayCrossingLines => 'line',
	  Railways => 'line',
	  RailwayStopPoints => 'point',
	  RailwayTunnelLines => 'line',
	  RailwayTunnelPoints => 'point',
	  RapidAreas => 'area',
	  RapidLines => 'line',
	  RecreationAreas => 'area',
	  Reserves => 'area',
	  Reservoirs => 'area',
	  RoadCrossingLines => 'line',
	  RoadCrossingPoints => 'point',
	  Roads => 'line',
	  RoadTunnelLines => 'line',
	  RoadTunnelPoints => 'line',
	  SandRidges => 'line',
	  Sands => 'area',
	  Seas => 'area',
	  Spillways => 'line',
	  SpotElevations => 'point',
	  Springs => 'point',
	  StorageTanks => 'point',
	  VerticalObstructions => 'point',
	  WatercourseAreas => 'area',
	  WatercourseLines => 'line',
	  WaterfallPoints => 'point',
	  Waterholes => 'point',
	  WaterPoints => 'point',
	  WaterTanks => 'point',
	  Windbreaks => 'line',
	  Windpumps => 'point',
	  Yards => 'point'
	  );

# Hash featuretype mirrors the featuretype table in the database. We should
# read it from there, and add new entries automatically when we find them!

use vars qw(%featuretype);

%featuretype = (
               );

use vars qw(%columndesc);
%columndesc = (
	    ANNOTATIONCLASSID => 'annotationclassid int',
	    ATTRREL => 'attrrel date',
	    AUTHORITY => 'authority text',
	    AVGHEIGHT => 'averageheight smallint',
	    CLASS => 'class text',
	    CODE => 'code text',
	    CREATED => 'created timestamp',
	    ELEMENT => 'element bytea',
	    ELEVACC => 'elevacc smallint',
	    ELEVATION => 'elevation float',
	    FEATREL => 'featrel date',
	    FEATUREID => 'featureid int',
	    FEATTYPE => 'featuretype featuretype',
	    FEATWIDTH => 'featurewidth float',
	    FORMATION => 'formation text',
	    GAUGE => 'gauge text',
	    PID => 'ga_pid int',
	    HEIGHT => 'height float',
	    HIERARCHY => 'hierarchy hierarchy',
	    MAPNUMBER => 'mapnumber text',
	    NAME => 'name text',
	    NRN => 'nrn text',
	    OCEANNAME => 'oceanname text',
	    ORDEROFACC => 'orderofacc text',
	    ORIENTATN => 'orientation smallint',
	    OTHWATERNM => 'otherwatername text',
	    PERENNIAL => 'perennial perennial',
	    PLANACC => 'planacc smallint',
	    PRODUCT => 'product text',
	    RELATION => 'relation text',
	    RETIRED => 'retired timestamp',
	    SEANAME => 'seaname text',
	    SHAPE_Area => 'shape_area float',
	    SHAPE_Length => 'shape_length float',
	    SHAPE => 'shape geometry',
	    SOURCE => 'source source',
	    SRN => 'srn text',
	    STATE => 'state state',
	    STATUS => 'status text',
	    SYMBOL => 'symbol smallint',
	    TEXTNOTE => 'textnote text',
	    TRACKS => 'tracks text',
	    TYPE => 'type int',
	    ZORDER => 'zorder int'
	    );

use vars qw(%tables);
use vars qw($debug);
$debug = 0;

my $dbh = DBI->connect("dbi:Pg:dbname=$db", "", "", {AutoCommit => 1});
my $sth = $dbh->prepare("SELECT name, type FROM ${prefix}FeatureType");
$sth->execute();

my @row;
my $max_featuretype = 0;
while ( @row = $sth->fetchrow_array )
{
   my $name = $row[0];
    my $type = $row[1];
    $featuretype{$name} = $type;
    $max_featuretype = $type if $type > $max_featuretype;
}

sub get_featuretype
{
    my $name = shift;
    return $featuretype{$name} if defined $featuretype{$name};
    my $type = ++$max_featuretype;
    $featuretype{$name} = $type;
    $name =~ s/\'/\\'/g;
    my $sth = $dbh->prepare("INSERT INTO ${prefix}FeatureType (name, type) VALUES ('$name', $type);");
    $sth->execute();
print STDERR "Added featuretype $type ($name) to database\n";
    return $type;
}


my $objects = 0;
my $columns = '';
my $columnvalues = '';
my $table_type = 0;
my $table_name;

sub do_insert
{
    if ($columns && $table_type)
    {
	$columns =~ s/\,\s*$//;
	$columnvalues =~ s/\,\s*$//;
	my $sth = $dbh->prepare("INSERT INTO ${prefix}$table_name ($columns) VALUES ($columnvalues);");
	print STDERR "INSERT INTO ${prefix}$table_name ($columns) VALUES ($columnvalues);\n" unless $sth->execute();
    }
    $columns = '';
    $columnvalues = '';
}

while(<>)
{
#    print;
    if(/Processing table \"(.*)\"/)
    {
	$table_name = $1;
	do_insert;
	$table_type = '';
	$table_type = $table{$table_name} if defined $table{$table_name};
#	open INSERT, ">250K.$table_name.insertions" if $table_type;
	next;
    }
    if (/^BBOX: (.*)/)
    {
#	$columnvalues .= "'$1', ";
#	$columns .= 'bbox, ';
	next;
    }
    if (/^Column (\d+) \((\w+)\)\: (.*)$/)
    {
	my $columnnumber = $1;
	my $columnname = $2;
	my $columnvalue = $3;
	do_insert unless $columnnumber;
	next unless defined $columndesc{$columnname};
	$columnvalue =~ s/^\s+//;
	$columnvalue =~ s/\s+$//;
	next unless $columnvalue;
	my ($name, $type) = split ' ', $columndesc{$columnname};
#	print "Line: column $name, type $type\n";
	if ($type eq 'int') {
	    $columnvalue =~ /^\s*(\d+)/;
	    if(defined $1)
	    {
		$columnvalues .= $1 . ', ';
	    }
	    $columns .= $name . ', ';
	} elsif ($type eq 'smallint')	{
	    $columnvalue =~ /^\s*(\d+)/;
	    if(defined $1)
	    {
		$columnvalues .= $1 . ', ';
	    }
	    $columns .= $name . ', ';
	} elsif ($type eq 'featuretype') {
	    my $ftype = get_featuretype($columnvalue);
	    $columnvalues .= $ftype . ', ';
	    $columns .= $name . ', ';
	} elsif ($type eq 'date') {
	    my @date = split ' ', $columnvalue;
	    $columnvalues .= "'$date[1] $date[2] $date[4]', ";
	    $columns .= $name . ', ';
	} elsif ($type eq 'source') {
	    $columnvalues .= '1, ';
	    $columns .= $name . ', ';
	} elsif ($type eq 'timestamp') {
	    $columnvalues .= "'$columnvalue', ";
	    $columns .= $name . ', ';
	} elsif ($type eq 'float') {
	    $columnvalues .= $columnvalue . ', ';
	    $columns .= $name . ', ';
	} elsif ($type eq 'text') {
	    $columnvalue =~ s/\\/\\\\/g;
	    $columnvalue =~ s/\'/\'\'/g;
	    $columnvalues .= "E'$columnvalue', ";
	    $columns .= $name . ', ';
	} elsif ($type eq 'geometry') {
#	    print "shape (type $table_type): $columnvalue\n";
	    if ($table_type eq 'point')
	    {
		$columnvalue =~ /Long (\S*) Lat (.*)/;
		my ($long, $lat) = ($1, $2);
		$long =~ s/\,$//;
		$columnvalues .= "ST_GeomFromText('POINT($long $lat)', 4326), ";
		$columns .= 'position, ';
	    } else {
		$columnvalue =~ s/\,//g;
		$columnvalue =~ s/\)\s+\(/, /g;
		$columnvalue =~ s/\s*Segment\s+\d+\:\s*/\) \(/g;
		$columnvalue =~ s/^\) //;
		$columnvalue =~ s/(,\s*)?$/\)/;
		$columnvalue =~ s/\)\)\s+\(\(/), (/g;
		$columnvalues .= "ST_GeomFromText('MULTILINESTRING $columnvalue', 4326), ";
		$columns .= 'shape, ';
	    }
        } elsif ($type eq 'bytea') {
# print "BYTEA: $columnvalue\n";
            $columns .= $name . ', ';
            $columnvalues .= "E'";
            for my $byte (split ' ', $columnvalue)
            {
                $columnvalues .= sprintf "\\\\%03o", hex($byte) if $byte;
            }
            $columnvalues .= "', ";
        }
    }
    if (/BBOX: (.*)/)
    {
        $columns .= 'bbox, ';
        $columnvalues .= "'$1', ";
    }
}

do_insert;

$dbh->disconnect();
