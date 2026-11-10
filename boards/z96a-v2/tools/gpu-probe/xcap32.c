#include <stdio.h>
#include <stdlib.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
int main(int argc,char**argv){
  Window target = argc>1 ? strtoul(argv[1],0,0) : DefaultRootWindow(XOpenDisplay(NULL));
  Display*d=XOpenDisplay(NULL); if(!d)return 1;
  XWindowAttributes a; if(!XGetWindowAttributes(d,target,&a))return 1;
  XImage*im=XGetImage(d,target,0,0,a.width,a.height,AllPlanes,ZPixmap); if(!im)return 1;
  printf("depth=%d %dx%d\n",a.depth,a.width,a.height);
  long n=0,az=0,af=0; double as=0; long rs=0,gs=0,bs=0;
  for(int y=0;y<a.height;y+=3)for(int x=0;x<a.width;x+=3){
    unsigned long p=XGetPixel(im,x,y);
    unsigned r=(p>>16)&0xff,g=(p>>8)&0xff,b=p&0xff;
    unsigned alpha = a.depth==32 ? (p>>24)&0xff : 255;
    rs+=r;gs+=g;bs+=b;as+=alpha;n++;
    if(alpha==0)az++; if(alpha>=250)af++;
  }
  printf("samples=%ld mean_rgb=(%.1f,%.1f,%.1f) mean_alpha=%.1f alpha0=%.1f%% alpha255=%.1f%%\n",
    n,(double)rs/n,(double)gs/n,(double)bs/n,as/n,100.0*az/n,100.0*af/n);
  return 0;
}
