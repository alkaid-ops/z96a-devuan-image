import sys
raw=open(sys.argv[1],'rb').read(); p=raw.split(b'\n',3)
w,h=[int(v) for v in p[1].split()[:2]]; d=p[3]
s=[0,0,0]; n=0; dist=set(); blk=0
for y in range(0,h,2):
    base=y*w*3
    for x in range(0,w,2):
        i=base+x*3; r,g,b=d[i],d[i+1],d[i+2]
        s[0]+=r; s[1]+=g; s[2]+=b; dist.add((r//16,g//16,b//16))
        if r<12 and g<12 and b<12: blk+=1
        n+=1
print("mean=(%.1f,%.1f,%.1f) distinct=%d near_black=%.1f%%"%(s[0]/n,s[1]/n,s[2]/n,len(dist),100.0*blk/n))
