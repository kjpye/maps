#!/usr/bin/env perl6

use NativeCall;

constant PGSIZE = 4096;

# sub mmap(Pointer $addr, int32 $length, int32 $prot, int32 $flags, int32 $fd, int32 $offset) returns CArray[int32] is native {*}

my $pages; # The memory-mapped mdb file

my $debug = 1;

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
#note "read-rint at $offset" if $debug;
  my $ret = 
  ($pages[$offset] +& 0xff)
    +| (($pages[$offset + 1] +& 0xff) +<  8)
    +| (($pages[$offset + 2] +& 0xff) +< 16)
    +| (($pages[$offset + 3] +& 0xff) +< 24);
#  note "read-rint @ {$offset.base(16)}: $ret ({$ret.base(16)})" if $debug;
  $ret;
}

# void
# find_lval(unsigned char **ptr, int *length, int pointer)
#      
# {
#   int page = pointer >> 8;
#   int row = pointer & 0xff;
#   unsigned char *p;
#   
#   p = pages + page*PGSIZE;
#   
#   *ptr = pages + page*PGSIZE + read_rshort(p+14+row*2);
#   if(row == 0)
#     {
#       *length = (p + PGSIZE) - *ptr;
#     } else {
#     *length = (read_rshort(p+14+(row-1)*2)&0x3fff)
# 	- (read_rshort(p+14+row*2)&0x3fff);
#     }
# }
# 
# void
# put_rbytes(unsigned char *p, int count)
# {
#   while(count--)
#     {
#       printf("%2.2x ", *p++);
#     }
# }
# 
# unsigned int
# read_rbyte(unsigned char *offset)
# {
#   return *offset;
# }
# 
# unsigned int
# sread_short(unsigned char *p)
# {
#   unsigned int val;
#   val = *p++;
#   val += *p << 8;
#   return val;
# }

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

