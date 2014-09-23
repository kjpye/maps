#!/usr/bin/perl6

use DBIish;
BEGIN { @*INC.push: '.'; } # for testing
use UTM;

my $symbols = 'Symbols_GA';

my $scale = 25000;
my ($lllongitude, $lllatitude);
my ($lrlongitude, $lrlatitude);
my ($ullongitude, $ullatitude);
my ($urlongitude, $urlatitude);
my ($lleasting, $llnorthing);
my ($lreasting, $lrnorthing);
my ($uleasting, $ulnorthing);
my ($ureasting, $urnorthing);
my Str $zone;

my @featuretype = ();
my %featuretype = ();
my @display_feature = ();
my %nofeature = ();

my %drawobjects;
my %allobjects = map {$_ => 1}, <
                  el_contour
                  hy_water_area_polygon
                  hy_water_point
                  hy_water_struct_area_polygon
                  hy_water_struct_line
                  hy_water_struct_point
                  hy_watercourse
                  lga_polygon
                  locality_polygon
                  tr_air_infra_area_polygon
                  tr_airport_infrastructure
                  tr_rail
                  tr_rail_infrastructure
                  tr_road
                  tr_road_infrastructure
                  graticule
                  grid
                  userannotations
                 >;

for %allobjects.keys -> $type {
    %drawobjects{$type} = 1; # default to drawing everything
}

my @annotations;

sub add_annotation(Real $long, Real $lat, Real $xoffset, Real $yoffset,Str $string) {
    my $annotation = {};
    %($annotation)<long>    = $long;
    %($annotation)<lat>     = $lat;
    %($annotation)<xoffset> = $xoffset;
    %($annotation)<yoffset> = $yoffset;
    %($annotation)<string>  = $string;
    @annotations.push: $annotation;
    #note "Adding annotation at $long,$lat: $string\n";
}

# Could add non-metric sizes to the hash here.
# Keys are papersize, values are a string with
# width and length in mm separated by commas.
my %papersizes;

# Calculate metric A paper sizes
  my $l = 1000 * sqrt(sqrt(2));
  my $w = 1e6/$l;
# $l * $w should be 1 square metre (1e6 mm^2) with a ratio of sqrt(2)
  for ^10 -> $s {
    %papersizes{'a' ~ $s.Str} = "$w, $l";
    $l = $w;
    $w = $l / sqrt(2);
  }

my $papersize = 'a3';
my ($paperwidth, $paperheight);
my $orientation = 'landscape';
my ($leftmarginwidth, $lowermarginwidth, $rightmarginwidth, $uppermarginwidth)
    = (30, 25, 30, 25); # negative to bleed over page boundary
my ($imagewidth, $imageheight);
my ($gridwidth, $graticulewidth);
my ($gridheight, $graticuleheight);
my $db = 'vicmap';
my $grid_spacing = 10000;
my $graticule_spacing = .25;
my ($ongrid, $ongraticule) = (0, 0);
my ($bleedright, $bleedtop) = (0, 0);

sub process_option($arg is copy) {
    note "Processing option $arg";
    if $arg ~~ / ^ annotation \=
                 ( \-? <[\d .]>+ )
                 <[, \s]>+ ( \-? <[\d .]>+ )
                 <[, \s]>+ ( \-? <[\d .]>+ )
                 <[, \s]>+ ( \-? <[\d .]>+ )
                 <[, \s]>+ (.*)
               / {
	add_annotation($1, $2, $3, $4, $5);
	return;
    }
# ignore whitespace in all remaining options
    $arg ~~ s:g/\s+//;
    if $arg ~~ / ^ papersize '=' (.*) / {
	$papersize = $0;
	return;
    }
    if $arg ~~ / orientation '=' (.*) / {
	$orientation = $0;
	return;
    }
    if $arg ~~ / bleedright '=' (.*) / {
	$bleedright = $0;
	$rightmarginwidth = -20;
	return;
    }
    if ($arg ~~ / bleedtop '=' (.*)/) {
	$bleedtop = $0;
	$uppermarginwidth = -10;
	return;
    }
    if ($arg ~~ /^leftmarginwidth '=' (d+(\.\d+)?)$/) {
        $leftmarginwidth = $0;
        return;
    }
    if ($arg ~~ /^rightmarginwidth '=' (d+(\.\d+)?)$/) {
        $rightmarginwidth = $0;
        return;
    }
    if ($arg ~~ /^(lower|bottom)marginwidth '=' (d+(\.\d+)?)$/) {
        $lowermarginwidth = $2;
        return;
    }
    if ($arg ~~ /^(upper|top)marginwidth '=' (d+(\.\d+)?)$/) {
        $uppermarginwidth = $2;
        return;
    }
    if ($arg ~~/d(ata)?b(ase)? '=' (.*)/) {
	$db = $3;
	return;
    }
    if $arg ~~ m/^ lat[itude]? '=' ( \-? <[\d\.]>+ ) $ / {
	$lllatitude = +$0;
	$ongraticule = 1;
	return;
    }
    if $arg ~~ m/^ long[itude]? '=' ( \-? <[\d\.]>+ ) $ / {
	$lllongitude = +$0;
	$ongraticule = 1;
	return;
    }
    if ($arg ~~ m:i/^east(ing)? '=' (\d+)(k?)m?$/) {
	$lleasting = $2;
	$lleasting *= 1000 if lc $3 eq 'k';
	$ongrid = 1;
        return;
    }
    if ($arg ~~ m:i/^north[ing]? '=' (\d+)(k?)m?$/) {
        $llnorthing = $0;
	$llnorthing *= 1000 if lc $1 eq 'k';
	$ongrid = 1;
        return;
    }
    if ($arg ~~ /^width '=' (\d+(\.\d+)?)([kK])?([dDmM]?)$/) {
	if (lc $4 eq 'm') {
	    $gridwidth = $0;
            $gridwidth *= 1000 if lc $3 eq 'k';
	    $ongrid = 1;
	    #note "Grid width: $gridwidth\n";
	} else {
	    $graticulewidth = $0;
	    $ongraticule = 1;
	}
        return;
    }
    if ($arg ~~ /^height '=' (\d+(\.\d+)?)([kK])?([dDmM]?)$/) {
	if (lc $4 eq 'm') {
	    $gridheight = $1;
            $gridheight *= 1000 if lc $3 eq 'k';
	    #note "Grid height: $gridheight\n";
	    $ongrid = 1;
	} else {
	    $graticuleheight = $1;
	    $ongraticule = 1;
	}
        return;
    }
    if ($arg ~~ m:i/^zone? '=' (\d+<[ A .. Z ]>?)$/) {
        $zone = uc $0;
	note "Zone: $zone\n";
        return;
    }
    if ($arg ~~ m:i/^scale\=(1:)?(\d+)(<[kKmM]>?)$/) {
	$scale = $2;
	$scale *= 1000 if lc $3 eq 'k';
	$scale *= 1000000 if lc $3 eq 'm';
	return;
    }
    if ($arg ~~ m/ ^ grid[spacing]? \= (\d+) (k?) m?$/) {
	$grid_spacing = $0;
	$grid_spacing *= 1000 if $1.defined && $1.lc eq 'k';
note "grid spacing: $grid_spacing ($0 \"$1\")";
	return;
    }
    if $arg ~~ m/^ graticule[spacing]? \= (\d+) (<[dDmM]>?) $/ {
note "Set graticule spacing -- $0 \"$1\"";
	$graticule_spacing = $0;
	$graticule_spacing /= 60 unless $1.lc eq 'd';
note "Graticule spacing set to $graticule_spacing";
	return;
    }
    if ($arg ~~ m:i/^display '=' all$/) {
	for keys %allobjects -> $type
	{
	    %drawobjects{$type} = 1;
	}
	return;
    }
    if ($arg ~~ m:i/^display '=' (\S+)$/) {
	%drawobjects{lc $0} = 1;
	return;
    }
    if ($arg ~~ m:i/^nodisplay '=' all$/) {
	%drawobjects = ();
	return;
    }
    if ($arg ~~ m:i/^nodisplay '=' (\S+)$/) {
	%drawobjects{lc $0} = Nil;
	return;
    }
    if ($arg ~~ m:i/^nofeature '=' (\S+)$/)
    {
        my $ft = $0;
        $ft ~~ s:g/_/ /;
        %nofeature{$ft} = 1;
        #note "No feature: $ft\n";
	return;
    }
    if ($arg ~~ m:i/^symbols '=' (\S+)$/) {
	$symbols = lc $0;
        return;
    }
    if ($arg ~~ m:i/^file '=' (.*)/) {
	#note "Including file $0\n";
        my IO::Handle $INC;
        $INC.open($0) and {
	    for $INC.lines -> $line {
		$line.chomp;
		$line ~~ s/'#' .*//;
		$line ~~ s/^\s+//;
		$line ~~ s/\s+$//;
		next unless $line;
		process_option($line);
	    }
	    $INC.close;
	}
	return;
    }
    note "Unknown option \"$arg\" ignored\n";
}

for '/home/kevinp/.drawrc', '.drawrc' -> $cfgfile {
note "Handling config file $cfgfile";
  if my $opt = $cfgfile.IO.open {
    for $opt.lines -> $line {
      s/'#' .*//;
      s/^\s+//;
      s/\s+$//;
      next unless $_;
      process_option($_);
    }
    $opt.close;
  }
}

