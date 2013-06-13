#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/stat.h>

#include "jpeglib.h"

#include "fat.h"
#include "small_printf.h"

fileTYPE *file;

char string[]="Hello world!\n";

static struct stat statbuf;


struct JPEGContext
{
	struct jpeg_decompress_struct cinfo;
	struct jpeg_error_mgr jerr;
	int fd;
	JSAMPROW rowptr[1];
};

void jpeg_unixio_src (j_decompress_ptr cinfo, int infile);

int main(int argc, char **argv)
{
	file=malloc(sizeof(fileTYPE));
	struct JPEGContext *jc=malloc(sizeof(struct JPEGContext));

	jc->cinfo.err = jpeg_std_error(&jc->jerr);
	jpeg_create_decompress(&jc->cinfo);
	printf("created decompress\n");
	jc->fd=open("80SDIVE JPG",0,O_RDONLY);
	printf("open() returned %d\n",jc->fd);

	if((jc->fd>0)&&!fstat(jc->fd,&statbuf))
	{
		char *imagebuf;
		printf("File size: %d\n",statbuf.st_size);
		jpeg_unixio_src(&jc->cinfo,jc->fd);
		printf("Added unixio source\n");
		if((imagebuf=malloc(640*480*2+7)))
		{
			int row;
			JOCTET *rowbuffer;
			int *imagep;
			imagebuf+=7;
			imagebuf=(char *)((int)imagebuf&0xfffffff8);
			imagep=(int *)imagebuf;
			HW_VGA(FRAMEBUFFERPTR)=(int)imagebuf;

			jpeg_read_header(&jc->cinfo, TRUE);
			printf("Read JPEG header - dimensions %d x %d\n",jc->cinfo.output_width,jc->cinfo.output_height);
			jpeg_start_decompress(&jc->cinfo);
			printf("Started decompress\n");
			printf("dimensions %d x %d\n",jc->cinfo.output_width,jc->cinfo.output_height);
			printf("components: %d\n",jc->cinfo.output_components);
			rowbuffer=malloc(jc->cinfo.output_width*jc->cinfo.output_components);	// Read data is 24 bits.

			for(row=0;row<jc->cinfo.output_height;++row)
			{
				JOCTET *t=rowbuffer;
				jc->rowptr[0]=rowbuffer;
				int x,w;
				int scanlines=jpeg_read_scanlines(&jc->cinfo,&jc->rowptr,1);
				printf("Scanlines read: %d\n",scanlines);
				for(x=0;x<jc->cinfo.output_width;x+=2)
				{
					int r=*t++;
					int g=*t++;
					int b=*t++;
					w=(r&0xf8)<<24;
					w|=(g&0xfc)<<19;
					w|=(b&0xf8)<<13;
					r=*t++;
					g=*t++;
					b=*t++;
					w|=(r&0xf8)<<8;
					w|=(g&0xfc)<<3;
					w|=(b&0xf8)>>3;
					*imagep++=w;
				}
			}

//			read(fd,imagebuf,statbuf.st_size);
		}
	}

	return(0);
}
