#!/usr/bin/env perl6

use NativeCall;

constant PGSIZE = 4096;

my $pages; # The memory-mapped mdb file

my $debug = 0;
#$debug = 1;
$*OUT.out-buffer = Nil if $debug;

sub read-rshort($offset)
{
  my $ret = ($pages[$offset] +& 0xff) +| (($pages[$offset + 1] +& 0xff) +< 8);
#  note "read-rshort from {$offset.base(16)}: $ret ({$ret.base(16)})" if $debug;
  $ret;
}

sub read-sshort($offset)
{
  my $ret;
  
  $ret = ($pages[$offset] +& 0xff) +| (($pages[$offset + 1] +& 0xff) +<8);
#  note "read-sshort from {$offset.base(16)}: $ret ({$ret.base(16)})" if $debug;
  $ret +& 0x8000 ?? $ret - 65536 !! $ret;
}

sub read-rint($offset)
{
note "read-rint at {$offset.base(16)}" if $debug;
  my $ret = 
  ($pages[$offset] +& 0xff)
    +| (($pages[$offset + 1] +& 0xff) +<  8)
    +| (($pages[$offset + 2] +& 0xff) +< 16)
    +| (($pages[$offset + 3] +& 0xff) +< 24);
#  note "read-rint @ {$offset.base(16)}: $ret ({$ret.base(16)})" if $debug;
  $ret;
}

sub find-lval($pointer) {
note "find-lval" if $debug;
    my $ptr;
    my $length;
    my $page = $pointer +> 8;
    my $row  = $pointer +& 0xff;
  
    my $p = $page * PGSIZE;
  
    $ptr = $p + read-rshort($p+14 + $row*2);
    if $row == 0 {
      $length = ($p + PGSIZE) - $ptr;
    } else {
	$length = (read-rshort($p+14 + ($row-1) * 2) +& 0x3fff) - (read-rshort($p+14 + $row*2) +& 0x3fff);
    }
note "find-lval returning \"{$ptr.base(16)}, $length\"" if $debug;
    my $x = 0;
    ($ptr, $length);
}

multi sub put-rbytes(Str $s, $count) {
    note "put-rbytes(string): {$count} bytes from {$s}" if $debug;
    my $buffer = $s.encode: :enc='latin1';
    for ^$count -> $i {
	printf '%2.2x ', $buffer[$i];
    }
    printf "\n";
}

multi sub put-rbytes(Int $p is copy, $count is copy) {
    note "put-rbytes(int): {$count} bytes from {$p.base(16)}" if $debug;
    while $count-- {
      printf "%2.2x ", $pages[$p++] +& 0xff;
    }
    printf "\n";
}

multi sub put-rbytes(Buf $p is copy, $count is copy) {
    note "put-rbytes(int): {$count} bytes from {$p.base(16)}" if $debug;
    for ^$count -> $i {
	print '%2.2x ', $p[$i];
    }
    printf "\n";
}

sub read-rbyte($offset) {
    $pages[$offset] +& 0xff;
}

sub read-byte($page, $offset) {
  my $ret = $pages[$page * PGSIZE + $offset] +& 0xff;
#  note "Read byte {$ret.base(16)} from page $page, offset $offset";
  $ret;
}

sub read-short($page, $offset) {
  read-rshort($page * PGSIZE + $offset);
}

sub read-int($page, $offset) {
  read-rint($page * PGSIZE + $offset);
}

sub read-rfloat($p) {
    my $buffer = Blob.new($pages[$p],
			  $pages[$p + 1],
			  $pages[$p + 2],
			  $pages[$p + 3]
	);
    $buffer.read-num32(0);
}

sub read-rdouble($p) {
    my $buffer = Blob.new($pages[$p],
			  $pages[$p + 1],
			  $pages[$p + 2],
			  $pages[$p + 3],
			  $pages[$p + 4],
			  $pages[$p + 5],
			  $pages[$p + 6],
			  $pages[$p + 7]
	);
    $buffer.read-num64(0);
}