for @*ARGS -> $arg {
    process_option($arg);
}

# Calculate various things which depend on the options

if $ongrid && $ongraticule {
    fail "Must use either grid coordinates or lat/lon; not a mixture";
}

# How much space do we have?

if (! %papersizes{$papersize}.defined) {
    fail "Invalid paper size $papersize";
}

note "Orientation is \"$orientation\"";
given $orientation {
  when 'portrait'
    { ($paperwidth, $paperheight) = %papersizes{$papersize}.split(','); }
  when 'landscape'
    { ($paperheight, $paperwidth) = %papersizes{$papersize}.split(','); }
  default
    { fail "Invalid paper orientation $orientation\n"; }
}
note "Page width: $paperwidth, height $paperheight";
$imagewidth
    = ($paperwidth  - $leftmarginwidth  - $rightmarginwidth) * $scale/1000;
$imageheight
    = ($paperheight - $lowermarginwidth - $uppermarginwidth) * $scale/1000;

# Work out where the lower left corner is

if ($ongraticule) {
    if (defined $lllongitude and defined $lllatitude) {
	my $tzone;
        if $zone.defined && $zone ne '' {
	($tzone, $lleasting, $llnorthing)
	    = latlon_to_utm_force_zone('WGS-84', $zone, $lllatitude, $lllongitude);
note "Calculated grid as $lleasting:$llnorthing from lat $lllatitude long $lllongitude zone $zone";
        } else {
	  ($zone, $lleasting, $llnorthing)
	    = latlon_to_utm('WGS-84', $lllatitude, $lllongitude);
          note "Calculated grid as $lleasting:$llnorthing from lat $lllatitude long $lllongitude calculated zone $zone";
      }
    } else {
	fail "No location specified\n";
    }
    if (!defined $graticulewidth) {
	my ($tlat, $tlong, Nil)
	    = utm_to_latlon('WGS-84', $zone, $lleasting+$imagewidth, $llnorthing);
	$graticulewidth = $tlong - $lllongitude;
note "Calculated graticule width as $tlong - $lllongitude ($lleasting $llnorthing $imagewidth) tlat = $tlat";
    }
    if (!defined $graticuleheight) {
	my ($tlat, $tlong, Nil)
	    = utm_to_latlon('WGS-84', $zone, $lleasting, $llnorthing+$imageheight);
	$graticuleheight = $tlat - $lllatitude;
    }
    $lrlongitude = $urlongitude = $lllongitude + $graticulewidth;
    $ullatitude = $urlatitude = $lllatitude + $graticuleheight;
    $ullongitude = $lllongitude;
    $lrlatitude = $lllatitude;
note "$graticulewidth: $lrlongitude $ullatitude $ullongitude $lrlatitude";
    (*, $lleasting, $llnorthing)
	= latlon_to_utm_force_zone('WGS-84', $zone, $lllatitude, $lllongitude);
    (*, $lreasting, $lrnorthing)
	= latlon_to_utm_force_zone('WGS-84', $zone, $lrlatitude, $lrlongitude);
    (*, $uleasting, $ulnorthing)
	= latlon_to_utm_force_zone('WGS-84', $zone, $ullatitude, $ullongitude);
    (*, $ureasting, $urnorthing)
	= latlon_to_utm_force_zone('WGS-84', $zone, $urlatitude, $urlongitude);
} else { # on grid
    if (!defined $lleasting or !defined $llnorthing or !defined $zone) {
	note "No location specified\n";
	exit 1;
    }
    if (!defined $gridwidth) {
	$gridwidth = $imagewidth;
    }
    if (!defined $gridheight) {
	$gridheight = $imageheight;
    }
    $ureasting = $lreasting = $lleasting + $gridwidth;
    $uleasting = $lleasting;
    $urnorthing = $ulnorthing = $llnorthing + $gridheight;
    $lrnorthing = $llnorthing;
    note "About to calculate bounding box (zone $zone)";
    ($lllatitude, $lllongitude, Nil)
	= utm_to_latlon('WGS-84', $zone, $lleasting, $llnorthing);
    ($lrlatitude, $lrlongitude, Nil)
	= utm_to_latlon('WGS-84', $zone, $lreasting, $lrnorthing);
    ($ullatitude, $ullongitude, Nil)
	= utm_to_latlon('WGS-84', $zone, $uleasting, $ulnorthing);
    ($urlatitude, $urlongitude, Nil)
	= utm_to_latlon('WGS-84', $zone, $ureasting, $urnorthing);
    note "$lllatitude $lllongitude $urlatitude $urlongitude\n";
}

if ($bleedright) {
    my (Nil, $teast, $tnorth) = latlon_to_utm_force_zone('WGS-84', $zone, $urlatitude.Real, $lllongitude.Real);
    my (Nil, $urlatitude, $urlongitude) = utm_to_latlon('WGS-84', $zone, $teast+$imagewidth, $tnorth);

}

if ($bleedtop) {
    my (Nil, $teast, $tnorth)
	= latlon_to_utm_force_zone('WGS-84', $zone, $lllatitude.Real, $urlongitude.Real);
    my (Nil, $urlatitude, $urlongitude)
	= utm_to_latlon('WGS-84', $zone, $teast+$imagewidth, $tnorth);
}

note qq:to 'EOF';
Grid corners:
    $uleasting $ulnorthing   $ureasting $urnorthing
    $lleasting $llnorthing   $lreasting $lrnorthing
EOF

  my $tmpfile = '/tmp/' ~ $*PID.Str;
  my $TMP = $tmpfile.IO.open(:a) or fail "Could not open /tmp/$*PID: $!";
  # FIX LATER unlink($tmpfile); # saves cleaning up later

print qq :to 'EOF';
\%!PS-Adobe
\% This product incorporates data which is Copyright State of Victoria 2001-2014
$papersize
72 25.4 div dup scale
EOF

say "$paperheight 0 translate 90 rotate" if $orientation eq 'landscape';

print Q:to 'EOF';
/Helvetica findfont
dup length dict begin
{ 1 index /FID ne {def} {pop pop} ifelse } forall
/Encoding ISOLatin1Encoding def
currentdict
end
/Helvetica-Latin1 exch definefont pop

/Helvetica-Narrow findfont
dup length dict begin
{ 1 index /FID ne {def} {pop pop} ifelse } forall
/Encoding ISOLatin1Encoding def
currentdict
end
/Helvetica-Narrow-Latin1 exch definefont pop

/Helvetica-Narrow-Oblique findfont
dup length dict begin
{ 1 index /FID ne {def} {pop pop} ifelse } forall
/Encoding ISOLatin1Encoding def
currentdict
end
/Helvetica-Narrow-Oblique-Latin1 exch definefont pop

/Helvetica-Narrow-BoldOblique findfont
dup length dict begin
{ 1 index /FID ne {def} {pop pop} ifelse } forall
/Encoding ISOLatin1Encoding def
currentdict
end
/Helvetica-Narrow-BoldOblique-Latin1 exch definefont pop

/Helvetica-BoldOblique findfont
dup length dict begin
{ 1 index /FID ne {def} {pop pop} ifelse } forall
/Encoding ISOLatin1Encoding def
currentdict
end
/Helvetica-BoldOblique-Latin1 exch definefont pop

EOF

#    if ($lowermarginwidth > 20) {
#	print q :to 'EOF'
#/Helvetica-Narrow-Latin1 3 selectfont
#8 8 moveto
#(This product incorporates data which is Copyright\251 State of Victoria 2001-2013) show
#EOF
#}

my %dependencies;
#my $rect;

my ($xoffset, $yoffset, $xmin, $ymin);
$xmin = $leftmarginwidth;
$ymin = $lowermarginwidth;
# The following four variables are used to do rough clipping during drawing
my ($minx, $miny, $maxx, $maxy);
$minx = $lllongitude - .001;
$maxx = $urlongitude + .001;
$miny = $lllatitude - .001;
$maxy = $urlatitude + .001;

my $xscale = 1000/$scale; # convert metres on the ground to mm on the map
my $yscale = $xscale;

my $passwd = 'xyz123';
my $dbh = DBIish.connect("Pg", user => 'ro', password => $passwd, dbname => $db);

# Get featuretypes

my $point_count = 0;
my $object_count = 0;
    
sub grid2page(Real $xin, Real $yin) {
    my $xout = $xin + $xoffset;
    my $yout = $yin + $yoffset;
    $xout *= $xscale;
    $yout *= $yscale;
    $xout += $xmin;
    $yout += $ymin;
    return ($xout, $yout);
}

sub latlon2page(Str $zone, Real $xin, Real $yin) {
    ++$point_count;
    my ($tzone, $xout, $yout) = latlon_to_utm_force_zone('WGS-84', $zone, $yin, $xin);
    return grid2page($xout, $yout);
}

sub sbsb(Int $s1, Int $b1, Str $s2, Str $b2) {
    $TMP.print: qq:to 'EOF';
/Helvetica-Latin1 4 selectfont
($b2) stringwidth pop ($b1) stringwidth pop add
/Helvetica-Latin1 2 selectfont
($s1) stringwidth pop ($s2) stringwidth pop add add
2 div neg 0 moveto
($s1) show
/Helvetica-Latin1 4 selectfont ($b1) show
/Helvetica-Latin1 2 selectfont ($s2) show
/Helvetica-Latin1 4 selectfont ($b2) show
EOF
}