# float
# read_rfloat(unsigned char *p)
# {
#   union {
#     unsigned char b[4];
#     float f;
#   } ret;
#   
#   ret.b[0] = *p++;
#   ret.b[1] = *p++;
#   ret.b[2] = *p++;
#   ret.b[3] = *p;
#   return ret.f;
# }
# 
# double
# read_rdouble(unsigned char *p)
# {
#   union {
#     unsigned char b[8];
#     double f;
#   } ret;
#   
#   ret.b[0] = *p++;
#   ret.b[1] = *p++;
#   ret.b[2] = *p++;
#   ret.b[3] = *p++;
#   ret.b[4] = *p++;
#   ret.b[5] = *p++;
#   ret.b[6] = *p++;
#   ret.b[7] = *p;
#   return ret.f;
# }
# 
# char *
# read_long_page(int pointer, int *len)
# {
#   char *str = NULL;
#   int length = 0;
# 
#   while(pointer)
#     {
#       int p = (pointer >> 8) * PGSIZE;
#       int offset = read_rshort(pages + p + 14);
#       int nlength;
#       pointer = read_rint(pages+p+offset); offset += 4;
#       nlength = PGSIZE - offset;
#       if (str)
# 	{
# 	  str = realloc(str, length+nlength);
# 	} else {
# 	  str = malloc(nlength);
# 	}
#       memcpy(str+length, &pages[p+offset], nlength);
#       length += nlength;
#     }
#   *len = length;
#   return str;
# }
# 
# void
# print_shape(char **bb, char **shape, unsigned int pointer)
# {
#   int count;
#   int segments;
#   double xmin, xmax, ymin, ymax, x, y;
#   unsigned char *ptr;
#   int length;
#   unsigned char *segptr;
#   int segstart, segment, point;
#   char bbox[60];
# 
#   find_lval(&ptr, &length, pointer);
#   count = read_rint(ptr);
#   ptr += 4;
#   if(debug)printf("%d points, Bounding Box: ", count);
#   xmin = read_rdouble(ptr);
#   ymin = read_rdouble(ptr+8);
#   xmax = read_rdouble(ptr+16);
#   ymax = read_rdouble(ptr+24);
#   ptr += 32;
#   if(debug)printf("(%g,%g) to (%g,%g) ", xmin, ymin, xmax, ymax);
#   if(bb)
#     {
#       sprintf(bbox, "((%.9g,%.9g) (%.9g,%.9g))", xmin, ymin, xmax, ymax);
#       *bb = bbox;
#     }
#   segments = read_rint(ptr);
#   ptr += 4;
#   count = read_rint(ptr);
#   segstart = read_rint(ptr+4);
#   ptr += 8;
#   if(debug)printf("%d segments, %d points, 1st segment at point %d ", segments, count, segstart);
#   segptr = ptr + segments * 4 - 4; /* where the actual points start */
#   segment = 0;
#   for(point = 0; point < count; ++point)
#     {
#       if(point == segstart)
# 	{
# 	  printf("Segment %d: ", segment);
# 	  ++segment;
# 	  if(segment < segments)
# 	    {
# 	      segstart = read_rint(ptr);
# 	      ptr += 4;
# 	    }
# 	}
#       x = read_rdouble(segptr);
#       y = read_rdouble(segptr+8);
#       printf("(%.9g, %.9g) ", x, y);
#       /* TODO: add point to shape */
#       segptr += 16;
#     }
# }
# 
# void
# print_shape2(char **bb, char **shape, char *p)
# {
#   int count;
#   int segments;
#   double xmin, xmax, ymin, ymax, x, y;
#   unsigned char *ptr;
#   int length;
#   unsigned char *segptr;
#   int segstart, segment, point;
#   char bbox[60];
# 
#   count = read_rint(p);
#   p += 4;
#   if(debug)printf("%d points, Bounding Box: ", count);
#   xmin = read_rdouble(p);
#   ymin = read_rdouble(p+8);
#   xmax = read_rdouble(p+16);
#   ymax = read_rdouble(p+24);
#   p += 32;
#   if(debug)printf("(%g,%g) to (%g,%g) ", xmin, ymin, xmax, ymax);
#   if(bb)
#     {
#       sprintf(bbox, "((%.5g,%.5g),(%.5g,%.5g))", xmin, ymin, xmax, ymax);
#       *bb = bbox;
#     }
#   segments = read_rint(p);
#   p += 4;
#   count = read_rint(p);
#   segstart = read_rint(p+4);
#   p += 8;
#   if(debug)printf("%d segments, %d points, 1st segment at point %d ", segments, count, segstart);
#   segptr = p + segments * 4 - 4; /* where the actual points start */
#   segment = 0;
#   for(point = 0; point < count; ++point)
#     {
#       if(point == segstart)
# 	{
# 	  printf("Segment %d: ", segment);
# 	  ++segment;
# 	  if(segment < segments)
# 	    {
# 	      segstart = read_rint(p);
# 	      p += 4;
# 	    }
# 	}
#       x = read_rdouble(segptr);
#       y = read_rdouble(segptr+8);
#       printf("(%g, %g) ", x, y);
#       /* TODO: add point to shape */
#       segptr += 16;
#     }
# }

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

my $tables;

# void read_table(unsigned int id);

