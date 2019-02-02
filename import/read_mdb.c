#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <time.h>

#define PGSIZE 4096

unsigned char *pages;
unsigned int debug = 0;

unsigned int
read_rshort(unsigned char *p)
{
  unsigned int ret;
  
  ret = *p++;
  ret |= *p << 8;
  return ret;
}

int
read_sshort(unsigned char *p)
{
  unsigned int ret;
  
  ret = *p++;
  ret |= *p << 8;
  if (ret & 0x8000)
    return ret - 65536;
  return ret;
}

unsigned int
read_rint(unsigned char *p)
{
  unsigned int ret;
  
  ret = *p++;
  ret |= *p++ << 8;
  ret |= *p++ << 16;
  ret |= *p << 24;
  return ret;
}

void
find_lval(unsigned char **ptr, int *length, int pointer)
     
{
  int page = pointer >> 8;
  int row = pointer & 0xff;
  unsigned char *p;
  
  p = pages + page*PGSIZE;
  
  *ptr = pages + page*PGSIZE + read_rshort(p+14+row*2);
  if(row == 0)
    {
      *length = (p + PGSIZE) - *ptr;
    } else {
    *length = (read_rshort(p+14+(row-1)*2)&0x3fff)
	- (read_rshort(p+14+row*2)&0x3fff);
    }
}

void
put_rbytes(unsigned char *p, int count)
{
  while(count--)
    {
      printf("%2.2x ", *p++);
    }
}

unsigned int
read_rbyte(unsigned char *offset)
{
  return *offset;
}

unsigned int
read_byte(unsigned int page, unsigned int offset)
{
  return pages[page * PGSIZE + offset];
}

unsigned int
sread_short(unsigned char *p)
{
  unsigned int val;
  val = *p++;
  val += *p << 8;
  return val;
}

unsigned int
read_short(unsigned int page, int offset)
{
  unsigned char *p = pages + page * PGSIZE + offset;
  unsigned int ret;
  
  if(offset >= PGSIZE - 1)
    exit(3);
  ret = *p++;
  ret |= *p << 8;
  return ret;
}

unsigned int
read_int(unsigned int page, int offset)
{
  unsigned char *p = pages + page * PGSIZE + offset;
  unsigned int ret;
  
  if(offset >= PGSIZE - 3)
    exit(3);
  ret = *p++;
  ret |= *p++ << 8;
  ret |= *p++ << 16;
  ret |= *p << 24;
  return ret;
}

float
read_rfloat(unsigned char *p)
{
  union {
    unsigned char b[4];
    float f;
  } ret;
  
  ret.b[0] = *p++;
  ret.b[1] = *p++;
  ret.b[2] = *p++;
  ret.b[3] = *p;
  return ret.f;
}

double
read_rdouble(unsigned char *p)
{
  union {
    unsigned char b[8];
    double f;
  } ret;
  
  ret.b[0] = *p++;
  ret.b[1] = *p++;
  ret.b[2] = *p++;
  ret.b[3] = *p++;
  ret.b[4] = *p++;
  ret.b[5] = *p++;
  ret.b[6] = *p++;
  ret.b[7] = *p;
  return ret.f;
}

char *
read_long_page(int pointer, int *len)
{
  char *str = NULL;
  int length = 0;

  while(pointer)
    {
      int p = (pointer >> 8) * PGSIZE;
      int offset = read_rshort(pages + p + 14);
      int nlength;
      pointer = read_rint(pages+p+offset); offset += 4;
      nlength = PGSIZE - offset;
      if (str)
	{
	  str = realloc(str, length+nlength);
	} else {
	  str = malloc(nlength);
	}
      memcpy(str+length, &pages[p+offset], nlength);
      length += nlength;
    }
  *len = length;
  return str;
}