sub lsbsb(Int $s1, Int $b1, Str $s2, Str $b2) {
    $TMP.print: qq:to 'EOF';
0 0 moveto
/Helvetica-Latin1 2 selectfont ($s1) show
/Helvetica-Latin1 4 selectfont ($b1) show
/Helvetica-Latin1 2 selectfont ($s2) show
/Helvetica-Latin1 4 selectfont ($b2) show
EOF
}

sub rsbsb(Int $s1, Int $b1, Str $s2, Str $b2) {
    $TMP.print: qq:to 'EOF';
/Helvetica-Latin1 4 selectfont
($b2) stringwidth pop ($b1) stringwidth pop add
/Helvetica-Latin1 2 selectfont
($s1) stringwidth pop ($s2) stringwidth pop add add
neg 0 moveto
($s1) show
/Helvetica-Latin1 4 selectfont ($b1) show
/Helvetica-Latin1 2 selectfont ($s2) show
/Helvetica-Latin1 4 selectfont ($b2) show
EOF
}

sub get_ann_string(Buf $element) {
    my $length = $element.substr(0, 4).unpack('V');
    substr($element, 0, 4) = '';
    my $string = '';
    while ($length > 0) {
	$string ~= $element.substr(0, 1);
	substr($element, 0, 2) = '';
	$length -= 2;
    }
#    $string ~~ s/\000$//;
    return ($string, $element);
}

sub get_ann_astring(Str $element) {
    my $length = ord(substr($element, 0, 1));
    substr($element, 0, 1) = '';
    my $string = substr($element, 0, $length);
    substr($element, 0, $length) = '';
    return ($string, $element);
}

sub ann_lastring(Buf $element) {
    my $length = substr($element, 0, 4).unpack('V');
    substr($element, 0, 4) = '';
    my $string = substr($element, 0, $length);
    substr($element, 0, $length) = '';
    return ($string, $element);
}

sub ann_byte(Buf $element) {
    my $val = $element.unpack('C');
    return $val;
}

sub ann_short(Buf $element) {
    my $val = $element.unpack('v');
    return $val;
}

sub ann_int(Buf $element) {
    my $val = $element.unpack('V');
    return $val;
}

sub ann_double(Buf $element) {
    my $val = $element.unpack('d');
    return $val;
}

sub ann_colour($element) {
    my ($cyan, $magenta, $yellow, $black) = $element.unpack('CCCC');
    #note "Colour: $cyan $magenta $yellow $black\n";
    $cyan /= 100;
    $magenta /= 100;
    $yellow /= 100;
    $black /= 100;
    return ($cyan, $magenta, $yellow, $black);
}

sub latlon2string($val is copy, $dirs, $full is copy) {
    my $dir;
    if ($val < 0) {
	$val = - $val;
	$dir = $dirs.substr(1, 1);
    } else {
	$dir = $dirs.substr(0, 1);
    }
    $full = 1 if $val == $val.Int;
    $val += .01;
    my $int = $val.Int;
    my $frac = $val - $int;
    my $string = '';
    $string = "$int\\260 " if $full;
    $frac = ($frac*60).Int;
    $string ~= sprintf "%02d'", $frac;
    $string ~= " $dir" if $full;
    return $string;
}

# These functions do clever things to avoid plotting too many points
# outside the clipping boundary, while not literally cutting corners
# when a line moves back inside the clip boundary.

my Bool $moveto;
my Int $quadrant = -1;
my Real $prev_x;
my Real $prev_y;

sub plot_point(Str $Zone, Real $x, Real $y, Bool $moveto) {
    my ($x1, $y1) = latlon2page $zone, $x, $y;
    $TMP.print: sprintf "%.5g %.5g %s\n", $x1, $y1, $moveto ?? 'moveto' !! 'lineto';
}

my $prev_moveto;
sub plot_previous_point(Str $zone) {
    if $prev_x.defined and $prev_y.defined && !$prev_moveto {
#	$TMP.say: "%plot_previous_point $zone $prev_x $prev_y $prev_moveto";
	plot_point($zone, $prev_x, $prev_y, $prev_moveto);
	$prev_x = (Real);
	$prev_y = (Real);
    }
}

sub add_point(Str $zone, Real $x, Real $y) {
    my $new_quadrant = 5;

    return unless $x.defined and $y.defined;

    $new_quadrant -= 1 if $x < $minx;
    $new_quadrant += 1 if $x > $maxx;
    $new_quadrant += 3 if $y < $miny;
    $new_quadrant -= 3 if $y > $maxy;
    
#    $TMP.say: "%add_point: $zone $x $y";
    if ($quadrant == 5 || $quadrant != $new_quadrant) {
	plot_previous_point($zone) if $quadrant != 5;
	plot_point($zone, $x, $y, $moveto);
	$prev_x = Nil;
	$prev_y = Nil;
	$moveto = 0;
    } else {
	$prev_x = $x;
	$prev_y = $y;
	$prev_moveto = $moveto;
    }
    $quadrant = $new_quadrant;
}

sub put_line(Str $zone, Str $shape, Str $func, Real $featurewidth) {
    $prev_x = Nil;
    $prev_y = Nil;

#note "put_line: $shape";
#    $TMP.say: "% $zone $shape";
    $shape ~~ s/^MULTILINESTRING\(\(//;
    $shape ~~ s/\)\)$//;
    my @segments = $shape.split: '\)\,?\s*\(';
    for @segments -> $segment {
#note "segment: $segment";
	$quadrant = -1;
	$moveto = True;
	my @points = $segment.split: ',';
#note "$#points points";
	for @points -> $point {
	    #note "$point";
	    #$TMP.say: "% $zone $point";
	    $point ~~ /(\-?[\d\.]+)\s+(\-?[\d\.]+)/;
	    add_point($zone, $1, $2);
	}
	plot_previous_point($zone) if $quadrant != 5;
    }
    plot_previous_point($zone) if $quadrant != 5;
    $TMP.say: "$featurewidth $func";
    %dependencies{$func}++;
}

my $sth_sym = $dbh.prepare('SELECT symbol_ga FROM vicmap_symbols WHERE type = ? AND ftype = ?');

my %symbol;

sub get_symbol(Str $type, Str $ftype) {
    return %symbol{"$type:$ftype"} if %symbol{"$type:$ftype"}.defined;
    note "Looking for $ftype($type)";
    $sth_sym.execute($type, $ftype);
    my $sym = 0;
    while ( my ($tsym) = $sth_sym.fetchrow_array()) {
	$sym = $tsym;
	note "Found $sym\n";
    }
    %symbol{"$type:$ftype"} = $sym;
    note "Unknown $type symbol $ftype" unless $sym;
    return $sym;
}

my $rect;

sub draw_areas(Str $zone, Str $table) {
    note "$table areas...";
    my $sth = $dbh.prepare("SELECT ftype_code, st_astext(the_geom) as shape FROM $table WHERE the_geom && $rect");
    
    $sth.execute();
    
    while ( my @row = $sth.fetchrow_array ) {
	my $ftype = @row[0];
	my $shape = @row[1];
	
        my $symbol = get_symbol('area', $ftype);

	next unless $symbol;
	++$object_count;
	put_line($zone, $shape, "area$symbol", '');
    }
}

my $powerlinestart = 1;
my $powerdirection = 1;
my $tickdirection = 0;

sub powerline(Real $x, Real $y, Real $angle, Real $width, Real $thick, Str $colour) {
#   $TMP.say: " % powerline: at $x, $y angle $angle";
    if ($powerlinestart) {
	$powerlinestart = 0;
	$powerdirection = 1;
	$TMP.print: "$x $y moveto\n";
    } else {
        $angle *= 3.14159265 / 180;
	my $nx = $x - $thick / 2 * sin($angle) * $powerdirection;
	my $ny = $y + $thick / 2 * cos($angle) * $powerdirection;
	$TMP.print: "$nx $ny lineto\n";
	$powerdirection = $powerdirection > 0 ?? -1 !! 1;
    }
}

sub leftticks(Real $x, Real $y, Real $angle, Real $width, Real $thick, Str $colour) {
#   note "lefttick: at $x, $y angle $angle";
    $TMP.print: "gsave $x $y translate $angle rotate $colour setcmykcolor $thick setlinewidth 0 0 moveto 0 $width lineto stroke grestore\n";
}

sub altticks(Real $x, Real $y, Real $angle, Real $width, Real $thick, Str $colour) {
    $width *= -1 if $tickdirection;
    $TMP.print: "gsave $x $y translate $angle rotate $colour setcmykcolor $thick setlinewidth 0 0 moveto 0 $width lineto stroke grestore\n";
    $tickdirection = $tickdirection ?? 0 !! 1;
}

