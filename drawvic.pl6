#!/usr/bin/perl6

# vi: syntax=on
use v6;

use DBIish;
use Geo::Coordinates::UTM;
use NativeCall;

### Global symbol definitions

my $TMP; # file handle for temporary output

my %defaults;
my $copyright = '';

my $symbols = 'Symbols_GA'; # Which symbols set to use

my $scale = 25000; # map scale; defaults to 1:25000

# positions of map corners

my ($lllongitude, $lllatitude);
my ($lrlongitude, $lrlatitude);
my ($ullongitude, $ullatitude);
my ($urlongitude, $urlatitude);
my ($lleasting, $llnorthing);
my ($lreasting, $lrnorthing);
my ($uleasting, $ulnorthing);
my ($ureasting, $urnorthing);
my Str $zone;

my @properties;
my %dependencies;

# Should read this from the database
# YES!
#my %allobjects = map {$_ => 1}, <
#                  contour
#                  el_grnd_surface_point
#                  hy_water_area_polygon
#                  hy_water_point
#                  hy_water_struct_area_polygon
#                  hy_water_struct_line
#                  hy_water_struct_point
#                  hy_watercourse
#                  lga_polygon
#                  locality_polygon
#		  locality_name
#                  property
#                  tr_air_infra_area_polygon
#                  tr_airport_infrastructure
#                  tr_rail
#                  tr_rail_infrastructure
#                  tr_road
#                  tr_road_infrastructure
#                  tree_density
#                  graticule
#                  grid
#                  userannotations
#                 >;
#my %drawobjects = %allobjects;
my @displays; # temporary stroage for [no]display options
my %allobjects;
my %drawobjects;

my %papersizes;
my $papersize = 'a3';
my ($paperwidth, $paperheight);
my $orientation = 'landscape';

my @annotations;

sub set_papersizes() {
  # Keys are papersize, values are a string with
  # width and length in mm separated by commas.
  %papersizes = (
    'a'      => '216,   279',
    'b'      => '279,   432',
    'c'      => '432,   559',
    'd'      => '559,   864',
    'e'      => '864,   1118',
    'letter' => '215.9, 279.4',
  );

# Calculate metric A and B paper sizes
  my $sqsq2 = sqrt(sqrt(2));
  my $l = 1000 * $sqsq2;
  my $w = 1e6/$l;
# $l * $w should be 1 square metre (1e6 mm^2) with a ratio of sqrt(2)
  for ^10 -> $s {
    %papersizes{'a' ~ $s.Str} = "$w, $l";
    %papersizes{'b' ~ $s.Str} = "{$w*$sqsq2}, {$l*$sqsq2}";
    $l = $w;
    $w = $l / sqrt(2);
  }
}

my ($xoffset, $yoffset, $xmin, $ymin); # where the map actually goes on the page

sub add_annotation(Real $long, Real $lat, Real $xoffset, Real $yoffset, Str $string) {
    my $annotation = {};
    %($annotation)<long>    = $long;
    %($annotation)<lat>     = $lat;
    %($annotation)<xoffset> = $xoffset;
    %($annotation)<yoffset> = $yoffset;
    %($annotation)<string>  = $string;
    @annotations.push: $annotation;
    note "Adding annotation at $long,$lat: $string\n";
}

my ($leftmarginwidth, $lowermarginwidth, $rightmarginwidth, $uppermarginwidth)
    = (30, 25, 30, 25); # negative to bleed over page boundary
my ($imagewidth, $imageheight);
my ($gridwidth, $graticulewidth);
my ($gridheight, $graticuleheight);
my $db = 'vicmap'; # which database to access
my $grid_spacing = 1000; # spacing betwen grid lines in metres
my $graticule_spacing = 1.0/60; # spacing between graticule lines in degrees
my (Bool $ongrid, Bool $ongraticule) = (False, False);
my (Bool $bleedright, Bool $bleedtop) = (False, False);

sub process_option($arg is copy) {
    note "Processing option $arg";
    if $arg ~~ m:i/ ^ annotation \=
                 ( \-? <[\d .]>+ )
                 <[, \s]>+ ( \-? <[\d .]>+ )
                 <[, \s]>+ ( \-? <[\d .]>+ )
                 <[, \s]>+ ( \-? <[\d .]>+ )
                 <[, \s]>+ (.*)
               / {
	add_annotation(+$0, +$1, +$2, +$3, ~$4);
	return;
    }
# ignore whitespace in all remaining options
    $arg ~~ s:g/\s+//;
    given $arg {
    when m:i/ ^ pa[per|ge]size '=' (.*) / {
	$papersize = $0;
    }
    when m:i/ orientation '=' (.*) / {
	$orientation = $0;
    }
    when m:i/ bleedright '=' (.*) / {
	$bleedright = ?$0;
	$rightmarginwidth = -20; # FIXME (only if turning bleeding on!)
    }
    when m:i/ bleedtop '=' (.*)/ {
	$bleedtop = ?$0;
	$uppermarginwidth = -10; # FIXME
    }
    when m:i/^leftmarginwidth '=' (d+[\.\d+]?)$/ {
        $leftmarginwidth = $0;
    }
    when m:i/^rightmarginwidth '=' (d+[\.\d+]?)$/ {
        $rightmarginwidth = $0;
    }
    when m:i/^(lower|bottom)marginwidth '=' (d+[\.\d+]?)$/ {
        $lowermarginwidth = $2;
    }
    when m:i/^(upper|top)marginwidth '=' (d+[\.\d+]?)$/ {
        $uppermarginwidth = $2;
    }
    when m:i/d[ata]?b[ase]? '=' (.*)/ {
	$db = $0;
    }
    when m:i/^ lat[itude]? '=' ( \-? <[\d\.]>+ ) $ / {
	$lllatitude = +$0;
	$ongraticule = True;
    }
    when m:i/^ long[itude]? '=' ( \-? <[\d\.]>+ ) $ / {
	$lllongitude = +$0;
	$ongraticule = True;
    }
    when m:i/^east[ing]? '=' (\d+)(k?)m?$/ {
	$lleasting = $0;
	$lleasting *= 1000 if $1.lc eq 'k';
	$ongrid = True;
    }
    when m:i/^north[ing]? '=' (\d+)(k?)m?$/ {
        $llnorthing = $0;
	$llnorthing *= 1000 if $1.lc eq 'k';
	$ongrid = True;
    }
    when m:i/^width '=' (\d+[\.\d+]?)([kK])?([dDmM]?)$/ {
	if ($2.lc eq 'm') {
	    $gridwidth = $0;
            $gridwidth *= 1000 if $1.lc eq 'k';
	    $ongrid = True;
	} else {
	    $graticulewidth = $0;
	    $ongraticule = True;
	}
    }
    when m:i/^height '=' (\d+[\.\d+]?)([kK])?([dDmM]?)$/ {
	if ($2.lc eq 'm') {
	    $gridheight = $0;
            $gridheight *= 1000 if $1.lc eq 'k';
	    $ongrid = True;
	} else {
	    $graticuleheight = $0;
	    $ongraticule = True;
	}
    }
    when m:i/^zone? '=' (\d+<[ A .. Z ]>?)$/ {
        $zone = $0.uc;
	note "Zone: $zone\n";
    }
    when m:i/^scale\=[1:]?(\d+)(<[kKmM]>?)$/ {
	$scale = $0;
	$scale *= 1000    if $1.lc eq 'k';
	$scale *= 1000000 if $1.lc eq 'm';
    }
    when m:i/ ^ grid[spacing]? \= (\d+) (k?) m?$/ {
	$grid_spacing = $0;
	$grid_spacing *= 1000 if $1.defined && $1.lc eq 'k';
    }
    when m:i/^ graticule[spacing]? \= (\d+) (<[dDmM]>?) $/ {
	$graticule_spacing = $0;
	$graticule_spacing /= 60 unless $1.lc eq 'd';
    }
    when m:i/^[no]?display '=' (\S+)$/ {
        @displays.push: $arg;
    }
    when m:i/^symbols '=' (\S+)$/ {
	$symbols = $0.lc;
    }
    when m:i/^property \= (<[\d,]>+) / {
       @properties.push: $0.split(',');
    }
    when m:i/^file '=' (.*)/ {
        my $includefile = $0;
        my $INC = $includefile.IO.open(:r) and {
	    for $INC.lines -> $line {
		$line ~~ s/'#' .*//;
		$line ~~ s/^\s+//;
		$line ~~ s/\s+$//;
		next unless $line;
		process_option($line);
	    }
	    $INC.close;
	}
    }
    default { note "Unknown option \"$arg\" ignored\n"; }
  }
}

sub postscript_encode_font(Str $font) {
  print qq:to 'EOF';
    /{$font} findfont
    dup length dict begin
    \{ 1 index /FID ne \{def} \{pop pop} ifelse } forall
    /Encoding ISOLatin1Encoding def
    currentdict
    end
    /{$font}-Latin1 exch definefont pop
    EOF
}