sub print-row($p is copy, $number is copy, $table) {
  note "print-row: $p $number $table";
  my $nullflags = 0;
  my $end;
#   int j;
#   struct column * columnp;
#   int ivalue;
#   double fvalue;
#   unsigned char *r;
#   int table_id;
#   char *string, *stringp, *table_name=0;
  
  note "print-row:";
  my $offset = read-rshort($p*PGSIZE + 14 + $number*2);
  if ($offset +& 0xc000) == 0xc000 {
      note "Deleted object";
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
  $*ERR.printf("Row position: %x\n", $r);
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
      my $column = $tables.columns[* - $j];
      if not $column.bitmask +& 1 {
	  $column.length = $end - $column.offset;
	  $*ERR.printf: "VAR: offset %x, length %x\n", $column.offset, $column.length if $debug;
	  $end = $column.offset +& 0x0fff;
    }
}
  
#   columnp = table->columns;
  my $table-id = 0;
  for ^$table.num-columns -> $j {
      my $column = $table.columns[$j];
      $*ERR.printf: "Column %d (%s): ", $column.number, $column.name;
      my $nullq = $nullflags +& 1;
      $nullflags +>= 1;
      if $column.bitmask +& 1 {
	  $*ERR.printf: "fixed " if $debug;
# 	  if (nullq)
# 	    {
# 	      if(debug)printf("type %d ", columnp->type);
# 	      switch(columnp->type)
# 		{
# 		case 1: /* boolean */
# 		  printf(nullq?"true":"false");
# 		  break;
# 		case 2: /* byte */
# 		  ivalue = read_rbyte(r+columnp->offset + 2);
# 		  printf("%d %2.2x", ivalue, ivalue);
# 		  break;
# 		case 3: /* short */
# 		  ivalue = read_sshort(r+columnp->offset + 2);
# 		  printf("%d %4.4x", ivalue, ivalue);
# 		  break;
# 		case 4: /* int */
# 		  ivalue = read_rint(r+columnp->offset + 2);
# 		  printf("%d %8.8x", ivalue, ivalue);
# 		  if(strcmp(columnp->name, "Id") == 0 && ivalue < 0x1000000 && ivalue >= 15)
# 		    {
# 		      table_id = ivalue;
# 		      /* if(debug)printf("Looking through table %d next\n", table_id); */
# 		    }
# 		  break;
# 		case 5: /* money */
# 		  put_rbytes(r+columnp->offset + 2, 8);
# 		  break;
# 		case 6: /* float */
# 		  fvalue = read_rfloat(r+columnp->offset + 2);
# 		  printf("%g", fvalue);
# 		  break;
# 		case 7: /* double */
# 		  fvalue = read_rdouble(r+columnp->offset + 2);
# 		  printf("%g", fvalue);
# 		  break;
# 		case 8: /* date/time */
# 		  fvalue = read_rdouble(r+columnp->offset + 2);
# 		  fvalue -= 25569;
# 		  fvalue *= 86400;
# 		  tvalue = fvalue;
# 		  printf("%s", ctime(&tvalue));
# 		  break;
# 		default:
# 		  if(debug)printf("unknown type %2.2x", columnp->type);
# 		}
# 	    } else {
# 	      if(debug)printf("(null)");
# 	    }
	} else {
# 	  unsigned int length, bitmask, pointer;
	  $*ERR.printf: "variable ";
# 	  if (nullq)
# 	    {
# 	      int count;
# 	      unsigned char *voffset;
# 	      switch(columnp->type)
# 		{
# 		case 10: /* text */
# 		  count = columnp->length / 2;
# 		  string = malloc(count+1);
# 		  stringp = string;
# 		  voffset = r + columnp->offset + 2;
# 		  while(count--)
# 		    {
# 		      int c = read_rbyte(voffset);
# 		      *stringp++ = c;
# 		      voffset += 2;
# 		    }
# 		  *stringp = '\0';
# 		  /* printf("column name: %s, value: %s\n", columnp->name, string); */
# 		  printf("%s\n", string);
# 		  if(strcmp(columnp->name, "Name") == 0)
# 		    table_name = string;
# 		  else
# 		    free(string);
# 		  break;
# 		case 11: /* OLE */
# 		  voffset = r + columnp->offset + 2;
# 		  if(debug)printf("voffset = %p\n", voffset);
# 		  length = read_rshort(voffset);
# 		  if(debug)printf("length: %d\n", length);
# 		  bitmask = read_rshort(voffset+2);
# 		  if(debug)printf("bitmask: %d\n", bitmask);
# 		  pointer = read_rint(voffset+4);
# 		  if(debug)printf("OLE: pointer %x\n", pointer);
# 		  if(bitmask & 0x8000)
# 		    {
# 		      /* data is here */
# 		      voffset += 12;
# 		      if(strcmp("SHAPE", columnp->name)==0)
# 			{
# 			  count = read_rint(voffset);
# 			  if(count == 1)
# 			    {
# 			      printf("Long %g, Lat %g ", read_rdouble(voffset+4), read_rdouble(voffset+12));
# 			    }
# 			} else {
# 			  put_rbytes(voffset, length);
# 			}
# 		    } else if(bitmask&0x4000) {
# 		      unsigned char *ptr;
# 		      int length;
# 		      if(strcmp("SHAPE", columnp->name)==0)
# 			{
# 			  char *bb;
# 			  print_shape(&bb, NULL, pointer);
# 			  printf("\nBBOX: %s\n", bb);
# 			} else {
# 			  if(debug)printf("pointer %x ", pointer);
# 			  find_lval(&ptr, &length, pointer);
# 			  put_rbytes(ptr, length);
# 			}
# 		    } else {
# 		      char *bb;
# 		      char *str;
# 		      int length;
# 		      str = read_long_page(pointer, &length);
# 		      if (strcmp("SHAPE", columnp->name)==0)
# 			{
# 			  print_shape2(&bb, NULL, str);
# 			  printf("\nBBOX: %s\n", bb);
# 			} else {
# 			  put_rbytes(str, length);
# 			}
# 		      free(str);
# 		    }
# 		  break;
# 		default:
# 		  put_rbytes(r+columnp->offset + 2, columnp->length);
# 		  break;
# 		}
# 	    } else {
# 	      if(debug)printf("(null)");
# 	    }
	}
      $*ERR.printf: "\n";
    }
#   if(table_id)
#     {
#       printf("Processing table \"%s\"\n", table_name);
#       read_table(table_id);
#     }
}