sub follow_line(Str $zone, Str $shape, $spacing, $func, Real $width, Real $thick, Str $colour) {
    my ($oldx, $oldy);
    my $counter = $spacing / 2;

    $shape ~~ s/^MULTILINESTRING\(\(//;
    $shape ~~ s/\)\)$//;
    my @segments = $shape.split: '\)\,\s*\(';
    for @segments -> $segment {
	my @points = $segment.split: '\,\s*';
	for @points -> $point	{
	    $point ~~ /(\-?[\d\.]+)\s+(\-?[\d\.]+)/;
	    my ($x, $y) = latlon2page $zone, $1, $2;
	    if ($oldx.defined) {
		my $deltax = $x - $oldx;
		my $deltay = $y - $oldy;
		my $length = sqrt($deltax * $deltax + $deltay * $deltay);
		#note "follow_line from ($oldx, $oldy) to ($x, $y) diff ($deltax, $deltay) length $length start $counter";
		if ($length >= $counter) {
		    my $angle = atan2($deltay, $deltax) * 180 / pi;
		    loop (my $l = $counter;
		         $l <= $length;
		         $l += $spacing) {
			my $frac = $l / $length;
			my $tx = $oldx + $deltax * $frac;
			my $ty = $oldy + $deltay * $frac;
			&$func($tx, $ty, $angle, $width, $thick, $colour);
			$counter -= $spacing;
		    }
		    $counter = $l - $length;
		} else {
		    $counter -= $length;
		}
	    }
	    $oldx = $x;
	    $oldy = $y;
	}
    }
#    $TMP.say: "$featurewidth $func";
}

sub draw_ftype(Str $zone, Str $table, Int $symbol) {
    note "$table lines...\n";
    my $sth = $dbh.prepare("SELECT ftype, st_astext(the_geom) as shape FROM $table WHERE the_geom && $rect");
    
    $sth.execute();
    
    while ( my @row = $sth.fetchrow_array ) {
	my $ftype = @row[0];
	my $shape = @row[1];
	
	next unless $symbol;
	++$object_count;
	put_line($zone, $shape, "line$symbol", 0);
    }
}

sub draw_lines(Str $zone, Str $table, Int $default_symbol = 0) {
    note "$table lines...";
    my $sth = $dbh.prepare("SELECT ftype_code, st_astext(the_geom) as shape FROM $table WHERE the_geom && $rect");
    
    $sth.execute();
    
    while ( my @row = $sth.fetchrow_array ) {
	my $ftype = @row[0];
	my $shape = @row[1];
	
	my $symbol = 0;
	if (defined $default_symbol and $default_symbol < 0) {
	    $symbol = -$default_symbol;
	} else {
            $symbol = get_symbol('line', $ftype);
	}
	$symbol = $default_symbol if defined $default_symbol and ! $symbol;
	next unless $symbol;
	++$object_count;
	if ($symbol == 57) { # Depression contour (index)
	} elsif ($symbol ==  58) { # Depression contour (standard)
	    put_line($zone, $shape, "line58A", 0);
	    follow_line($zone, $shape, 4, \&leftticks, .3, .15, '0 .59 1 .18');
	} elsif ($symbol ==  31) { # Embankment
# TODO
	} elsif ($symbol == 542) { # Powerline
	    $powerlinestart = 1;
	    follow_line($zone, $shape, .5, \&powerline, .5, .2, '1 .73 0 0');
	    $TMP.say: "1 .73 0 0 setcmykcolor .2 setlinewidth stroke";
	} elsif ($symbol == 543) { # Powerline (WAC)
	    $powerlinestart = 1;
	    follow_line($zone, $shape, .5, \&powerline, .5, .2, '.79 .9 0 0');
	    $TMP.say: ".79 .9 0 0 setcmykcolor .2 setlinewidth stroke";
	} elsif ($symbol == 920) { # Cliff (WAC)
	    put_line($zone, $shape, "line920A", 0);
	    follow_line($zone, $shape, 1, \&leftticks, .4, .15, '0 .59 1 .18');
	} elsif ($symbol == 923) { # Cutting
# TODO
	} elsif ($symbol == 924) { # Cliff
	    put_line($zone, $shape, "line924A", 0);
	    follow_line($zone, $shape, 1, \&leftticks, .4, .15, '0 0 0 1');
	} elsif ($symbol == 929) { # Razorback
	    put_line($zone, $shape, "line929A", 0);
	    follow_line($zone, $shape, 1, \&altticks, .4, .15, '0 0 0 1');
	} else {
	    put_line($zone, $shape, "line$symbol", 0);
	}
    }
}

sub draw_wlines(Str $zone, Str $table, Int $default_symbol) {
    note "$table lines...";
    my $sth = $dbh.prepare("SELECT symbol, st_astext(shape) as shape, featurewidth FROM $table WHERE shape && $rect");
    
    $sth.execute();
    
    while ( my @row = $sth.fetchrow_array ) {
	my $symbol = @row[0];
	my $shape = @row[1];
	my $featurewidth = @row[3];
	$featurewidth = 0 unless defined $featurewidth && $featurewidth;
	
	if (defined $default_symbol and $default_symbol < 0) {
	    $symbol = -$default_symbol;
	}
	$symbol = $default_symbol if defined $default_symbol and ! $symbol;
	next unless $symbol;
	++$object_count;
	if ($symbol == 57) { # Depression contour (index)
	} elsif ($symbol == 58) { # Depression contour (standard)
	} elsif ($symbol == 31) { # Embankment
	} elsif ($symbol == 542) { # Powerline
	} elsif ($symbol == 543) { # Powerline (WAC)
	} elsif ($symbol == 920) { # Cliff (WAC)
	} elsif ($symbol == 923) { # Cutting
	} elsif ($symbol == 924) { # Cliff
	} elsif ($symbol == 929) { # Razorback
	} else {
	    put_line($zone, $shape, "line$symbol", $featurewidth);
	}
    }
}

# This shouldn't be here, but in a database somewhere

my %roadsymbols = (
  'road_0s'    => 250, # dual carriageway
  'road_1s'    => 251, # principal sealed
  'road_2s'    => 251, # principal sealed
  'road_3s'    => 256, # secondary sealed
  'road_4s'    => 256, # secondary sealed
  'road_5s'    => 256, # secondary sealed
  'road_6s'    => 257, # minor sealed
  'road_7s'    => 257, # minor sealed
  'road_8s'    => 257, # minor sealed
  'road_9s'    => 257, # minor sealed
  'road_10s'   => 257, # minor sealed
  'road_11s'   => 257, # minor sealed
  'road_0u'    => 258, # principal unsealed
  'road_1u'    => 258, # principal unsealed
  'road_2u'    => 258, # principal unsealed
  'road_3u'    => 259, # secondary unsealed
  'road_4u'    => 259, # secondary unsealed
  'road_5u'    => 259, # secondary unsealed
  'road_6u'    => 253, # minor unsealed
  'road_7u'    => 253, # minor unsealed
  'road_8u'    => 254, # vehicular track
  'road_9u'    => 254, # vehicular track
  'road_10u'   => 254, # vehicular track
  'road_11u'   => 254, # vehicular track
  'footbridge' => 268, # foot bridge
);

sub draw_roads(Str $zone) {
    my @dual;
    my $featurewidth;

    note "Roads...";
    my $sth = $dbh.prepare("SELECT pfi, ftype_code, class_code, dir_code, road_seal, div_rd, st_astext(the_geom) as shape FROM tr_road WHERE the_geom && $rect");
    
    $sth.execute();
    
    while ( my @row = $sth.fetchrow_array ) {
	my $objectid     = @row[0];
	my $ftype_code   = @row[1];
	my $featurewidth = 0;
        my $class        = @row[2];
        my $dir          = @row[3];
        my $sealed       = @row[4];
        my $divided      = @row[5];
	my $shape        = @row[6];
	
        $sealed = ($sealed == 1) ?? 's' !! 'u';
        my $symbol = %roadsymbols{"{$ftype_code}_$class$sealed"};
	next unless $symbol;
	@dual.push: $objectid if $symbol == 250;
	++$object_count;
	put_line($zone, $shape, "line$symbol", $featurewidth);
    }

# Now go back and draw the yellow centre line on dual carriageways

    $sth = $dbh.prepare("SELECT symbol, st_astext(shape) as shape FROM Roads WHERE objectid = ?");
    for @dual -> $objectid {
	$sth.execute($objectid);
	
	while ( my @row = $sth.fetchrow_array ) {
	    my $symbol = @row[0];
	    my $shape = @row[1];
	    
	    put_line($zone, $shape, 'line250A', $featurewidth);
	}
    }
}

# Put this in the database somewhere

my %osmroads2ga = (
    'motorway'      => 250,
    'trunk'         => 250,
    'primary'       => 250,
    'motorway_link' => 251,
    'secondary'     => 251,
    'trunk'         => 251,
    'trunl_link'    => 256,
    'tertiary'      => 256,
    'unclassified'  => 257,
    'road'          => 257,
    'service'       => 257,
    'residential'   => 257,
    'track'         => 254,
    'footway'       => 22,
    'path'          => 22,
    'cycleway'      => 22,
    );