sub postscript_prefix() {
  print qq :to 'EOF';
\%!PS-Adobe
\%! $copyright
$papersize
72 25.4 div dup scale
EOF

  say "$paperheight 0 translate 90 rotate" if $orientation eq 'landscape';

  postscript_encode_font('Helvetica');
  postscript_encode_font('Helvetica-Narrow');
  postscript_encode_font('Helvetica-Narrow-Oblique');
  postscript_encode_font('Helvetica-Narrow-BoldOblique');
  postscript_encode_font('Helvetica-BoldOblique');
#  postscript_encode_font('Helvetica'); # was this meant to be something else???

  if ($lowermarginwidth > 20) {
    print qq :to 'EOF'
      /Helvetica-Narrow-Latin1 3 selectfont
      8 8 moveto
      ($copyright) show
    EOF
  }
}

sub read_points (Str $shape) {
  if $shape ~~ /^POLYGON\(\(/ {
    $shape.comb(/ <[+-]>? \d+ [ '.' \d+ ]/ );
  } else {
    note "Unknown shape in $shape";
  }
}

my $point_count = 0;
my $object_count = 0;
my $xscale;
my $yscale;
    
sub grid2page(Real $xin, Real $yin) {
  ( ($xin + $xoffset) * $xscale + $xmin,
           ($yin + $yoffset) * $yscale + $ymin);
}

sub latlon2page(Real $xin, Real $yin) {
    ++$point_count;
    my ($tzone, $xout, $yout) = latlon_to_utm('WGS-84', :$zone, $yin, $xin);
# inline grid2page for speed
    #return grid2page($xout, $yout);
  ( ($xout + $xoffset) * $xscale + $xmin,
           ($yout + $yoffset) * $yscale + $ymin);
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
    $string = "$int\\260 " if $full; # Assumes Latin1, not UTF8
    $frac = ($frac*60).Int;
    $string ~= sprintf "%02d'", $frac;
    $string ~= " $dir" if $full;
    $string;
}

# These functions do clever things to avoid plotting too many points
# outside the clipping boundary, while not literally cutting corners
# when a line moves back inside the clip boundary.

my Bool $moveto;
my Int  $quadrant = -1;
my Real $prev_x;
my Real $prev_y;

sub plot_point(Real $x, Real $y, Bool $moveto) {
    my ($x1, $y1) = latlon2page $x, $y;
    $TMP.print: sprintf "%.5g %.5g %s\n", $x1, $y1, $moveto ?? 'moveto' !! 'lineto';
}

my $prev_moveto;
sub plot_previous_point() {
    if $prev_x.defined and $prev_y.defined && !$prev_moveto {
	plot_point($prev_x, $prev_y, $prev_moveto);
	$prev_x = (Real);
	$prev_y = (Real);
    }
}

my ($minx, $miny, $maxx, $maxy);

sub add_point(Real $x, Real $y) {
    my $new_quadrant = 5;

    return unless $x.defined and $y.defined;

    $new_quadrant -= 1 if $x < $minx;
    $new_quadrant += 1 if $x > $maxx;
    $new_quadrant += 3 if $y < $miny;
    $new_quadrant -= 3 if $y > $maxy;
    
    if ($quadrant == 5 || $quadrant != $new_quadrant) {
	plot_previous_point() if $quadrant != 5;
	plot_point($x, $y, $moveto);
	$prev_x = Nil;
	$prev_y = Nil;
	$moveto = False;
    } else {
	$prev_x = $x;
	$prev_y = $y;
	$prev_moveto = $moveto;
    }
    $quadrant = $new_quadrant;
}

sub put_line(Str $shape is copy, Str $func, $featurewidth = '') {
    $prev_x = Nil;
    $prev_y = Nil;

    my @segments = $shape.split: '),(';
#$TMP.print: "% ",  $shape, "\n";
    my $segno = 1;
    for @segments -> $segment {
$TMP.print: "% Segment ", $segno++, "\n";
	$quadrant = -1;
	$moveto = True;
        for $segment.comb: /\-?<[\d\.]>+/ -> $x, $y { # just extract the numbers and ignore anything else
	  add_point(+$x, +$y);
	}
	plot_previous_point() if $quadrant != 5;
    }
    plot_previous_point() if $quadrant != 5;
    $TMP.say: "$featurewidth $func";
    %dependencies{$func}++;
}

my $dbh;
my $sth_sym;

use experimental :cached;
sub get_symbol (Str $type, Str $ftype) is cached {
  my $symbol = 0;
  note "Looking for $ftype\($type)";
  $sth_sym.execute($type, $ftype);
  my $sym = 0;
  while my @row = $sth_sym.fetchrow_array {
    $sym = @row[0].Int;
    next unless $sym;
    $symbol = $sym;
    note "Found $sym";
  }
  if !$symbol {
    note "Unknown $type symbol $ftype";
  }
  $symbol;
}

my $rect;

sub draw_areas(Str $table) {
  note "$table areas...";
  my $geomcol = %defaults{'areageometry'};
  my $sth = $dbh.prepare("SELECT ftype_code, st_astext($geomcol) as shape FROM $table WHERE $geomcol && $rect");
  
  if $sth.execute {
    
    while my @row = $sth.fetchrow_array {
      my $ftype = @row[0];
      my $shape = @row[1];
      
     my $ft = '';
     $ft ~= $ftype;
      my $symbol = get_symbol 'area', $ft;
      
      next unless $symbol;
      ++$object_count;
      put_line($shape, "area$symbol");
    }
  } else {
    note "$table not found";
  }
}

sub draw_ga_areas(Str $table) {
  note "$table areas...";
  my $geomcol = %defaults<areageometry>;
  my $sth = $dbh.prepare("SELECT symbol, st_astext($geomcol) as shape FROM $table WHERE $geomcol && $rect");
  
  if $sth.execute {
    
    while my @row = $sth.fetchrow_array {
      my $symbol = @row[0].Int;
      my $shape = @row[1];
      
      next unless so $symbol;
      ++$object_count;
      put_line($shape, "area$symbol");
    }
  } else {
    note "$table not found";
  }
}

sub draw_treeden() {
  note "tree_density areas...";
  my $geomcol = %defaults{'areageometry'};
  my $sth = $dbh.prepare("SELECT ftype_code, tree_den, st_astext($geomcol) as shape FROM tree_density where $geomcol && $rect", RaiseError => 0);

  if $sth.execute {
    
    while my @row = $sth.fetchrow_array {
      my $ftype = @row[0];
      my $density = @row[1];
      my $shape = @row[2];
   
      my $symbol = get_symbol('area', ([~] $ftype, '_', $density).Str.lc);
      
      next unless $symbol;
      ++$object_count;
      put_line($shape, "area$symbol");
    }
  } else {
    note "Table tree_density not found";
  }
}

my $powerlinestart = 1;
my $powerdirection = 1;
my $tickdirection = 0;

sub powerline(Real $x, Real $y, Real $angle, Real $width, Real $thick, Str $colour) {
    if ($powerlinestart) {
	$powerlinestart = 0;
	$powerdirection = 1;
	$TMP.say: "$x $y moveto";
    } else {
        $angle *= pi / 180;
	my $nx = $x - $thick / 2 * sin($angle) * $powerdirection;
	my $ny = $y + $thick / 2 * cos($angle) * $powerdirection;
	$TMP.say: "$nx $ny lineto";
	$powerdirection = $powerdirection > 0 ?? -1 !! 1;
    }
}

sub leftticks(Real $x, Real $y, Real $angle, Real $width, Real $thick, Str $colour) {
    $TMP.say: "gsave $x $y translate $angle rotate $colour setcmykcolor $thick setlinewidth 0 0 moveto 0 $width lineto stroke grestore";
}

sub altticks(Real $x, Real $y, Real $angle, Real $width is rw, Real $thick, Str $colour) {
    $width *= -1 if $tickdirection;
    $TMP.say: "gsave $x $y translate $angle rotate $colour setcmykcolor $thick setlinewidth 0 0 moveto 0 $width lineto stroke grestore";
    $tickdirection = ! $tickdirection;
}

sub follow_line(Str $shape, $spacing, $func, Real $width, Real $thick, Str $colour) {
    my ($oldx, $oldy);
    my $counter = $spacing / 2;

    my @segments = $shape.split: '\)\,\s*\(';
    for @segments -> $segment {
	for $segment.comb(/(\-?<[\d.]>+)/) -> $lx, $ly {
	    my ($x, $y) = latlon2page $lx.Num, $ly.Num;
	    if ($oldx.defined) {
		my $deltax = $x - $oldx;
		my $deltay = $y - $oldy;
		my $length = sqrt($deltax * $deltax + $deltay * $deltay);
		if ($length >= $counter) {
		    my $angle = atan2($deltay, $deltax) * 180 / π;
		    loop (my $l  = $counter;
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
}

sub draw_lines(Str $table, Str $typecolumn, Int $default_symbol = 0) {
  note "$table lines...";
  my $geomcol = %defaults{'linegeometry'};
note "draw_lines: geomcol is $geomcol";
  my $sth = $dbh.prepare("SELECT $geomcol, st_astext($geomcol) as shape FROM $table WHERE $geomcol && $rect");
  
  if $sth.execute {
    
    while my @row = $sth.fetchrow_array {
      my $ftype = @row[0];
      my $shape = @row[1];
      
      my $ft = '';
      $ft ~= $ftype;
      my $symbol = 0;
      if ($default_symbol.defined and $default_symbol < 0) {
	$symbol = -$default_symbol;
      } else {
	$symbol = get_symbol('line', $ft);
      }
      $symbol = $default_symbol if $default_symbol.defined and ! $symbol;
      next unless $symbol;
      ++$object_count;
      given $symbol {
        when  57 {} # Depression contour (index)
        when  58 { # Depression contour (standard)
          put_line($shape, "line58A", 0);
	  follow_line($shape, 4, &leftticks, .3, .15, '0 .59 1 .18');
        }
	when  31 {} # Embankment
        when 542 { # Powerline
          $powerlinestart = 1;
          follow_line($shape, .5, &powerline, .5, .2, '1 .73 0 0');
          $TMP.say: "1 .73 0 0 setcmykcolor .2 setlinewidth stroke";
        }
	when 543 { # Powerline (WAC)
          $powerlinestart = 1;
          follow_line($shape, .5, &powerline, .5, .2, '.79 .9 0 0');
          $TMP.say: ".79 .9 0 0 setcmykcolor .2 setlinewidth stroke";
        }
	when 920 { # Cliff (WAC)
          put_line($shape, "line920A", 0);
          follow_line($shape, 1, &leftticks, .4, .15, '0 .59 1 .18');
        }
	when 923 {} # Cutting
        when 924 { # Cliff
          put_line($shape, "line924A", 0);
          follow_line($shape, 1, &leftticks, .4, .15, '0 0 0 1');
        }
	when 929 { # Razorback
          put_line($shape, "line929A", 0);
          follow_line($shape, 1, &altticks, .4, .15, '0 0 0 1');
        }
	default {
          put_line($shape.Str, "line$symbol", 0);
        }
      }
    }
  } else {
    note "Table $table not found";
  }
}

sub draw_ga_lines(Str $table, Str $typecolumn, Int $default_symbol = 0) {
  note "$table ($default_symbol) lines...";
  my $geomcol = %defaults{'linegeometry'};
#note "Reading column $geomcol ($rect)";
  my $sth = $dbh.prepare("SELECT symbol, st_astext($geomcol) as shape FROM $table WHERE $geomcol && $rect");
  
  if $sth.execute {
    
    while my @row = $sth.fetchrow_array {
      my $symbol = @row[0].Int;
      my $shape = @row[1];
      
#note $symbol;
      if $default_symbol > 0 {
        note "Changing symbol type from $symbol to $default_symbol";
	$symbol = $default_symbol;
      }
      next unless so $symbol;
      ++$object_count;
      given $symbol {
        when  57 {} # Depression contour (index)
        when  58 { # Depression contour (standard)
          put_line($shape, "line58A", 0);
	  follow_line($shape, 4, &leftticks, .3, .15, '0 .59 1 .18');
        }
	when  31 {} # Embankment
        when 542 { # Powerline
          $powerlinestart = 1;
          follow_line($shape, .5, &powerline, .5, .2, '1 .73 0 0');
          $TMP.say: "1 .73 0 0 setcmykcolor .2 setlinewidth stroke";
        }
	when 543 { # Powerline (WAC)
          $powerlinestart = 1;
          follow_line($shape, .5, &powerline, .5, .2, '.79 .9 0 0');
          $TMP.say: ".79 .9 0 0 setcmykcolor .2 setlinewidth stroke";
        }
	when 920 { # Cliff (WAC)
          put_line($shape, "line920A", 0);
          follow_line($shape, 1, &leftticks, .4, .15, '0 .59 1 .18');
        }
	when 923 {} # Cutting
        when 924 { # Cliff
          put_line($shape, "line924A", 0);
          follow_line($shape, 1, &leftticks, .4, .15, '0 0 0 1');
        }
	when 929 { # Razorback
          put_line($shape, "line929A", 0);
          follow_line($shape, 1, &altticks, .4, .15, '0 0 0 1');
        }
	default {
          put_line($shape.Str, "line$symbol", 0);
        }
      }
    }
  } else {
    note "Table $table not found";
  }
}

sub put_outline(Str $text, Real $x, Real $y, Real $size, Str $colour, Real $thickness) { 
    $TMP.print: sprintf "%f %f moveto (%s) /Helvetica findfont %f scalefont setfont stringwidth pop 2 div neg 0 rmoveto (%s) false charpath %s setcmykcolor %f setlinewidth stroke\n", $x, $y, $text, $size, $text, $colour, $thickness;
}

sub draw_polygon_outline_names(Str $table, Str $column, Real $size, Real $thickness, Str $colour) {
  note "$table outline names...";
  my $geomcol = %defaults{'line'};
  my $sth = $dbh.prepare("SELECT $column, st_astext(st_envelope($geomcol)) as bbox FROM $table WHERE $geomcol && $rect");
  
  if $sth.execute {
    
    while my @row = $sth.fetchrow_array {
      last unless @row[0].defined;

      my $name  = @row[0].Str;
      my $shape = @row[1].Str;
      my @x = read_points($shape);
      my $centrex = (@x[0] + @x[4]) / 2;
      my $centrey = (@x[1] + @x[5]) / 2;
#      note "Locality $name $centrex $centrey $shape";
      my ($cx, $cy) = latlon2page($centrex, $centrey);
      my @text = $name.split: ' ';
      my $yoffset = (@text.end + 1)/2;
      for @text -> $text {
			  put_outline $text, $cx, $cy+$yoffset, $size, $colour, $thickness;
			  $yoffset -= $size;
			 }
        ++$object_count;
    }
  } else {
    note "Table $table not found";
  }
}

sub draw_properties() {
    note "property lines...";
  my $geomcol = %defaults{'linegeometry'};
    my $sth = $dbh.prepare("SELECT st_astext($geomcol) as shape FROM property_view WHERE pfi = ?");
    
    for @properties -> $property {
        $sth.execute($property);
    
        while my @row = $sth.fetchrow_array {
            my $shape = @row[0];
            ++$object_count;
            put_line($shape, 'line927', 0);
        }
    }
}

sub draw_ga_wlines(Str $table) {
    note "$table lines...";
   my $sth = $dbh.prepare("SELECT symbol, st_astext(shape) as shape, featurewidth FROM $table WHERE shape && $rect");
    
    $sth.execute();
    
    while ( my @row = $sth.fetchrow_array ) {
	my $symbol = @row[0].Int;
	my $shape = @row[1];
	my $featurewidth = @row[3];
	$featurewidth = 0 unless $featurewidth.defined && $featurewidth;
	
	next unless so $symbol;
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
	    put_line($shape, "line$symbol", $featurewidth);
	}
    }
}

sub draw_ga_wlines_orig(Str $table, Int $default_symbol) {
    note "$table lines...";
    my $sth = $dbh.prepare("SELECT symbol, st_astext(shape) as shape, featurewidth FROM $table WHERE shape && $rect");
    
    $sth.execute();
    
    while ( my @row = $sth.fetchrow_array ) {
	my $symbol = @row[0].Int;
	my $shape = @row[1];
	my Real $featurewidth = @row[3];
	$featurewidth = 0 unless $featurewidth.defined && $featurewidth;
	
	if ($default_symbol.defined and $default_symbol < 0) {
	    $symbol = -$default_symbol;
	}
	$symbol = $default_symbol if $default_symbol.defined and ! $symbol;
	next unless so $symbol;
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
	    put_line($shape, "line$symbol", $featurewidth);
	}
    }
}

# This shouldn't be here, but in a database somewhere

my %roadsymbols = (
  'road_0s'     => 250, # dual carriageway
  'road_1s'     => 251, # principal sealed
  'road_2s'     => 251, # principal sealed
  'road_3s'     => 256, # secondary sealed
  'road_4s'     => 256, # secondary sealed
  'road_5s'     => 256, # secondary sealed
  'road_6s'     => 257, # minor sealed
  'road_7s'     => 257, # minor sealed
  'road_8s'     => 257, # minor sealed
  'road_9s'     => 257, # minor sealed
  'road_10s'    => 257, # minor sealed
  'road_11s'    => 257, # minor sealed
  'road_12s'    =>  22, # minor sealed
  'road_0u'     => 258, # principal unsealed
  'road_1u'     => 258, # principal unsealed
  'road_2u'     => 258, # principal unsealed
  'road_3u'     => 259, # secondary unsealed
  'road_4u'     => 259, # secondary unsealed
  'road_5u'     => 259, # secondary unsealed
  'road_6u'     => 253, # minor unsealed
  'road_7u'     => 253, # minor unsealed
  'road_8u'     => 254, # vehicular track
  'road_9u'     => 254, # vehicular track
  'road_10u'    => 254, # vehicular track
  'road_11u'    => 254, # vehicular track
  'road_12u'    =>  22, # foot track
  'footbridge'  => 268, # foot bridge
  'foot_bridge' => 268, # foot bridge
  'ford'        => 253,
  'bridge_0s'   => 260, # bridge
  'bridge_1s'   => 260, # bridge
  'bridge_2s'   => 260, # bridge
  'bridge_3s'   => 260, # bridge
  'bridge_4s'   => 260, # bridge
  'bridge_5s'   => 260, # bridge
  'bridge_6s'   => 260, # bridge
  'bridge_5u'   => 260, # bridge
  'bridge_6u'   => 260, # bridge
  'bridge'      => 260, # bridge
  'connector'   =>   0,
  'roundabout'  => 256,
);

sub draw_roads() {
    my @dual;
    my $featurewidth;

    note "Roads...";
    my $geomcol = %defaults{'linegeometry'};
#    my $sth = $dbh.prepare("SELECT pfi, ftype_code, class_code, dir_code, road_seal, div_rd, st_astext($geomcol) as shape FROM tr_road WHERE $geomcol && $rect");
#    my $sth = $dbh.prepare("SELECT ga_pid, ftype_code, class_code, dir_code, road_seal, div_rd, st_astext($geomcol) as shape FROM roads WHERE $geomcol && $rect");
    my $sth = $dbh.prepare("SELECT ga_pid, ftype_code, class_code, dir_code, road_seal, div_rd, $geomcol as shape FROM roads WHERE $geomcol && $rect");
    
    $sth.execute();
    
    while my @row = $sth.fetchrow_array {

	my $objectid     = @row[0];
	my $ftype_code   = @row[1];
	my $featurewidth = 0.9;
        my $class        = @row[2];
        my $dir          = @row[3];
        my $sealed       = @row[4];
        my $divided      = @row[5];
	my $shape        = @row[6];
	
        $sealed = ($sealed == 1) ?? 's' !! 'u';
        my $symbol = %roadsymbols{"{$ftype_code}"}; # get default
        $symbol = %roadsymbols{"{$ftype_code}_$class$sealed"};
	note "Unknown road type \"{$ftype_code}_$class$sealed\"" unless $symbol;
	next unless $symbol;
	@dual.push: $objectid if $symbol == 250;
	++$object_count;
	put_line($shape, "line$symbol", $featurewidth);
    }

# Now go back and draw the yellow centre line on dual carriageways

    note "Centre lines of roads...";

    $sth = $dbh.prepare("SELECT ftype_code, st_astext(geom) as shape FROM tr_road WHERE pfi = ?");
    for @dual -> $objectid {
	$sth.execute($objectid);
	
	while my @row = $sth.fetchrow_array {
	    my $symbol = @row[0];
	    my $shape = @row[1];
	    $featurewidth = 0.6;
	    
	    put_line($shape, 'line250A', $featurewidth);
	}
    }
}

sub draw_ga_roads() {
    my @dual;
    my $featurewidth;

    note "Roads...";
    my $geomcol = %defaults{'linegeometry'};
    my $sth = $dbh.prepare("SELECT objectid, symbol, featurewidth,  st_astext($geomcol) as shape FROM roads WHERE $geomcol && $rect");
    
    $sth.execute();
    
    while my @row = $sth.fetchrow_array {

	my $objectid     = @row[0];
	my $symbol       = @row[1].Int;
        my $featurewidth = @row[2];
	my $shape        = @row[3];
	$featurewidth = 0 unless $featurewidth.defined && $featurewidth;
	
	next unless so $symbol;
	@dual.push: $objectid if $symbol == 250;
	++$object_count;
	put_line($shape, "line$symbol", $featurewidth);
    }

# Now go back and draw the yellow centre line on dual carriageways

    note "Centre lines of roads...";

    $sth = $dbh.prepare("SELECT symbol, shape FROM Roads WHERE objectid = ?");
    for @dual -> $objectid {
	$sth.execute($objectid);
	
	while my @row = $sth.fetchrow_array {
	    my $symbol = @row[0];
	    my $shape = @row[1];
#	    $featurewidth = 0.6;
	    
	    put_line($shape, 'line250A', $featurewidth);
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

sub draw_osmroads() {
    my @dual;
    my $featurewidth = 0;

    note "OSMRoads...\n";
    my $osmdbh = DBIish.connect("Pg", dbname => 'osm', RaiseError => 0); # or die $DBIish::errstr;
    #my $osmdbh = DBIish.connect("dbi:Pg:dbname=osm", "", "", {AutoCommit => 0});
    my $sth = $osmdbh.prepare("SELECT osm_id, highway, st_astext(way) as shape FROM planet_osm_line WHERE highway IS NOT NULL AND way && $rect");
    
    $sth.execute();
    
    while my @row = $sth.fetchrow_array {
	my $objectid = @row[0];
	my $type = @row[1];
	my $shape = @row[2];
	my $symbol = %osmroads2ga{$type};
	if ($symbol.defined) {
	    $featurewidth = 0 unless $featurewidth.defined && $featurewidth;
	    
	    next unless $symbol;
	    @dual.push: $objectid if $symbol == 250;
	    ++$object_count;
	    put_line($shape, "line$symbol", $featurewidth);
	} else {
	    note "Unknown road type $type";
	}
    }

# Now go back and draw the yellow centre line on dual carriageways

    $sth = $osmdbh.prepare("SELECT st_astext(way) as shape FROM planet_osm_line WHERE osm_id = ?");
    for @dual -> $objectid {
	$sth.execute($objectid);
	
	while (my @row = $sth.fetchrow_array) {
	    my $shape = @row[0];
	    
	    put_line($shape, 'line250A', $featurewidth);
	}
    }
    $osmdbh.disconnect();
}

sub draw_points(Str $table, Str $column) {
    note "$table points...";
  my $geomcol = %defaults{'pointgeometry'};

  #my $sth = $dbh.prepare("SELECT $column, st_astext($geomcol) AS position, rotation
  my $sth = $dbh.prepare("SELECT $column, $geomcol AS position, rotation
                            FROM $table
			    WHERE {%defaults{'pointgeometry'}} && $rect
			   ");
    
    $sth.execute();
    
      while my @row = $sth.fetchrow_array {
	my $ftype        = @row[0];
	my $position     = @row[1];
	my $orientation  = 90 - @row[2] || 0;
	my $featurewidth = 0;
	my $featuretype  = $ftype;

	my $ft = '';
        $ft ~= $ftype;
        my $symbol = get_symbol('point', $ft);
	
	#next unless @display_feature[$featuretype]; ### TODO
	next unless $symbol;
	++$object_count;
	$position ~~ / \( ( \-? <[\d\.]>+) \s+ ( \-? <[\d\.]>+ ) \) /;
	my ($x, $y) = latlon2page +$0, +$1;
	%dependencies{"point$symbol"}++;
	$TMP.print: sprintf("$orientation %.6g %.6g $featurewidth point$symbol\n", $x, $y);
    }
}

sub draw_ga_points(Str $table) {
    note "$table points...";
  my $geomcol = %defaults{'pointgeometry'};

  my $sth = $dbh.prepare("SELECT symbol, st_astext($geomcol) AS position, orientation, featurewidth
                            FROM $table
			    WHERE $geomcol && $rect
			   ");
    
    $sth.execute();
    
      while my @row = $sth.fetchrow_array {
	my $symbol       = @row[0].Int;
	my $position     = @row[1];
	my $orientation  = @row[2] || 0;
	my $featurewidth = @row[3];
	$featurewidth = 0 unless $featurewidth.defined && $featurewidth;

	next unless so $symbol;
	++$object_count;
	$position ~~ / \( ( \-? <[\d\.]>+) \s+ ( \-? <[\d\.]>+ ) \) /;
	my ($x, $y) = latlon2page +$0, +$1;
	%dependencies{"point$symbol"}++;
	$TMP.print: sprintf("$orientation %.6g %.6g $featurewidth point$symbol\n", $x, $y);
    }
}

sub draw_spot_heights() {
    note "spot heights...";
  my $geomcol = %defaults{'pointgeometry'};
    my $sth = $dbh.prepare("SELECT ftype_code, st_astext($geomcol) AS position, altitude FROM el_grnd_surface_point WHERE $geomcol && $rect");
    
    $TMP.say: "/Helvetica-Latin1 2 selectfont 0 0 0 1 setcmykcolor";

    $sth.execute();
    
      while my @row = $sth.fetchrow_array {
        my $ftype    = @row[0];
        my $position = @row[1];
        my $altitude = @row[2] || 0;
        my $featuretype = $ftype;

        next unless $featuretype eq 'spot_height';
        
        $position ~~ / \( (\-?<[\d.]>+) \s+ (\-?<[\d.]>+) \) /;
        my ($x, $y) = latlon2page $1, $2;
        $TMP.print: sprintf "%.6g %.6g moveto ($altitude) show newpath\n", $x+0.5, $y-0.5;
    }
}

my @road_widths = (.9, .9, .9, .6, .6, .6, .4, .4, .4, .4, .2, .2, .2);

sub draw_roadpoints() {
    note "tr_road_infrastructure points...";
  my $geomcol = %defaults{'pointgeometry'};
    my $sth = $dbh.prepare("SELECT ftype_code, st_astext($geomcol) as position, rotation, ufi, width FROM tr_road_infrastructure WHERE $geomcol && $rect");
    my $sth2 = $dbh.prepare("SELECT ftype_code, class_code FROM tr_road WHERE from_ufi = ? OR to_ufi = ?");
    
    if $sth.execute {
     
      while my @row = $sth.fetchrow_array {

        my $ftype        = @row[0];
        my $position     = @row[1];
        my $orientation  = 90 - @row[2] || 0;
        my $ufi          = @row[3];
        my $featurewidth = @row[4];
        my $featuretype  = $ftype;
	
	my Str $ft = '';
        $ft ~= $ftype;
        my $symbol = get_symbol('point', $ft);
        
        #next unless @display_feature[$featuretype]; ### TODO
        next unless $symbol;
        ++$object_count;
        $position ~~ / \( (\-? <[\d.]>+) \s+ (\-? <[\d.]>+) \) /;
        my ($x, $y) = latlon2page +$0, +$1;
        %dependencies{"point$symbol"}++;
        if $featurewidth <= 0 {
	  # Find the width of the adjoining roads
	  my $adjcode = 12; # largest real class_code
	  $sth2.execute($ufi, $ufi);
	  while my @row = $sth2.fetchrow_array() {
	    $adjcode = @row[1] if @row[1] < $adjcode;
	  }
	  $featurewidth = @road_widths[$adjcode];
        }
	  $TMP.print: sprintf "$orientation %.6g %.6g $featurewidth point$symbol\n", $x, $y;
      }
    } else {
      note "Table tr_road_infrastructure does not exist";
    }
}


class Annotation {
  has $!length;
  has @!bytes;
  has $!index;

  my %tobin = ('0' => 0, '1' => 1, '2' => 2, '3' => 3,
               '4' => 4, '5' => 5, '6' => 6, '7' => 7,
               '8' => 8, '9' => 9,
	       'a' => 10, 'b' => 11, 'c' => 12, 'd' => 13, 'e' => 14, 'f' => 15,
	       'A' => 10, 'B' => 11, 'C' => 12, 'D' => 13, 'E' => 14, 'F' => 15
              );

  use experimental :pack;

  method start($annotation) {
#note $annotation;
    $!index = 0;
    $!length = $annotation.elems;
    for ^$!length -> $i {
      @!bytes.push($annotation.subbuf($i, 1).unpack('C'));
    }
  }

  method skip(Int $skip) {
#note "skipping $skip bytes";
    $!index += $skip;
  }

  method byte {
    fail('annotation out of range') if $!index >= $!length;
#note "about to read byte number $!index (@!bytes[$!index])";
    @!bytes[$!index++];
  }

  method getbytes(Int $count) {
#note "getbytes $count";
    $!index += $count;
    @!bytes[($!index-$count) ..^ $!index - 1]>>.chr.join;
  }

  method getutf16(Int $count) {
    $!index += $count;
    my @utf16;
    for @!bytes[($!index-$count) ..^ $!index - 2] -> $l, $h { @utf16.push: $h*256 + $l };
    @utf16>>.chr.join;
  }

  method string {
#note "read string";
    my $length = self.int;
#note "reading string of length $length";
    self.getutf16($length);
  }

  method colour {
    my $cyan    = self.byte / 100;
    my $magenta = self.byte / 100;
    my $yellow  = self.byte / 100;
    my $black   = self.byte / 100;
    ($cyan, $magenta, $yellow, $black);
  }

  method astring {
    my $length = self.byte;
    self.getbytes($length);
  }

  method lastring {
    my $length = self.int;
    self.getbytes($length);
  }

  method short {
     $!index += 2;
     nativecast((int32), Blob.new(@!bytes[$!index-2 ..^ $!index]));
#    my $short = self.byte;
#    $short |= self.byte +<  8;
  }

  method int {
     $!index += 4;
     nativecast((int32), Blob.new(@!bytes[$!index-4 ..^ $!index]));
#    my $long = self.byte;
#    $long +|= (self.byte +<  8);
#    $long +|= (self.byte +< 16);
#    $long +|= (self.byte +< 24);
#note "int: $long";
#    $long;
  }

  method double {
    $!index += 8;
    nativecast((num64), Blob.new(@!bytes[($!index-8) ..^ $!index]));
  }

}

sub draw_annotations() {
    note "Annotations...\n";
    my $sth = $dbh.prepare("SELECT element, st_astext(shape) as shape FROM Annotations WHERE shape && $rect");
    
    $sth.execute();
    
    for $sth.allrows -> @row {
#    while ( my @row = $sth.fetchrow_array ) {
	++$object_count;
	my $element = @row[0];
	my $shape = @row[1];
	my ($string2, $string3, $font);
	my ($x1, $y1, $x2, $y2);
	my $unknown1;
	my $justn = 0;
	my ($rotangle, $xdiff, $ydiff);
	
	my $ann = Annotation.new();
        $ann.start($element);

# The following horrendous code is an attempt to extract data from the undocumented annotations in the Australian 1:250000 series maps
	#{my $el = $element; while ($el) {$TMP.printf: "%02.2x ", ord(substr($el, 0, 1)); substr($el, 0, 1) = ''; } $TMP.print: "\n";}
	$ann.skip(54);
	$string2 = $ann.string;
	#note "draw_annotation: $string2\n";
	$unknown1 = $ann.byte;
        $ann.skip(21);
	$unknown1 = $ann.byte;
        $ann.skip(15);
	$unknown1 = $ann.short();
	$unknown1 = $ann.short();
	my ($cyan, $magenta, $yellow, $black) = $ann.colour;
	#note "colour: $cyan $magenta $yellow $black\n";
        $ann.skip(2);
	$unknown1 = $ann.int;
	$ann.skip(21) if ($unknown1 == 0);
	$unknown1 = $ann.int;
	$justn = $ann.int;
        $ann.skip(2);
	$rotangle = $ann.double;
	$xdiff = $ann.double;
	$ydiff = $ann.double;
        $ann.skip(110);
	$unknown1 = $ann.short;
        $ann.skip(61);
	$string3 = $ann.string;
        $ann.skip(6);
	#note "Second copy of string: $string3\n";
	my $pointsize = $ann.byte;
	$pointsize = $pointsize / 4 * 25.4 / 72;
	#note "Point size: $pointsize\n";
        $ann.skip(48);
	$unknown1 = $ann.byte;
	$unknown1 = $ann.short;
	$pointsize = $ann.int;
	$pointsize = $pointsize / 10000 * 25.4 / 72;
	$font = $ann.astring;
	#note "Font: $font\n";
        $ann.skip(18);
	$unknown1 = $ann.byte;
	#$TMP.print: "unknown1: $unknown1\n"; ###
	if ($unknown1 == 16) {
            $ann.skip(17);
	    $unknown1 = $ann.short;
            $ann.skip(6);
	    $x1 = $ann.double;
	    $y1 = $ann.double;
	    $x2 = $ann.double;
	    $y2 = $ann.double;
	    #$TMP.print: "16: $x1 $y1 $x2 $y2\n"; ###
            $ann.skip(4);
	    my $count = $ann.int;
            $ann.skip(4);
	    #$TMP.print: "count: $count\n"; ###
	    if ($count) {
		my @coords = ();
		while ($count--) {
		    my $x = $ann.double;
		    my $y = $ann.double;
		    push @coords, [$x, $y];
		}
		($x1, $y1) = @(@coords[0]);
		($x2, $y2) = @(@coords[1]);
		if (%drawobjects{'annotation_position'}) {
		    my ($tx, $ty) = latlon2page($x1, $y1);
		    $TMP.print: "%%%%%%%\n$tx $ty moveto\n";
		    for @coords -> $posn {
			my ($x, $y) = @$posn;
			($tx, $ty) = latlon2page($x, $y);
			$TMP.print: "$tx $ty lineto\n";
		    }
		    $TMP.print: "1 1 0 0 setcmykcolor 0.5 setlinewidth stroke\n";
		}
		$xdiff = 0;
		$ydiff = 0;
		$justn = 0;
	    }
	} elsif ($unknown1 == 65) {
            $ann.skip(17);
	    $unknown1 = $ann.short;
            $ann.skip(6);
	    $x1 = $ann.double;
	    $y1 = $ann.double;
	    #note "65: $x1 $y1\n";
	    if (%drawobjects{'annotation_position'}) {
		my ($tx, $ty) = latlon2page $x1, $y1;
		$TMP.print: "$tx $ty moveto 1 0 rlineto 1 1 0 0 setcmykcolor 0.5 setlinewidth stroke %%%%%\n";
	    }
	    $xdiff = $ydiff = 0;
	} else {
	    note "Unknown annotation value $unknown1, ignoring\n";
	}
        $ann.skip(18);
	$ann.lastring;
        $ann.skip(41);
	
	# finished parsing; now print something
	
	# Check for valid location -- sometimes we gat lat/lon with NaN values!
	if ($x1 == $x1 and $y1 == $y1) {
	    $font = ($font eq 'Zurich Cn BT') ?? 'Helvetica-Narrow-Latin1' !! 'Helvetica-Latin1';
	    $TMP.print: sprintf "/$font %.4g selectfont\n", $pointsize;
	    
	    my $annotation = $string2;
	    ($x1, $y1) = latlon2page $x1, $y1;
	    my $angle;
	    if ($y2.defined) {
		($x2, $y2) = latlon2page $x2, $y2;
		$angle = atan2($y2 - $y1, $x2 - $x1) * 180 / 3.1415926535;
	    } else {
		$angle = 0;
	    }
            # $angle = $rotangle if $rotangle;
	    $annotation ~~ s:g/\\/\\\\/;
	    $annotation ~~ s:g/\(/\\\(/;
	    $annotation ~~ s:g/\)/\\\)/;
	    $TMP.print: sprintf "gsave %.6g %.6g translate %.6g rotate 0 0 moveto %.4g %.4g %.4g %.4g setcmykcolor ", $x1+$xdiff, $y1+$ydiff, $angle, $cyan, $magenta, $yellow, $black;
	    if ($justn == 2) {
		$TMP.print: "($annotation) stringwidth pop neg 0 rmoveto ";
	    } elsif ($justn == 1) {
		$TMP.print: "($annotation) stringwidth pop 2 div neg 0 rmoveto ";
	    }
	    $TMP.print: "($annotation) show grestore\n";
	}
    }
}

my ($starteasting, $mineasting, $maxeasting, $startnorthing, $minnorthing, $maxnorthing);

sub label_grid(Bool $left, Bool $right) {
    my ($x, $y1, $y2);
    my ($lat, $long, $z);
    my $easting;
# Label grid lines
# Eastings below and above
    ($lat, $long, $z) = utm_to_latlon('WGS-84', $zone, $starteasting, $minnorthing);
    ($x, $y1) = latlon2page($long, $lllatitude);
    $y1 -= 4;
    ($lat, $long, $z) = utm_to_latlon('WGS-84', $zone, $starteasting, $maxnorthing);
    ($x, $y2) = latlon2page($long, $urlatitude);
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
	($x, $y1) = latlon2page($long, $lllatitude);
#	($x, $y1) = grid2page($easting, $minnorthing);
	$y1 -= 4;
	($lat, $long, $z) = utm_to_latlon('WGS-84', $zone, $easting, $maxnorthing);
	($x, $y2) = latlon2page($long, $urlatitude);
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
	my ($x, $y) = latlon2page($lllongitude, $lat);
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
	    ($x, $y) = latlon2page($lllongitude, $lat);
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
	my ($x, $y) = latlon2page($urlongitude, $lat);
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
	    ($x, $y) = latlon2page($urlongitude, $lat);
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

sub label_graticule(Bool $left, Bool $right) {    
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
	my ($x, $y) = latlon2page $long, $lllatitude;
	$y -= 10;
	my $string = latlon2string($long, "EW", $first);
	$TMP.print: "$x $y moveto ($string) dup stringwidth pop 2 div neg 0 rmoveto show\n" unless ($first && ! $left);
	($x, $y) = latlon2page $long, $urlatitude;
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
	    my ($x, $y) = latlon2page $long, $lat;
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
	    my ($x, $y) = latlon2page $urlongitude, $lat;
	    $x += 7;
	    $y -= 2;
	    $TMP.print: "$x $y moveto ($string) show\n";
	    $lat += $graticule_spacing;
	    $first = 0;
	}
    }
}

sub draw_graticule() {
    note "Drawing graticule...";
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
	my ($x, $y) = latlon2page $long, $lat;
	$TMP.print: "% Longitude $long\n";
	$TMP.print: ".1 setlinewidth 0 0 0 1 setcmykcolor\n";
	$TMP.print: "$x $y moveto\n";
	$lat += 1.0/60.0;
	while ($lat <= $urlatitude + .0001) {
	    ($x, $y) = latlon2page $long, $lat;
	    $TMP.print: "$x $y lineto\n";
	    $lat += 1.0/60.0;
	}
	#$TMP.print: "stroke\n";
	$long += $graticule_spacing;
    }
    
# Longitude ticks
    
    $long = $minlong;
    
    while ($long < $urlongitude + .0001) {
	my $lat = (($lllatitude*60).Int)/60;;
	my ($x, $y) = latlon2page $long, $lat;
	while ($lat <= $urlatitude + .0001) {
	    ($x, $y) = latlon2page $long, $lat;
	    $TMP.print: "$x $y moveto -.5 0 rlineto 1 0 rlineto stroke\n";
	    $lat += 1.0/60.0;
	}
	#$TMP.print: "stroke\n";
	$long += $graticule_spacing;
    }
    
    $long = $minlong;
    
    while ($long < $urlongitude + .0001) {
	my $lat = (($lllatitude*12).Int)/12;;
	my ($x, $y) = latlon2page $long, $lat;
	while ($lat <= $urlatitude + .0001) {
	    ($x, $y) = latlon2page $long, $lat;
	    $TMP.print: "$x $y moveto -1 0 rlineto 2 0 rlineto stroke\n";
	    $lat += 5.0/60.0;
	}
	#$TMP.print: "stroke\n";
	$long += $graticule_spacing;
    }
    
# Latitude
    
    my $lat = $minlat;
    
    while ($lat < $urlatitude + .0001) {
	my $long = $lllongitude;
	my ($x, $y) = latlon2page $long, $lat;
	$TMP.print: "% Latitude $lat\n";
	$TMP.print: "$x $y moveto\n";
	$long += 1.0/60.0;
	while ($long <= $urlongitude + .1) {
	    ($x, $y) = latlon2page $long, $lat;
	    $TMP.print: "$x $y lineto % $zone $long $lat\n";
	    $long += 1.0/60.0;
	}
	#$TMP.print: "stroke % latitude\n";
	$lat += $graticule_spacing;
    }
    
# Latitude ticks
    
    $lat = $minlat;
    
    while ($lat < $urlatitude + .0001) {
	my $long = ($lllongitude*60).Int/60;;
	while ($long <= $urlongitude + .0001) {
	    my ($x, $y) = latlon2page $long, $lat;
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
	    my ($x, $y) = latlon2page $long, $lat;
	    $TMP.print: "$x $y moveto 0 -1 rlineto 0 2 rlineto stroke\n";
	    $long += 5.0/60.0;
	}
	$TMP.print: "stroke\n";
	$lat += $graticule_spacing;
    }
}
    
sub draw_grid() {
# Finally draw the blue grid
    note "Displaying grid...";
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

sub format_dms(Real $lat is copy, Str $pos, Str $neg) {
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
    $string;
}

sub format_lat(Real $lat) {
    format_dms($lat, 'N', 'S');
}

sub format_long(Real $long) {
    format_dms($long, 'E', 'W');
}

sub put_annotation(Real $pagex, Real $pagey, Real $long, Real $lat, Real $x1, Real $y1, Str $string is copy) {
    my $longstr = format_long($long);
    my $latstr = format_lat($lat);
#note "longitude: $longstr, latitude: $latstr, annotation: $string";
    $string.subst(/\$LONG/, $longstr);
    $string.subst(/\$LAT/, $latstr);
    $string ~~ s/\$LONG/{$longstr}/;
    $string ~~ s/\$LAT/{$latstr}/;
#note $string;
    my @lines = $string.lines;

    my ($x2, $y2) = ($pagex, $pagey);
    #note "put_annotation: $x1 $y1 $x2 $y2";
# Calculate box height
    my $height = @lines.end * 2 + 2;
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

sub draw_userannotations(Real $xoff, Real $yoff, Real $slopedeg) {
    my $slope = $slopedeg * π / 180;
    my $c = cos($slope);
    my $s = sin($slope);
    #note "cos theta: $c, sin theta: $s";
    #note "Draw_userannotation: $zone $xoff $yoff $slope";
    for @annotations -> $ann {
	next if %($ann)<long> < $lllongitude;
        next if %($ann)<long> > $urlongitude;
        next if %($ann)<lat>  < $lllatitude;
        next if %($ann)<lat>  > $urlatitude;
        my ($x, $y) = latlon2page %($ann)<long>, %($ann)<lat>;
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
	put_annotation(%($ann)<pagex>,
	               %($ann)<pagey>,
		       %($ann)<long>,
                       %($ann)<lat>,
                       %($ann)<xoffset>,
                       %($ann)<yoffset>,
                       %($ann)<string>
                      );
    }
}

sub draw_margins(Bool $left, Bool $right) {
    my ($xoff, $yoff, $slope);

    (*, $xoffset, $yoffset)
	= latlon_to_utm('WGS-84', :$zone, $lllatitude, $lllongitude);
    
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
	    my ($x1, $y1) = latlon2page($urlongitude, $lllatitude);
	    my ($x2, $y2) = latlon2page($urlongitude, $urlatitude);
	    $slope = atan2($y2-$y1, $x2-$x1) * 180 / 3.141596353 - 90;
	    #note
            #   "Right hand edge from ($x1, $y1) to ($x2, $y2, slope $slope";
	    $TMP.print: sprintf
		"$x1 $y1 translate %f rotate $x1 neg $y1 neg translate\n", -$slope;
	    $xoff = $x1;
	    $yoff = $y1;
	} else { # Calculate slope and position of left hand side
	    my ($x3, $y3) = latlon2page($lllongitude, $lllatitude);
	    my ($x4, $y4) = latlon2page($lllongitude, $urlatitude);
	    $slope = atan2($y4-$y3, $x4-$x3) * 180 / 3.141596353 - 90;
	    #note
	    #   "Left hand edge from ($x3, $y3) to ($x4, $y4), slope $slope";
	    $xoff = $x3;
	    $yoff = $y4;
	    $TMP.print:
		sprintf "$xoff $yoff translate %f rotate $xmin neg $ymin neg translate\n", -$slope;
	}
    }
    
    label_grid($left, $right)      if %drawobjects<grid>.defined;
    label_graticule($left, $right) if %drawobjects<graticule>.defined;

    ($xoff, $yoff, $slope);
}

# Draw the bounding box, remembering the path which then becomes the clip path
    
sub draw_bbox() {
    if ($ongraticule) {
	my $long = $lllongitude;
	my $lat = $lllatitude;
	my ($x, $y) = latlon2page($long, $lat);
	$TMP.say: "$x $y moveto";
	$long += 1/60;
	while $long < $urlongitude {
	    ($x, $y) = latlon2page($long, $lat);
	    $TMP.say: "$x $y lineto";
	    $long += 1/60;
	}
	$long = $urlongitude;
	($x, $y) = latlon2page($long, $lat);
	$TMP.say: "$x $y lineto"; ### moveto???
	
	$lat += 1/60;
	while ($lat <= $urlatitude) {
	    ($x, $y) = latlon2page($long, $lat);
	    $TMP.print: "$x $y lineto\n";
	    $lat += 1/60;
	}
	$lat = $urlatitude;
	($x, $y) = latlon2page($long, $lat);
	$TMP.print: "$x $y lineto\n";
	
	$long -= 1/60;
	while ($long > $lllongitude) {
	    ($x, $y) = latlon2page($long, $lat);
	    $TMP.print: "$x $y lineto\n";
	    $long -= 1/60;
	}
	$long = $lllongitude;
	($x, $y) = latlon2page($long, $lat);
	$TMP.print: "$x $y lineto\n";
	
	$lat -= 1/60;
	while ($lat > $lllatitude) {
	    ($x, $y) = latlon2page($long, $lat);
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
}

# Fetch and display all the objects
    
# perl6 ./drawvic.pl6 db-newmap250k scale=250000 long=127.7 lat=-15.75 grid=10km display=homesteads display=yards >x.ps

sub draw_objects(Real $xoff, Real $yoff, Real $slope) {
    my $geometry_point = %defaults{'pointgeometry'};
    my $geometry_line  = %defaults{'linegeometry'};
    my $geometry_area  = %defaults{'pointgeometry'};
    my $sth_draw = $dbh.prepare("SELECT featurename, drawtype, tablename, featurecolumn, defaultsymbol, displayorder FROM displayorder ORDER BY displayorder");
    $sth_draw.execute;
    while my @row     = $sth_draw.fetchrow_array {
      my $feature     = @row[0].Str;
      my $draw        = @row[1];
      my $table       = @row[2].Str;
      my $typecolumn  = @row[3].Str;
      my $default     = @row[4].Int;
      my $order       = @row[5].Str;
      $default = 0 unless $default.defined && $default;
      note "Drawing $feature: '$draw' '$table' '$typecolumn' ($order)";
      if $order && %drawobjects{$feature.lc} {
        given $draw {
          when 'treeden'        { draw_treeden\             (                                    ); }
          when 'area'           { draw_areas\               ($table                              ); }
          when 'ga_area'        { draw_ga_areas\            ($table                              ); }
          when 'line'           { draw_lines\               ($table, $typecolumn,      -$default ); }
          when 'ga_line'        { draw_ga_lines\            ($table, $typecolumn,      -$default ); }
          when 'line_f'         { draw_lines\               ($table, $typecolumn,      -$default,); }
          when 'outline'        { draw_polygon_outline_names($table, $typecolumn, 8, 0.2, '1 0 .86 0'); }
          when 'road'           { draw_roads\               (                                    ); }
          when 'ga_road'        { draw_ga_roads\            (                                    ); }
          when 'osm_road'       { draw_osmroads\            (                                    ); }
#         when 'wline'          { draw_wlines\              ($table                              ); }
          when 'ga_wline'       { draw_ga_wlines\           ($table,                             ); }
          when 'property'       { draw_properties\          (                                    ); }
          when 'point'          { draw_points\              ($table, $typecolumn                 ); }
          when 'ga_point'       { draw_ga_points\           ($table,                            ); }
          when 'spotheight'     { draw_spot_heights\        (                                    ); }
          when 'roadpoint'      { draw_roadpoints\          (                                    ); }
          when 'graticule'      { draw_graticule\           (                                    ); }
          when 'grid'           { draw_grid\                (                                    ); }
         when 'annotation'     { draw_annotations\         (                                    ); }
          when 'userannotation' { draw_userannotations\     ($xoff, $yoff, $slope                ); }
          default               { note "Unknown draw type $draw for feature $feature: objects ignored"; }
        }
      }
    }
}

sub drawit(Str $drawzone, Real $d_lllong, Real $d_lllat, Real $d_urlong, Real $d_urlat, Bool $left, Bool $right) {
    $zone = $drawzone;
    my ($tlllong, $turlong, $tlllat, $turlat)
	= ($lllongitude, $urlongitude, $lllatitude, $urlatitude);
    ($lllongitude, $urlongitude, $lllatitude, $urlatitude)
	= ($d_lllong, $d_urlong, $d_lllat, $d_urlat);
    note "drawit: $zone $lllongitude $lllatitude $urlongitude $urlatitude $left $right";

    my ($lllong, $lllat, $urlong, $urlat) = ($lllongitude - 0.01,
    					     $lllatitude - 0.01,
        				     $urlongitude + 0.01,
					     $urlatitude + 0.01
				            );

    $rect = "ST_GeometryFromText('POLYGON(($lllong $lllat, $urlong $lllat, $urlong $urlat, $lllong $urlat, $lllong $lllat))', 4326)"; # 4283)";

    my ($xoff, $yoff, $slope) = draw_margins($left, $right);
    draw_bbox();

    $TMP.say: 'closepath';
    $TMP.say: '.1 setlinewidth 0 0 0 1 setcmykcolor gsave stroke grestore' if %drawobjects<graticule>;
    $TMP.say: 'clip newpath';
    
    draw_objects($xoff, $yoff, $slope);

    $TMP.say: 'restore'; # undo the clip path
    ($lllongitude, $urlongitude, $lllatitude, $urlatitude) = ($tlllong, $turlong, $tlllat, $turlat);
}

# Print out the Postscript definitions needed by this map

my %done_deps = ();

sub do_dependencies() {
  my $sth = $dbh.prepare("SELECT dependencies, body FROM $symbols WHERE name = ?");
  for keys %dependencies -> $dep {
    do_dependency($sth, $dep);
  }
}

sub do_dependency($sth is copy, Str $dependency) {
    return if %done_deps{$dependency}.defined;

    note "Dependency: $dependency";    
    
    $sth.execute($dependency);
    while my @row = $sth.fetchrow_array {
	my $deps = @row[0];
	my $body = @row[1];
	if ($deps) {
	    my @deps = $deps.words;
	    for @deps -> $dep {
		do_dependency($sth, $dep) unless %done_deps{$dep}.defined;
	    }
	}
	print $body;
	%done_deps{$dependency} = 1;
    }
}

# START RUNNING HERE -- everything is defined

set_papersizes();

for %*ENV<HOME> ~ '/.drawrc', '.drawrc' -> $cfgfile {
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

fail 'Must use either grid coordinates or lat/lon; not a mixture' if $ongrid && $ongraticule;
fail "Unknown paper size $papersize" unless %papersizes{$papersize}.defined;

note "Orientation is \"$orientation\"";
given $orientation {
  when 'portrait'
    { ($paperwidth, $paperheight) = %papersizes{$papersize}.split(','); }
  when 'landscape'
    { ($paperheight, $paperwidth) = %papersizes{$papersize}.split(','); }
  default
    { fail "Unknown paper orientation $orientation\n"; }
}
note "Page width: $paperwidth, height $paperheight";
$imagewidth  = ($paperwidth  - $leftmarginwidth  - $rightmarginwidth) * $scale/1000;
$imageheight = ($paperheight - $lowermarginwidth - $uppermarginwidth) * $scale/1000;

# Work out where the lower left corner is

if ($ongraticule) {
  fail "No location specified" unless $lllongitude.defined && $lllatitude.defined;
  if $zone.defined && $zone ne '' {
    (*, $lleasting, $llnorthing)
	    = latlon_to_utm('WGS-84', :$zone, $lllatitude, $lllongitude);
    note "Calculated grid as $lleasting:$llnorthing from lat $lllatitude long $lllongitude zone $zone";
  } else {
    ($zone, $lleasting, $llnorthing)
	    = latlon_to_utm('WGS-84', $lllatitude, $lllongitude);
    note "Calculated grid as $lleasting:$llnorthing from lat $lllatitude long $lllongitude calculated zone $zone";
  }
  if (! $graticulewidth.defined) {
    my ($tlat, $tlong, Nil)
	    = utm_to_latlon('WGS-84', $zone, $lleasting+$imagewidth, $llnorthing);
    $graticulewidth = $tlong - $lllongitude;
    note "Calculated graticule width as $tlong - $lllongitude ($lleasting $llnorthing $imagewidth) tlat = $tlat";
  }
  if (! $graticuleheight.defined) {
    my ($tlat, $tlong, Nil)
	    = utm_to_latlon('WGS-84', $zone, $lleasting, $llnorthing+$imageheight);
    $graticuleheight = $tlat - $lllatitude;
  }
  $lrlongitude = $urlongitude = $lllongitude + $graticulewidth;
  $ullatitude = $urlatitude = $lllatitude + $graticuleheight;
  $ullongitude = $lllongitude;
  $lrlatitude = $lllatitude;
  note "$graticulewidth: $lrlongitude $ullatitude $ullongitude $lrlatitude";
  (*, $lleasting, $llnorthing) = latlon_to_utm('WGS-84', :$zone, $lllatitude, $lllongitude);
  (*, $lreasting, $lrnorthing) = latlon_to_utm('WGS-84', :$zone, $lrlatitude, $lrlongitude);
  (*, $uleasting, $ulnorthing) = latlon_to_utm('WGS-84', :$zone, $ullatitude, $ullongitude);
  (*, $ureasting, $urnorthing) = latlon_to_utm('WGS-84', :$zone, $urlatitude, $urlongitude);
} else { # on grid
  if (! $lleasting.defined or ! $llnorthing.defined or ! $zone.defined) {
    fail "No location specified\n";
  }
  if (! $gridwidth.defined) {
    $gridwidth = $imagewidth;
  }
  if (! $gridheight.defined) {
    $gridheight = $imageheight;
  }
  $ureasting = $lreasting = $lleasting + $gridwidth;
  $uleasting = $lleasting;
  $urnorthing = $ulnorthing = $llnorthing + $gridheight;
  $lrnorthing = $llnorthing;
  note "About to calculate bounding box (zone $zone)";
  ($lllatitude, $lllongitude, Nil) = utm_to_latlon('WGS-84', $zone, $lleasting, $llnorthing);
  ($lrlatitude, $lrlongitude, Nil) = utm_to_latlon('WGS-84', $zone, $lreasting, $lrnorthing);
  ($ullatitude, $ullongitude, Nil) = utm_to_latlon('WGS-84', $zone, $uleasting, $ulnorthing);
  ($urlatitude, $urlongitude, Nil) = utm_to_latlon('WGS-84', $zone, $ureasting, $urnorthing);
  note "$lllatitude $lllongitude $urlatitude $urlongitude\n";
}

if ($bleedright) {
  my ($d1, $teast, $tnorth) = latlon_to_utm('WGS-84', :zone($zone), $urlatitude.Real, $lllongitude.Real);
  my ($d2, $urlatitude, $urlongitude)  = utm_to_latlon('WGS-84', $zone, $teast+$imagewidth, $tnorth);
}

if ($bleedtop) {
  my ($d1, $teast, $tnorth) = latlon_to_utm('WGS-84', :$zone, $lllatitude.Real, $urlongitude.Real);
  my ($d2, $urlatitude, $urlongitude)  = utm_to_latlon('WGS-84', $zone, $teast+$imagewidth, $tnorth);
}

note qq:to 'EOF';
Grid corners:
    $uleasting $ulnorthing   $ureasting $urnorthing
    $lleasting $llnorthing   $lreasting $lrnorthing
EOF

my $tmpfile = '/tmp/' ~ $*PID.Str;
$TMP = $tmpfile.IO.open(:a) or fail "Could not open /tmp/$*PID: $!";
# FIX LATER unlink($tmpfile); # saves cleaning up later

$xmin = $leftmarginwidth;
$ymin = $lowermarginwidth;
# The following four variables are used to do rough clipping during drawing
$minx = $lllongitude - .001;
$maxx = $urlongitude + .001;
$miny = $lllatitude  - .001;
$maxy = $urlatitude  + .001;

$yscale = $xscale = 1000/$scale; # convert metres on the ground to mm on the map

# Connect to database
my $passwd = 'xyz123';
#$dbh = DBIish.connect("Pg", user => 'ro', password => $passwd, dbname => $db, RaiseError => 0); # or die $DBIish::errstr;
note "Connecting to database $db";
$dbh = DBIish.connect("Pg", dbname => $db, RaiseError => False); # or die $DBIish::errstr;

my $sth_def = $dbh.prepare('SELECT name, value FROM defaults');
$sth_def.execute();
while (my @row = $sth_def.fetchrow_array()) {
  my ($name, $value) = @row;
  %defaults{$name} = $value;
}
note "Defaults are {%defaults}";
$copyright = %defaults<copyright>;

postscript_prefix();

# Set up lists of object types (for use by display/nodisplay arguments)
$sth_def = $dbh.prepare('SELECT featurename FROM displayorder');
$sth_def.execute();
while @row = $sth_def.fetchrow_array() {
  %allobjects{@row[0].lc} = 1;
}
%drawobjects = %allobjects;

# Now we can handle the [no]display options

for @displays -> $arg {
    given $arg {
        when m:i/^display '=' all$/ {
            for keys %allobjects -> $type
    	    {
                %drawobjects{$type} = 1;
            }
        }
        when m:i/^display '=' (\S+)$/ {
            %drawobjects{$0.lc} = 1;
        }
        when m:i/^nodisplay '=' all$/ {
            %drawobjects = ();
        }
        when m:i/^nodisplay '=' (\S+)$/ {
        %drawobjects{$0.lc} = 0;
        }
    }
}

$sth_sym = $dbh.prepare("SELECT symbol_ga FROM {%defaults{'symbols'}} WHERE type = ? AND ftype = ?");

my ($leftzone, $rightzone);

if ($ongraticule) {
  ($leftzone,  *, *) = latlon_to_utm('WGS-84', $lllatitude, $lllongitude+.0000001);
  ($rightzone, *, *) = latlon_to_utm('WGS-84', $urlatitude, $urlongitude-.0000001);
} else {
  $leftzone = $rightzone = $zone;
}

if ($leftzone eq $rightzone) {
  drawit($leftzone, $lllongitude, $lllatitude, $urlongitude, $urlatitude, True, True);
} else {
  my $boundary = $urlongitude.Int; # works for maps less than 1 degree wide -- FIX
  drawit($leftzone,  $lllongitude, $lllatitude, $boundary, $urlatitude, True, False);
  drawit($rightzone, $boundary, $lllatitude, $urlongitude, $urlatitude, False, True);
}

put_userannotations();

do_dependencies();

$dbh.dispose();

#$TMP.seek(0, SeekFromBeginning) or fail "Could not seek in TMP file: $!";
$TMP = $tmpfile.IO.open(:r);
.say for $TMP.lines;
$TMP.close;
unlink $tmpfile;

say "showpage";

note "$object_count objects, $point_count points\n";

# vi: filetype=perl6:
#!/usr/bin/perl6