sub read-long-page($pointer is copy) {
note "Read-long-page: {$pointer.base(16)}" if $debug;
    my @bytes;
    my $length = 0;

    while $pointer {
      my $p = ($pointer +> 8) * PGSIZE;
      my $offset = read-rshort($p + 14);
      $pointer = read-rint($p+$offset); $offset += 4;
      my $nlength = PGSIZE - $offset;
      $length += $nlength;
      while $nlength-- {
	  @bytes.push: $pages[$p + $offset++] +& 0xff;
      }
    }
    (Buf.new(|@bytes), $length);
}

sub print-shape($pointer) {
    my $bb;
    my $shape;

note "print-shape {$pointer.base(16)}" if $debug;
  my ($ptr, $length) = |find-lval($pointer);
  my $count = read-rint($ptr);
  $ptr += 4;
  $*ERR.printf: "%d points, Bounding Box: ", $count if $debug;
  my $xmin = read-rdouble($ptr);
  my $ymin = read-rdouble($ptr+8);
  my $xmax = read-rdouble($ptr+16);
  my $ymax = read-rdouble($ptr+24);
  $ptr += 32;
    $*ERR.printf: "(%g,%g) to (%g,%g) ", $xmin, $ymin, $xmax, $ymax if $debug;
    $bb = sprintf "((%.9g,%.9g) (%.9g,%.9g))", $xmin, $ymin, $xmax, $ymax;
    my $segments = read-rint($ptr);    $ptr += 4;
    $count = read-rint($ptr);       $ptr += 4;
    my $segstart = read-rint($ptr+4);  $ptr += 4;
  $*ERR.printf: "%d segments, %d points, 1st segment at point %d ", $segments, $count, $segstart if $debug;
  my $segptr = $ptr + $segments * 4 - 4; # where the actual points start
  my $segment = 0;
for ^$count -> $point {
    if $point == $segstart {
	  printf "Segment %d: ", $segment;
	  ++$segment;
	  if $segment < $segments {
	      $segstart = read-rint($ptr);   $ptr += 4;
	    }
	}
      my $x = read-rdouble($segptr);
      my $y = read-rdouble($segptr+8);
      printf "(%.9g, %.9g) ", $x, $y;
      # TODO: add point to shape
      $segptr += 16;
    }
    ($bb, $shape);
}

sub print-shape2(Buf $p) {
    my $offset = 0;
    my $bb;
    my $shape;

dd $p if $debug;
  my $count = $p.read-int32($offset);
  $offset += 4;
  $*ERR.printf: "%d points, Bounding Box: ", $count if $debug;
  my $xmin = $p.read-num64($offset);
  my $ymin = $p.read-num64($offset+8);
  my $xmax = $p.read-num64($offset+16);
  my $ymax = $p.read-num64($offset+24);
  $offset += 32;
  $*ERR.printf: "(%g,%g) to (%g,%g) ", $xmin, $ymin, $xmax, $ymax if $debug;
      $bb = sprintf "((%.5g,%.5g),(%.5g,%.5g))", $xmin, $ymin, $xmax, $ymax;
  my $segments = $p.read-int32($offset);
  $offset += 4;
  $count = $p.read-int32($offset);
  my $segstart = $p.read-int32($offset+4);
  $offset += 8;
  $*ERR.printf: "%d segments, %d points, 1st segment at point %d ", $segments, $count, $segstart if $debug;
  my $segptr = $offset + $segments * 4 - 4; # where the actual points start
  my $segment = 0;
    for ^$count -> $point {
	if $point == $segstart {
	  printf "Segment %d: ", $segment;
	  ++$segment;
	  if $segment < $segments {
	      $segstart = $p.read-int32($offset);
	      $offset += 4;
	  }
	}
      my $x = $p.read-num64($segptr);
      my $y = $p.read-num64($segptr+8);
      printf "(%g, %g) ", $x, $y;
      # TODO: add point to shape
	$segptr += 16;
    }
    ($bb, $shape);
}

class Column {
  has $.number  is rw;
  has $.type    is rw;
  has $.bitmask is rw;
  has $.offset  is rw;
  has $.length  is rw;
  has $.name    is rw;
}