void
print_shape(char **bb, char **shape, unsigned int pointer)
{
  int count;
  int segments;
  double xmin, xmax, ymin, ymax, x, y;
  unsigned char *ptr;
  int length;
  unsigned char *segptr;
  int segstart, segment, point;
  char bbox[60];

  find_lval(&ptr, &length, pointer);
  count = read_rint(ptr);
  ptr += 4;
  if(debug)printf("%d points, Bounding Box: ", count);
  xmin = read_rdouble(ptr);
  ymin = read_rdouble(ptr+8);
  xmax = read_rdouble(ptr+16);
  ymax = read_rdouble(ptr+24);
  ptr += 32;
  if(debug)printf("(%g,%g) to (%g,%g) ", xmin, ymin, xmax, ymax);
  if(bb)
    {
      sprintf(bbox, "((%.9g,%.9g) (%.9g,%.9g))", xmin, ymin, xmax, ymax);
      *bb = bbox;
    }
  segments = read_rint(ptr);
  ptr += 4;
  count = read_rint(ptr);
  segstart = read_rint(ptr+4);
  ptr += 8;
  if(debug)printf("%d segments, %d points, 1st segment at point %d ", segments, count, segstart);
  segptr = ptr + segments * 4 - 4; /* where the actual points start */
  segment = 0;
  for(point = 0; point < count; ++point)
    {
      if(point == segstart)
	{
	  printf("Segment %d: ", segment);
	  ++segment;
	  if(segment < segments)
	    {
	      segstart = read_rint(ptr);
	      ptr += 4;
	    }
	}
      x = read_rdouble(segptr);
      y = read_rdouble(segptr+8);
      printf("(%.9g, %.9g) ", x, y);
      /* TODO: add point to shape */
      segptr += 16;
    }
}

void
print_shape2(char **bb, char **shape, char *p)
{
  int count;
  int segments;
  double xmin, xmax, ymin, ymax, x, y;
  unsigned char *ptr;
  int length;
  unsigned char *segptr;
  int segstart, segment, point;
  char bbox[60];

  count = read_rint(p);
  p += 4;
  if(debug)printf("%d points, Bounding Box: ", count);
  xmin = read_rdouble(p);
  ymin = read_rdouble(p+8);
  xmax = read_rdouble(p+16);
  ymax = read_rdouble(p+24);
  p += 32;
  if(debug)printf("(%g,%g) to (%g,%g) ", xmin, ymin, xmax, ymax);
  if(bb)
    {
      sprintf(bbox, "((%.5g,%.5g),(%.5g,%.5g))", xmin, ymin, xmax, ymax);
      *bb = bbox;
    }
  segments = read_rint(p);
  p += 4;
  count = read_rint(p);
  segstart = read_rint(p+4);
  p += 8;
  if(debug)printf("%d segments, %d points, 1st segment at point %d ", segments, count, segstart);
  segptr = p + segments * 4 - 4; /* where the actual points start */
  segment = 0;
  for(point = 0; point < count; ++point)
    {
      if(point == segstart)
	{
	  printf("Segment %d: ", segment);
	  ++segment;
	  if(segment < segments)
	    {
	      segstart = read_rint(p);
	      p += 4;
	    }
	}
      x = read_rdouble(segptr);
      y = read_rdouble(segptr+8);
      printf("(%g, %g) ", x, y);
      /* TODO: add point to shape */
      segptr += 16;
    }
}

struct column {
  int number;
  int type;
  int bitmask;
  int offset;
  int length;
  char *name;
};

struct table {
  struct table *next; /* linked list */
  int page; /* which page was this defined on? */
  int type;
  int num_columns;
  int num_var_cols;
  int usage_bitmask;
  int num_rows;
  int auto_number;
  struct column *columns;
};

struct table *tables = 0;

void read_table(unsigned int id);

