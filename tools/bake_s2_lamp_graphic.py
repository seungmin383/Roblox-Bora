"""Bake only the selected Tripo headlamp color to a clean flat insert texture."""
import bpy,numpy as np
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform
from collections import deque
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/vehicles/retopology'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'BoraS2_Clean.blend'))
o=bpy.data.objects['Body_paint'];me=o.data;me.calc_loop_triangles();layer=me.uv_layers.active
vv=[];ff=[];tex=[]
for t in me.loop_triangles:
 p=me.polygons[t.polygon_index]
 if p.material_index!=1 or p.center.y>0 or p.center.x<0:continue
 s=len(vv);vv.extend(o.matrix_world@me.vertices[i].co for i in t.vertices);ff.append((s,s+1,s+2));tex.append([Vector((*layer.data[li].uv,0)) for li in t.loops])
tree=BVHTree.FromPolygons(vv,ff,all_triangles=True)
mat=bpy.data.materials['S2 • lamp graphics only'];src=next(n.image for n in mat.node_tree.nodes if n.type=='TEX_IMAGE' and n.image)
SW,SH=src.size;pixels=np.asarray(src.pixels[:],dtype=np.float32).reshape(SH,SW,4)
W=512;H=256;img=np.ones((H,W,4),dtype=np.float32);img[:,:,:3]=(.025,.034,.045);hitmask=np.zeros((H,W),dtype=bool)
for j in range(H):
 z=.614+.213*j/(H-1)
 for i in range(W):
  x=.531+.376*i/(W-1);hit,n,ti,d=tree.ray_cast(Vector((x,-3,z)),Vector((0,1,0)),1.5)
  if hit is None:continue
  a,b,c=(vv[k] for k in ff[ti]);uv=barycentric_transform(hit,a,b,c,*tex[ti]);u=float(uv.x)%1;v=float(uv.y)%1
  xx=u*(SW-1);yy=v*(SH-1);ix=int(xx);iy=int(yy);fx=xx-ix;fy=yy-iy
  color=pixels[iy,ix]*(1-fx)*(1-fy)+pixels[iy,min(ix+1,SW-1)]*fx*(1-fy)+pixels[min(iy+1,SH-1),ix]*(1-fx)*fy+pixels[min(iy+1,SH-1),min(ix+1,SW-1)]*fx*fy
  img[j,i]=color;hitmask[j,i]=True
raw=bpy.data.images.new('Raw lamp color bake',width=W,height=H);raw.pixels[:]=img.ravel();raw.filepath_raw=str(OUT/'s2-fit-lamp-raw.png');raw.file_format='PNG';raw.save()
# Rectify the measured lens quad, excluding surrounding source body paint.
# Coordinates below are on the orthographic source bake (top-left image axes).
TL=np.array((1,94));TR=np.array((365,51));BR=np.array((330,150));BL=np.array((30,190))
v,u=np.mgrid[0:H,0:W];u=u/(W-1);v=v/(H-1)
q=(BL[None,None,:]*(1-u[:,:,None])+BR[None,None,:]*u[:,:,None])*(1-v[:,:,None])+(TL[None,None,:]*(1-u[:,:,None])+TR[None,None,:]*u[:,:,None])*v[:,:,None]
xx=np.clip(q[:,:,0],0,W-1);yy=np.clip(H-1-q[:,:,1],0,H-1);ix=xx.astype(int);iy=yy.astype(int);fx=(xx-ix)[:,:,None];fy=(yy-iy)[:,:,None]
rect=img[iy,ix]*(1-fx)*(1-fy)+img[iy,np.minimum(ix+1,W-1)]*fx*(1-fy)+img[np.minimum(iy+1,H-1),ix]*(1-fx)*fy+img[np.minimum(iy+1,H-1),np.minimum(ix+1,W-1)]*fx*fy
im=bpy.data.images.new('Baked selected Tripo headlamp',width=W,height=H);im.pixels[:]=rect.ravel();im.filepath_raw=str(OUT/'BoraS2_FitLampBaked.png');im.file_format='PNG';im.save()
print('BAKED_LAMP',W,H,flush=True)