sub draw_osmroads(Str $zone) {
    my @dual;
    my $featurewidth;

    note "OSMRoads...\n";
    my $osmdbh = DBIish.connect("dbi:Pg:dbname=osm", "", "", {AutoCommit => 0});
    my $sth = $osmdbh.prepare("SELECT objectid, type, st_astext(shape) as shape FROM HighwayWays WHERE shape && $rect");
    
    $sth.execute();
    
    while ( my @row = $sth.fetchrow_array ) {
	my $objectid = @row[0];
	my $type = @row[1];
	my $shape = @row[2];
	my $symbol = %osmroads2ga{$type};
	if ($symbol.defined) {
	    $featurewidth = 0 unless $featurewidth.defined && $featurewidth;
	    
	    next unless $symbol;
	    @dual.push: $objectid if $symbol == 250;
	    ++$object_count;
	    put_line($zone, $shape, "line$symbol", $featurewidth);
	} else {
	    note "Unknown road type $type";
	}
    }

# Now go back and draw the yellow centre line on dual carriageways

    $sth = $osmdbh.prepare("SELECT shape FROM HighwayWays WHERE objectid = ?");
    for @dual -> $objectid {
	$sth.execute($objectid);
	
	while (my @row = $sth.fetchrow_array) {
	    my $shape = @row[0];
	    
	    put_line($zone, $shape, 'line250A', $featurewidth);
	}
    }
    $osmdbh.disconnect();
}

#sub min {
#    my $a = shift;
#    my $b = shift;
#    return $a if $a <= $b;
#    return $b;
#}

#sub max {
#    my $a = shift;
#    my $b = shift;
#    return $a if $a >= $b;
#    return $b;
#}

sub draw_points(Str $zone, Str $table) {
    note "$table points...";
    my $sth = $dbh.prepare("SELECT ftype_code, st_astext(the_geom) as position, rotation FROM $table WHERE the_geom && $rect");
    
    $sth.execute();
    
    while ( my @row = $sth.fetchrow_array ) {
	my $ftype        = @row[0];
	my $position     = @row[1];
	my $orientation  = 90 - @row[2] || 0;
	my $featurewidth = 0;
	my $featuretype  = $ftype;

        my $symbol = get_symbol('point', $ftype);
	
	#next unless $display_feature[$featuretype]; ### TODO
	next unless $symbol;
	++$object_count;
	$position ~~ /\((\-?[\d\.]+)\s+(\-?[\d\.]+)\)/;
	my ($x, $y) = latlon2page $zone, $1, $2;
	%dependencies{"point$symbol"}++;
	$TMP.printf: "$orientation %.6g %.6g $featurewidth point$symbol\n", $x, $y;
    }
}

sub draw_annotations(Str $zone) {
    note "Annotations...\n";
    my $sth = $dbh.prepare("SELECT element, st_astext(shape) as shape FROM Annotations WHERE shape && $rect");
    
    $sth.execute();
    
    while ( my @row = $sth.fetchrow_array ) {
	++$object_count;
	my $element = @row[0];
	my $shape = @row[1];
	my ($string2, $string3, $font);
	my ($x1, $y1, $x2, $y2);
	my $unknown1;
	my $justn = 0;
	my ($rotangle, $xdiff, $ydiff);
	
	#{my $el = $element; while ($el) {$TMP.printf: "%02.2x ", ord(substr($el, 0, 1)); substr($el, 0, 1) = ''; } $TMP.print: "\n";}
	substr($element, 0, 54) = ''; # first 54 bytes are invariant
	($string2, $element) = get_ann_string($element);
	#note "draw_annotation: $string2\n";
	$unknown1 = substr($element, 0, 1); # What is this?
	substr($element, 0, 22) = ''; # 21 invariant bytes
	$unknown1 = substr($element, 0, 1);
	substr($element, 0, 16) = ''; # 15 invariant bytes
	$unknown1 = ann_short(substr($element, 0, 2)); substr($element, 0, 2) = '';
	$unknown1 = ann_short(substr($element, 0, 2)); substr($element, 0, 2) = '';
	my ($cyan, $magenta, $yellow, $black) = ann_colour(substr($element, 0, 4));
	#note "colour: $cyan $magenta $yellow $black\n";
	substr($element, 0, 6) = ''; # 2 invariant bytes
	$unknown1 = ann_int(substr($element, 0, 4)); substr($element, 0, 4) = '';
	substr($element, 0, 21) = '' if ($unknown1 == 0);
	$unknown1 = ann_int(substr($element, 0, 4)); substr($element, 0, 4) = '';
	$justn = ann_int(substr($element, 0, 4));
	substr($element, 0, 6) = ''; # 2 invariant bytes
	$rotangle = ann_double(substr($element, 0, 8)); substr($element, 0, 8) = '';
	$xdiff = ann_double(substr($element, 0, 8)); substr($element, 0, 8) = '';
	$ydiff = ann_double(substr($element, 0, 8)); substr($element, 0, 8) = '';
        substr($element, 0, 110) = ''; # invariant bytes
	$unknown1 = ann_short(substr($element, 0, 2)); substr($element, 0, 2) = '';
	substr($element, 0, 61) = '';
	($string3, $element) = get_ann_string($element);
	substr($element, 0, 6) = ''; # invariant
	#note "Second copy of string: $string3\n";
	my $pointsize = ord(substr($element, 0, 1)); substr($element, 0, 1) = '';
	$pointsize = $pointsize / 4 * 25.4 / 72;
	#note "Point size: $pointsize\n";
	substr($element, 0, 48) = ''; # invariant
	$unknown1 = ann_byte(substr($element, 0, 1)); substr($element, 0, 1) = '';
	$unknown1 = ann_short(substr($element, 0, 2)); substr($element, 0, 2) = '';
	$pointsize = ann_int(substr($element, 0, 4)); substr($element, 0, 4) = '';
	$pointsize = $pointsize / 10000 * 25.4 / 72;
	($font, $element) = get_ann_astring($element);
	#note "Font: $font\n";
	substr($element, 0, 18) = ''; # invariant
	$unknown1 = ann_byte(substr($element, 0, 1)); substr($element, 0, 1) = '';
	#$TMP.print: "unknown1: $unknown1\n"; ###
	if ($unknown1 == 16) {
	    substr($element, 0, 17) = ''; # invariant
	    $unknown1 = ann_short(substr($element, 0, 2)); substr($element, 0, 2) = '';
	    substr($element, 0, 6) = '';
	    $x1 = ann_double(substr($element, 0, 8)); substr($element, 0, 8) = '';
	    $y1 = ann_double(substr($element, 0, 8)); substr($element, 0, 8) = '';
	    $x2 = ann_double(substr($element, 0, 8)); substr($element, 0, 8) = '';
	    $y2 = ann_double(substr($element, 0, 8)); substr($element, 0, 8) = '';
	    #$TMP.print: "16: $x1 $y1 $x2 $y2\n"; ###
	    substr($element, 0, 4) = '';
	    my $count = ann_int(substr($element, 0, 4)); substr($element, 0, 4) = '';
	    substr($element, 0, 4) = ''; # invariant
	    #$TMP.print: "count: $count\n"; ###
	    if ($count) {
		my @coords = ();
		while ($count--) {
		    my $x = ann_double(substr($element, 0, 8)); substr($element, 0, 8) = '';
		    my $y = ann_double(substr($element, 0, 8)); substr($element, 0, 8) = '';
		    push @coords, [$x, $y];
		}
		($x1, $y1) = @(@coords[0]);
		($x2, $y2) = @(@coords[1]);
		if (%drawobjects{'annotation_position'}) {
		    my ($tx, $ty) = latlon2page($zone, $x1, $y1);
		    $TMP.print: "%%%%%%%\n$tx $ty moveto\n";
		    for @coords -> $posn {
			my ($x, $y) = @$posn;
			($tx, $ty) = latlon2page($zone, $x, $y);
			$TMP.print: "$tx $ty lineto\n";
		    }
		    $TMP.print: "1 1 0 0 setcmykcolor 0.5 setlinewidth stroke\n";
		}
		$xdiff = 0;
		$ydiff = 0;
		$justn = 0;
	    }
	} elsif ($unknown1 == 65) {
	    substr($element, 0, 17) = ''; # invariant
	    $unknown1 = ann_short(substr($element, 0, 2));
	    substr($element, 0, 8) = ''; # 6 invariant bytes
	    $x1 = ann_double(substr($element, 0, 8)); substr($element, 0, 8) = '';
	    $y1 = ann_double(substr($element, 0, 8)); substr($element, 0, 8) = '';
	    #note "65: $x1 $y1\n";
	    if (%drawobjects{'annotation_position'}) {
		my ($tx, $ty) = latlon2page $zone, $x1, $y1;
		$TMP.print: "$tx $ty moveto 1 0 rlineto 1 1 0 0 setcmykcolor 0.5 setlinewidth stroke %%%%%\n";
	    }
	    $xdiff = $ydiff = 0;
	} else {
	    note "Unknown annotation value $unknown1, ignoring\n";
	}
	substr($element, 0, 18) = '';
	(Nil, $element) = ann_lastring($element);
	substr($element, 0, 41) = ''; # $element should now be empty!
	
	# finished parsing; now print something
	
	# Check for valid location -- sometimes we gat lat/lon with NaN values!
	if ($x1 == $x1 and $y1 == $y1) {
	    $font = ($font eq 'Zurich Cn BT') ?? 'Helvetica-Narrow-Latin1' !! 'Helvetica-Latin1';
	    $TMP.printf: "/$font %.4g selectfont\n", $pointsize;
	    
	    my $annotation = $string2;
	    ($x1, $y1) = latlon2page $zone, $x1, $y1;
	    my $angle;
	    if (defined $y2) {
		($x2, $y2) = latlon2page $zone, $x2, $y2;
		$angle = atan2($y2 - $y1, $x2 - $x1) * 180 / 3.1415926535;
	    } else {
		$angle = 0;
	    }
            # $angle = $rotangle if $rotangle;
	    $annotation ~~ s:g/\\/\\\\/;
	    $annotation ~~ s:g/\(/\\\(/;
	    $annotation ~~ s:g/\)/\\\)/;
	    $TMP.printf: "gsave %.6g %.6g translate %.6g rotate 0 0 moveto %.4g %.4g %.4g %.4g setcmykcolor ", $x1+$xdiff, $y1+$ydiff, $angle, $cyan, $magenta, $yellow, $black;
	    if ($justn == 2) {
		$TMP.print: "($annotation) stringwidth pop neg 0 rmoveto ";
	    } elsif ($justn == 1) {
		$TMP.print: "($annotation) stringwidth pop 2 div neg 0 rmoveto ";
	    }
	    $TMP.printf: "($annotation) show grestore\n";
	}
    }
}