void
print_row(int p, int number, struct table *table)
{
  long long nullflags = 0;
  int end;
  int j;
  struct column * columnp;
  int ivalue;
  double fvalue;
  unsigned char *r;
  int table_id;
  int offset;
  char *string, *stringp, *table_name=0;
  
  if(debug)printf("print_row:\n");
  offset = read_rshort(pages + p*PGSIZE + 14 + number*2);
  if ((offset & 0xc000) == 0xc000)
    {
      if(debug)printf("Deleted object\n");
      return;
    }
  if (offset & 0x4000)
    {
      unsigned int indirect;
      if(debug)printf("Row indirect %4.4x\n", offset & 0x0fff);
      indirect = read_rint(pages + p * PGSIZE +(offset & 0x0fff));
      number = indirect & 0xff;
      p = indirect >> 8;
      if(debug)printf("Redirecting to page %d (%x), number %d\n", p, p, number);
      offset = read_rshort(pages + p * PGSIZE + 14 + number * 2);
    }
  if(number)
    {
      end = read_rshort(pages + p * PGSIZE + 14 + (number - 1) * 2) - 1;
    } else {
      end = PGSIZE - 1;
    }
  if(debug)printf("  Row: start %x, end %x\n", offset, end);
#if 0
  if (offset & 0x8000)
    {
      if(debug)printf("offset has msb set; ignoring row\n");
      return;
    }
#endif
  offset &= 0x0fff;
  end &= 0x0fff;
  if(debug)printf("  Row: start %d, end %d\n", offset, end);
  r = pages + p * PGSIZE + offset;
  if(debug)printf("Row pointer: %p\n", r);
  for(j = table->num_columns; j > 0; j -= 8)
    {
      nullflags <<= 8;
      nullflags |= read_byte(p, end--);
    }
  if(debug)printf("  Nullflags: %8.8x\n", (unsigned int)nullflags);
  
  /* fix offsets and lengths for variable objects */
  int num_var_cols = read_short(p, end-1);
  end -= 2;
  if(debug)printf("  %d variable columns\n", num_var_cols);
  columnp = table->columns;
  for(j = table->num_columns;
      j;
      --j, ++columnp)
    {
      if(columnp->bitmask & 1)
	continue; /* fixed length object */
      columnp->offset = read_short(p, end-1) - 2; /* WHY -2 ? */
      if(debug)printf("Read offset as %x\n", columnp->offset);
      end -= 2;
    }
    end = (read_short(p, end - 1) & 0x0fff) - 2; /* WHY -2 ? */
  if(debug)printf("Read end as %x\n", end);
  columnp = table->columns + table->num_columns - 1;
  for(j = table->num_columns;
      j;
      --j, --columnp)
    {
      if(columnp->bitmask & 1)
	continue; /* fixed length object */
      columnp->length = end - columnp->offset;
      if(debug)printf("VAR: offset %x, length %x\n", columnp->offset, columnp->length);
      end = columnp->offset & 0x0fff;
    }
  
  columnp = table->columns;
  table_id = 0;
  for(j = table->num_columns;
      j;
      --j, ++columnp)
    {
      time_t tvalue;
      int nullq;
      printf("Column %d (%s): ", columnp->number, columnp->name);
      nullq = nullflags & 1;
      nullflags >>= 1;
      if (columnp->bitmask & 1)
	{
	  /* if(debug)printf("fixed "); */
	  if (nullq)
	    {
	      if(debug)printf("type %d ", columnp->type);
	      switch(columnp->type)
		{
		case 1: /* boolean */
		  printf(nullq?"true":"false");
		  break;
		case 2: /* byte */
		  ivalue = read_rbyte(r+columnp->offset + 2);
		  printf("%d %2.2x", ivalue, ivalue);
		  break;
		case 3: /* short */
		  ivalue = read_sshort(r+columnp->offset + 2);
		  printf("%d %4.4x", ivalue, ivalue);
		  break;
		case 4: /* int */
		  ivalue = read_rint(r+columnp->offset + 2);
		  printf("%d %8.8x", ivalue, ivalue);
		  if(strcmp(columnp->name, "Id") == 0 && ivalue < 0x1000000 && ivalue >= 15)
		    {
		      table_id = ivalue;
		      /* if(debug)printf("Looking through table %d next\n", table_id); */
		    }
		  break;
		case 5: /* money */
		  put_rbytes(r+columnp->offset + 2, 8);
		  break;
		case 6: /* float */
		  fvalue = read_rfloat(r+columnp->offset + 2);
		  printf("%g", fvalue);
		  break;
		case 7: /* double */
		  fvalue = read_rdouble(r+columnp->offset + 2);
		  printf("%g", fvalue);
		  break;
		case 8: /* date/time */
		  fvalue = read_rdouble(r+columnp->offset + 2);
		  fvalue -= 25569;
		  fvalue *= 86400;
		  tvalue = fvalue;
		  printf("%s", ctime(&tvalue));
		  break;
		default:
		  if(debug)printf("unknown type %2.2x", columnp->type);
		}
	    } else {
	      if(debug)printf("(null)");
	    }
	} else {
	  unsigned int length, bitmask, pointer;
	  /* if(debug)printf("variable "); */
	  if (nullq)
	    {
	      int count;
	      unsigned char *voffset;
	      switch(columnp->type)
		{
		case 10: /* text */
		  count = columnp->length / 2;
		  string = malloc(count+1);
		  stringp = string;
		  voffset = r + columnp->offset + 2;
		  while(count--)
		    {
		      int c = read_rbyte(voffset);
		      *stringp++ = c;
		      voffset += 2;
		    }
		  *stringp = '\0';
		  /* printf("column name: %s, value: %s\n", columnp->name, string); */
		  printf("%s\n", string);
		  if(strcmp(columnp->name, "Name") == 0)
		    table_name = string;
		  else
		    free(string);
		  break;
		case 11: /* OLE */
		  voffset = r + columnp->offset + 2;
		  if(debug)printf("voffset = %p\n", voffset);
		  length = read_rshort(voffset);
		  if(debug)printf("length: %d\n", length);
		  bitmask = read_rshort(voffset+2);
		  if(debug)printf("bitmask: %d\n", bitmask);
		  pointer = read_rint(voffset+4);
		  if(debug)printf("OLE: pointer %x\n", pointer);
		  if(bitmask & 0x8000)
		    {
		      /* data is here */
		      voffset += 12;
		      if(strcmp("SHAPE", columnp->name)==0)
			{
			  count = read_rint(voffset);
			  if(count == 1)
			    {
			      printf("Long %g, Lat %g ", read_rdouble(voffset+4), read_rdouble(voffset+12));
			    }
			} else {
			  put_rbytes(voffset, length);
			}
		    } else if(bitmask&0x4000) {
		      unsigned char *ptr;
		      int length;
		      if(strcmp("SHAPE", columnp->name)==0)
			{
			  char *bb;
			  print_shape(&bb, NULL, pointer);
			  // printf("\nBBOX: %s\n", bb);
			} else {
			  if(debug)printf("pointer %x ", pointer);
			  find_lval(&ptr, &length, pointer);
			  put_rbytes(ptr, length);
			}
		    } else {
		      char *bb;
		      char *str;
		      int length;
		      str = read_long_page(pointer, &length);
		      if (strcmp("SHAPE", columnp->name)==0)
			{
			  print_shape2(&bb, NULL, str);
			  // printf("\nBBOX: %s\n", bb);
			} else {
			  put_rbytes(str, length);
			}
		      free(str);
		    }
		  break;
		default:
		  put_rbytes(r+columnp->offset + 2, columnp->length);
		  break;
		}
	    } else {
	      if(debug)printf("(null)");
	    }
	}
      printf("\n");
    }
  if(table_id)
    {
      printf("Processing table \"%s\"\n", table_name);
      read_table(table_id);
    }
}