class Table {
  has $.next             is rw; # linked list
  has $.page;  # page this table was defined on
  has $.type             is rw;
  has $.num-columns      is rw;
  has $.num-var-columns  is rw;
  has $.usage-bitmask    is rw;
  has $.num-rows         is rw;
  has $.auto-number      is rw;
  has @.columns          is rw;
}

my @tables;

# void read_table(unsigned int id);

sub print-row($p is copy, $number is copy, $table) {
  note "print-row: $p $number $table" if $debug;
  my $nullflags = 0;
  my $end;
  my $table-name;
  
  note "print-row:" if $debug;
  my $offset = read-rshort($p*PGSIZE + 14 + $number*2);
  if ($offset +& 0xc000) == 0xc000 {
      note "Deleted object" if $debug;
      return;
  }
  if $offset +& 0x4000 {
      $*ERR.printf: "Row redirect %4.4x\n", $offset +& 0x0fff if $debug;
      my $indirect = read-rint($p * PGSIZE +($offset +& 0x0fff));
      $number = $indirect +& 0xff;
      $p = $indirect +> 8;
      $*ERR.printf: "Redirecting to page %d (%x), number %d\n", $p, $p, $number if $debug;
      $offset = read-rshort($p * PGSIZE + 14 + $number * 2);
  }
  if $number {
      $end = read-rshort($p * PGSIZE + 14 + ($number - 1) * 2) - 1;
  } else {
      $end = PGSIZE - 1;
    }
  $*ERR.printf: "  Row: start %x, end %x\n", $offset, $end if $debug;
  $offset +&= 0x0fff;
  $end    +&= 0x0fff;
  $*ERR.printf: "Row: start %x, end %x\n", $offset, $end if $debug;
  my $r = $p * PGSIZE + $offset; # offset into file
  $*ERR.printf("Row position: %x\n", $r) if $debug;
  my $j = $table.num-columns;
  while $j > 0 {
      $nullflags +<= 8;
      $nullflags +|= read-byte($p, $end--);
      $j -= 8;
  }
  $*ERR.printf: "Nullflags: %8.8x\n", $nullflags if $debug;

  # fix offsets and lengths for variable objects */
  my $num-var-cols = read-short($p, $end-1);
  $end -= 2;
  $*ERR.printf: "%d variable columns\n", $num-var-cols if $debug;
  for ^$table.num-columns -> $j {
      my $column = $table.columns[$j];
#dd $column;
      if not $column.bitmask +& 1 {
	  $column.offset = read-short($p, $end-1) - 2; # WHY -2 ?
	  $*ERR.printf: "Read offset as %x from %x\n", $column.offset, ($end - 1) if $debug;
	  $end -= 2;
      }
  }
  $end = (read-short($p, $end - 1) +& 0x0fff) - 2; # WHY -2 ?
  $*ERR.printf: "Read end as %x\n", $end if $debug;
  for 1 .. $table.num-columns -> $j {
      my $column = $table.columns[* - $j];
      if not $column.bitmask +& 1 {
	  $column.length = $end - $column.offset;
	  $*ERR.printf: "VAR: offset %x, length %x\n", $column.offset, $column.length if $debug;
	  $end = $column.offset +& 0x0fff;
    }
}
  
  my $table-id = 0;
  for ^$table.num-columns -> $j {
      my $column = $table.columns[$j];
      printf("Column %d (%s): ", $column.number, $column.name);
      my $nullq = $nullflags +& 1;
      $nullflags +>= 1;
      if $column.bitmask +& 1 {
	  $*ERR.printf: "fixed " if $debug;
 	  if $nullq {
	      $*ERR.printf: "type %d ", $column.type if $debug;
              given $column.type {
		when 1 { # boolean
		    say $nullq ?? "true" !! "false";
                }
		when 2 { # byte
		  my $ivalue = read-rbyte($r+$column.offset + 2);
		  printf("%d %2.2x\n", $ivalue, $ivalue);
		}
		when 3 { # short
		  my $ivalue = read-sshort($r+$column.offset + 2);
		  printf("%d %4.4x\n", $ivalue, $ivalue);
		}
		when 4 { # int
		  my $ivalue = read-rint($r+$column.offset + 2);
		  printf("%d %8.8x\n", $ivalue, $ivalue);
		  if $column.name eq  'Id' && $ivalue < 0x1000000 && $ivalue >= 15 {
		      $table-id = $ivalue;
		      $*ERR.printf: "Looking through table %d next\n", $table-id if $debug;
		    }
		}
		when 5 { # money
		  put-rbytes($r+$column.offset + 2, 8);
		}
		when 6 { # float
		  my $fvalue = read-rfloat($r+$column.offset + 2);
		  printf("%g\n", $fvalue);
		}
		when 7 { # double
		  my $fvalue = read-rdouble($r+$column.offset + 2);
		  printf("%g\n", $fvalue);
		}
		when 8 { # date/time
		  my $fvalue = read-rdouble($r+$column.offset + 2);
		  $fvalue -= 25569;
		  $fvalue *= 86400;
		  my $tvalue = $fvalue;
		  printf("%s\n", DateTime.new($tvalue).Str);
		}
		default {
		  $*ERR.printf: "unknown type %2.2x\n", $column.type if $debug;
		}
	      }
	    } else {
	      printf "\n";
	    }
	} else {
# 	  unsigned int length, bitmask, pointer;
	  $*ERR.printf: "variable " if $debug;
	  if $nullq {
# 	      int count;
# 	      unsigned char *voffset;
	      given $column.type {
		  when 10 { # text
		      my $count = $column.length / 2;
		      my $string = '';
		      my $voffset = $r + $column.offset + 2;
		      while $count-- {
			  $string ~= read-rbyte($voffset).chr;
			  $voffset += 2;
		      }
		      $*ERR.printf: "column name: %s, value: %s\n", $column.name, $string if $debug;
		      printf("%s\n", $string);
		      if $column.name eq 'Name' {
			  $table-name = $string;
		      }
		  }
		  when 11 { # OLE
		      my $voffset = $r + $column.offset + 2;
		      $*ERR.printf: "voffset = %x\n", $voffset if $debug;
		      my $length = read-rshort($voffset);
		      $*ERR.printf: "length: %d\n", $length if $debug;
		      my $bitmask = read-rshort($voffset+2);
		      $*ERR.printf: "bitmask: %x\n", $bitmask if $debug;
		      my $pointer = read-rint($voffset+4);
		      $*ERR.printf: "OLE: pointer %x\n", $pointer if $debug;
		      if $bitmask +& 0x8000 {
			  note "0x8000" if $debug;
			  # data is here
			  $voffset += 12;
			  if 'SHAPE' eq $column.name {
			      my $count = read-rint($voffset);
			      if $count == 1 {
				  printf("Long %g, Lat %g\n", read-rdouble($voffset+4), read-rdouble($voffset+12));
			      }
			  } else {
			      put-rbytes($voffset, $length);
			  }
		      } elsif $bitmask +& 0x4000 {
			  note "0x4000 Column {$column.name}" if $debug;
			  if $column.name eq 'SHAPE' {
			      my ($bb, $shape) = |print-shape($pointer);
			      printf("\nBBOX: %s\n", $bb);
			  } else {
			      $*ERR.printf: "pointer %x\n", $pointer if $debug;
			      my ($ptr, $length) = |find-lval($pointer);
			      put-rbytes($ptr, $length);
			      note "Finished" if $debug;
			  }
		  } else {
note "0x4000 not set: column name {$column.name}" if $debug;
		      my ($str, $length) = |read-long-page($pointer);
dd $str if $debug;
		      if $column.name eq 'SHAPE' {
			  my ($bb, $shape) = print-shape2($str);
			  printf("\nBBOX: %s\n", $bb);
		      } else {
			  put-rbytes($str, $length);
		      }
		  }
		}
		default {
note "Default case for OLE" if $debug;
		    put-rbytes($r+$column.offset + 2, $column.length);
		}
	      }
	  } else {
	      printf("(null)\n");
	  }
      }
      $*ERR.printf: "\n" if $debug;
  }
  if $table-id {
      printf("Processing table \"%s\" (id: %d)\n", $table-name, $table-id);
      read-table($table-id);
  }
note "Returning from print-row" if $debug;
}