my ($starteasting, $mineasting, $maxeasting, $startnorthing, $minnorthing, $maxnorthing);

sub label_grid(Str $zone, Bool $left, Bool $right) {
    my ($x, $y1, $y2);
    my ($lat, $long, $z);
    my $easting;
# Label grid lines
# Eastings below and above
    ($lat, $long, $z) = utm_to_latlon('WGS-84', $zone, $starteasting, $minnorthing);
    ($x, $y1) = latlon2page($zone, $long, $lllatitude);
    $y1 -= 4;
    ($lat, $long, $z) = utm_to_latlon('WGS-84', $zone, $starteasting, $maxnorthing);
    ($x, $y2) = latlon2page($zone, $long, $urlatitude);
    $y2 += 1;
    $TMP.print: "gsave $x $y1 translate ";
    my $a = $starteasting / $grid_spacing;
    my $b = ($a/10).Int;
    $a -= $b*10;
    sbsb($b.Int, $a.Int, '0 000m ', 'E');
    $TMP.say: " grestore";
    $TMP.print: "gsave $x $y2 translate ";
    sbsb($b.Int, $a.Int, '0 000m ', 'E');
    $TMP.print: " grestore\n";
    $easting = $starteasting + $grid_spacing;
    
    while ($easting <= $maxeasting) {
	($lat, $long, $z) = utm_to_latlon('WGS-84', $zone, $easting, $minnorthing);
	($x, $y1) = latlon2page($zone, $long, $lllatitude);
#	($x, $y1) = grid2page($easting, $minnorthing);
	$y1 -= 4;
	($lat, $long, $z) = utm_to_latlon('WGS-84', $zone, $easting, $maxnorthing);
	($x, $y2) = latlon2page($zone, $long, $urlatitude);
#	($x, $y2) = grid2page($easting, $maxnorthing);
	$y2 += 1;
	$TMP.print: "gsave $x $y1 translate\n";
	$a = $easting / $grid_spacing;
	$b = ($a/10).Int;
	$a -= $b*10;
	sbsb($b, $a.Int, '', '');
	$TMP.print: "grestore\n";
	$TMP.print: "gsave $x $y2 translate\n";
	sbsb($b, $a.Int, '', '');
	$TMP.print: "grestore\n";
	$easting += $grid_spacing;
    }
    
# Northings
    if ($left) {
	my ($lat, $long, $z) = utm_to_latlon('WGS-84', $zone, $mineasting, $startnorthing);
	my ($x, $y) = latlon2page($zone, $lllongitude, $lat);
#	my ($x, $y) = grid2page($mineasting, $startnorthing);
	$x -= 1;
	my $a = $startnorthing / $grid_spacing;
	my $b = ($a/10).Int;
	$a -= $b * 10;
	$TMP.print: "gsave $x $y translate 90 rotate\n";
	sbsb($b, $a.Int, '0 000m ', 'N');
	$TMP.print: "grestore\n";
	my $northing = $startnorthing + $grid_spacing;
	
	while ($northing <= $maxnorthing) {
	    ($lat, $long, $z) = utm_to_latlon('WGS-84', $zone, $mineasting, $northing);
	    ($x, $y) = latlon2page($zone, $lllongitude, $lat);
#	    ($x, $y) = grid2page($mineasting, $northing);
	    $x -= 1;
	    $y -= 2;
	    $a = $northing / $grid_spacing;
	    $b = ($a/10).Int;
	    $a -= $b * 10;
	    $TMP.print: "gsave $x $y translate\n";
	    rsbsb($b, $a.Int, '', '');
	    $TMP.print: "grestore\n";
	    $northing += $grid_spacing;
	}
    }	
    if ($right) {
	my ($lat, $long, $z) = utm_to_latlon('WGS-84', $zone, $maxeasting, $startnorthing);
	my ($x, $y) = latlon2page($zone, $urlongitude, $lat);
#	my ($x, $y) = grid2page($maxeasting, $startnorthing);
	$x += 4;
	my $a = $startnorthing / $grid_spacing;
	my $b = ($a/10).Int;
	$a -= $b * 10;
	$TMP.print: "gsave $x $y translate 90 rotate\n";
	sbsb($b, $a.Int, '0 000m ', 'N');
	$TMP.print: "grestore\n";
	my $northing = $startnorthing + $grid_spacing;
	
	while ($northing <= $maxnorthing) {
	    ($lat, $long, $z) = utm_to_latlon('WGS-84', $zone, $maxeasting, $northing);
	    ($x, $y) = latlon2page($zone, $urlongitude, $lat);
#	    ($x, $y) = grid2page($maxeasting, $northing);
	    $x += 1;
	    $y -= 2;
	    $a = $northing / $grid_spacing;
	    $b = ($a/10).Int;
	    $a -= $b * 10;
	    $TMP.print: "gsave $x $y translate\n";
	    lsbsb($b, $a.Int, '', '');
	    $TMP.print: "grestore\n";
	    $northing += $grid_spacing;
	}
    }
}

sub label_graticule(Str $zone, Bool $left, Bool $right) {    
# Now label the lines of longitude and latitude:
    
    $TMP.print: "0 0 0 1 setcmykcolor /Helvetica-Latin1 4 selectfont\n";
    
    my $startlat = ($lllatitude/$graticule_spacing).Int * $graticule_spacing;
    $startlat += $graticule_spacing if $startlat < $lllatitude;
    my $startlong = ($lllongitude/$graticule_spacing).Int * $graticule_spacing;
    $startlong += $graticule_spacing if $startlong < $lllongitude;
    
# Longitude
    
    my $long = $startlong;
    
    my $first = 1;
    while ($long < $urlongitude + .0001) {
	my $lat = $lllatitude;
	my ($x, $y) = latlon2page $zone, $long, $lllatitude;
	$y -= 10;
	my $string = latlon2string($long, "EW", $first);
	$TMP.print: "$x $y moveto ($string) dup stringwidth pop 2 div neg 0 rmoveto show\n" unless ($first && ! $left);
	($x, $y) = latlon2page $zone, $long, $urlatitude;
	$y += 7;
	$TMP.print: "$x $y moveto ($string) dup stringwidth pop 2 div neg 0 rmoveto show\n" unless ($first && !$left);
	$long += $graticule_spacing;
	$first = 0;
    }
    
# Latitude
    
    if ($left) {
	my $lat = $startlat;
	
	$first = 1;
	while ($lat < $urlatitude + .0001) {
	    $TMP.print: "% Latitude $lat\n";
	    my $long = $lllongitude;
	    my ($x, $y) = latlon2page $zone, $long, $lat;
	    $x -= 7;
	    $y -= 2;
	    my $string = latlon2string $lat, "NS", $first;
	    $TMP.print: "$x $y moveto ($string) dup stringwidth pop neg 0 rmoveto show\n";
	    $lat += $graticule_spacing;
	    $first = 0;
	}
    }
    if ($right) {
	$TMP.print: "0 0 0 1 setcmykcolor /Helvetica-Latin1 4 selectfont\n";
# Latitude
	
	my $lat = $startlat;
	
	$first = 1;
	while ($lat < $urlatitude + .0001) {
	    $TMP.print: "% Latitude $lat\n";
	    my $long = $lllongitude;
	    my $string = latlon2string $lat, "NS", $first;
	    my ($x, $y) = latlon2page $zone, $urlongitude, $lat;
	    $x += 7;
	    $y -= 2;
	    $TMP.print: "$x $y moveto ($string) show\n";
	    $lat += $graticule_spacing;
	    $first = 0;
	}
    }
}