void
process_data_page(unsigned int page)
{
  int unknown_byte;
  int tablep;
  int numrec;
  int i;
  int roffset;
  int *rowp;
  int *r;
  struct table *table;
  unsigned int ptr;
  
  if(debug)printf("Data page\n");
  unknown_byte = read_byte(page, 1);
  if(debug)printf("  Unknown: %2.2x\n", unknown_byte);
  if(debug)printf("  Free space: %4.4x\n", read_short(page, 2));
  tablep = read_int(page, 4);
  if (tablep == 0x4c41564c) /* "LVAL" */
    {
      if(debug)printf("Found unexpected LVAL page\n");
      exit(5);
    }
  
  if(debug)printf("  Table Description pointer: %d\n", tablep);
  table = tables;
  while(table)
    {
      if(debug)printf("table pointer is %d\n", table->page);
      if (table->page == tablep)
	break;
      table = table->next;
    }
  if (table)
    {
      if(debug)printf("Found table definition\n");
    } else {
      if(debug)printf("No table definition found\n");
      return;
    }
  
  
  if(debug)printf("  Unknown: %8.8x\n", read_int(page, 8));
  numrec = read_short(page, 12);
  if(debug)printf("  %d records in this page\n", numrec);
  rowp = malloc ((numrec+2) * sizeof (int));
  r = rowp;
  *r++ = PGSIZE;
  ptr = 14;
  for (i = 0; i < numrec; ++i)
    {
      roffset = read_short(page, ptr);
      ptr += 2;
      if(debug)printf("    %4.4x\n", roffset);
      *r++ = roffset;
    }
  *r++ = 0;
  
  /* Now try to interpret the rows */
  for(i = 0, r = rowp+1; i < numrec; ++i, ++r)
    {
      print_row(page, i, table);
    }
}