sub process-data-page($page) {
  note "Data page\n" if $debug;
  my $unknown-byte = read-byte($page, 1);
  $*ERR.printf: "Unknown: %2.2x\n", $unknown-byte if $debug;
  $*ERR.printf: "Free space: %4.4x\n", read-short($page, 2) if $debug;
  my $tablep = read-int($page, 4);
  if $tablep == 0x4c41564c { # "LVAL"
      note "Found unexpected LVAL page" if $debug;
      exit(5);
    }
  
  $*ERR.printf: "Table Description pointer: %d\n", $tablep if $debug;
  my $table = @tables[*-1];
  while $table {
      $*ERR.printf: "table pointer is %d\n", $table.page if $debug;
      if $table.page == $tablep {
	  last;
      }
      $table = $table.next;
  }
  if $table {
      note "Found table definition" if $debug;
  } else {
      note "No table definition found" if $debug;
      return;
  }
  
  
  $*ERR.printf: "Unknown: %8.8x\n", read-int($page, 8) if $debug;
  my $numrec = read-short($page, 12);
  $*ERR.printf: "%d records in this page", $numrec if $debug;
  my @row = (PGSIZE,);
  my $ptr = 14;
  for ^$numrec -> $i {
      my $roffset = read-short($page, $ptr);     $ptr += 2;
      $*ERR.printf: "    %4.4x\n", $roffset if $debug;
      @row.push: $roffset;
  }
  
  # Now try to interpret the rows
  for ^$numrec -> $i {
      print-row($page, $i, $table);
  }
}