sub draw_graticule(Str $zone) {
# Now draw the lines of longitude and latitude:

    my $minlat = ($lllatitude/$graticule_spacing).Int * $graticule_spacing;
    $minlat += $graticule_spacing if $minlat < $lllatitude;
    my $minlong = ($lllongitude/$graticule_spacing).Int * $graticule_spacing;
    $minlong += $graticule_spacing if $minlong < $lllongitude;
    
# Longitude
    
    my $long = $minlong;
    
$TMP.print: "% draw graticule from $minlong, $minlat to $urlongitude, $urlatitude\n";
    while ($long < $urlongitude + .0001) {
	my $lat = $lllatitude;
	my ($x, $y) = latlon2page $zone, $long, $lat;
	$TMP.print: "% Longitude $long\n";
	$TMP.print: ".1 setlinewidth 0 0 0 1 setcmykcolor\n";
	$TMP.print: "$x $y moveto\n";
	$lat += 1.0/60.0;
	while ($lat <= $urlatitude + .0001) {
	    ($x, $y) = latlon2page $zone, $long, $lat;
	    $TMP.print: "$x $y lineto\n";
	    $lat += 1.0/60.0;
	}
	$TMP.print: "stroke\n";
	$long += $graticule_spacing;
    }
    
# Longitude ticks
    
    $long = $minlong;
    
    while ($long < $urlongitude + .0001) {
	my $lat = (($lllatitude*60).Int)/60;;
	my ($x, $y) = latlon2page $zone, $long, $lat;
	while ($lat <= $urlatitude + .0001) {
	    ($x, $y) = latlon2page $zone, $long, $lat;
	    $TMP.print: "$x $y moveto -.5 0 rlineto 1 0 rlineto stroke\n";
	    $lat += 1.0/60.0;
	}
	$TMP.print: "stroke\n";
	$long += $graticule_spacing;
    }
    
    $long = $minlong;
    
    while ($long < $urlongitude + .0001) {
	my $lat = (($lllatitude*12).Int)/12;;
	my ($x, $y) = latlon2page $zone, $long, $lat;
	while ($lat <= $urlatitude + .0001) {
	    ($x, $y) = latlon2page $zone, $long, $lat;
	    $TMP.print: "$x $y moveto -1 0 rlineto 2 0 rlineto stroke\n";
	    $lat += 5.0/60.0;
	}
	$TMP.print: "stroke\n";
	$long += $graticule_spacing;
    }
    
# Latitude
    
    my $lat = $minlat;
    
    while ($lat < $urlatitude + .0001) {
	my $long = $lllongitude;
	my ($x, $y) = latlon2page $zone, $long, $lat;
	$TMP.print: "% Latitude $lat\n";
	$TMP.print: "$x $y moveto\n";
	$long += 1.0/60.0;
	while ($long <= $urlongitude + .1) {
	    ($x, $y) = latlon2page $zone, $long, $lat;
	    $TMP.print: "$x $y lineto % $zone $long $lat\n";
	    $long += 1.0/60.0;
	}
	$TMP.print: "stroke % latitude\n";
	$lat += $graticule_spacing;
    }
    
# Latitude ticks
    
    $lat = $minlat;
    
    while ($lat < $urlatitude + .0001) {
	my $long = ($lllongitude*60).Int/60;;
	while ($long <= $urlongitude + .0001) {
	    my ($x, $y) = latlon2page $zone, $long, $lat;
	    $TMP.print: "$x $y moveto 0 -.5 rlineto 0 1 rlineto stroke\n";
	    $long += 1.0/60.0;
	}
	$TMP.print: "stroke\n";
	$lat += $graticule_spacing;
    }
    
    $lat = $minlat;
    
    while ($lat < $urlatitude + .0001) {
	my $long = ($lllongitude*12).Int/12;;
	while ($long <= $urlongitude + .0001) {
	    my ($x, $y) = latlon2page $zone, $long, $lat;
	    $TMP.print: "$x $y moveto 0 -1 rlineto 0 2 rlineto stroke\n";
	    $long += 5.0/60.0;
	}
	$TMP.print: "stroke\n";
	$lat += $graticule_spacing;
    }
}
    
sub draw_grid(Str $zone) {
# Finally draw the blue grid
    
    $TMP.say: "1 .1 0 .1 setcmykcolor\ngsave";

    $minnorthing = min($llnorthing, $lrnorthing);
    $startnorthing = (($minnorthing+($grid_spacing-1))/$grid_spacing).Int * $grid_spacing;
    $mineasting = min($lleasting, $uleasting);
    $starteasting = (($mineasting+($grid_spacing-1))/$grid_spacing).Int * $grid_spacing;
    my $maxeasting = max($lreasting, $ureasting);
    my $maxnorthing = max($ulnorthing, $urnorthing);
    
    $TMP.say: "% draw grid: $mineasting, $minnorthing to $maxeasting, $maxnorthing by $grid_spacing";
    my $easting = $starteasting;
    while ($easting <= $maxeasting) {
	my ($x1, $y1) = grid2page($easting, $minnorthing);
	my ($x2, $y2) = grid2page($easting, $maxnorthing);
	$TMP.print: "$x1 $y1 moveto $x2 $y2 lineto stroke\n";
	$easting += $grid_spacing;
    }
    
    my $northing = $startnorthing;
    while ($northing <= $maxnorthing) {
	my ($x1, $y1) = grid2page($mineasting, $northing);
	my ($x2, $y2) = grid2page($maxeasting, $northing);
	$TMP.print: "$x1 $y1 moveto $x2 $y2 lineto stroke\n";
	$northing += $grid_spacing;
    }
    $TMP.print: "grestore\n";
}

sub format_dms(Real $lat, Str $pos, Str $neg) {
    my $string = '';
    my $hemisphere = $lat >= 0 ?? $pos !! $neg;
    $lat = - $lat if $lat < 0;
    my $deg = $lat.Int;
    $lat = ($lat-$deg) * 60;
    my $min = $lat.Int;
    my $sec = ($lat-$min) * 60;
    if ($sec >= 60) {
	$min++;
	$sec -= 60;
    }
    if ($min >= 60) {
	$deg++;
	$min -= 60;
    }
    $string = sprintf "%d\\260%d'%.2f\" %s", $deg, $min, $sec, $hemisphere;
    return $string;
}

sub format_lat(Real $lat) {
    return format_dms($lat, 'N', 'S');
}

sub format_long(Real $long) {
    return format_dms($long, 'E', 'W');
}

sub put_annotation(Str $zone, Real $pagex, Real $pagey, Real $long, Real $lat, Real $x1, Real $y1, Str $string) {
    my $longstr = format_long($long);
    my $latstr = format_lat($lat);
    $string ~~ s/\$LONG/$longstr/;
    $string ~~ s/\$LAT/$latstr/;
    my @lines = $string.lines;

    my ($x2, $y2) = ($pagex, $pagey);
    #note "put_annotation: $x1 $y1 $x2 $y2";
# Calculate box height
    my $height = @lines * 2 + 2;
# Calculate box width
    $TMP.print: "gsave 0\n";
    $TMP.print: "/Helvetica-Narrow-Latin1 1.5 selectfont\n";
    for @lines -> $line {
	$TMP.say: "($line) stringwidth pop 2 copy lt \{exch\} if pop";
    }
    $TMP.print: "2 add $x2 $y2 translate 0.2 setlinewidth 0 0 0 1 setcmykcolor $x1 $y1 moveto 0 0 lineto stroke\n";
    $TMP.print: "$x1 $y1 translate dup 2 div neg $height 2 div moveto dup 0 rlineto 0 $height neg rlineto dup neg 0 rlineto closepath gsave 0 0 0 0 setcmykcolor fill grestore 0 0 0 1 setcmykcolor stroke\n";
    $TMP.print: "2 div neg 1 add $height 2 div 1.5 sub translate\n";
    for @lines -> $line {
	$TMP.print: "0 0 moveto ($line) show 0 -2 translate\n";
    }
    $TMP.print: "grestore\n";
}

my @ann;

sub draw_userannotations(Str $zone, Real $xoff, Real $yoff, Real $slope) {
    $slope *= pi / 180;
    my $c = cos($slope);
    my $s = sin($slope);
    #note "cos theta: $c, sin theta: $s";
    #note "Draw_userannotation: $zone $xoff $yoff $slope";
    for @annotations -> $ann {
	next if %($ann)<long> < $lllongitude;
        next if %($ann)<long> > $urlongitude;
        next if %($ann)<lat>  < $lllatitude;
        next if %($ann)<lat>  > $urlatitude;
        my ($x, $y) = latlon2page $zone, %($ann)<long>, %($ann)<lat>;
        my ($x1, $y1) = ($x * $c + $y * $s + $xoff * (1 - $c) - $yoff * $s,
			 -$x * $s + $y * $c + $xoff * $s + $yoff * (1-$c));
	#note "($x, $y) -> ($x1, $y1)";
        $($ann)<pagex> = $x1;
        $($ann)<pagey> = $y1;
        @ann.push: $ann;
    }
}

sub put_userannotations {
    for @ann -> $ann {
	put_annotation($zone,
		       %($ann)<pagex>,
	               %($ann)<pagey>,
		       %($ann)<long>,
                       %($ann)<lat>,
                       %($ann)<xoffset>,
                       %($ann)<yoffset>,
                       %($ann)<string>
                      );
    }
}

my ($xoff, $yoff);