struct table *
process_table_page(unsigned int page)
{
  struct table *table;
  int num_real_index;
  int i;
  struct column *columns;
  struct column *columnp;
  unsigned int ptr;
  
  /* debug = 1; */
  if(debug)printf("Table definition\n");
  table = malloc (sizeof (struct table));
  table->next = tables;
  table->page = page;
  tables = table;
  ptr = 1;
  if(debug)printf("  unknown: %2.2x\n", read_byte(page, ptr)); ptr++;
  if(debug)printf("  unknown: %4.4x\n", read_short(page, ptr)); ptr += 2;
  if(debug)printf("  next page: %8.8x\n", read_int(page, ptr)); ptr += 4;
  if(debug)printf("  length of data: %8.8x\n", read_int(page, ptr)); ptr += 4;
  if(debug)printf("  unknown: %8.8x\n", read_int(page, ptr)); ptr += 4;
  table->num_rows = read_int(page, ptr); ptr += 4;
  if(debug)printf("  %d records\n", table->num_rows);
  table->auto_number = read_int(page, ptr); ptr += 4;
  if(debug)printf("  next autonumber value: %d\n", table->auto_number);
  if(debug)printf("  unknown: %8.8x\n", read_int(page, ptr)); ptr += 4;
  if(debug)printf("  unknown: %8.8x\n", read_int(page, ptr)); ptr += 4;
  if(debug)printf("  unknown: %8.8x\n", read_int(page, ptr)); ptr += 4;
  if(debug)printf("  unknown: %8.8x\n", read_int(page, ptr)); ptr += 4;
  table->type = read_byte(page, ptr++);
  if(debug)printf("  table type: %2.2x\n", table->type);
  if(debug)printf("  max columns: %d\n", read_short(page, ptr)); ptr += 2;
  table->num_var_cols = read_short(page, ptr); ptr += 2;
  if(debug)printf("  number of variable columns: %d\n", table->num_var_cols);
  table->num_columns = read_short(page, ptr); ptr += 2;
  if(debug)printf("  number of columns: %d\n", table->num_columns);
  if(debug)printf("  %d indexes\n", read_int(page, ptr)); ptr += 4;
  num_real_index = read_int(page, ptr); ptr += 4;
  if(debug)printf("  %d real indexes\n", num_real_index);
  table->usage_bitmask = read_int(page, ptr); ptr += 4;
  if(debug)printf("  Usage bitmask: %8.8x\n", table->usage_bitmask);
  if(debug)printf("  Free pages: %8.8x\n", read_int(page, ptr)); ptr+= 4;
  
  for (i = 0; i < num_real_index; ++i)
    {
      if(debug)printf("  index %d:\n", i+1);
      if(debug)printf("    unknown %8.8x\n", read_int(page, ptr)); ptr += 4;
      if(debug)printf("    %d index rows\n", read_int(page, ptr)); ptr += 4;
      if(debug)printf("    unknown %8.8x\n", read_int(page, ptr)); ptr += 4;
    }
  
  columns = malloc(table->num_columns * sizeof (struct column));
  table->columns = malloc(table->num_columns * sizeof (struct column));
  columnp = columns;
  for (i = 0; i < table->num_columns; ++i, ++columnp)
    {
      if(debug)printf("  column %d:\n", i+1);
      columnp->type = read_byte(page, ptr++);
      if(debug)printf("    column type %2.2x (", columnp->type);
      switch(columnp->type)
	{
	case 1:
	  if(debug)printf("boolean)\n");
	  break;
	case 2:
	  if(debug)printf("byte)\n");
	  break;
	case 3:
	  if(debug)printf("short)\n");
	  break;
	case 4:
	  if(debug)printf("int)\n");
	  break;
	case 5:
	  if(debug)printf("currency)\n");
	  break;
	case 6:
	  if(debug)printf("float)\n");
	  break;
	case 7:
	  if(debug)printf("double)\n");
	  break;
	case 8:
	  if(debug)printf("short date/time)\n");
	  break;
	case 9:
	  if(debug)printf("binary -- 255 bytes)\n");
	  break;
	case 10:
	  if(debug)printf("text -- 255 bytes)\n");
	  break;
	case 11:
	  if(debug)printf("OLE)\n");
	  break;
	case 12:
	  if(debug)printf("memo)\n");
	  break;
	case 15:
	  if(debug)printf("GUID)\n");
	  break;
	default:
	  if(debug)printf("unknown)\n");
	  break;
	}
      if(debug)printf("    unknown %8.8x\n", read_int(page, ptr)); ptr += 4;
      columnp->number = read_short(page, ptr); ptr += 2;
      if(debug)printf("    column number %d\n", columnp->number);
      columnp->offset = read_short(page, ptr); ptr += 2;
      if(debug)printf("    variable offset: %4.4x\n", columnp->offset);
      if(debug)printf("    column number %d\n", read_short(page, ptr)); ptr += 2;
      if(debug)printf("    unknown %8.8x\n", read_int(page, ptr)); ptr += 4;
      columnp->bitmask = read_byte(page, ptr++);
      if(debug)printf("    bitmask: %2.2x\n", columnp->bitmask);
      if(debug)printf("    unknown: %2.2x\n", read_byte(page, ptr)); ptr++;
      if(debug)printf("    unknown %8.8x\n", read_int(page, ptr)); ptr += 4;
      columnp->offset = read_short(page, ptr); ptr += 2;
      if(debug)printf("    fixed offset: %4.4x\n", columnp->offset);
      columnp->length = read_short(page, ptr); ptr += 2;
      if(debug)printf("    column length: %d\n", columnp->length);
    }
  for (columnp = columns, i = 0;
       i < table->num_columns;
       ++i, ++columnp)
    {
      int len;
      int c;
      char *namep;
      
      len = read_short(page, ptr); ptr += 2;
      if(debug)printf("   Column %d (%d) label (%d chars): \"",
	     i, columnp->number, len/2);
      columnp->name = malloc(len+1);
      namep = columnp->name;
      while(len)
	{
	  c = read_short(page, ptr); ptr += 2;
	  if(debug)putchar(c);
	  *namep++ = c;
	  len -= 2;
	}
      *namep = '\0';
      if(debug)printf("\"\n");
    }
  /* now put the column definitions into the table structure in order */
  for (columnp = columns, i = 0;
       i < table->num_columns;
       ++i, ++columnp)
    {
      table->columns[columnp->number] = *columnp;
    }
  free(columns);
  
  for (i = 0; i < num_real_index; ++i)
    {
      if(debug)printf("  index %d: %8.8x\n", i+1, read_int(page, ptr));
      ptr += 4;
    }
  return table;
}