sub process-table-page($page) {
  note "Table definition ($page)\n" if $debug;
  my $table = Table.new(:$page);
  @tables.push: $table;
#  dd $table if $debug;
#  dd @tables if $debug;
  my $ptr = 1;
  note "unknown: {read-byte($page, $ptr).base(16)}"       if $debug; $ptr++;
  note "Free space - 8: {read-short($page, $ptr).base(16)}"      if $debug; $ptr += 2;
  note "next page: {read-int($page, $ptr).base(16)}"      if $debug; $ptr += 4;
  note "length of data: {read-int($page, $ptr).base(16)}" if $debug; $ptr += 4;
  note "unknown: {read-int($page, $ptr).base(16)}"        if $debug;   $ptr += 4;
  $table.num-rows = read-int($page, $ptr); $ptr += 4;
  note "{$table.num-rows} records" if $debug;
  $table.auto-number = read-int($page, $ptr); $ptr += 4;
  note "next autonumber value: {$table.auto-number}" if $debug;
  note "auto-number flag: {read-int($page, $ptr).base(16)}"         if $debug; $ptr += 4;
  note "autonumber for complex columns: {read-int($page, $ptr).base(16)}"         if $debug; $ptr += 4;
  note "unknown: {read-int($page, $ptr).base(16)}"         if $debug; $ptr += 4;
  note "unknown: {read-int($page, $ptr).base(16)}"         if $debug; $ptr += 4;
  $table.type = read-byte($page, $ptr++);
  note "table type: {$table.type.base(16)}"                      if $debug;
  note "max columns: {read-short($page, $ptr)}"            if $debug; $ptr += 2;
  $table.num-var-columns = read-short($page, $ptr);                      $ptr += 2;
  note "number of variable columns: {$table.num-var-columns}" if $debug;
  $table.num-columns = read-short($page, $ptr);                                $ptr += 2;
  note "number of columns: {$table.num-columns}"           if $debug;
  note "{read-int($page, $ptr)} indexes"                   if $debug; $ptr += 4;
  my $num-real-index = read-int($page, $ptr);                                  $ptr += 4;
  note "{$num-real-index} index entries"                    if $debug;
  $table.usage-bitmask = read-int($page, $ptr);                                $ptr += 4;
  note "Usage bitmask: {$table.usage-bitmask.base(16)}"          if $debug;
  note "Free pages: {read-int($page, $ptr).base(16)}"            if $debug; $ptr+= 4;
   
  for ^$num-real-index -> $i {
      note "index {$i+1}"                                 if $debug;
      note "unknown {read-int($page, $ptr).base(16)}"          if $debug; $ptr += 4;
      note "{read-int($page, $ptr)} index rows"          if $debug; $ptr += 4;
      note "unknown {read-int($page, $ptr)}"          if $debug; $ptr += 4;
    }
  
  my $columns;
#  $table.columns = malloc(table->num_columns * sizeof (struct column));
   for ^$table.num-columns -> $i {
       note "column {$i+1}" if $debug;
      $columns[$i] = Column.new(type => read-byte($page, $ptr++));
#      $columns[$i].type = read_byte(page, ptr++);
      $*ERR.printf("    column type %2.2x (", $columns[$i].type) if $debug;
      given $columns[$i].type {
	when  1 { note "boolean)"             if $debug; }
	when  2 { note "byte)"                if $debug; }
	when  3 { note "short)"               if $debug; }
	when  4 { note "int)"                 if $debug; }
	when  5 { note "currency)"            if $debug; }
	when  6 { note "float)"               if $debug; }
	when  7 { note "double)"              if $debug; }
	when  8 { note "short date/time)"     if $debug; }
	when  9 { note "binary -- 255 bytes)" if $debug; }
	when 10 { note "text -- 255 bytes)"   if $debug; }
	when 11 { note "OLE)"                 if $debug; }
	when 12 { note "memo)"                if $debug; }
	when 15 { note "GUID)"                if $debug; }
	default { note "unknown)"             if $debug; }
      }
      $*ERR.printf("    unknown %8.8x\n", read-int($page, $ptr))        if $debug; $ptr += 4;
      $columns[$i].number = read-short($page, $ptr);                         $ptr += 2;
      $*ERR.printf("    column number %d\n", $columns[$i].number)       if $debug;
      $columns[$i].offset = read-short($page, $ptr);                         $ptr += 2;
      $*ERR.printf("    variable offset: %4.4x\n", $columns[$i].offset) if $debug;
      $*ERR.printf("    column number %d\n", read-short($page, $ptr))   if $debug; $ptr += 2;
      $*ERR.printf("    unknown %8.8x\n",    read-int($page, $ptr))     if $debug; $ptr += 4;
      $columns[$i].bitmask = read-byte($page, $ptr++);
      $*ERR.printf("    bitmask: %2.2x\n", $columns[$i].bitmask)        if $debug;
      $*ERR.printf("    misc_flags: %2.2x\n", read-byte($page, $ptr))      if $debug; $ptr++;
      $*ERR.printf("    unknown %8.8x\n", read-int($page, $ptr))        if $debug; $ptr += 4;
      $columns[$i].offset = read-short($page, $ptr);                         $ptr += 2;
      $*ERR.printf("    fixed offset: %4.4x\n", $columns[$i].offset)    if $debug;
      $columns[$i].length = read-short($page, $ptr);                         $ptr += 2;
      $*ERR.printf("    column length: %d\n", $columns[$i].length)      if $debug;
    }
  for ^$table.num-columns -> $i {
      my $c;
      my $namep;
      
# FIX -- this is really reading a little-endian UCS-2 string, and assumes only ASCII is used
      my $len = read-short($page, $ptr); $ptr += 2;
      $*ERR.printf: "   Column %d (%d) label (%d chars): \"",
	     $i, $columns[$i].number, $len/2 if $debug;
      my $name;
      while $len > 0 {
          my $c = read-short($page, $ptr); $ptr += 2;
	  $len -= 2;
          $name ~= $c.chr;
      }
      $*ERR.printf("$name\"\n") if $debug;
      $columns[$i].name = $name;
    }
  # now put the column definitions into the table structure in order
  for ^$table.num-columns -> $i {
      $table.columns[$columns[$i].number] = $columns[$i];
  }
dd $table if $debug;
  
  for ^$num-real-index -> $i {
      $*ERR.printf("  index %d: %8.8x\n", $i+1, read-int($page, $ptr)) if $debug;
      $ptr += 4;
  }
  $table;
}

