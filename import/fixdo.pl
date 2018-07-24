#!/usr/bin/env perl6

for lines() {
  my ($source, $featurename, $drawtype, $tablename, $featurecolumn, $defaultsymbol, $displayorder, $geomcol, $rest) = .split(';');

  say "update displayorder set source = '$source', featurename = '$featurename', drawtype = '$drawtype', featurecolumn = '$featurecolumn', geomcol = '$geomcol' where tablename = '$tablename' and displayorder = $displayorder;"
}