int *
read_bitmask(int ptr)
{
  int entry;
  unsigned char *p;
  int *pgs, *pg;
  int page_offset;
  int count = 0;
  int page;
  int i, j;
  int offset;
  int bytes, end;
  
  if(debug)printf("read_bitmask: %x\n", ptr);
  entry = ptr & 0xff;
  p = pages + (ptr >> 8) * PGSIZE + 14 + (ptr & 0xff) * 2;
  offset = read_rshort(p);
  if(entry == 0)
    {
      bytes = PGSIZE - offset - 5;
    } else {
      end = read_rshort(p-2);
      bytes = end - offset - 5;
    }
  if(debug)printf("read_bitmask: offset %d\n", offset);
  p = pages + (ptr >> 8) * PGSIZE + offset;
  if (*p == 0x00)
    {
      ++p;
      page_offset = read_rint(p);
      p += 4;
    } else if (*p == 0x01) {
      unsigned int next_page;
      next_page = read_rint(p+1);
      page_offset = 0;
      p = pages + next_page * PGSIZE + 4;
      bytes = PGSIZE - 4;
    } else {
      if(debug)fprintf(stderr, "Unknown bit map page type %d\n", *p);
      exit(3);
    }
  for(i=0; i<bytes; ++i)
    {
      int x;
      x = p[i];
      if(debug)printf("%2.2x ", x);
      while(x)
	{
	  x &= x-1;
	  ++count;
	}
    }
  if(debug)printf("read_bitmask: %d pages, page offset %d\n", count, page_offset);
  pgs = malloc((count+1)*sizeof(int));
  pg = pgs;
  page = 0;
  for(i=0; i<bytes; ++i)
    {
      int x;
      x = p[i];
      if(x)
	{
	  for(j=0; j<8; ++j)
	    {
	      if(x&1)
		{
		  *pg++ = page + page_offset;
		  if(debug)printf("%d ", page + page_offset);
		}
	      page++;
	      x >>= 1;
	    }
	} else {
	  page += 8;
	}
    }
  *pg++ = 0;
  return pgs;
}

