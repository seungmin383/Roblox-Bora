"""Convex clipping with interpolated positions, normals and texture coordinates."""
def split(poly,normal,offset):
    inside=[];outside=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        da=sum(a[i]*normal[i] for i in range(3))-offset;db=sum(b[i]*normal[i] for i in range(3))-offset
        (inside if da<=1e-8 else outside).append(a)
        if (da< -1e-8 and db>1e-8) or (da>1e-8 and db< -1e-8):
            t=da/(da-db);p=tuple(a[i]+t*(b[i]-a[i]) for i in range(len(a)));inside.append(p);outside.append(p)
    return inside,outside

def partition(poly,planes):
    if any(all(sum(v[i]*n[i] for i in range(3))-d>1e-8 for v in poly) for n,d in planes):return [],[poly]
    inside=poly;outside=[]
    for normal,offset in planes:
        if len(inside)<3:return [],outside
        inside,cut=split(inside,normal,offset)
        if len(cut)>=3:outside.append(cut)
    return inside,outside

def box(x0,x1,y0,y1,z0,z1):
    return [((1,0,0),x1),((-1,0,0),-x0),((0,1,0),y1),((0,-1,0),-y0),((0,0,1),z1),((0,0,-1),-z0)]