sub process-data-page($page) {
  note "Data page\n" if $debug;
  my $unknown-byte = read-byte($page, 1);
  $*ERR.printf: "Unknown: %2.2x\n", $unknown-byte if $debug;
  $*ERR.printf: "Free space: %4.4x\n", read-short($page, 2);
  my $tablep = read-int($page, 4);
  if $tablep == 0x4c41564c { # "LVAL"
      note "Found unexpected LVAL page" if $debug;
      exit(5);
    }
  
  $*ERR.printf: "Table Description pointer: %d\n", $tablep if $debug;
  my $table = $tables;
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
#   struct table *table;
#   int num_real_index;
#   int i;
#   struct column *columns;
#   struct column *columnp;
#   unsigned int ptr;
#   
#   /* debug = 1; */
  note "Table definitioni ($page)\n" if $debug;
  my $table = Table.new(next => $tables, :$page);
  $tables = $table;
  my $ptr = 1;
  note "unknown: {read-byte($page, $ptr).base(16)}"       if $debug; $ptr++;
  note "Free space - 8: {read-short($page, $ptr).base(16)}"      if $debug; $ptr += 2;
  note "next page: {read-int($page, $ptr).base(16)}"      if $debug; $ptr += 4;
  note "length of data: {read-int($page, $ptr).base(16)}" if $debug; $ptr += 4;
  note "unknown: {read-int($page, $ptr).base(16)}";   $ptr += 4;
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
      $*ERR.printf("   Column %d (%d) label (%d chars): \"",
	     $i, $columns[$i].number, $len/2) if $debug;
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
dd $table;
  
  for ^$num-real-index -> $i {
      $*ERR.printf("  index %d: %8.8x\n", $i+1, read-int($page, $ptr)) if $debug;
      $ptr += 4;
  }
  $table;
}

sub read-bitmask($ptr) {
#   int entry;
#   unsigned char *p;
#   int *pgs, *pg;
  my $page-offset;
#   int count = 0;
#   int page;
#   int i, j;
#   int offset;
    my $bytes;
    my $end;
#   
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
      ++$p;
      $page-offset = read-rint($p);
      $p += 4;
    } elsif $pages[$p] == 0x01 {
      my $next-page = read-rint($p+1);
      $page-offset = 0;
      $p = $next-page * PGSIZE + 4;
      $bytes = PGSIZE - 4;
    } else {
      $*ERR.printf: "Unknown bit map page type %d\n", $pages[$p];
      exit(3);
    }
  my $count;
note "Reading bitmap ($bytes bytes) from position {$p.base(16)}" if $debug;
  for ^$bytes -> $i {
      my $x = $pages[$p + $i];
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
  return @pgs;
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
  note sprintf("Reading table on page %d (%x)\n", $id, $id) if $debug;
  my $table = process-table-page($id);
  printf("table bitmask: %x\n", $table.usage-bitmask) if $debug;
  my $pgs = read-bitmask($table.usage-bitmask);
dd $pgs;
  for @$pgs -> $pp {
      print-data-pages($pp);
#      $*ERR.printf("Data page %d\n", $pp) if $debug;
      read-data-page($pp);
  }
  printf("No more data pages\n") if $debug;
}

sub mmap(Pointer $addr, int32 $length, int32 $prot, int32 $flags, int32 $fd, int32 $offset) returns CArray[uint8] is native {*}

sub MAIN($file) {
 
#   struct stat statbuf;
#   
#   setvbuf(stdout, 0, _IONBF, 0);
#   fstat (0,&statbuf);

note "Opening $file";
  my $fh = $file.IO.open or fail "Could not open $file\n";

  #$pages = mmap(0, statbuf.st_size, PROT_READ, MAP_SHARED, 0, 0);
  $pages = mmap(Pointer, 1_000_000_000, 1, 1, $fh.native-descriptor, 0); # FIX

  read-table 2;
  exit 0;
}