void
read_data_page(unsigned int id)
{
  int type;

  if(debug)printf("read_data_page: reading page %d (%x)\n", id, id);
  type = read_byte(id, 0);
  if(debug)printf("read_data_page: type %d\n", type);
  if(type != 0x01)
    {
      if(debug)printf("Pointer to data page does not point to data page\n");
      exit(4);
    }
  process_data_page(id);
}

void
print_data_pages(int *p)
{
  if(debug)printf("Remaining data pages:");
  while (*p)
    {
      if(debug)printf(" %d", *p);
      ++p;
    }
  if(debug)printf("\n");
}

void
read_table(unsigned int id)
{
  int *pgs;
  int *pp;
  struct table *table;

  if(debug)printf("Reading table on page %d (%x)\n", id, id);
  table = process_table_page(id);
  if(debug)printf("table bitmask: %x\n", table->usage_bitmask);
  pgs = read_bitmask(table->usage_bitmask);
  pp = pgs;
  while(*pp)
    {
      print_data_pages(pp);
      if(debug)printf("Data page %d\n", *pp);
      read_data_page(*pp++);
    }
  if(debug)printf("No more data pages\n");
  free(pgs);
}

int
main(int argc, char *argv[])
{

  struct stat statbuf;
  
  setvbuf(stdout, 0, _IONBF, 0);
  fstat (0,&statbuf);
  pages = mmap(0, statbuf.st_size, PROT_READ, MAP_SHARED, 0, 0);
  
  if(debug)printf("File mapped at address %p, length %d\n", pages, statbuf.st_size);
  read_table(2);
  exit(0);
}
