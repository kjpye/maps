#!/usr/bin/env perl6

use v6;

use DBIish;

my %table = (AerialCableway => 'line',
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

my %featuretype = ( );

my %columndesc = (
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
	       #MAPNUMBER => 'mapnumber text',
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
               SHAPE_AREA => 'shape_area float',
               SHAPE_LENGTH => 'shape_length float',
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

my %tables;
my $debug = 0;
$debug = 1;
my @row;
my $max-featuretype = 0;
my $dbh;

sub get-featuretype($name, $prefix) {
    return %featuretype{$name} if defined %featuretype{$name};
    my $type = ++$max-featuretype;
    %featuretype{$name} = $type;
    $name ~~ s:g/\'/\\'/;
    my $sth = $dbh.prepare("INSERT INTO {$prefix}FeatureType (name, type) VALUES (?, ?);");
    $sth.execute($name, $type);
    $*ERR.say: "Added featuretype $type ($name) to database\n" if $debug;
    $type;
}


my $objects = 0;
my $columns = '';
my $columnvalues = '';
my $table-type = '';
my $table-name;

sub do-insert($prefix){
    if $columns && $table-type {
	$columns ~~ s/\,\s*$//;
	$columnvalues ~~ s/\,\s*$//;
	my $sth = $dbh.prepare("INSERT INTO {$prefix ~ $table-name} ($columns) VALUES ({$columnvalues});");
        $*ERR.print: "INSERT INTO {$prefix ~ $table-name} ($columns) VALUES ($columnvalues);\n" unless $sth.execute;
    }
    $columns = '';
    $columnvalues = '';
}

sub MAIN(:$db = 'maps', :$prefix = 'ga_') {
  $dbh = DBIish.connect('Pg', dbname => $db, RaiseError => False);
  my $sth = $dbh.prepare("SELECT name, type FROM {$prefix}FeatureType");
  $sth.execute();

  while @row = $sth.fetchrow_array {
    my $name = @row[0];
    my $type = @row[1];
    %featuretype{$name} = $type;
    $max-featuretype = $type if $type > $max-featuretype;
  }

for lines() {
  when /Processing ' ' table ' ' \" (.*) \" / {
#    do-insert $prefix;
      $columns = '';
      $columnvalues = '';
    $table-name = ~$0;
    #dd $table-name;
    $table-type = %table{~$table-name} // 0;
  }
#  when /^BBOX\: (.*)/ {
#    $columns ~= 'bbox, ';
#    $columnvalues ~= "'$0', ";
#  }
  when /^Column \s* (\d+) \s* \( (\w+) \) \: (.*) / {
    my $columnnumber = +$0;
    my $columnname   = ~$1;
    my $columnvalue  = ~$2;
    #dd $columnnumber;
    #dd $columnname;
    #dd $columnvalue;
    do-insert $prefix if $columnnumber == 0;
    next unless %columndesc{$columnname.uc}.defined;
    $columnvalue ~~ s/ ^ \s+   //;
    $columnvalue ~~ s/   \s+ $ //;
    next unless $columnvalue;
    my ($name, $type) = %columndesc{$columnname.uc}.split: ' ';
    $*ERR.say: "Line: column $name, type $type" if $debug;
    given $type {
	when 'int' | 'smallint' {
	    $columnvalue ~~ / ^ \s* (\d+)/;
	    if $0.defined {
		$columnvalues ~= $0 ~ ', ';
		$columns ~= $name ~ ',';
	    }
	}
	when 'featuretype' {
	    my $ftype = get-featuretype($columnvalue, $prefix);
	    $columnvalues ~= $ftype ~ ', ';
	    $columns      ~= $name  ~ ', ';
	}
	when 'date' {
#            $columnvalue ~~ /^\s*[\S+]\s+(\S+)\s*(\d+)\s*[\S+]\s*(\d+)$/;
            $columnvalue ~~ /^\s*(....)\-(..)\-(..).*/;
	    $columnvalues ~= "'$0 $1 $2', ";
	    $columns      ~= $name ~ ', ';
	}
	when 'source' {
            $columnvalues ~= '1, '; # FIX
	    $columns      ~= $name ~ ', ';
	}
	when 'timestamp' {
	    $columnvalues ~= "'$columnvalue', ";
	    $columns      ~= $name ~ ', ';
	}
	when 'float' {
            $columnvalues ~= $columnvalue ~ ', ';
	    $columns      ~= $name ~ ', ';
	}
	when 'text' {
            $columnvalue ~~ s:g/ \\ /\\\\/;
            $columnvalue ~~ s:g/ \' /\'\'/;
	    $columnvalues ~= "E'{$columnvalue}', ";
	    $columns      ~= $name ~ ', ';
	}
	when 'geometry' {
	    $*ERR.say: "shape (type {$table-type}): {$columnvalue}" if $debug;
	    if $table-type eq 'point' {
	      $columnvalue ~~ /Long ' ' (\S+) ' ' Lat ' ' (.*)/;
              my ($long, $lat) = (~$0, ~$1);
              $long ~~ s/\,$//;
              $columnvalues ~= "ST_GeomFromText('POINT($long $lat)', 4326), ";
              $columns      ~= 'position, ';
	    } else {
              $columnvalue ~~ s:g/\,//;
              $columnvalue ~~ s:g/ \) \s+ \( /, /;
              $columnvalue ~~ s/^/(/;
              $columnvalue ~~ s:g/ \s* Segment \s+ \d+ \: \s*/) (/;
              $columnvalue ~~ s/^\(\) //;
              $columnvalue ~~ s/[\,\s\(]? $//;
              $columnvalue ~~ s:g/ \) \) \s+ \( \( /), (/;
              $columnvalue ~~ s/^\s+//;
say $columnvalue;
              $columnvalues ~= "ST_GeomFromText('MULTILINESTRING$columnvalue)', 4326), ";
              $columns      ~= 'shape, ';
	    }
	}
	when 'bytea' {
	    $*ERR.say: "BYTEA: {$columnvalue}" if $debug;
            $columns      ~= $name ~ ', ';
            $columnvalues ~= "E'";
            for $columnvalue.split: ' ' -> $byte {
              $columnvalues ~= sprintf "\\\\%03o", :16($byte) if $byte;
            }
            $columnvalues ~= "', ";
	}
    }
  }
}

do-insert $prefix;

$dbh.dispose();
}