sub read-bitmask($ptr) {
  my $page-offset;
    my $bytes;
    my $end;

  $*ERR.printf("read-bitmask: %x\n", $ptr) if $debug;
  my $entry = $ptr +& 0xff;
  my $p = ($ptr +> 8) * PGSIZE + 14 + $entry   * 2;
  my $offset = read-rshort($p);
  if $entry == 0 {
      $bytes = PGSIZE - $offset - 5;
note "Entry is 0, offset $offset" if $debug;
    } else {
      $end = read-rshort($p - 2);
note "Entry is 1, end: $end, offset: $offset" if $debug;
      $bytes = $end - $offset - 5;
    }
  $*ERR.printf("read-bitmask: offset %04.4x, length %d\n", $offset, $bytes) if $debug;
  $p = ($ptr +> 8) * PGSIZE + $offset;
  if $pages[$p] == 0x00 {
note "bitmap type 0" if $debug;
      ++$p;
      $page-offset = read-rint($p);
      $p += 4;
    } elsif $pages[$p] == 0x01 {
note "bitmap type 1" if $debug;
      my $next-page = read-rint($p+1);
      $page-offset = 0;
      $p = $next-page * PGSIZE + 4;
      $bytes = PGSIZE - 4;
    } else {
      $*ERR.printf: "Unknown bit map page type %d\n", $pages[$p] if $debug;
      exit(3);
    }
  my $count = 0;
note "Reading bitmap ($bytes bytes) from position {$p.base(16)}" if $debug;
  for ^$bytes -> $i {
      my $x = $pages[$p + $i] +& 0xff;
      $*ERR.printf("%2.2x ", $x) if $debug;
      while $x {
	  $x +&= $x-1;
	  ++$count;
	}
    }
  $*ERR.printf("\nread-bitmask: %d pages, page offset %d\n", $count, $page-offset) if $debug;
  my @pgs;
  my $page = 0;
  for ^$bytes -> $i {
      my $x = $pages[$p +$i];
      if $x {
          for ^8 {
	      if $x +& 1 {
                  @pgs.push: $page + $page-offset;
		  $*ERR.printf("%d ", $page + $page-offset) if $debug;
		}
	      $page++;
	      $x +>= 1;
	    }
	} else {
	  $page += 8;
	}
    }
  dd @pgs if $debug;
  @pgs;
}