sub drawit(Str $zone, Real $d_lllong, Real $d_lllat, Real $d_urlong, Real $d_urlat, Bool $left, Bool $right) {
    my ($tlllong, $turlong, $tlllat, $turlat)
	= ($lllongitude, $urlongitude, $lllatitude, $urlatitude);
    ($lllongitude, $urlongitude, $lllatitude, $urlatitude)
	= ($d_lllong, $d_urlong, $d_lllat, $d_urlat);
    note "drawit: $zone $lllongitude $lllatitude $urlongitude $urlatitude $left $right";
    my $slope;

my ($lllong, $lllat, $urlong, $urlat) = ($lllongitude - 0.01,
					$lllatitude - 0.01,
					$urlongitude + 0.01,
					$urlatitude + 0.01);

    $rect = "GeometryFromText('POLYGON(($lllong $lllat, $urlong $lllat, $urlong $urlat, $lllong $urlat, $lllong $lllat))', 4283)";
    #note $rect;

# First draw everything in the margin
    
    (*, $xoffset, $yoffset)
	= latlon_to_utm_force_zone('WGS-84', $zone, $lllatitude, $lllongitude);
    
    $xoffset = -$xoffset;
    $yoffset = -$yoffset;
    
    $TMP.say: "save 1 .1 0 .1 setcmykcolor";
	
    $minnorthing = min($llnorthing, $lrnorthing);
    $maxnorthing = max($ulnorthing, $urnorthing);
    $mineasting  = min($lleasting,  $lreasting);
    $maxeasting  = max($uleasting,  $ureasting);
    $startnorthing
	= (($minnorthing+($grid_spacing-1))/$grid_spacing).Int * $grid_spacing;
    $starteasting
	= (($mineasting+($grid_spacing-1))/$grid_spacing).Int * $grid_spacing;
    if ($ongraticule) {
	if ($left) { # Calculate slope and position of right hand side
	    my ($x1, $y1) = latlon2page($zone, $urlongitude, $lllatitude);
	    my ($x2, $y2) = latlon2page($zone, $urlongitude, $urlatitude);
	    $slope = atan2($y2-$y1, $x2-$x1) * 180 / 3.141596353 - 90;
	    #note
            #   "Right hand edge from ($x1, $y1) to ($x2, $y2, slope $slope";
	    $TMP.print: sprintf
		"$x1 $y1 translate %f rotate $x1 neg $y1 neg translate\n", -$slope;
	    $xoff = $x1;
	    $yoff = $y1;
	} else { # Calculate slope and position of left hand side
	    my ($x3, $y3) = latlon2page($zone, $lllongitude, $lllatitude);
	    my ($x4, $y4) = latlon2page($zone, $lllongitude, $urlatitude);
	    $slope = atan2($y4-$y3, $x4-$x3) * 180 / 3.141596353 - 90;
	    #note
	    #   "Left hand edge from ($x3, $y3) to ($x4, $y4), slope $slope";
	    $TMP.printf:
		"$xoff $yoff translate %f rotate $xmin neg $ymin neg translate\n", -$slope;
	}
    }
    
    label_grid($zone, $left, $right)      if %drawobjects<grid>.defined;
    label_graticule($zone, $left, $right) if %drawobjects<graticule>.defined;

# Now draw the bounding box, remembering the path which then becomes the clip path
    
    if ($ongraticule) {
	my $long = $lllongitude;
	my $lat = $lllatitude;
	my ($x, $y) = latlon2page($zone, $long, $lat);
	$TMP.say: "$x $y moveto";
	$long += 1/60;
	while $long < $urlongitude {
	    ($x, $y) = latlon2page($zone, $long, $lat);
	    $TMP.say: "$x $y lineto";
	    $long += 1/60;
	}
	$long = $urlongitude;
	($x, $y) = latlon2page($zone, $long, $lat);
	$TMP.say: "$x $y lineto"; ### moveto???
	
	$lat += 1/60;
	while ($lat <= $urlatitude) {
	    ($x, $y) = latlon2page($zone, $long, $lat);
	    $TMP.print: "$x $y lineto\n";
	    $lat += 1/60;
	}
	$lat = $urlatitude;
	($x, $y) = latlon2page($zone, $long, $lat);
	$TMP.print: "$x $y lineto\n";
	
	$long -= 1/60;
	while ($long > $lllongitude) {
	    ($x, $y) = latlon2page($zone, $long, $lat);
	    $TMP.print: "$x $y lineto\n";
	    $long -= 1/60;
	}
	$long = $lllongitude;
	($x, $y) = latlon2page($zone, $long, $lat);
	$TMP.print: "$x $y lineto\n";
	
	$lat -= 1/60;
	while ($lat > $lllatitude) {
	    ($x, $y) = latlon2page($zone, $long, $lat);
	    $TMP.print: "$x $y lineto\n";
	    $lat -= 1/60;
	}
    } else { # on grid
	my ($x, $y) = grid2page($lleasting, $llnorthing);
	$TMP.print: "$x $y moveto\n";
        ($x, $y) = grid2page($lreasting, $lrnorthing);
        $TMP.print: "$x $y lineto\n";
        ($x, $y) = grid2page($ureasting, $urnorthing);
        $TMP.print: "$x $y lineto\n";
        ($x, $y) = grid2page($uleasting, $ulnorthing);
        $TMP.print: "$x $y lineto\n";
    }

    $TMP.print: "closepath\n";
    if (%drawobjects{'graticule'}) {
	$TMP.print:
	    ".1 setlinewidth 0 0 0 1 setcmykcolor gsave stroke grestore\n";
    }
    $TMP.print: "clip newpath\n";
    
# Fetch and display all the objects
    
    for <
          hy_water_area_polygon
          hy_water_struct_area_polygon
          tr_air_infra_area_polygon
        > -> $object_type {
	if %drawobjects{$object_type.lc}.defined {
	    draw_areas($zone, $object_type);
	}
    }
    
    draw_lines($zone, 'Tracks', -1001)    if %drawobjects<tracks>.defined;
    draw_lines($zone, 'MineAreas')        if %drawobjects<mineareas>.defined;
    draw_lines($zone, 'Reserves', 65)     if %drawobjects<reserves>.defined;
    draw_lines($zone, 'Lakes', -114)      if %drawobjects<lakes>.defined;
    draw_lines($zone, 'hy_water_area_polygon', -114)
                                          if %drawobjects<hy_water_area_polygon>.defined;
    draw_lines($zone, 'Reservoirs', -114) if %drawobjects<reservoirs>.defined;
    
my %line_has_width = (
                      el_contour => 0,
                      hy_water_struct_line => 0,
                      hy_watercourse => 0,
                      tr_rail => 0,
                      tr_road => 0,
                     );

    for <
          locality_polygon
          lga_polygon
          el_contour
          hy_water_struct_line
          hy_watercourse
          tr_rail
          tr_road
        > -> $object_type {
	if %drawobjects{lc $object_type}.defined {
          if $object_type eq 'tr_road' {
            draw_roads($zone);
          } elsif $object_type eq 'OSMRoads' {
            draw_osmroads($zone);
	  } elsif $object_type eq 'lga_polygon' {
	      draw_ftype($zone, 'lga_polygon', 80);
	  } elsif $object_type eq 'locality_polygon' {
	      draw_ftype($zone, 'locality_polygon', 650);
	  } elsif %line_has_width{$object_type} {
	    draw_wlines($zone, $object_type) if %drawobjects{lc $object_type}.defined;
	  }
	  else {
	    draw_lines($zone, $object_type) if %drawobjects{lc $object_type}.defined;
	  }
        }
    }
   
    for <
          hy_water_point
          hy_water_struct_point
          tr_airport_infrastructure
          tr_rail_infrastructure
          tr_road_infrastructure
        > -> $object_type {
	if %drawobjects{lc $object_type}.defined {
	    draw_points($zone, $object_type);
	}
    }

    draw_graticule($zone) if defined %drawobjects{'graticule'};
    draw_grid($zone) if defined %drawobjects{'grid'};
#    draw_annotations($zone) if %drawobjects<annotations>.defined;

    draw_userannotations($zone, $xoff, $yoff, $slope) if %drawobjects<userannotations>.defined;

    $TMP.say: "restore"; # undo the clip path
    ($lllongitude, $urlongitude, $lllatitude, $urlatitude) = ($tlllong, $turlong, $tlllat, $turlat);
}

my ($leftzone, $rightzone);

if ($ongraticule) {
    ($leftzone, *, *)
	= latlon_to_utm('WGS-84', $lllatitude, $lllongitude+.0000001);
    ($rightzone, *, *)
	= latlon_to_utm('WGS-84', $urlatitude, $urlongitude-.0000001);
} else {
    $leftzone = $rightzone = $zone;
}

if ($leftzone eq $rightzone) {
    drawit($leftzone, $lllongitude, $lllatitude, $urlongitude, $urlatitude, True, True);
} else {
    my $boundary = $urlongitude.Int; # works for maps less than 1 degree wide -- FIX
    drawit($leftzone, $lllongitude, $lllatitude, $boundary, $urlatitude, True, False);
    drawit($rightzone, $boundary, $lllatitude, $urlongitude, $urlatitude, False, True);
}

put_userannotations();

# Print out the Postscript definitions needed by this map

my %done_deps = ();

sub do_dependency(Str $dependency) {
    return if %done_deps{$dependency}.defined;

    note "Dependency: $dependency";    
    my $sth = $dbh.prepare("SELECT dependencies, body FROM $symbols WHERE name = '$dependency'");
    
    $sth.execute();
    while ( my @row = $sth.fetchrow_array ) {
	my $deps = @row[0];
	my $body = @row[1];
	if ($deps) {
	    my @deps = $deps.words;
	    for @deps -> $dep {
		do_dependency($dep) unless %done_deps{$dep}.defined;
	    }
	}
	print $body;
	%done_deps{$dependency} = 1;
    }
}

for keys %dependencies -> $dep {
    do_dependency($dep);
}

$dbh.disconnect();

$TMP.seek(0, 0) or fail "Could not seek in TMP file: $!";
$TMP = $tmpfile.IO.open(:r);
.say for $TMP.lines;
$TMP.close;

say "showpage";

note "$object_count objects, $point_count points\n";
