#!/usr/bin/perl

my $first = 1;
my $xmin;
my $ymin;
my $xmax;
my $ymax;

# <trkseg>
# <trkpt lat="-36.666204929" lon="148.474602699">
#   <ele>1046.532471</ele>
#   <time>2009-03-09T01:31:49Z</time>
# </trkpt>
# ...

while(<>)
{
    chomp;

    if (/<trkpt lat=\"([-0-9\.]*)\" lon=\"([-0-9\.]*)\">/) {
      ($y, $x) = ($1, $2);
    }
    if (/<time>(.*)<\/time>/) {
      $date = $1;
    }
   if (/<\/trkpt>/) {
       print "INSERT INTO Spot (date, shape) VALUES ('$date', ST_GeomFromText(\'POINT($x $y)',4283));\n";
   }
  next;
}