sub read-data-page($id) {
  $*ERR.printf: "read_data_page: reading page %d (%x)\n", $id, $id if $debug;
  my $type = read-byte($id, 0);
  $*ERR.printf: "read_data_page: type %d\n", $type if $debug;
  if $type != 0x01 {
      note "Pointer to data page does not point to data page" if $debug;
      exit(4);
  }
  process-data-page($id);
}

sub print-data-pages($p) {
#  $*ERR.printf: "Remaining data pages:" if $debug;
#  while (*p)
#    {
#      if(debug)printf(" %d", *p);
#      ++p;
#    }
#  if(debug)printf("\n");
}

sub read-table($id) {
  $*ERR.printf: "Reading table on page %d (%x)\n", $id, $id if $debug;
  my $table = process-table-page($id);
  $*ERR.printf: "table bitmask: %x\n", $table.usage-bitmask if $debug;
  my @pgs = read-bitmask($table.usage-bitmask);
  dd @pgs if $debug;
  for @pgs -> $pp {
      note "Reading data page $pp" if $debug;
      print-data-pages($pp);
      $*ERR.printf("Data page %d\n", $pp) if $debug;
      read-data-page($pp);
  }
  note "No more data pages" if $debug;
}

sub mmap(Pointer $addr, int32 $length, int32 $prot, int32 $flags, int32 $fd, int32 $offset) returns CArray[uint8] is native {*}

sub MAIN($file) {
 
    note "Opening $file" if $debug;
  my $fh = $file.IO.open or fail "Could not open $file\n";

  $pages = mmap(Pointer, 1_000_000_000, 1, 1, $fh.native-descriptor, 0); # FIX

  read-table 2;
  exit 0;
}
