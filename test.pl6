#!/home/kevinp/.rakudobrew/bin/perl6

use v6;

#use Grammar::Debugger;
use CSV::Parser;

my $file;
my $table;
my @columns;
my %columns;

grammar Description {
  rule TOP { <statement>* }
  rule statement {
             | <file>
             | <table>
             | <columns>
  }
  rule file { 'file' (<identifier>) { $file = ~$0; }}
  rule table {  'table' (<identifier>) { $table = ~$0;} }
  rule columns {
    'columns' '{'
      <column>+
    '}'
  }
  rule column { (<identifier>) (<identifier>) { @columns.push(~$0); %columns{~$0} = $1; } }
  token identifier { (\S+) }
} 

sub MAIN(Str $filename) {
  my $filecontents = $filename.IO.slurp;
  Description.parse($filecontents);
  #say $file, ' ', $table;
  say @columns;

  print qq:to 'HEADER';
    drop table $table if exists;
    create table $table (
    HEADER
  for @columns -> $col {
    my $type = %columns{$col};
    print "  $col $type,\n";
  }
  print ");\n";
  my $fh = open $file, :r;
  my $parser = CSV::Parser.new( file_handle => $fh, contains_header_row => True );
  my %data;

  my $count = 0;
  my $columns = "(" ~ @columns.join(', ') ~ ')';
  while %data = %($parser.get_line()) {
    print "INSERT INTO $table $columns VALUES (";
    for @columns -> $col {
      given %columns{$col} {
        when 'integer' { print %data{$col}, ','; }
        when 'text'    { print "E'", %data{$col}.subst("'", "\\'"), "',"; }
        when 'boolean' { print %data{$col}||'False', ','; }
        when 'double'  { print %data{$col}, ','; }
      }
    }
    print ");\n";
    ++$count;
  }
  say "$count entries created";
}
